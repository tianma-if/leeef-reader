import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/reader/reader_navigation_history.dart';

void main() {
  test('supports browser-style back, forward, and branch replacement', () {
    final history = ReaderNavigationHistory()..reset(1);
    history
      ..visit(2)
      ..visit(8);

    expect(history.back(), 2);
    expect(history.back(), 1);
    expect(history.forward(), 2);
    history.visit(5);
    expect(history.canGoForward, isFalse);
    expect(history.back(), 2);
  });
}
