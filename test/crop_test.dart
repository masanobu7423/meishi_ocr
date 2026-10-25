import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meishi_ocr/ocr/capture_guide.dart';
import 'package:meishi_ocr/ocr/crop.dart';

void main() {
  test('rectifyToQuad straightens a tilted dark card into a 91:55 image', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_rect_');
    addTearDown(() => tmp.delete(recursive: true));
    final still = img.Image(width: 600, height: 1200)..clear(img.ColorRgb8(250, 250, 250));
    const quad = [(x: 0.2, y: 0.3), (x: 0.85, y: 0.35), (x: 0.8, y: 0.7), (x: 0.15, y: 0.62)];
    final pts = [for (final q in quad) img.Point(q.x * 600, q.y * 1200)];
    img.fillPolygon(still, vertices: pts, color: img.ColorRgb8(40, 40, 40));
    final src = await File('${tmp.path}/still.jpg').writeAsBytes(img.encodeJpg(still));

    final out = await rectifyToQuad(src, quad, const Size(600, 1200));
    final card = img.decodeJpg(await out.readAsBytes())!;
    expect((card.width, card.height), (rectifiedWidth, rectifiedHeight));
    for (final (x, y) in [(0.5, 0.5), (0.05, 0.05), (0.95, 0.05), (0.95, 0.95), (0.05, 0.95)]) {
      final p = card.getPixel((x * card.width).round(), (y * card.height).round());
      expect(p.r, lessThan(90), reason: 'inside the card at ($x, $y)');
    }
  });

  test('cropToGuide writes a new JPEG holding the guide area of the still', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_crop_');
    addTearDown(() => tmp.delete(recursive: true));
    // Portrait still 600x1200: white, with a dark card drawn where the guide is.
    final still = img.Image(width: 600, height: 1200)..clear(img.ColorRgb8(250, 250, 250));
    const preview = Size(300, 600);
    final g = cropRect(preview, const Size(600, 1200), margin: 0);
    img.fillRect(still,
        x1: g.left.round(), y1: g.top.round(), x2: g.right.round() - 1, y2: g.bottom.round() - 1,
        color: img.ColorRgb8(40, 40, 40));
    final src = await File('${tmp.path}/still.jpg').writeAsBytes(img.encodeJpg(still));

    final out = await cropToGuide(src, preview);
    expect(out.path, isNot(src.path));
    final cropped = img.decodeJpg(await out.readAsBytes())!;
    final expected = cropRect(preview, const Size(600, 1200));
    expect(cropped.width, expected.width.round());
    expect(cropped.height, expected.height.round());
    // The centre of the crop is the dark card; the default margin keeps a light rim.
    final c = cropped.getPixel(cropped.width ~/ 2, cropped.height ~/ 2);
    expect(c.r, lessThan(80));
    final corner = cropped.getPixel(2, 2);
    expect(corner.r, greaterThan(200));
  });
}
