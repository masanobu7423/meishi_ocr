import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/auto_shutter.dart';

/// A luminance plane: [border] everywhere, a [centre]-bright rectangle in
/// the middle 60 %, with vertical stripes inside it when [stripes].
Uint8List plane(int w, int h, {int border = 40, int centre = 220, bool stripes = false}) {
  final y = Uint8List(w * h);
  for (var r = 0; r < h; r++) {
    for (var c = 0; c < w; c++) {
      final inside = c > w * 0.2 && c < w * 0.8 && r > h * 0.2 && r < h * 0.8;
      y[r * w + c] = !inside ? border : (stripes && (c ~/ 4).isOdd ? 30 : centre);
    }
  }
  return y;
}

void main() {
  group('FrameSampler', () {
    test('a bright textured card on a dark desk: bright centre, dark border, edges', () {
      final s = FrameSampler().sample(plane(160, 90, stripes: true), 160, 90, rowStride: 160);
      expect(s.center, greaterThan(100));
      expect(s.border, lessThan(60));
      expect(s.edges, greaterThan(20));
    });

    test('a plain desk: no contrast, no edges; motion is 0 for identical frames and > 0 otherwise', () {
      final sampler = FrameSampler();
      final flat = plane(160, 90, border: 90, centre: 90);
      final s1 = sampler.sample(flat, 160, 90, rowStride: 160);
      expect(s1.edges, 0);
      expect(s1.center - s1.border, 0);
      expect(sampler.sample(flat, 160, 90, rowStride: 160).motion, 0);
      expect(sampler.sample(plane(160, 90, stripes: true), 160, 90, rowStride: 160).motion, greaterThan(10));
    });

    test('honours a row stride wider than the width', () {
      final w = 160, h = 90, stride = 192;
      final src = plane(w, h, stripes: true);
      final padded = Uint8List(stride * h);
      for (var r = 0; r < h; r++) {
        padded.setRange(r * stride, r * stride + w, src, r * w);
      }
      final s = FrameSampler().sample(padded, w, h, rowStride: stride);
      expect(s.center, greaterThan(100));
      expect(s.border, lessThan(60));
    });
  });

  group('quad detection', () {
    /// A luminance plane with a bright convex quadrilateral (a tilted card).
    Uint8List tilted(int w, int h, List<(double, double)> corners, {int bright = 220, int dark = 60}) {
      final y = Uint8List(w * h);
      bool inside(double px, double py) {
        var sign = 0;
        for (var i = 0; i < 4; i++) {
          final (ax, ay) = corners[i];
          final (bx, by) = corners[(i + 1) % 4];
          final cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
          final s = cross >= 0 ? 1 : -1;
          if (sign == 0) sign = s;
          if (s != sign) return false;
        }
        return true;
      }
      for (var r = 0; r < h; r++) {
        for (var c = 0; c < w; c++) {
          y[r * w + c] = inside(c / w, r / h) ? bright : dark;
        }
      }
      return y;
    }

    test('finds the four corners of a tilted bright card, in frame-normalised coordinates', () {
      const corners = [(0.25, 0.20), (0.80, 0.28), (0.72, 0.82), (0.18, 0.70)]; // TL TR BR BL
      final s = FrameSampler().sample(tilted(320, 180, corners), 320, 180, rowStride: 320);
      final q = s.quad;
      expect(q, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(q![i].x, closeTo(corners[i].$1, 0.05), reason: 'corner $i x');
        expect(q[i].y, closeTo(corners[i].$2, 0.06), reason: 'corner $i y');
      }
    });

    test('no quad on a flat desk, on a dark card, or when the bright area is tiny', () {
      expect(FrameSampler().sample(plane(320, 180, border: 90, centre: 90), 320, 180).quad, isNull);
      const tiny = [(0.48, 0.48), (0.52, 0.48), (0.52, 0.52), (0.48, 0.52)];
      expect(FrameSampler().sample(tilted(320, 180, tiny), 320, 180).quad, isNull);
    });
  });

  group('AutoShutter', () {
    const q = [(x: 0.2, y: 0.2), (x: 0.8, y: 0.2), (x: 0.8, y: 0.8), (x: 0.2, y: 0.8)];
    FrameStats card({double motion = 0}) =>
        (center: 200, border: 50, edges: 30, motion: motion, quad: q);
    FrameStats desk() => (center: 60, border: 55, edges: 1, motion: 0, quad: null);
    final t0 = DateTime(2026, 10, 26, 9);

    test('fires once after the card has been still for stableFrames, then waits for the card to change', () {
      final a = AutoShutter(stableFrames: 5);
      final fired = <int>[];
      for (var i = 0; i < 12; i++) {
        if (a.feed(card(), t0.add(Duration(milliseconds: 100 * i)))) fired.add(i);
      }
      expect(fired, [4], reason: 'exactly once, on the 5th still frame');
      // The card is taken away and the next one placed: fires again after the cooldown.
      for (var i = 12; i < 16; i++) {
        expect(a.feed(desk(), t0.add(Duration(milliseconds: 100 * i))), isFalse);
      }
      for (var i = 30; i < 40; i++) {
        if (a.feed(card(), t0.add(Duration(milliseconds: 100 * i)))) fired.add(i);
      }
      expect(fired, [4, 34]);
    });

    test('motion resets the countdown; progress reports how close it is', () {
      final a = AutoShutter(stableFrames: 4);
      expect(a.feed(card(), t0), isFalse);
      expect(a.feed(card(), t0), isFalse);
      expect(a.progress, 0.5);
      expect(a.feed(card(motion: 30), t0), isFalse);
      expect(a.progress, 0);
      expect(a.feed(card(), t0), isFalse);
      expect(a.feed(card(), t0), isFalse);
      expect(a.feed(card(), t0), isFalse);
      expect(a.feed(card(), t0), isTrue);
    });

    test('without a detected card it never fires', () {
      final a = AutoShutter(stableFrames: 2);
      for (var i = 0; i < 10; i++) {
        expect(a.feed(desk(), t0), isFalse);
        expect(a.feed((center: 200, border: 190, edges: 2, motion: 0, quad: null), t0), isFalse);
      }
    });
  });
}
