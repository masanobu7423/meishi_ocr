/// One OCR text line with its bounding box in image pixels.
///
/// Mirrors the subset of ML Kit's `TextLine` the extractor needs, so the
/// extractor and its golden tests stay pure Dart (no device, no plugin).
class OcrLine {
  final String text;
  final double left, top, width, height;

  /// Rotation of the line in degrees (ML Kit's `angle`, or derived from the
  /// corner points). 0 for old dumps that did not record it.
  final double angle;

  const OcrLine(
    this.text, {
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.angle = 0,
  });

  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
        j['text'] as String,
        left: (j['l'] as num? ?? 0).toDouble(),
        top: (j['t'] as num? ?? 0).toDouble(),
        width: (j['w'] as num? ?? 0).toDouble(),
        height: (j['h'] as num? ?? 0).toDouble(),
        angle: (j['a'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() =>
      {'text': text, 'l': left, 't': top, 'w': width, 'h': height, 'a': angle};
}
