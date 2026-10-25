import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/burst.dart';

void main() {
  final t0 = DateTime(2026, 10, 25, 22, 0, 0, 1);

  test('front/back session: titles, file names, blank back, finish only between cards', () {
    final s = BurstSession(paired: true);
    expect(s.side, CardSide.front);
    expect(s.title, '表面を撮影（1 枚目）');
    expect(s.canFinish, isTrue);

    final front1 = s.nextName(t0);
    expect(front1, endsWith('_1_front'));
    expect(s.side, CardSide.back);
    expect(s.title, '裏面を撮影（1 枚目）');
    expect(s.canFinish, isFalse, reason: 'a card is half done');

    final back1 = s.nextName(t0);
    expect(back1, front1.replaceAll('_front', '_back'));
    expect(s.side, CardSide.front);
    expect(s.title, '表面を撮影（2 枚目）');

    s.nextName(DateTime(2026, 10, 25, 22, 0, 0, 2)); // front of card 2
    final blank = s.blankStem();
    expect(blank, isNotNull);
    expect(s.side, CardSide.front);
    expect(s.blankStem(), isNull, reason: 'nothing waiting for a back');
    expect((s.cards, s.backs), (2, 2));
    expect(s.summary, '2 枚を取込フォルダに保存しました（表 2 枚、裏 2 枚）。「まとめて取込」で読み取って、1 枚ずつ確認できます');
  });

  test('front-only session: every capture is a card and can always finish', () {
    final s = BurstSession(paired: false);
    expect(s.nextName(t0), isNot(contains('_front')));
    expect(s.side, CardSide.front);
    expect(s.canFinish, isTrue);
    expect(s.blankStem(), isNull);
    expect(s.title, '表面を撮影（2 枚目）');
    expect(s.summary, '1 枚を取込フォルダに保存しました。「まとめて取込」で読み取って、1 枚ずつ確認できます');
    expect(BurstSession(paired: false).summary, isNull, reason: 'nothing saved, nothing to say');
  });
}
