enum ObjectStorageProviderId {
  aliyun,
  tencent,
  qiniu,
  huawei,
  volcengine,
  aws,
  r2,
  minio,
  custom,
}

class ObjectStorageRegion {
  const ObjectStorageRegion({required this.id, required this.label});

  final String id;
  final String label;
}

class ObjectStorageConfiguration {
  const ObjectStorageConfiguration({
    required this.providerId,
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.prefix,
    required this.pathStyle,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken = '',
    this.accountId = '',
  });

  final ObjectStorageProviderId providerId;
  final String endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final bool pathStyle;
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final String accountId;
}

class ObjectStorageProvider {
  const ObjectStorageProvider({
    required this.id,
    required this.name,
    required this.accessKeyLabel,
    required this.secretKeyLabel,
    required this.bucketLabel,
    required this.helper,
    required this.regions,
    required this.defaultRegion,
    required this.pathStyle,
    required this.needsEndpoint,
    required this.needsAccountId,
    required this.endpointFor,
  });

  final ObjectStorageProviderId id;
  final String name;
  final String accessKeyLabel;
  final String secretKeyLabel;
  final String bucketLabel;
  final String helper;
  final List<ObjectStorageRegion> regions;
  final String defaultRegion;
  final bool pathStyle;
  final bool needsEndpoint;
  final bool needsAccountId;
  final String Function({required String regionId, String accountId})
  endpointFor;

  bool get needsRegion => regions.isNotEmpty;

  static ObjectStorageProvider byId(ObjectStorageProviderId id) =>
      catalog.firstWhere((provider) => provider.id == id);

  static const catalog = <ObjectStorageProvider>[
    ObjectStorageProvider(
      id: ObjectStorageProviderId.aliyun,
      name: '阿里云 OSS',
      accessKeyLabel: 'AccessKey ID',
      secretKeyLabel: 'AccessKey Secret',
      bucketLabel: '存储空间名',
      helper: '打开阿里云 OSS 控制台，把 Bucket 名称、地域和 AccessKey 填进来。不用手写 Endpoint。',
      defaultRegion: 'oss-cn-hangzhou',
      pathStyle: false,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _aliyunRegions,
      endpointFor: _aliyunEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.tencent,
      name: '腾讯云 COS',
      accessKeyLabel: 'SecretId',
      secretKeyLabel: 'SecretKey',
      bucketLabel: '存储桶名',
      helper: '存储桶名通常是 bucket-appid，例如 example-1250000000。地域与 COS 控制台一致。',
      defaultRegion: 'ap-guangzhou',
      pathStyle: false,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _tencentRegions,
      endpointFor: _tencentEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.qiniu,
      name: '七牛云 Kodo',
      accessKeyLabel: 'AccessKey',
      secretKeyLabel: 'SecretKey',
      bucketLabel: '存储空间名',
      helper: '使用七牛的 S3 兼容访问。空间名、密钥和区域都可以在 Kodo 控制台直接复制。',
      defaultRegion: 'cn-east-1',
      pathStyle: true,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _qiniuRegions,
      endpointFor: _qiniuEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.huawei,
      name: '华为云 OBS',
      accessKeyLabel: 'Access Key Id',
      secretKeyLabel: 'Secret Access Key',
      bucketLabel: '桶名称',
      helper: '地域选择与 OBS 桶概览里的区域一致，例如华北-北京四。',
      defaultRegion: 'cn-north-4',
      pathStyle: false,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _huaweiRegions,
      endpointFor: _huaweiEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.volcengine,
      name: '火山引擎 TOS',
      accessKeyLabel: 'Access Key',
      secretKeyLabel: 'Secret Key',
      bucketLabel: 'Bucket 名称',
      helper: '使用 TOS 的 S3 兼容 Endpoint。地域填控制台中的 Region，例如 cn-beijing。',
      defaultRegion: 'cn-beijing',
      pathStyle: true,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _volcengineRegions,
      endpointFor: _volcengineEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.aws,
      name: 'Amazon S3',
      accessKeyLabel: 'Access Key ID',
      secretKeyLabel: 'Secret Access Key',
      bucketLabel: 'Bucket',
      helper: '选择 Bucket 所在区域即可，Endpoint 会按区域自动生成。',
      defaultRegion: 'us-east-1',
      pathStyle: false,
      needsEndpoint: false,
      needsAccountId: false,
      regions: _awsRegions,
      endpointFor: _awsEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.r2,
      name: 'Cloudflare R2',
      accessKeyLabel: 'Access Key ID',
      secretKeyLabel: 'Secret Access Key',
      bucketLabel: 'Bucket',
      helper: 'Account ID 在 R2 概览页，用来生成 Endpoint。密钥在 R2 的 S3 API 令牌里创建。',
      defaultRegion: 'auto',
      pathStyle: true,
      needsEndpoint: false,
      needsAccountId: true,
      regions: [],
      endpointFor: _r2Endpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.minio,
      name: 'MinIO / NAS',
      accessKeyLabel: 'Access Key',
      secretKeyLabel: 'Secret Key',
      bucketLabel: 'Bucket',
      helper: '适用于 MinIO、群晖、威联通等兼容服务。填写局域网或公网的 S3 地址。',
      defaultRegion: 'us-east-1',
      pathStyle: true,
      needsEndpoint: true,
      needsAccountId: false,
      regions: [],
      endpointFor: _emptyEndpoint,
    ),
    ObjectStorageProvider(
      id: ObjectStorageProviderId.custom,
      name: '自定义 S3',
      accessKeyLabel: 'Access Key ID',
      secretKeyLabel: 'Secret Access Key',
      bucketLabel: 'Bucket',
      helper: '其他 S3 兼容服务可在这里填写完整 Endpoint 和 Region。',
      defaultRegion: 'us-east-1',
      pathStyle: true,
      needsEndpoint: true,
      needsAccountId: false,
      regions: [],
      endpointFor: _emptyEndpoint,
    ),
  ];
}

