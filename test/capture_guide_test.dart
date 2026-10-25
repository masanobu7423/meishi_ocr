import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/capture_guide.dart';

void main() {
  test('frameToView rotates sensor-frame points into the preview box', () {
    const p = (x: 0.1, y: 0.3);
    expect(frameToView(p, rotation: 0), p);
    expect(frameToView(p, rotation: 90), (x: 0.7, y: 0.1));
    expect(frameToView(p, rotation: 180), (x: 0.9, y: 0.7));
    expect(frameToView(p, rotation: 270), (x: 0.3, y: 0.9));
  });

  test('viewToImage centres a preview that is narrower than the still', () {
    final m = viewToImage(const Size(300, 600), const Size(900, 1800));
    expect((m.s, m.offX, m.offY), (3.0, 0.0, 0.0));
    final wider = viewToImage(const Size(300, 600), const Size(1200, 1800)); // 4:3 still, 1:2 preview
    expect(wider.s, 3.0);
    expect(wider.offX, 150.0);
    expect(wider.offY, 0.0);
  });

  test('cropRect maps the guide onto the still with a margin, clamped to the image', () {
    const preview = Size(400, 800); // portrait preview box
    const still = Size(1200, 2400); // same aspect, 3x
    final g = guideRect(preview);
    final r = cropRect(preview, still, margin: 0);
    expect(r.left, closeTo(g.left * 3, 0.01));
    expect(r.width, closeTo(g.width * 3, 0.01));
    final m = cropRect(preview, still, margin: 0.05);
    expect(m.width, closeTo(g.width * 3 * 1.1, 0.01));
    expect(m.left, greaterThanOrEqualTo(0));
    expect(m.right, lessThanOrEqualTo(1200));
    // A huge margin never leaves the image.
    final big = cropRect(preview, still, margin: 5);
    expect(big, const Rect.fromLTWH(0, 0, 1200, 2400));
  });

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
