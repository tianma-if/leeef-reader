import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('core interface text is localized to English and Japanese', () {
    final english = AppStrings(const Locale('en'));
    final japanese = AppStrings(const Locale('ja'));

    expect(english.library, 'Library');
    expect(english.text('开始使用'), 'Get started');
    expect(english.text('阶段汇总'), 'Period summary');
    expect(english.text('自动同步'), 'Automatic sync');
    expect(english.text('配置 WebDAV'), 'Configure WebDAV');
    expect(english.text('配置对象存储'), 'Configure object storage');
    expect(english.text('阿里云 OSS'), 'Aliyun OSS');
    expect(english.text('生成配对二维码'), 'Generate pairing QR code');
    expect(english.text('扫描配对二维码'), 'Scan pairing QR code');
    expect(
      english.text('在电脑上配置后会自动同步到此设备'),
      'Configure on a computer; it will sync to this device',
    );
    expect(english.text('已从电脑同步'), 'Synced from a computer');
    expect(english.text('同步存储'), 'Sync storage');
    expect(english.text('扫码同步'), 'Scan to sync');
    expect(english.failure('读取书库', 'offline'), 'Load library failed: offline');
    expect(english.deleteExcerpts(3), 'Delete 3 excerpts?');
    expect(japanese.settings, '設定');
    expect(japanese.text('AI 阅读助手'), 'AI 読書アシスタント');
    expect(japanese.text('界面语言'), '表示言語');
    expect(japanese.text('同步方式'), '同期方法');
    expect(japanese.text('已从电脑同步'), 'パソコンから同期済み');
    expect(japanese.backupCompleted(2, 4), '2 冊の本と 4 個のファイルをバックアップしました');
  });

  test('unknown text safely falls back to source language', () {
    expect(AppStrings(const Locale('en')).text('未登记文案'), '未登记文案');
  });

  test(
    'setThemeMode notifies listeners before persistence completes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final appearance = AppAppearanceController.instance;
      appearance.themeMode = ThemeMode.system;
      var notifications = 0;
      void listener() => notifications++;
      appearance.addListener(listener);
      addTearDown(() {
        appearance.removeListener(listener);
        appearance.themeMode = ThemeMode.system;
      });

      final future = appearance.setThemeMode(ThemeMode.dark);
      expect(appearance.themeMode, ThemeMode.dark);
      expect(notifications, 1);
      await future;
    },
  );
}
