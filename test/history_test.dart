import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/history.dart';

const _a = '''---
type: meishi
name: 山田 太郎
company: 株式会社サンライズ
title: 部長
scanned: 2026-10-24
source: k01.json
image_front: images/k01_front.jpg
memo: 展示会で名刺交換
tags: [名刺]
---
''';
const _b = '''---
type: meishi
name: 鈴木 一郎
company: トビショク商事
scanned: 2026-10-25
source: k02.json
tags: [名刺]
---
''';
const _index = '''---
type: meishi_index
count: 2
---
''';

void main() {
  test('cardSummaries lists card notes newest first and skips the index', () {
    final s = cardSummaries({'山田_太郎_2026-10-24': _a, '_名刺一覧': _index, '鈴木_一郎_2026-10-25': _b});
    expect(s.map((c) => c.name), ['鈴木 一郎', '山田 太郎']);
    expect(s.last.company, '株式会社サンライズ');
    expect(s.last.title, '部長');
    expect(s.last.stem, 'k01');
    expect(s.last.imageFront, 'images/k01_front.jpg');
    expect(s.last.memo, '展示会で名刺交換');
    expect(s.first.imageFront, isNull);
  });

  test('matches searches name, company, title and memo, case/width-insensitively', () {
    final s = cardSummaries({'a': _a, 'b': _b});
    expect(s.where((c) => c.matches('山田')).length, 1);
    expect(s.where((c) => c.matches('サンライズ')).length, 1);
    expect(s.where((c) => c.matches('部長')).length, 1);
    expect(s.where((c) => c.matches('展示会')).length, 1);
    expect(s.where((c) => c.matches('')).length, 2);
    expect(s.where((c) => c.matches('ｻﾝﾗｲｽﾞ')).length, 1, reason: 'half-width katakana');
    expect(s.where((c) => c.matches('いない')).length, 0);
  });
}
