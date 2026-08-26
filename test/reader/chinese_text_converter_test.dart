import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/reader/chinese_text_converter.dart';

void main() {
  const converter = ChineseTextConverter();

  test('converts between simplified and traditional Chinese', () {
    expect(converter.convert('阅读与书籍', 'traditional'), '閱讀與書籍');
    expect(converter.convert('閱讀與書籍', 'simplified'), '阅读与书籍');
  });

  test('original mode does not alter content', () {
    expect(converter.convert('原文 Mixed 123', 'original'), '原文 Mixed 123');
  });
}
