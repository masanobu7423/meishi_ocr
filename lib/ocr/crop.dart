import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'capture_guide.dart';

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
