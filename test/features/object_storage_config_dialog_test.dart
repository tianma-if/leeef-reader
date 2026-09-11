import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/settings/object_storage_config_dialog.dart';
import 'package:leeef_reader/src/sync/object_storage_provider.dart';

void main() {
  testWidgets('Aliyun form hides Endpoint and saves the generated host', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ObjectStorageConfiguration? saved;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showObjectStorageConfigDialog(context: context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('配置对象存储'), findsOneWidget);
    expect(find.text('阿里云 OSS'), findsWidgets);
    expect(find.text('按云厂商填写控制台里的同名项目，不用自己拼 Endpoint。'), findsOneWidget);
    expect(_field('存储空间名'), findsOneWidget);
    expect(_field('AccessKey ID'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(_field('Endpoint'), findsNothing);

    await tester.enterText(_field('AccessKey ID'), 'LTAI-example');
    await tester.enterText(_field('AccessKey Secret'), 'secret-example');
    await tester.enterText(_field('存储空间名'), 'leeef-books');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.providerId, ObjectStorageProviderId.aliyun);
    expect(saved!.endpoint, 'https://oss-cn-hangzhou.aliyuncs.com');
    expect(saved!.bucket, 'leeef-books');
    expect(saved!.region, 'oss-cn-hangzhou');
    expect(saved!.pathStyle, isFalse);
  });

  testWidgets('switching to MinIO asks for an endpoint instead of a region', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showObjectStorageConfigDialog(context: context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'MinIO / NAS'));
    await tester.pumpAndSettle();

    expect(find.text('适用于 MinIO、群晖、威联通等兼容服务。填写局域网或公网的 S3 地址。'), findsOneWidget);
    expect(_field('Endpoint'), findsOneWidget);
    expect(find.text('http://192.168.1.10:9000'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
