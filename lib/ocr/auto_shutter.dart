import 'dart:typed_data';

/// A point in frame-normalised coordinates (0..1 of width / height).
typedef QuadPoint = ({double x, double y});

/// Cheap per-frame numbers from the camera's luminance plane, plus the
/// card's four corners (TL, TR, BR, BL) when a bright quadrilateral stands
/// out against the surface.
typedef FrameStats = ({
  double center,
  double border,
  double edges,
  double motion,
  List<QuadPoint>? quad,
});

/// Samples a Y (luminance) plane on a coarse grid: mean brightness of the
/// centre 60 % and of the border, mean horizontal gradient in the centre
/// (printed text), mean absolute change against the previous frame, and
/// the corners of the bright region.
/// ponytail: the "edge detection" is a threshold halfway between centre and
/// border brightness plus the classic min/max of x±y for the corners. It
/// follows a tilted card on a darker desk; on a white desk there is no
/// contrast and no quad (the guide crop still applies).
class FrameSampler {
  final int step;
  List<int>? _prev;
  FrameSampler({this.step = 8});

  FrameStats sample(Uint8List y, int width, int height, {int rowStride = 0}) {
    final stride = rowStride == 0 ? width : rowStride;
    final half = step ~/ 2;
    final samples = <int>[];
    final xs = <int>[], ys = <int>[];
    var centerSum = 0, centerN = 0, borderSum = 0, borderN = 0, edgeSum = 0, edgeN = 0;
    for (var r = 0; r < height; r += step) {
      final inRow = r > height * 0.2 && r < height * 0.8;
      for (var c = 0; c < width; c += step) {
        final v = y[r * stride + c];
        samples.add(v);
        xs.add(c);
        ys.add(r);
        if (inRow && c > width * 0.2 && c < width * 0.8) {
          centerSum += v;
          centerN++;
          if (c + half < width) {
            edgeSum += (y[r * stride + c + half] - v).abs();
            edgeN++;
          }
        } else {
          borderSum += v;
          borderN++;
        }
      }
    }
    var motion = 0.0;
    final prev = _prev;
    if (prev != null && prev.length == samples.length) {
      var d = 0;
      for (var i = 0; i < samples.length; i++) {
        d += (samples[i] - prev[i]).abs();
      }
      motion = d / samples.length;
    }
    _prev = samples;
    final center = centerN == 0 ? 0.0 : centerSum / centerN;
    final border = borderN == 0 ? 0.0 : borderSum / borderN;
    return (
      center: center,
      border: border,
      edges: edgeN == 0 ? 0 : edgeSum / edgeN,
      motion: motion,
      quad: _quad(samples, xs, ys, width, height, center, border),
    );
  }

  List<QuadPoint>? _quad(
      List<int> v, List<int> xs, List<int> ys, int w, int h, double center, double border) {
    if (center - border < 15) return null;
    final t = (center + border) / 2;
    var n = 0;
    double? tlS, trS, brS, blS;
    QuadPoint tl = (x: 0, y: 0), tr = tl, br = tl, bl = tl;
    for (var i = 0; i < v.length; i++) {
      if (v[i] <= t) continue;
      n++;
      final p = (x: xs[i] / w, y: ys[i] / h);
      final sum = p.x + p.y, diff = p.x - p.y;
      if (tlS == null || sum < tlS) {
        tlS = sum;
        tl = p;
      }
      if (brS == null || sum > brS) {
        brS = sum;
        br = p;
      }
      if (trS == null || diff > trS) {
        trS = diff;
        tr = p;
      }
      if (blS == null || diff < blS) {
        blS = diff;
        bl = p;
      }
    }
    if (n < v.length * 0.06) return null;
    final wide = (tr.x - tl.x).abs() >= 0.25 || (br.x - bl.x).abs() >= 0.25;
    final tall = (bl.y - tl.y).abs() >= 0.25 || (br.y - tr.y).abs() >= 0.25;
    if (!wide || !tall) return null;
    return [tl, tr, br, bl];
  }
}

/// Decides when to take the picture: a card is detected, it has been still
/// for [stableFrames] frames, and the previous card has left the frame since
/// the last shot (plus [cooldown]).
class AutoShutter {
  final double maxMotion;
  final int stableFrames;
  final Duration cooldown;
  int _stable = 0;
  bool _armed = true;
  DateTime? _lastShot;

  // A hand-held phone over a textured desk jitters by a few levels per
  // frame; read the live numbers (debug builds) before tightening.
  AutoShutter({
    this.maxMotion = 12,
    this.stableFrames = 6,
    this.cooldown = const Duration(milliseconds: 1500),
  });

  /// 0..1: how much of the stillness countdown has elapsed.
  double get progress => _stable / stableFrames;

  /// True exactly on the frame a picture should be taken.
  bool feed(FrameStats s, DateTime now) {
    if (s.quad == null) {
      _stable = 0;
      _armed = true; // the card left the frame: the next one may fire
      return false;
    }
    if (s.motion > maxMotion) {
      _stable = 0;
      return false;
    }
    if (!_armed) return false;
    _stable++;
    if (_stable < stableFrames) return false;
    final last = _lastShot;
    if (last != null && now.difference(last) < cooldown) {
      _stable = stableFrames - 1; // still, armed, but too soon: hold
      return false;
    }
    _stable = 0;
    _armed = false;
    _lastShot = now;
    return true;
  }
}
