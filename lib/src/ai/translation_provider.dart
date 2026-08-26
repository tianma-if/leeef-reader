import 'dart:async';

class TranslationRequest {
  const TranslationRequest({
    required this.text,
    required this.context,
    this.targetLanguage = '简体中文',
  });

  final String text;
  final String context;
  final String targetLanguage;
}

abstract interface class TranslationProvider {
  Future<String> translate(
    TranslationRequest request, {
    TranslationCancellationToken? cancellationToken,
  });
}

class TranslationCancelled implements Exception {
  const TranslationCancelled();
  @override
  String toString() => 'Translation cancelled.';
}

class TranslationCancellationToken {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const TranslationCancelled();
  }
}

abstract interface class TranslationCache {
  Future<String?> get(String key);
  Future<void> put(String key, String value);
}

class MemoryTranslationCache implements TranslationCache {
  final _values = <String, String>{};
  @override
  Future<String?> get(String key) async => _values[key];
  @override
  Future<void> put(String key, String value) async => _values[key] = value;
}