const _aliyunRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'oss-cn-hangzhou', label: '华东1（杭州）'),
  ObjectStorageRegion(id: 'oss-cn-shanghai', label: '华东2（上海）'),
  ObjectStorageRegion(id: 'oss-cn-nanjing', label: '华东5（南京）'),
  ObjectStorageRegion(id: 'oss-cn-fuzhou', label: '华东6（福州）'),
  ObjectStorageRegion(id: 'oss-cn-wuhan', label: '华中1（武汉）'),
  ObjectStorageRegion(id: 'oss-cn-qingdao', label: '华北1（青岛）'),
  ObjectStorageRegion(id: 'oss-cn-beijing', label: '华北2（北京）'),
  ObjectStorageRegion(id: 'oss-cn-zhangjiakou', label: '华北3（张家口）'),
  ObjectStorageRegion(id: 'oss-cn-huhehaote', label: '华北5（呼和浩特）'),
  ObjectStorageRegion(id: 'oss-cn-wulanchabu', label: '华北6（乌兰察布）'),
  ObjectStorageRegion(id: 'oss-cn-shenzhen', label: '华南1（深圳）'),
  ObjectStorageRegion(id: 'oss-cn-heyuan', label: '华南2（河源）'),
  ObjectStorageRegion(id: 'oss-cn-guangzhou', label: '华南3（广州）'),
  ObjectStorageRegion(id: 'oss-cn-chengdu', label: '西南1（成都）'),
  ObjectStorageRegion(id: 'oss-cn-hongkong', label: '中国香港'),
  ObjectStorageRegion(id: 'oss-us-west-1', label: '美国西部1（硅谷）'),
  ObjectStorageRegion(id: 'oss-us-east-1', label: '美国东部1（弗吉尼亚）'),
  ObjectStorageRegion(id: 'oss-ap-southeast-1', label: '新加坡'),
  ObjectStorageRegion(id: 'oss-ap-northeast-1', label: '日本（东京）'),
  ObjectStorageRegion(id: 'oss-eu-central-1', label: '德国（法兰克福）'),
];

const _tencentRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'ap-beijing', label: '北京'),
  ObjectStorageRegion(id: 'ap-nanjing', label: '南京'),
  ObjectStorageRegion(id: 'ap-shanghai', label: '上海'),
  ObjectStorageRegion(id: 'ap-guangzhou', label: '广州'),
  ObjectStorageRegion(id: 'ap-chengdu', label: '成都'),
  ObjectStorageRegion(id: 'ap-chongqing', label: '重庆'),
  ObjectStorageRegion(id: 'ap-hongkong', label: '中国香港'),
  ObjectStorageRegion(id: 'ap-singapore', label: '新加坡'),
  ObjectStorageRegion(id: 'ap-tokyo', label: '东京'),
  ObjectStorageRegion(id: 'na-siliconvalley', label: '硅谷'),
  ObjectStorageRegion(id: 'na-ashburn', label: '弗吉尼亚'),
  ObjectStorageRegion(id: 'eu-frankfurt', label: '法兰克福'),
];

const _qiniuRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'cn-east-1', label: '华东-浙江'),
  ObjectStorageRegion(id: 'cn-east-2', label: '华东-浙江2'),
  ObjectStorageRegion(id: 'cn-north-1', label: '华北-河北'),
  ObjectStorageRegion(id: 'cn-south-1', label: '华南-广东'),
  ObjectStorageRegion(id: 'us-north-1', label: '北美-洛杉矶'),
  ObjectStorageRegion(id: 'ap-southeast-1', label: '亚太-新加坡'),
];

