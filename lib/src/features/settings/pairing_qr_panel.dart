import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/sync/trusted/pairing_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

bool canScanPairingQr([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

class PairingQrPanel extends StatelessWidget {
  const PairingQrPanel({super.key, required this.code, required this.payload});

  final String code;
  final String payload;

  factory PairingQrPanel.fromSession(PairingHostSession session) =>
      PairingQrPanel(code: session.code, payload: session.invite.toQrPayload());

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.text('用手机扫描这个二维码。两台设备需要连接同一个局域网。')),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: payload,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectionArea(
          child: Text(
            code,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.text('也可以手动输入配对码。配对码 5 分钟内有效且只能使用一次。'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
      ],
    );
  }
}

Future<void> copyPairingCode(PairingHostSession session) {
  return Clipboard.setData(ClipboardData(text: session.code));
}
