import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/deskew.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

OcrLine _l(String t, double angle, {double w = 300, double h = 30}) =>
    OcrLine(t, width: w, height: h, angle: angle);

void main() {
  test('OcrLine keeps the angle through JSON', () {
    final j = _l('x', -7.5).toJson();
    expect(j['a'], -7.5);
    expect(OcrLine.fromJson(j).angle, -7.5);
    expect(OcrLine.fromJson({'text': 'old dump'}).angle, 0);
  });

  test('skewAngle is the median angle of wide (horizontal) lines', () {
    final lines = [
      _l('株式会社サンライズ', -6.2),
      _l('山田 太郎', -5.8),
      _l('TEL 03-1234-5678', -6.0),
      _l('〒150-0001 東京都', -6.4),
      _l('|', 40, w: 20, h: 300), // vertical sliver: ignored
    ];
    expect(skewAngle(lines), closeTo(-6.1, 0.01));
  });

  test('skewAngle still sees a 20° card whose axis-aligned boxes are only 2:1', () {
    // Device dump k06_rot20: ML Kit reports angle -20 and boxes with w/h ~ 2.
    final lines = [
      _l('株式会社サンライズ', -20.2, w: 313, h: 146),
      _l('営業部 部長', -19.7, w: 154, h: 79),
      _l('山田 太郎', -20.0, w: 353, h: 192),
      _l('TEL 03-1234-5678', -19.9, w: 408, h: 169),
    ];
    expect(skewAngle(lines), closeTo(-19.95, 0.01));
  });

  test('skewAngle is null when the tilt is negligible or there are too few lines', () {
    expect(skewAngle([_l('a', 0.5), _l('b', -0.8), _l('c', 1.0)]), isNull);
    expect(skewAngle([_l('a', -9), _l('b', -9)]), isNull);
    expect(skewAngle(const []), isNull);
  });
}
