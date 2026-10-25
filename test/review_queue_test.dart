import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/review_queue.dart';

void main() {
  test('empty queue has no current item', () {
    final q = ReviewQueue<String>();
    expect(q.current, isNull);
    expect(q.label, '');
  });

  test('next/prev move within bounds and label shows position', () {
    final q = ReviewQueue<String>(['a', 'b', 'c']);
    expect(q.current, 'a');
    expect(q.label, '1/3');
    expect(q.prev(), isFalse);
    expect(q.next(), isTrue);
    expect(q.current, 'b');
    q.next();
    expect(q.next(), isFalse);
    expect(q.current, 'c');
    expect(q.label, '3/3');
  });

  test('clear resets the position so a smaller next batch cannot go out of range', () {
    final q = ReviewQueue<String>(['a', 'b', 'c', 'd', 'e'])..next()..next()..next()..next();
    q.clear();
    expect(q.current, isNull);
    expect(q.label, '');
    q.items.addAll(['x', 'y']);
    expect(q.current, 'x');
    expect(q.label, '1/2');
  });

  test('removeCurrent drops the item and keeps a valid position', () {
    final q = ReviewQueue<String>(['a', 'b', 'c'])..next()..next();
    q.removeCurrent();
    expect(q.current, 'b');
    expect(q.label, '2/2');
    q.removeCurrent();
    q.removeCurrent();
    expect(q.current, isNull);
  });

  test('shotStems names a burst of captures uniquely and file-safely', () {
    final stems = shotStems(DateTime(2026, 10, 25, 18, 12, 7, 42), 3);
    expect(stems,
        ['shot_20261025-181207042_1', 'shot_20261025-181207042_2', 'shot_20261025-181207042_3']);
    expect(stems.toSet().length, 3);
    expect(shotStems(DateTime(2026, 10, 25, 18, 12, 7, 43), 1), isNot(stems.sublist(0, 1)));
    expect(stems.every((s) => RegExp(r'^[\w-]+$').hasMatch(s)), isTrue);
    expect(shotStems(DateTime(2026), 0), isEmpty);
  });
}
