import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

/// Golden accuracy harness.
///
/// Each `test/golden/*.json` holds the raw OCR lines of one card plus the
/// hand-corrected `expected` fields. Files with `"strict": true` (synthetic
/// fixtures) must match exactly; real captures only feed the accuracy table
/// printed at the end, so a regression shows up as a number, not a crash.
String _norm(String? s) => s == null
    ? ''
    : normalize(s).replaceAll(RegExp(r'[\s\-ー]'), '').toLowerCase();

void main() {
  final files = Directory('test/golden')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final hits = <String, int>{};
  final totals = <String, int>{};
  final misses = <String>[];

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    List<OcrLine> lines(String key) => [
          for (final e in (j[key] as List? ?? const []))
            OcrLine.fromJson(e as Map<String, dynamic>)
        ];
    final expected = (j['expected'] as Map<String, dynamic>? ?? const {});
    final strict = j['strict'] == true;

    test(name, () {
      final got = extract(lines('front'), back: lines('back')).toJson();
      for (final e in expected.entries) {
        final want = e.value as String?;
        if (want == null || want.isEmpty) {
          // An explicit null in a strict fixture means "must NOT be extracted".
          if (strict) expect(got[e.key], isNull, reason: '$name field ${e.key}');
          continue;
        }
        totals[e.key] = (totals[e.key] ?? 0) + 1;
        if (_norm(got[e.key]) == _norm(want)) {
          hits[e.key] = (hits[e.key] ?? 0) + 1;
        } else {
          misses.add('$name ${e.key}: want "$want" got "${got[e.key]}"');
        }
        if (strict) expect(got[e.key], want, reason: '$name field ${e.key}');
      }
    });
  }

  test('isVertical flags the 縦書き device dump and nothing else', () {
    for (final file in files) {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final front = [
        for (final e in (j['front'] as List? ?? const []))
          OcrLine.fromJson(e as Map<String, dynamic>)
      ];
      expect(isVertical(front), file.path.contains('vertical'),
          reason: file.path);
    }
  });

  tearDownAll(() {
    final buf = StringBuffer('\n=== golden accuracy (${files.length} cards) ===\n');
    for (final k in CardFields.keys) {
      final t = totals[k] ?? 0;
      if (t == 0) continue;
      final h = hits[k] ?? 0;
      buf.writeln('${k.padRight(10)} ${(100 * h / t).toStringAsFixed(0).padLeft(3)}%  ($h/$t)');
    }
    if (misses.isNotEmpty) buf.writeln('--- misses ---\n${misses.join('\n')}');
    // ignore: avoid_print
    print(buf);
  });
}
