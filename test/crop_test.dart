import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meishi_ocr/ocr/capture_guide.dart';
import 'package:meishi_ocr/ocr/crop.dart';

void main() {
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
