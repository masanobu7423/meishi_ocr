import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/romaji.dart';

void main() {
  group('fixRomanSpacing', () {
    test('glues a 1-2 letter lowercase fragment back onto the previous word', () {
      expect(fixRomanSpacing('Misaki Takahash i'), 'Misaki Takahashi');
      expect(fixRomanSpacing('Taka hashi Misaki'), 'Takahashi Misaki');
    });
    test('leaves real two-word names alone', () {
      expect(fixRomanSpacing('Ken Sasaki'), 'Ken Sasaki');
      expect(fixRomanSpacing('SUZUKI Ichiro'), 'SUZUKI Ichiro');
    });
  });

  group('romanToKana', () {
    test('converts Hepburn syllables including digraphs and sokuon', () {
      expect(romanToKana('Takahashi'), 'タカハシ');
      expect(romanToKana('Shunsuke'), 'シュンスケ');
      expect(romanToKana('Tsuchiya'), 'ツチヤ');
      expect(romanToKana('Hattori'), 'ハットリ');
      expect(romanToKana('Itoh'), 'イトウ');
      expect(romanToKana('Ryo'), 'リョ');
    });
    test('returns null when the text is not plain romaji', () {
      expect(romanToKana('山田'), isNull);
      expect(romanToKana('Mc Donald'), isNull);
    });
  });

  group('kanaName', () {
    test('family name first: ALL-CAPS token is the family name', () {
      expect(kanaName('SUZUKI Ichiro'), 'スズキ イチロ');
    });
    test('Given Family order is flipped to Japanese order', () {
      expect(kanaName('Taro Yamada'), 'ヤマダ タロ');
      expect(kanaName('Misaki Takahashi'), 'タカハシ ミサキ');
    });
  });
}
