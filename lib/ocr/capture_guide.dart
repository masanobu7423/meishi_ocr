import 'dart:ui';

/// Japanese business card: 91 x 55 mm.
const cardAspect = 91 / 55;

/// Where to draw the framing guide on a camera preview of [preview] size:
/// a 91:55 landscape rectangle, centred, filling 90 % of whichever
/// dimension limits it.
/// The guide mapped onto the captured still (pixels), grown by [margin] of
/// its own size on every side and clamped to the image. When the still has
/// a wider field of view than the preview (CameraX often captures 4:3 while
/// previewing 16:9), the preview is its centre: scale by the smaller ratio
/// and centre the rest.
Rect cropRect(Size preview, Size image, {double margin = 0.03}) {
  final g = guideRect(preview);
  final s = [image.width / preview.width, image.height / preview.height].reduce((a, b) => a < b ? a : b);
  final offX = (image.width - preview.width * s) / 2;
  final offY = (image.height - preview.height * s) / 2;
  final r = Rect.fromLTWH(offX + g.left * s, offY + g.top * s, g.width * s, g.height * s);
  final grown = Rect.fromLTRB(r.left - r.width * margin, r.top - r.height * margin,
      r.right + r.width * margin, r.bottom + r.height * margin);
  return grown.intersect(Rect.fromLTWH(0, 0, image.width, image.height));
}

Rect guideRect(Size preview) {
  var w = preview.width * 0.9;
  var h = w / cardAspect;
  if (h > preview.height * 0.9) {
    h = preview.height * 0.9;
    w = h * cardAspect;
  }
  return Rect.fromCenter(center: preview.center(Offset.zero), width: w, height: h);
}
