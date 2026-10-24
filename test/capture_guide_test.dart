import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/capture_guide.dart';

void main() {
  test('guide is a 91:55 card centred at 90 % of a portrait preview width', () {
    final r = guideRect(const Size(400, 800));
    expect(r.width, 360);
    expect(r.height, closeTo(360 * 55 / 91, 0.01));
    expect(r.center, const Offset(200, 400));
  });

  test('guide is limited by height on a wide landscape preview', () {
    final r = guideRect(const Size(1600, 300));
    expect(r.height, 270);
    expect(r.width, closeTo(270 * 91 / 55, 0.01));
    expect(r.center, const Offset(800, 150));
  });
}
