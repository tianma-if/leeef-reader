import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:leeef_reader/src/sync/trusted/encrypted_document_codec.dart';
import 'package:leeef_reader/src/sync/trusted/portable_configuration.dart';
import 'package:leeef_reader/src/sync/trusted/sync_space_store.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_device.dart';

class PairingService {
  PairingService({
    required this.spaceStore,
    required this.configuration,
    EncryptedDocumentCodec? codec,
    DateTime Function()? clock,
    Random? random,
  }) : _codec = codec ?? EncryptedDocumentCodec(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const discoveryPort = 47831;
  static const _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  final SyncSpaceStore spaceStore;
  final PortableConfiguration configuration;
  final EncryptedDocumentCodec _codec;
  final DateTime Function() _clock;
  final Random _random;
  final X25519 _keyExchange = X25519();
  final Hkdf _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<PairingHostSession> startHost({
    Duration lifetime = const Duration(minutes: 5),
  }) async {
    final code = _newCode();
    final sessionId = _randomToken(16);
    final expiresAt = _clock().toUtc().add(lifetime);
    final hostKeyPair = await _keyExchange.newKeyPair();
    final hostPublicKey = await hostKeyPair.extractPublicKey();
    final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final udp = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    final completion = Completer<TrustedDevice>();
    late PairingHostSession session;

    final udpSubscription = udp.listen((event) {
      if (event != RawSocketEvent.read || _clock().toUtc().isAfter(expiresAt)) {
        return;
      }
      final datagram = udp.receive();
      if (datagram == null) return;
      try {
        final request = jsonDecode(utf8.decode(datagram.data));
        if (request is! Map ||
            request['type'] != 'leeef-pair-discover-v1' ||
            request['verifier'] != _codeVerifier(code)) {
          return;
        }
        final response = utf8.encode(
          jsonEncode({
            'type': 'leeef-pair-host-v1',
            'sessionId': sessionId,
            'port': httpServer.port,
            'publicKey': base64UrlEncode(hostPublicKey.bytes),
            'expiresAt': expiresAt.toIso8601String(),
          }),
        );
        udp.send(response, datagram.address, datagram.port);
      } on Object {
        // Ignore unrelated LAN traffic on the discovery port.
      }
    });

    final httpSubscription = httpServer.listen((request) async {
      if (request.method != 'POST' || request.uri.path != '/pair') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      if (completion.isCompleted || _clock().toUtc().isAfter(expiresAt)) {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        return;
      }
      try {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (body['sessionId'] != sessionId) {
          throw const FormatException('Pairing session does not match.');
        }
        final clientPublicKeyBytes = base64Url.decode(
          body['publicKey']! as String,
        );
        final sharedSecret = await _keyExchange.sharedSecretKey(
          keyPair: hostKeyPair,
          remotePublicKey: SimplePublicKey(
            clientPublicKeyBytes,
            type: KeyPairType.x25519,
          ),
        );
        final pairingKey = await _derivePairingKey(
          sharedSecret,
          code,
          sessionId,
        );
        final requestPayload = await _codec.decryptJson(
          document: base64Url.decode(body['payload']! as String),
          key: pairingKey,
          associatedData: 'pair-request:$sessionId',
          expectedKeyEpoch: 0,
        );
        final client = TrustedDevice.fromJson(
          Map<String, Object?>.from(requestPayload['device']! as Map),
        );
        if (client.publicKey != body['publicKey']) {
          throw const FormatException('Pairing device key does not match.');
        }

        final space = await spaceStore.ensureSpace();
        final hostIdentity = await spaceStore.loadOrCreateIdentity();
        final entries = await configuration.capture(hostIdentity.device.id);
        await spaceStore.upsertCachedDevice(hostIdentity.device);
        await spaceStore.upsertCachedDevice(client);
        final devices = await spaceStore.loadDevices();
        final responsePayload = await _codec.encryptJson(
          value: {
            'spaceId': space.id,
            'keyEpoch': space.keyEpoch,
            'groupKey': base64UrlEncode(space.groupKey),
            'configuration': entries.map((item) => item.toJson()).toList(),
            'devices': devices.map((item) => item.toJson()).toList(),
          },
          key: pairingKey,
          associatedData: 'pair-response:$sessionId',
          keyEpoch: 0,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'payload': base64UrlEncode(responsePayload)}),
        );
        await request.response.close();
        completion.complete(client);
        unawaited(session.close());
      } on Object catch (error) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': '$error'}));
        await request.response.close();
      }
    });

    session = PairingHostSession._(
      code: code,
      expiresAt: expiresAt,
      completion: completion.future,
      httpServer: httpServer,
      udp: udp,
      httpSubscription: httpSubscription,
      udpSubscription: udpSubscription,
    );
    Timer(lifetime, () => unawaited(session.close()));
    return session;
  }

  Future<PairingJoinResult> join(
    String rawCode, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final code = _normalizeCode(rawCode);
    if (code.length != 12) throw const FormatException('配对码格式不正确。');
    final identity = await spaceStore.loadOrCreateIdentity();
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final host = Completer<_DiscoveredHost>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || host.isCompleted) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final value = jsonDecode(utf8.decode(datagram.data));
        if (value is! Map || value['type'] != 'leeef-pair-host-v1') return;
        host.complete(
          _DiscoveredHost(
            address: datagram.address,
            port: value['port']! as int,
            sessionId: value['sessionId']! as String,
            publicKey: base64Url.decode(value['publicKey']! as String),
          ),
        );
      } on Object {
        // Ignore unrelated discovery responses.
      }
    });
    final discovery = utf8.encode(
      jsonEncode({
        'type': 'leeef-pair-discover-v1',
        'verifier': _codeVerifier(code),
      }),
    );
    Timer? retransmit;
    void sendDiscovery() {
      try {
        socket.send(
          discovery,
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      } on SocketException {
        // Sandboxed hosts can have no broadcast route. Keep loopback discovery
        // available so local devices and test environments still pair.
      }
      // Loopback keeps pairing available between local simulators and makes
      // the discovery protocol deterministic in desktop test environments.
      socket.send(discovery, InternetAddress.loopbackIPv4, discoveryPort);
    }

    sendDiscovery();
    retransmit = Timer.periodic(const Duration(seconds: 1), (_) {
      sendDiscovery();
    });
    late _DiscoveredHost discovered;
    try {
      discovered = await host.future.timeout(timeout);
    } on TimeoutException {
      throw const PairingUnavailable('没有在局域网内找到对应的配对设备。');
    } finally {
      retransmit.cancel();
      await subscription.cancel();
      socket.close();
    }

    final keyPair = await _keyExchange.newKeyPairFromSeed(identity.privateKey);
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        discovered.publicKey,
        type: KeyPairType.x25519,
      ),
    );
    final pairingKey = await _derivePairingKey(
      sharedSecret,
      code,
      discovered.sessionId,
    );
    final payload = await _codec.encryptJson(
      value: {'device': identity.device.toJson()},
      key: pairingKey,
      associatedData: 'pair-request:${discovered.sessionId}',
      keyEpoch: 0,
    );
    final client = HttpClient();
    try {
      final uri = Uri(
        scheme: 'http',
        host: discovered.address.address,
        port: discovered.port,
        path: '/pair',
      );
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'sessionId': discovered.sessionId,
          'publicKey': identity.device.publicKey,
          'payload': base64UrlEncode(payload),
        }),
      );
      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw PairingUnavailable('配对设备拒绝了请求：$responseBody');
      }
      final outer = jsonDecode(responseBody) as Map;
      final result = await _codec.decryptJson(
        document: base64Url.decode(outer['payload']! as String),
        key: pairingKey,
        associatedData: 'pair-response:${discovered.sessionId}',
        expectedKeyEpoch: 0,
      );
      final state = SyncSpaceState(
        id: result['spaceId']! as String,
        keyEpoch: result['keyEpoch']! as int,
        groupKey: base64Url.decode(result['groupKey']! as String),
      );
      await spaceStore.saveSpace(state);
      final entries = (result['configuration']! as List)
          .whereType<Map>()
          .map(
            (item) =>
                ConfigurationEntry.fromJson(Map<String, Object?>.from(item)),
          )
          .toList();
      final changed = await configuration.applyPairingSnapshot(entries);
      final devices =
          (result['devices']! as List)
              .whereType<Map>()
              .map(
                (item) =>
                    TrustedDevice.fromJson(Map<String, Object?>.from(item)),
              )
              .toList()
            ..add(identity.device);
      await spaceStore.replaceCachedDevices(devices);
      return PairingJoinResult(
        space: state,
        importedConfigurationValues: changed,
        devices: devices,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _derivePairingKey(
    SecretKey sharedSecret,
    String code,
    String sessionId,
  ) async => (await _kdf.deriveKey(
    secretKey: sharedSecret,
    nonce: utf8.encode(_normalizeCode(code)),
    info: utf8.encode('leeef-pair-v1:$sessionId'),
  )).extractBytes();

  String _newCode() {
    final value = List.generate(
      12,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '${value.substring(0, 4)}-${value.substring(4, 8)}-${value.substring(8)}';
  }

  String _randomToken(int bytes) =>
      base64UrlEncode(List<int>.generate(bytes, (_) => _random.nextInt(256)));

  static String _normalizeCode(String value) =>
      value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  static String _codeVerifier(String code) => base64UrlEncode(
    crypto.sha256.convert(utf8.encode(_normalizeCode(code))).bytes,
  );
}

class PairingHostSession {
  PairingHostSession._({
    required this.code,
    required this.expiresAt,
    required this.completion,
    required HttpServer httpServer,
    required RawDatagramSocket udp,
    required StreamSubscription<HttpRequest> httpSubscription,
    required StreamSubscription<RawSocketEvent> udpSubscription,
  }) : _httpServer = httpServer,
       _udp = udp,
       _httpSubscription = httpSubscription,
       _udpSubscription = udpSubscription;

  final String code;
  final DateTime expiresAt;
  final Future<TrustedDevice> completion;
  final HttpServer _httpServer;
  final RawDatagramSocket _udp;
  final StreamSubscription<HttpRequest> _httpSubscription;
  final StreamSubscription<RawSocketEvent> _udpSubscription;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _udpSubscription.cancel();
    _udp.close();
    await _httpSubscription.cancel();
    await _httpServer.close(force: true);
  }
}

class PairingJoinResult {
  const PairingJoinResult({
    required this.space,
    required this.importedConfigurationValues,
    required this.devices,
  });

  final SyncSpaceState space;
  final int importedConfigurationValues;
  final List<TrustedDevice> devices;
}

class PairingUnavailable implements Exception {
  const PairingUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DiscoveredHost {
  const _DiscoveredHost({
    required this.address,
    required this.port,
    required this.sessionId,
    required this.publicKey,
  });

  final InternetAddress address;
  final int port;
  final String sessionId;
  final List<int> publicKey;
}
