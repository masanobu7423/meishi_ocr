import 'dart:async';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'card_store.dart';
import 'deskew.dart';
import 'ocr_line.dart';

/// Result of one recognition, with what the pipeline did to get it.
class OcrResult {
  final List<OcrLine> lines;
  final String imagePath;
  final double? deskewedBy;

  /// First-pass lines when a levelled second pass replaced them (kept so the
  /// golden set can score both).
  final List<OcrLine>? rawLines;
  const OcrResult(this.lines, this.imagePath, {this.deskewedBy, this.rawLines});
  int get chars => lines.fold(0, (n, l) => n + l.text.replaceAll(' ', '').length);
}

/// Image -> OCR lines. One job at a time (ML Kit's native side is not
/// re-entrant: FastaLife hit SIGSEGV; we hit interleaved state), 30 s timeout
/// per call, failures logged and returned as empty rather than thrown.
///
/// Tilt handling: recognise once, estimate the tilt from the line angles, and
/// when it is worth it rotate the image level and recognise again, keeping
/// whichever pass read more characters. Perspective (trapezoid) is not
/// corrected here; on Android the document scanner does that before capture.
class OcrPipeline {
  final CardStore store;
  // One Japanese recognizer for both sides: it reads Latin fine (emails,
  // "Taro Yamada"), while the Latin model returns 0 lines on a Japanese
  // back side, which is what a user hit on a real card.
  final _jp = TextRecognizer(script: TextRecognitionScript.japanese);
  Future<void> _chain = Future.value();

  OcrPipeline(this.store);

  bool _busy = false;
  bool get busy => _busy;

  Future<OcrResult> recognize(String path, {required bool front}) {
    final done = _chain.then((_) => _run(path, front));
    _chain = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<OcrResult> _run(String path, bool front) async {
    _busy = true;
    try {
      final first = await _pass(path, front);
      final tilt = skewAngle(first.lines);
      if (tilt == null) return first;
      final levelled = await preprocessImage(path, angle: tilt);
      final second = await _pass(levelled, front);
      final keepSecond = second.chars >= first.chars;
      await store.appendLog('deskew.txt',
          '${path.split('/').last} tilt=${tilt.toStringAsFixed(1)} '
          'chars ${first.chars}->${second.chars} ${keepSecond ? "levelled" : "kept original"}');
      return keepSecond
          ? OcrResult(second.lines, levelled, deskewedBy: tilt, rawLines: first.lines)
          : first;
    } catch (e) {
      await store.appendError(path, e);
      return OcrResult(const [], path);
    } finally {
      _busy = false;
    }
  }

  Future<OcrResult> _pass(String path, bool front) async {
    final rec = await _jp
        .processImage(InputImage.fromFilePath(path))
        .timeout(const Duration(seconds: 30));
    return OcrResult([
      for (final b in rec.blocks)
        for (final l in b.lines)
          OcrLine(l.text,
              left: l.boundingBox.left,
              top: l.boundingBox.top,
              width: l.boundingBox.width,
              height: l.boundingBox.height,
              angle: l.angle ?? _angleOf(l)),
    ], path);
  }

  /// iOS has no `angle`: derive it from the top edge of the corner points.
  static double _angleOf(TextLine l) {
    if (l.cornerPoints.length < 2) return 0;
    final p0 = l.cornerPoints[0], p1 = l.cornerPoints[1];
    return math.atan2((p1.y - p0.y).toDouble(), (p1.x - p0.x).toDouble()) * 180 / math.pi;
  }

  void dispose() => _jp.close();
}
