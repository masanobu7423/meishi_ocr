import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/learned.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

OcrLine _l(String t, {double h = 20, double w = 200}) => OcrLine(t, width: w, height: h);

void main() {
  group('Learned.learn', () {
    test('remembers a line the user moved into a field', () {
      final lines = [_l('トビショク商事', h: 26), _l('鈴木 一郎', h: 50)];
      final learned = Learned();
      learned.learn(
        guess: {'company': null, 'name': '鈴木 一郎'},
        corrected: {'company': 'トビショク商事', 'name': '鈴木 一郎'},
        lines: lines,
      );
      expect(learned.fieldFor('トビショク商事'), 'company');
      expect(learned.fieldFor('鈴木 一郎'), isNull, reason: 'unchanged fields are not learned');
    });

    test('learns a title word the built-in list does not know', () {
      final learned = Learned()
        ..learn(
          guess: {'title': null},
          corrected: {'title': 'フェロー'},
          lines: [_l('フェロー')],
        );
      expect(learned.terms['title'], contains('フェロー'));
    });

    test('a multi-word line goes to line memory, not to the vocabulary', () {
      final learned = Learned()
        ..learn(guess: {'title': '部長'}, corrected: {'title': '営業部 部長'}, lines: [_l('営業部 部長')]);
      expect(learned.fieldFor('営業部 部長'), 'title');
      expect(learned.terms['title'] ?? const [], isEmpty);
    });

    test('counts a character confusion when the correction is a 1-char edit', () {
      final learned = Learned();
      for (var i = 0; i < 2; i++) {
        learned.learn(
          guess: {'name': '田中 健ニ'},
          corrected: {'name': '田中 健二'},
          lines: [_l('田中 健ニ', h: 50)],
        );
      }
      expect(learned.confusions['ニ→二'], 2);
      expect(learned.fix('山田 健ニ'), '山田 健二');
      expect(Learned().fix('山田 健ニ'), '山田 健ニ', reason: 'nothing learned, nothing changed');
    });

    test('a confusion seen once is not applied yet', () {
      final learned = Learned()
        ..learn(guess: {'name': '健ニ'}, corrected: {'name': '健二'}, lines: [_l('健ニ', h: 50)]);
      expect(learned.fix('健ニ'), '健ニ');
    });

    test('round-trips through JSON', () {
      final learned = Learned()
        ..learn(
          guess: {'company': null, 'title': null, 'name': '健ニ'},
          corrected: {'company': 'トビショク商事', 'title': 'フェロー', 'name': '健二'},
          lines: [_l('トビショク商事'), _l('フェロー'), _l('健ニ', h: 50)],
        );
      final back = Learned.fromJson(jsonDecode(jsonEncode(learned.toJson())) as Map<String, dynamic>);
      expect(back.fieldFor('トビショク商事'), 'company');
      expect(back.terms['title'], ['フェロー']);
      expect(back.confusions['ニ→二'], 1);
    });
  });

  group('extract with Learned', () {
    test('a remembered company line wins over the tallest-line fallback', () {
      // Without memory: company falls back to the tallest remaining CJK line
      // that is not the name -> "営業推進グループ" would be wrong anyway, but
      // here the real company has no 株式会社 keyword and is small.
      final lines = [
        _l('ABC', h: 18, w: 60),
        _l('営業推進', h: 30),
        _l('佐々木 健', h: 50),
        _l('TEL 03-0000-0000', h: 18),
      ];
      expect(extract(lines).company, '営業推進');
      final learned = Learned()
        ..learn(guess: {'company': '営業推進', 'dept': null},
            corrected: {'company': 'ABC', 'dept': '営業推進'}, lines: lines);
      final f = extract(lines, learned: learned);
      expect(f.company, 'ABC');
      expect(f.dept, '営業推進');
      expect(f.name, '佐々木 健');
    });

    test('a learned title term is matched like a built-in one', () {
      final lines = [_l('株式会社X', h: 28), _l('フェロー', h: 20), _l('山田 太郎', h: 50)];
      expect(extract(lines).title, isNull);
      final learned = Learned()..terms['title'] = ['フェロー'];
      expect(extract(lines, learned: learned).title, 'フェロー');
    });

    test('learned confusions are applied to the name', () {
      final lines = [_l('株式会社X', h: 28), _l('田中 健ニ', h: 50)];
      final learned = Learned()..confusions['ニ→二'] = 2;
      expect(extract(lines, learned: learned).name, '田中 健二');
    });
  });
}