const _huaweiRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'cn-north-1', label: '华北-北京一'),
  ObjectStorageRegion(id: 'cn-north-4', label: '华北-北京四'),
  ObjectStorageRegion(id: 'cn-east-2', label: '华东-上海二'),
  ObjectStorageRegion(id: 'cn-east-3', label: '华东-上海一'),
  ObjectStorageRegion(id: 'cn-south-1', label: '华南-广州'),
  ObjectStorageRegion(id: 'cn-southwest-2', label: '西南-贵阳一'),
  ObjectStorageRegion(id: 'ap-southeast-1', label: '中国-香港'),
];

const _volcengineRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'cn-beijing', label: '华北2（北京）'),
  ObjectStorageRegion(id: 'cn-shanghai', label: '华东2（上海）'),
  ObjectStorageRegion(id: 'cn-guangzhou', label: '华南1（广州）'),
  ObjectStorageRegion(id: 'ap-southeast-1', label: '亚太东南（柔佛）'),
];

const _awsRegions = <ObjectStorageRegion>[
  ObjectStorageRegion(id: 'us-east-1', label: 'US East (N. Virginia)'),
  ObjectStorageRegion(id: 'us-west-1', label: 'US West (N. California)'),
  ObjectStorageRegion(id: 'us-west-2', label: 'US West (Oregon)'),
  ObjectStorageRegion(id: 'eu-west-1', label: 'Europe (Ireland)'),
  ObjectStorageRegion(id: 'eu-central-1', label: 'Europe (Frankfurt)'),
  ObjectStorageRegion(id: 'ap-northeast-1', label: 'Asia Pacific (Tokyo)'),
  ObjectStorageRegion(id: 'ap-southeast-1', label: 'Asia Pacific (Singapore)'),
  ObjectStorageRegion(id: 'ap-east-1', label: 'Asia Pacific (Hong Kong)'),
  ObjectStorageRegion(id: 'ap-southeast-2', label: 'Asia Pacific (Sydney)'),
];

String _aliyunEndpoint({required String regionId, String accountId = ''}) =>
    'https://$regionId.aliyuncs.com';

String _tencentEndpoint({required String regionId, String accountId = ''}) =>
    'https://cos.$regionId.myqcloud.com';

String _qiniuEndpoint({required String regionId, String accountId = ''}) =>
    'https://s3.$regionId.qiniucs.com';

String _huaweiEndpoint({required String regionId, String accountId = ''}) =>
    'https://obs.$regionId.myhuaweicloud.com';

String _volcengineEndpoint({required String regionId, String accountId = ''}) =>
    'https://tos-s3-$regionId.volces.com';

String _awsEndpoint({required String regionId, String accountId = ''}) =>
    'https://s3.$regionId.amazonaws.com';

String _r2Endpoint({required String regionId, String accountId = ''}) =>
    'https://${accountId.trim()}.r2.cloudflarestorage.com';

String _emptyEndpoint({required String regionId, String accountId = ''}) => '';

ObjectStorageProviderId parseObjectStorageProviderId(String? raw) {
  if (raw == null || raw.isEmpty) return ObjectStorageProviderId.custom;
  return ObjectStorageProviderId.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => ObjectStorageProviderId.custom,
  );
}

ObjectStorageProviderId inferObjectStorageProvider({
  String? endpoint,
  String? region,
}) {
  final host = Uri.tryParse(endpoint ?? '')?.host.toLowerCase() ?? '';
  if (host.endsWith('.aliyuncs.com') || host == 'aliyuncs.com') {
    return ObjectStorageProviderId.aliyun;
  }
  if (host.contains('.myqcloud.com') || host.endsWith('myqcloud.com')) {
    return ObjectStorageProviderId.tencent;
  }
  if (host.contains('.qiniucs.com') || host.endsWith('qiniucs.com')) {
    return ObjectStorageProviderId.qiniu;
  }
  if (host.contains('.myhuaweicloud.com') ||
      host.endsWith('myhuaweicloud.com')) {
    return ObjectStorageProviderId.huawei;
  }
  if (host.contains('.volces.com') || host.endsWith('volces.com')) {
    return ObjectStorageProviderId.volcengine;
  }
  if (host.contains('.amazonaws.com') || host.endsWith('amazonaws.com')) {
    return ObjectStorageProviderId.aws;
  }
  if (host.contains('.r2.cloudflarestorage.com') ||
      host.endsWith('r2.cloudflarestorage.com')) {
    return ObjectStorageProviderId.r2;
  }
  if ((endpoint ?? '').trim().isEmpty && (region ?? '').startsWith('oss-')) {
    return ObjectStorageProviderId.aliyun;
  }
  return ObjectStorageProviderId.custom;
}

