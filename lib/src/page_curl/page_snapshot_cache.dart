import 'dart:collection';
import 'dart:ui' as ui;

enum PageSnapshotSlot { previous, current, next }

class PageSnapshotKey {
  const PageSnapshotKey({
    required this.bookId,
    required this.locator,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.themeRevision,
    required this.slot,
  });

  final String bookId;
  final String locator;
  final int viewportWidth;
  final int viewportHeight;
  final int themeRevision;
  final PageSnapshotSlot slot;

  @override
  bool operator ==(Object other) =>
      other is PageSnapshotKey &&
      other.bookId == bookId &&
      other.locator == locator &&
      other.viewportWidth == viewportWidth &&
      other.viewportHeight == viewportHeight &&
      other.themeRevision == themeRevision &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(
    bookId,
    locator,
    viewportWidth,
    viewportHeight,
    themeRevision,
    slot,
  );
}

abstract interface class PageSnapshotSource {
  Future<ui.Image> capture(PageSnapshotKey key);
}

class PageSnapshotCache {
  PageSnapshotCache({required PageSnapshotSource source, this.capacity = 3})
    : assert(capacity > 0),
      _source = source;

  final PageSnapshotSource _source;
  final int capacity;
  final LinkedHashMap<PageSnapshotKey, ui.Image> _images = LinkedHashMap();
  final Map<PageSnapshotKey, Future<ui.Image>> _inFlight = {};

  Future<ui.Image> get(PageSnapshotKey key) async {
    final image = await _load(key);
    return image.clone();
  }

  Future<void> prefetch(Iterable<PageSnapshotKey> keys) async {
    await Future.wait(keys.map(_load));
  }

  Future<ui.Image> _load(PageSnapshotKey key) async {
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return cached;
    }
    final existingRequest = _inFlight[key];
    if (existingRequest != null) return existingRequest;

    final request = _source.capture(key).then((image) {
      _images[key] = image;
      _evictIfNeeded();
      return image;
    });
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  void _evictIfNeeded() {
    while (_images.length > capacity) {
      final oldestKey = _images.keys.first;
      _images.remove(oldestKey)?.dispose();
    }
  }
}
