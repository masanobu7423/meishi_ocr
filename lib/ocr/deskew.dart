import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import 'ocr_line.dart';

/// Tilt of the card in degrees, from the median angle of the wide
/// (horizontal-text) lines ML Kit returned. Null when the tilt is too small
/// to matter or there are too few lines to trust a median.
double? skewAngle(List<OcrLine> lines) {
  // Axis-aligned boxes of a 20° line are only ~2:1, so "wider than tall"
  // is the right filter; it still drops 縦書き columns.
  final angles = [
    for (final l in lines)
      if (l.width > l.height && l.text.trim().length >= 3) l.angle,
  ]..sort();
  if (angles.length < 3) return null;
  final mid = angles.length ~/ 2;
  final median =
      angles.length.isOdd ? angles[mid] : (angles[mid - 1] + angles[mid]) / 2;
  return median.abs() < 1.5 ? null : median;
}

/// FastaLife's OCR preprocessing, trimmed to what a printed card needs:
/// long side <= 2048 px (ML Kit's sweet spot), mild contrast, optional
/// rotation by [-angle] to level the text. Runs in an isolate; returns the
/// path of a JPEG next to the original.
// ponytail: no grayscale / adaptive threshold / sharpen. Those were tuned for
// clinical reports; add one at a time only if the golden set moves.
Future<String> preprocessImage(String path, {double angle = 0}) =>
    Isolate.run(() {
      var image = img.decodeImage(File(path).readAsBytesSync())!;
      image = img.bakeOrientation(image);
      final long = image.width > image.height ? image.width : image.height;
      if (long > 2048) {
        final s = 2048 / long;
        image = img.copyResize(image,
            width: (image.width * s).round(),
            height: (image.height * s).round(),
            interpolation: img.Interpolation.cubic);
      }
      if (angle != 0) {
        image = img.copyRotate(image, angle: -angle, interpolation: img.Interpolation.cubic);
      }
      image = img.adjustColor(image, contrast: 1.3);
      // Into the system temp dir, never next to the source: the inbox batch
      // import would otherwise pick the derived JPEG up as a new card.
      final stem = path.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.\w+$'), '');
      final out = '${Directory.systemTemp.path}/${stem}_'
          '${angle == 0 ? 'pre' : 'deskew${angle.toStringAsFixed(1)}'}.jpg';
      File(out).writeAsBytesSync(img.encodeJpg(image, quality: 92));
      return out;
    });
