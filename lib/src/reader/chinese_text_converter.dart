import 'package:pinyin/pinyin.dart';

/// Phrase-aware pure Dart display conversion. Source text is never persisted, so
/// switching back to `original` is lossless.
class ChineseTextConverter {
  const ChineseTextConverter();

  String convert(String text, String mode) {
    if (mode == 'original' || text.isEmpty) return text;
    return mode == 'traditional'
        ? ChineseHelper.convertToTraditionalChinese(text)
        : ChineseHelper.convertToSimplifiedChinese(text);
  }

  List<String> convertAll(List<String> texts, String mode) {
    if (mode == 'original' || texts.isEmpty) return texts;
    return [for (final text in texts) convert(text, mode)];
  }
}
