import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'capture_guide.dart';

/// Output size of a rectified card: 91:55 at a resolution OCR is happy with.
const rectifiedWidth = 1400, rectifiedHeight = 846;

/// Perspective-corrects the card whose corners (TL, TR, BR, BL, normalised
/// preview-box coordinates) were detected on the preview, and writes
/// `<name>_card.jpg` next to the original. Off the UI thread.
Future<File> rectifyToQuad(File src, List<({double x, double y})> quad, Size preview) async {
  final out = '${src.path.replaceAll(RegExp(r'\.\w+$'), '')}_card.jpg';
  final bytes = await src.readAsBytes();
  await Isolate.run(() {
    var image = img.decodeImage(bytes);
    if (image == null) throw const FormatException('not an image');
    image = img.bakeOrientation(image);
    final (:s, :offX, :offY) = viewToImage(preview, Size(image.width.toDouble(), image.height.toDouble()));
    img.Point px(({double x, double y}) p) =>
        img.Point(offX + p.x * preview.width * s, offY + p.y * preview.height * s);
    final card = img.copyRectify(image,
        topLeft: px(quad[0]),
        topRight: px(quad[1]),
        bottomRight: px(quad[2]),
        bottomLeft: px(quad[3]),
        interpolation: img.Interpolation.linear,
        toImage: img.Image(width: rectifiedWidth, height: rectifiedHeight));
    File(out).writeAsBytesSync(img.encodeJpg(card, quality: 92));
  });
  return File(out);
}

/// Crops a still from the in-app camera to the framing guide (the card the
/// user aligned, plus a small rim) and writes it next to the original as
/// `<name>_crop.jpg`. The EXIF orientation is baked first so the guide and
/// the pixels agree. Runs off the UI thread.
Future<File> cropToGuide(File src, Size preview) async {
  final out = '${src.path.replaceAll(RegExp(r'\.\w+$'), '')}_crop.jpg';
  final bytes = await src.readAsBytes();
  await Isolate.run(() {
    var image = img.decodeImage(bytes);
    if (image == null) throw const FormatException('not an image');
    image = img.bakeOrientation(image);
    final r = cropRect(preview, Size(image.width.toDouble(), image.height.toDouble()));
    final cropped = img.copyCrop(image,
        x: r.left.round(), y: r.top.round(), width: r.width.round(), height: r.height.round());
    File(out).writeAsBytesSync(img.encodeJpg(cropped, quality: 92));
  });
  return File(out);
}
