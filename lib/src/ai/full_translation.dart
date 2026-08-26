import 'package:leeef_reader/src/ai/translation_provider.dart';

enum TranslationDisplayMode { translated, bilingual, original }

class FullTranslationProgress {
  const FullTranslationProgress({
    required this.completed,
    required this.total,
    required this.output,
  });
  final int completed;
  final int total;
  final String output;
  double get fraction => total == 0 ? 0 : completed / total;
}

class FullTranslationController {
  FullTranslationController({required TranslationProvider provider})
    : _provider = provider;
  final TranslationProvider _provider;
  TranslationCancellationToken? _token;

  void cancel() => _token?.cancel();

  Future<String> translate({
    required String text,
    required String targetLanguage,
    TranslationDisplayMode mode = TranslationDisplayMode.bilingual,
    Map<String, String> glossary = const {},
    void Function(FullTranslationProgress progress)? onProgress,
  }) async {
    cancel();
    final token = TranslationCancellationToken();
    _token = token;
    final chunks = _chunks(text);
    final output = <String>[];
    String previous = '';
    for (var index = 0; index < chunks.length; index++) {
      token.throwIfCancelled();
      final original = chunks[index];
      final glossaryText = glossary.entries
          .map((item) => '${item.key} → ${item.value}')
          .join('\n');
      final translated = await _provider.translate(
        TranslationRequest(
          text: original,
          targetLanguage: targetLanguage,
          context: [
            if (glossaryText.isNotEmpty) '必须遵循术语表：\n$glossaryText',
            if (previous.isNotEmpty) '上一段译文（用于保持衔接、人名和语气）：\n$previous',
            '这是长文本的第 ${index + 1}/${chunks.length} 段。只翻译本段，保持段落结构。',
          ].join('\n\n'),
        ),
        cancellationToken: token,
      );
      previous = translated;
      output.add(switch (mode) {
        TranslationDisplayMode.original => original,
        TranslationDisplayMode.translated => translated,
        TranslationDisplayMode.bilingual => '$original\n\n$translated',
      });
      onProgress?.call(
        FullTranslationProgress(
          completed: index + 1,
          total: chunks.length,
          output: output.join('\n\n'),
        ),
      );
    }
    return output.join('\n\n');
  }

  static List<String> _chunks(String value, {int maximumLength = 3500}) {
    final paragraphs = value.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    var current = StringBuffer();
    void flush() {
      final text = current.toString().trim();
      if (text.isNotEmpty) chunks.add(text);
      current = StringBuffer();
    }

    for (final paragraph in paragraphs) {
      if (paragraph.length > maximumLength) {
        flush();
        for (var start = 0; start < paragraph.length; start += maximumLength) {
          chunks.add(
            paragraph.substring(
              start,
              (start + maximumLength).clamp(0, paragraph.length),
            ),
          );
        }
      } else if (current.length + paragraph.length + 2 > maximumLength) {
        flush();
        current.write(paragraph);
      } else {
        if (current.isNotEmpty) current.write('\n\n');
        current.write(paragraph);
      }
    }
    flush();
    if (chunks.isEmpty) throw ArgumentError('Text is empty.');
    return chunks;
  }
}
