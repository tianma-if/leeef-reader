import 'dart:async';
import 'dart:io';

class ReaderBookSource {
  const ReaderBookSource({
    required this.bookId,
    required this.file,
    required this.mediaType,
  });

  final String bookId;
  final File file;
  final String mediaType;
}

class ReaderBookInfo {
  const ReaderBookInfo({required this.title, required this.toc, this.author});

  final String title;
  final String? author;
  final List<ReaderTocItem> toc;
}

class ReaderTocItem {
  const ReaderTocItem({
    required this.label,
    required this.href,
    this.children = const [],
  });

  final String label;
  final String href;
  final List<ReaderTocItem> children;
}

sealed class ReaderEvent {
  const ReaderEvent();
}

class ReaderRelocated extends ReaderEvent {
  const ReaderRelocated({
    required this.cfi,
    required this.fraction,
    this.chapterTitle,
  });

  final String cfi;
  final double fraction;
  final String? chapterTitle;
}

class ReaderSelectionChanged extends ReaderEvent {
  const ReaderSelectionChanged({required this.quote, required this.cfi});

  final String quote;
  final String cfi;
}

class ReaderFailure extends ReaderEvent {
  const ReaderFailure(this.message);

  final String message;
}

/// Format-independent contract consumed by the reader UI and page curl layer.
abstract interface class ReaderEngine {
  Stream<ReaderEvent> get events;

  Future<ReaderBookInfo> open(
    ReaderBookSource source, {
    String? initialLocator,
  });

  Future<void> goTo(String locator);

  Future<void> next();

  Future<void> previous();

  Future<void> close();
}