String inferObjectStorageRegion({
  required ObjectStorageProviderId providerId,
  String? endpoint,
  String? region,
}) {
  final provider = ObjectStorageProvider.byId(providerId);
  final host = Uri.tryParse(endpoint ?? '')?.host ?? '';
  final candidates = <String>[
    if (region != null && region.trim().isNotEmpty) region.trim(),
    ..._regionCandidatesFromHost(providerId, host),
  ];
  for (final candidate in candidates) {
    if (provider.regions.any((item) => item.id == candidate)) {
      return candidate;
    }
  }
  return provider.defaultRegion;
}

String inferObjectStorageAccountId(String? endpoint) {
  final host = Uri.tryParse(endpoint ?? '')?.host ?? '';
  const suffix = '.r2.cloudflarestorage.com';
  if (host.endsWith(suffix)) {
    return host.substring(0, host.length - suffix.length);
  }
  return '';
}

List<String> _regionCandidatesFromHost(
  ObjectStorageProviderId providerId,
  String host,
) {
  if (host.isEmpty) return const [];
  switch (providerId) {
    case ObjectStorageProviderId.aliyun:
      final bucketless = host.contains('.oss-')
          ? host.substring(host.indexOf('.oss-') + 1)
          : host;
      return [bucketless.replaceAll('.aliyuncs.com', '')];
    case ObjectStorageProviderId.tencent:
      final match = RegExp(
        r'cos\.([a-z0-9-]+)\.myqcloud\.com',
      ).firstMatch(host);
      return [if (match != null) match.group(1)!];
    case ObjectStorageProviderId.qiniu:
      final match = RegExp(r's3\.([a-z0-9-]+)\.qiniucs\.com').firstMatch(host);
      return [if (match != null) match.group(1)!];
    case ObjectStorageProviderId.huawei:
      final match = RegExp(
        r'obs\.([a-z0-9-]+)\.myhuaweicloud\.com',
      ).firstMatch(host);
      return [if (match != null) match.group(1)!];
    case ObjectStorageProviderId.volcengine:
      final match = RegExp(
        r'tos-s3-([a-z0-9-]+)\.volces\.com',
      ).firstMatch(host);
      return [if (match != null) match.group(1)!];
    case ObjectStorageProviderId.aws:
      final match = RegExp(
        r's3\.([a-z0-9-]+)\.amazonaws\.com',
      ).firstMatch(host);
      return [if (match != null) match.group(1)!];
    case ObjectStorageProviderId.r2:
    case ObjectStorageProviderId.minio:
    case ObjectStorageProviderId.custom:
      return const [];
  }
}

String? objectStorageRegionLabel({
  required ObjectStorageProviderId providerId,
  required String regionId,
}) {
  for (final region in ObjectStorageProvider.byId(providerId).regions) {
    if (region.id == regionId) return region.label;
  }
  return regionId.isEmpty ? null : regionId;
}

ObjectStorageConfiguration resolveObjectStorageConfiguration({
  required ObjectStorageProviderId providerId,
  required String bucket,
  required String accessKeyId,
  required String secretAccessKey,
  String regionId = '',
  String prefix = 'leeef',
  String customEndpoint = '',
  bool? pathStyle,
  String sessionToken = '',
  String accountId = '',
}) {
  final provider = ObjectStorageProvider.byId(providerId);
  final resolvedRegion = regionId.trim().isEmpty
      ? provider.defaultRegion
      : regionId.trim();
  final endpoint = customEndpoint.trim().isNotEmpty
      ? customEndpoint.trim()
      : provider.endpointFor(regionId: resolvedRegion, accountId: accountId);
  return ObjectStorageConfiguration(
    providerId: providerId,
    endpoint: endpoint,
    bucket: bucket.trim(),
    region: resolvedRegion,
    prefix: prefix.trim(),
    pathStyle: pathStyle ?? provider.pathStyle,
    accessKeyId: accessKeyId.trim(),
    secretAccessKey: secretAccessKey,
    sessionToken: sessionToken.trim(),
    accountId: accountId.trim(),
  );
}

String? validateObjectStorageConfiguration(
  ObjectStorageConfiguration configuration,
) {
  final provider = ObjectStorageProvider.byId(configuration.providerId);
  if (configuration.accessKeyId.isEmpty ||
      configuration.secretAccessKey.isEmpty ||
      configuration.bucket.isEmpty) {
    return '请填写完整的存储配置。';
  }
  if (provider.needsAccountId && configuration.accountId.isEmpty) {
    return '请填写完整的存储配置。';
  }
  final endpoint = Uri.tryParse(configuration.endpoint);
  if (endpoint == null ||
      (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
      endpoint.host.isEmpty) {
    return '请填写完整的存储配置。';
  }
  if (provider.needsRegion && configuration.region.isEmpty) {
    return '请填写完整的存储配置。';
  }
  return null;
}
