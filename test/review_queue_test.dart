import 'dart:io';

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

  test('pairInboxFiles joins *_front/*_back by stem; other files are fronts', () {
    final files = [
      File('/in/shot_1_back.jpg'),
      File('/in/shot_1_front.jpg'),
      File('/in/k01.png'),
      File('/in/shot_2_front.jpg'),
      File('/in/orphan_back.jpg'),
    ];
    final pairs = pairInboxFiles(files);
    expect(pairs.map((p) => (p.stem, p.front.path, p.back?.path)), [
      ('k01', '/in/k01.png', null),
      ('orphan', '/in/orphan_back.jpg', null),
      ('shot_1', '/in/shot_1_front.jpg', '/in/shot_1_back.jpg'),
      ('shot_2', '/in/shot_2_front.jpg', null),
    ]);
  });

  test('burstPauseText reports what is saved and which side comes next', () {
    expect(burstPauseText(3, 2, paired: true, nextIsBack: true), '保存 3 枚（表 3 枚、裏 2 枚）。次は裏面です');
    expect(burstPauseText(3, 3, paired: true, nextIsBack: false), '保存 3 枚（表 3 枚、裏 3 枚）。次は表面です');
    expect(burstPauseText(0, 0, paired: true, nextIsBack: false), 'まだ保存していません。次は表面です');
    expect(burstPauseText(4, 0, paired: false, nextIsBack: false), '保存 4 枚');
    expect(burstPauseText(0, 0, paired: false, nextIsBack: false), 'まだ保存していません');
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
