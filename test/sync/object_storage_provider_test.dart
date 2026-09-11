import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/object_storage_provider.dart';

void main() {
  test('Aliyun region maps to the official OSS endpoint', () {
    final configuration = resolveObjectStorageConfiguration(
      providerId: ObjectStorageProviderId.aliyun,
      bucket: 'leeef-books',
      accessKeyId: 'id',
      secretAccessKey: 'secret',
      regionId: 'oss-cn-hangzhou',
    );

    expect(configuration.endpoint, 'https://oss-cn-hangzhou.aliyuncs.com');
    expect(configuration.region, 'oss-cn-hangzhou');
    expect(configuration.pathStyle, isFalse);
    expect(validateObjectStorageConfiguration(configuration), isNull);
  });

  test('Tencent, Qiniu, Huawei and R2 resolve vendor endpoints', () {
    expect(
      resolveObjectStorageConfiguration(
        providerId: ObjectStorageProviderId.tencent,
        bucket: 'example-1250000000',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
        regionId: 'ap-beijing',
      ).endpoint,
      'https://cos.ap-beijing.myqcloud.com',
    );
    expect(
      resolveObjectStorageConfiguration(
        providerId: ObjectStorageProviderId.qiniu,
        bucket: 'space',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
        regionId: 'cn-east-1',
      ).endpoint,
      'https://s3.cn-east-1.qiniucs.com',
    );
    expect(
      resolveObjectStorageConfiguration(
        providerId: ObjectStorageProviderId.huawei,
        bucket: 'bucket',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
        regionId: 'cn-north-4',
      ).endpoint,
      'https://obs.cn-north-4.myhuaweicloud.com',
    );
    expect(
      resolveObjectStorageConfiguration(
        providerId: ObjectStorageProviderId.r2,
        bucket: 'library',
        accessKeyId: 'id',
        secretAccessKey: 'secret',
        accountId: 'abc123',
      ).endpoint,
      'https://abc123.r2.cloudflarestorage.com',
    );
  });

  test('custom endpoint override wins over the generated vendor endpoint', () {
    final configuration = resolveObjectStorageConfiguration(
      providerId: ObjectStorageProviderId.aliyun,
      bucket: 'leeef-books',
      accessKeyId: 'id',
      secretAccessKey: 'secret',
      regionId: 'oss-cn-beijing',
      customEndpoint: 'https://oss-cn-beijing-internal.aliyuncs.com',
      pathStyle: true,
    );

    expect(
      configuration.endpoint,
      'https://oss-cn-beijing-internal.aliyuncs.com',
    );
    expect(configuration.pathStyle, isTrue);
  });

  test('existing endpoints restore the matching vendor and region', () {
    expect(
      inferObjectStorageProvider(
        endpoint: 'https://oss-cn-shanghai.aliyuncs.com',
      ),
      ObjectStorageProviderId.aliyun,
    );
    expect(
      inferObjectStorageRegion(
        providerId: ObjectStorageProviderId.aliyun,
        endpoint: 'https://my-bucket.oss-cn-shanghai.aliyuncs.com',
      ),
      'oss-cn-shanghai',
    );
    expect(
      inferObjectStorageProvider(
        endpoint: 'https://cos.ap-guangzhou.myqcloud.com',
      ),
      ObjectStorageProviderId.tencent,
    );
    expect(
      inferObjectStorageAccountId('https://abc123.r2.cloudflarestorage.com'),
      'abc123',
    );
  });

  test('incomplete forms are rejected before saving', () {
    expect(
      validateObjectStorageConfiguration(
        resolveObjectStorageConfiguration(
          providerId: ObjectStorageProviderId.aliyun,
          bucket: '',
          accessKeyId: 'id',
          secretAccessKey: 'secret',
        ),
      ),
      '请填写完整的存储配置。',
    );
    expect(
      validateObjectStorageConfiguration(
        resolveObjectStorageConfiguration(
          providerId: ObjectStorageProviderId.minio,
          bucket: 'library',
          accessKeyId: 'id',
          secretAccessKey: 'secret',
        ),
      ),
      '请填写完整的存储配置。',
    );
    expect(
      validateObjectStorageConfiguration(
        resolveObjectStorageConfiguration(
          providerId: ObjectStorageProviderId.r2,
          bucket: 'library',
          accessKeyId: 'id',
          secretAccessKey: 'secret',
        ),
      ),
      '请填写完整的存储配置。',
    );
  });
}
