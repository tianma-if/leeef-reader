import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/sync/object_storage_provider.dart';

Future<ObjectStorageConfiguration?> showObjectStorageConfigDialog({
  required BuildContext context,
  ObjectStorageConfiguration? current,
  Future<void> Function(ObjectStorageConfiguration configuration)? onTest,
}) {
  return showDialog<ObjectStorageConfiguration>(
    context: context,
    builder: (context) =>
        _ObjectStorageConfigDialog(current: current, onTest: onTest),
  );
}

class _ObjectStorageConfigDialog extends StatefulWidget {
  const _ObjectStorageConfigDialog({this.current, this.onTest});

  final ObjectStorageConfiguration? current;
  final Future<void> Function(ObjectStorageConfiguration configuration)? onTest;

  @override
  State<_ObjectStorageConfigDialog> createState() =>
      _ObjectStorageConfigDialogState();
}

class _ObjectStorageConfigDialogState
    extends State<_ObjectStorageConfigDialog> {
  late ObjectStorageProviderId _providerId;
  late final TextEditingController _bucket;
  late final TextEditingController _prefix;
  late final TextEditingController _accessKey;
  late final TextEditingController _secretKey;
  late final TextEditingController _endpoint;
  late final TextEditingController _region;
  late final TextEditingController _accountId;
  late final TextEditingController _sessionToken;
  late bool _pathStyle;
  var _showAdvanced = false;
  var _testing = false;
  String? _testMessage;
  bool _testSucceeded = false;
  String? _error;

  ObjectStorageProvider get _provider =>
      ObjectStorageProvider.byId(_providerId);

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _providerId = current == null
        ? ObjectStorageProviderId.aliyun
        : current.providerId;
    final inferredRegion = inferObjectStorageRegion(
      providerId: _providerId,
      endpoint: current?.endpoint,
      region: current?.region,
    );
    _bucket = TextEditingController(text: current?.bucket ?? '');
    _prefix = TextEditingController(
      text: current?.prefix.isNotEmpty == true ? current!.prefix : 'leeef',
    );
    _accessKey = TextEditingController(text: current?.accessKeyId ?? '');
    _secretKey = TextEditingController(text: current?.secretAccessKey ?? '');
    _endpoint = TextEditingController(text: current?.endpoint ?? '');
    _region = TextEditingController(text: inferredRegion);
    _accountId = TextEditingController(
      text: current?.accountId.isNotEmpty == true
          ? current!.accountId
          : inferObjectStorageAccountId(current?.endpoint),
    );
    _sessionToken = TextEditingController(text: current?.sessionToken ?? '');
    _pathStyle = current?.pathStyle ?? _provider.pathStyle;
    _showAdvanced =
        _provider.needsEndpoint ||
        (current != null &&
            current.endpoint.isNotEmpty &&
            current.endpoint !=
                _provider.endpointFor(
                  regionId: inferredRegion,
                  accountId: _accountId.text,
                ));
  }

  @override
  void dispose() {
    _bucket.dispose();
    _prefix.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _endpoint.dispose();
    _region.dispose();
    _accountId.dispose();
    _sessionToken.dispose();
    super.dispose();
  }

  void _selectProvider(ObjectStorageProviderId id) {
    if (id == _providerId) return;
    final previousNeedsEndpoint = _provider.needsEndpoint;
    final next = ObjectStorageProvider.byId(id);
    setState(() {
      _providerId = id;
      _region.text = next.defaultRegion;
      _pathStyle = next.pathStyle;
      _error = null;
      _testMessage = null;
      if (!previousNeedsEndpoint) {
        _endpoint.clear();
      }
      _showAdvanced = next.needsEndpoint;
    });
  }

  ObjectStorageConfiguration _draft() {
    final generated = _provider.endpointFor(
      regionId: _region.text.trim().isEmpty
          ? _provider.defaultRegion
          : _region.text.trim(),
      accountId: _accountId.text,
    );
    final typedEndpoint = _endpoint.text.trim();
    final customEndpoint = _provider.needsEndpoint
        ? typedEndpoint
        : (typedEndpoint.isNotEmpty && typedEndpoint != generated
              ? typedEndpoint
              : '');
    return resolveObjectStorageConfiguration(
      providerId: _providerId,
      bucket: _bucket.text,
      accessKeyId: _accessKey.text,
      secretAccessKey: _secretKey.text,
      regionId: _region.text,
      prefix: _prefix.text,
      customEndpoint: customEndpoint,
      pathStyle: _pathStyle,
      sessionToken: _sessionToken.text,
      accountId: _accountId.text,
    );
  }

  void _save() {
    final configuration = _draft();
    final error = validateObjectStorageConfiguration(configuration);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, configuration);
  }

  Future<void> _test() async {
    final onTest = widget.onTest;
    if (onTest == null || _testing) return;
    final configuration = _draft();
    final error = validateObjectStorageConfiguration(configuration);
    if (error != null) {
      setState(() {
        _error = error;
        _testMessage = null;
      });
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
      _testMessage = null;
    });
    try {
      await onTest(configuration);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSucceeded = true;
        _testMessage = AppStrings.of(context).text('同步后端连接和读写能力正常');
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSucceeded = false;
        _testMessage = AppStrings.of(context).failure('同步后端检测', error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Text(strings.text('配置对象存储')),
      content: SizedBox(
        width: width < 640 ? width - 48 : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('按云厂商填写控制台里的同名项目，不用自己拼 Endpoint。'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final provider in ObjectStorageProvider.catalog)
                    ChoiceChip(
                      label: Text(strings.text(provider.name)),
                      selected: provider.id == _providerId,
                      onSelected: (_) => _selectProvider(provider.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                strings.text(_provider.helper),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_provider.needsAccountId)
                TextField(
                  controller: _accountId,
                  decoration: InputDecoration(
                    labelText: 'Account ID',
                    helperText: strings.text('R2 控制台概览页中的 Account ID'),
                  ),
                ),
              if (_provider.needsEndpoint)
                TextField(
                  controller: _endpoint,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Endpoint',
                    hintText: _providerId == ObjectStorageProviderId.minio
                        ? 'http://192.168.1.10:9000'
                        : 'https://s3.example.com',
                    helperText: strings.text('MinIO 或 NAS 上的 S3 地址'),
                  ),
                ),
              TextField(
                controller: _accessKey,
                decoration: InputDecoration(
                  labelText: _provider.accessKeyLabel,
                  helperText: strings.text('与控制台中的密钥名称一致'),
                ),
              ),
              TextField(
                controller: _secretKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _provider.secretKeyLabel,
                ),
              ),
              TextField(
                controller: _bucket,
                decoration: InputDecoration(
                  labelText: strings.text(_provider.bucketLabel),
                  helperText: strings.text('控制台里 Bucket 的名称，不要填网址'),
                ),
              ),
              if (_provider.needsRegion)
                DropdownButtonFormField<String>(
                  key: ValueKey('${_providerId.name}-region'),
                  initialValue:
                      _provider.regions.any(
                        (region) => region.id == _region.text,
                      )
                      ? _region.text
                      : _provider.defaultRegion,
                  decoration: InputDecoration(
                    labelText: strings.text('存储区域'),
                    helperText: strings.text('与 Bucket 概览里的地域一致'),
                  ),
                  items: [
                    for (final region in _provider.regions)
                      DropdownMenuItem(
                        value: region.id,
                        child: Text(
                          '${strings.text(region.label)}  (${region.id})',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _region.text = value;
                      _testMessage = null;
                    });
                  },
                ),
              TextField(
                controller: _prefix,
                decoration: InputDecoration(
                  labelText: strings.text('存储路径'),
                  helperText: strings.text('书籍会放在这个目录下，一般不用改'),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                key: ValueKey('advanced-${_providerId.name}'),
                initiallyExpanded: _showAdvanced,
                tilePadding: EdgeInsets.zero,
                title: Text(strings.text('高级选项')),
                subtitle: Text(
                  strings.text('自定义 Endpoint、Path-style、临时密钥'),
                  style: theme.textTheme.bodySmall,
                ),
                onExpansionChanged: (value) =>
                    setState(() => _showAdvanced = value),
                children: [
                  if (!_provider.needsEndpoint)
                    TextField(
                      controller: _endpoint,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: strings.text('自定义 Endpoint'),
                        hintText: _provider.endpointFor(
                          regionId: _region.text.isEmpty
                              ? _provider.defaultRegion
                              : _region.text,
                          accountId: _accountId.text,
                        ),
                      ),
                    ),
                  if (!_provider.needsRegion)
                    TextField(
                      controller: _region,
                      decoration: InputDecoration(
                        labelText: strings.text('存储区域'),
                        hintText: _provider.defaultRegion,
                      ),
                    ),
                  TextField(
                    controller: _sessionToken,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.text('Session Token（可选）'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pathStyle,
                    title: Text(strings.text('Path-style 请求')),
                    subtitle: Text(strings.text('MinIO、NAS 等兼容服务通常需要开启')),
                    onChanged: (value) => setState(() => _pathStyle = value),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  strings.text(_error!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_testMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _testMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _testSucceeded
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onTest != null)
          TextButton(
            onPressed: _testing ? null : _test,
            child: _testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.text('检测连接')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.text('取消')),
        ),
        FilledButton(onPressed: _save, child: Text(strings.text('保存'))),
      ],
    );
  }
}
