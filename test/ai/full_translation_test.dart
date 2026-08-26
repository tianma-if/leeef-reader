import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/ai/full_translation.dart';
import 'package:leeef_reader/src/ai/translation_provider.dart';

void main() {
  test(
    'chunks long text, carries context, applies glossary, and reports progress',
    () async {
      final provider = _Provider();
      final progress = <FullTranslationProgress>[];
      final result = await FullTranslationController(provider: provider)
          .translate(
            text: '${'a' * 3600}\n\nsecond paragraph',
            targetLanguage: '中文',
            glossary: const {'Leeef': '叶读'},
            onProgress: progress.add,
          );
      expect(provider.requests.length, 3);
      expect(provider.requests.first.context, contains('Leeef → 叶读'));
      expect(provider.requests[1].context, contains('上一段译文'));
      expect(progress.last.fraction, 1);
      expect(result, contains('translated-3'));
    },
  );

  test('cancellation stops subsequent chunks', () async {
    final provider = _Provider();
    final controller = FullTranslationController(provider: provider);
    final future = controller.translate(
      text: '${'a' * 4000}\n\nmore',
      targetLanguage: '中文',
    );
    controller.cancel();
    await expectLater(future, throwsA(isA<TranslationCancelled>()));
  });
}

class _Provider implements TranslationProvider {
  final requests = <TranslationRequest>[];
  @override
  Future<String> translate(
    TranslationRequest request, {
    TranslationCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    requests.add(request);
    await Future<void>.delayed(Duration.zero);
    cancellationToken?.throwIfCancelled();
    return 'translated-${requests.length}';
  }
}
