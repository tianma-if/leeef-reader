/// Bounded browser-style navigation history for page based readers.
class ReaderNavigationHistory {
  ReaderNavigationHistory({this.limit = 100}) : assert(limit > 1);

  final int limit;
  final List<int> _entries = [];
  int _index = -1;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _entries.length - 1;

  void reset(int page) {
    _entries
      ..clear()
      ..add(page);
    _index = 0;
  }

  void visit(int page) {
    if (_index >= 0 && _entries[_index] == page) return;
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(page);
    if (_entries.length > limit) _entries.removeAt(0);
    _index = _entries.length - 1;
  }

  int? back() {
    if (!canGoBack) return null;
    return _entries[--_index];
  }

  int? forward() {
    if (!canGoForward) return null;
    return _entries[++_index];
  }
}
