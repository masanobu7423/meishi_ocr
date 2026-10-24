import 'dart:ui';

/// Japanese business card: 91 x 55 mm.
const cardAspect = 91 / 55;

/// Where to draw the framing guide on a camera preview of [preview] size:
/// a 91:55 landscape rectangle, centred, filling 90 % of whichever
/// dimension limits it.
Rect guideRect(Size preview) {
  var w = preview.width * 0.9;
  var h = w / cardAspect;
  if (h > preview.height * 0.9) {
    h = preview.height * 0.9;
    w = h * cardAspect;
  }
  return Rect.fromCenter(center: preview.center(Offset.zero), width: w, height: h);
}
