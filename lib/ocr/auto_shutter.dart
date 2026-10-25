import 'dart:typed_data';

/// Cheap per-frame numbers from the camera's luminance plane.
typedef FrameStats = ({double center, double border, double edges, double motion});

/// Samples a Y (luminance) plane on a coarse grid: mean brightness of the
/// centre 60 % and of the border, mean horizontal gradient in the centre
/// (printed text), and mean absolute change against the previous frame.
/// ponytail: no edge detection or perspective; a bright, textured, still
/// centre on a darker surface is "a card in the frame". Tune the thresholds
/// in [AutoShutter] from real desks before anything smarter.
class FrameSampler {
  final int step;
  List<int>? _prev;
  FrameSampler({this.step = 8});

  FrameStats sample(Uint8List y, int width, int height, {int rowStride = 0}) {
    final stride = rowStride == 0 ? width : rowStride;
    final half = step ~/ 2;
    final samples = <int>[];
    var centerSum = 0, centerN = 0, borderSum = 0, borderN = 0, edgeSum = 0, edgeN = 0;
    for (var r = 0; r < height; r += step) {
      final inRow = r > height * 0.2 && r < height * 0.8;
      for (var c = 0; c < width; c += step) {
        final v = y[r * stride + c];
        samples.add(v);
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
    return (
      center: centerN == 0 ? 0 : centerSum / centerN,
      border: borderN == 0 ? 0 : borderSum / borderN,
      edges: edgeN == 0 ? 0 : edgeSum / edgeN,
      motion: motion,
    );
  }
}

/// Decides when to take the picture: a card is in the frame (bright centre
/// against the surface, with text edges), it has been still for
/// [stableFrames] frames, and the previous card has been taken away since
/// the last shot (plus [cooldown]).
class AutoShutter {
  final double minBrightness, minContrast, minEdges, maxMotion;
  final int stableFrames;
  final Duration cooldown;
  int _stable = 0;
  bool _armed = true;
  DateTime? _lastShot;

  // Thresholds: a hand-held phone over a textured desk jitters by a few
  // levels per frame, and most centre samples land on blank paper, so the
  // mean gradient of a real card is small. Read the live numbers on the
  // capture screen (debug builds) before tightening these.
  AutoShutter({
    this.minBrightness = 110,
    this.minContrast = 15,
    this.minEdges = 3,
    this.maxMotion = 12,
    this.stableFrames = 6,
    this.cooldown = const Duration(milliseconds: 1500),
  });

  /// 0..1: how much of the stillness countdown has elapsed.
  double get progress => _stable / stableFrames;

  /// True exactly on the frame a picture should be taken.
  bool feed(FrameStats s, DateTime now) {
    final present =
        s.center >= minBrightness && s.center - s.border >= minContrast && s.edges >= minEdges;
    if (!present) {
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
