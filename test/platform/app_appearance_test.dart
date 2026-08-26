import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';

void main() {
  test('core interface text is localized to English and Japanese', () {
    final english = AppStrings(const Locale('en'));
    final japanese = AppStrings(const Locale('ja'));

    expect(english.library, 'Library');
    expect(english.text('开始使用'), 'Get started');
    expect(english.text('阶段汇总'), 'Period summary');
    expect(english.text('自动同步'), 'Automatic sync');
    expect(english.text('配置 WebDAV'), 'Configure WebDAV');
    expect(english.failure('读取书库', 'offline'), 'Load library failed: offline');
    expect(english.deleteExcerpts(3), 'Delete 3 excerpts?');
    expect(japanese.settings, '設定');
    expect(japanese.text('AI 阅读助手'), 'AI 読書アシスタント');
    expect(japanese.text('界面语言'), '表示言語');
    expect(japanese.text('同步方式'), '同期方法');
    expect(japanese.backupCompleted(2, 4), '2 冊の本と 4 個のファイルをバックアップしました');
  });

  test('unknown text safely falls back to source language', () {
    expect(AppStrings(const Locale('en')).text('未登记文案'), '未登记文案');
  });
}
