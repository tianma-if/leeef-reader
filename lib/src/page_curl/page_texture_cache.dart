import 'dart:collection';
import 'dart:ui' as ui;

class PageTextureCache<K> {
  PageTextureCache({this.capacity = 3}) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, ui.Image> _images = LinkedHashMap();
  final Map<K, Future<ui.Image>> _inFlight = {};
  bool _disposed = false;

  Future<ui.Image> get(K key, Future<ui.Image> Function() loader) async {
    final image = await _load(key, loader);
    return image.clone();
  }

  Future<void> prefetch(K key, Future<ui.Image> Function() loader) async {
    await _load(key, loader);
  }

  Future<ui.Image> _load(K key, Future<ui.Image> Function() loader) async {
    if (_disposed) throw StateError('PageTextureCache has been disposed.');
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return cached;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final request = loader().then((image) {
      if (_disposed) {
        image.dispose();
        throw StateError('PageTextureCache was disposed while rendering.');
      }
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

  void dispose() {
    _disposed = true;
    clear();
  }

  void _evictIfNeeded() {
    while (_images.length > capacity) {
      _images.remove(_images.keys.first)?.dispose();
    }
  }
}
