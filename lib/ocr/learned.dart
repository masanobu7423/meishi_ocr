import 'extractor.dart';
import 'ocr_line.dart';

/// What the user's manual corrections teach the extractor. Three cheap,
/// on-device "models" that work at tens of cards, where a trained model
/// cannot:
///
/// 1. line memory: a whole OCR line the user moved into a field is assigned
///    there next time it is seen (same company / department / title again);
/// 2. vocabulary: title / department words the built-in lists lack;
/// 3. character confusions: a 1-character fix (健ニ -> 健二) seen at least
///    twice is applied to name / company text.
///
/// Every correction also stays in `log/corrections.jsonl` and the golden JSON,
/// so the harness and CI measure what the rules actually gain.
class Learned {
  /// normalized line text -> field key
  final Map<String, String> lineField = {};

  /// field key (title / dept) -> learned words
  final Map<String, List<String>> terms = {};

  /// 'wrong→right' (single characters) -> times seen
  final Map<String, int> confusions = {};

  static const _vocabFields = {'title', 'dept', 'division'};
  static const _userOwned = {'job', 'trust', 'category', 'related'};
  static const _textFields = {'name', 'company'};

  Learned();

  factory Learned.fromJson(Map<String, dynamic> j) => Learned()
    ..lineField.addAll(Map<String, String>.from(j['lineField'] as Map? ?? {}))
    ..terms.addAll({
      for (final e in (j['terms'] as Map? ?? {}).entries)
        e.key as String: List<String>.from(e.value as List)
    })
    ..confusions.addAll(Map<String, int>.from(j['confusions'] as Map? ?? {}));

  Map<String, dynamic> toJson() =>
      {'lineField': lineField, 'terms': terms, 'confusions': confusions};

  String? fieldFor(String lineText) => lineField[normalize(lineText)];

  bool get isEmpty => lineField.isEmpty && terms.isEmpty && confusions.isEmpty;

  /// [guess] = what the extractor produced, [corrected] = what the user saved.
  void learn({
    required Map<String, String?> guess,
    required Map<String, String?> corrected,
    required List<OcrLine> lines,
  }) {
    final texts = {for (final l in lines) normalize(l.text)};
    for (final e in corrected.entries) {
      final k = e.key;
      if (_userOwned.contains(k)) continue; // never OCR'd, so nothing to learn
      final c = e.value == null ? null : normalize(e.value!);
      final g = guess[k] == null ? null : normalize(guess[k]!);
      if (c == null || c.isEmpty || c == g) continue;
      if (texts.contains(c)) lineField[c] = k;
      // Vocabulary is matched per whitespace token, so only single words
      // are worth keeping; a whole line is covered by lineField above.
      if (_vocabFields.contains(k) && !c.contains(' ') && !terms[k].orEmpty.contains(c)) {
        terms.putIfAbsent(k, () => []).add(c);
      }
      if (_textFields.contains(k) && g != null) {
        final pair = _oneCharDiff(g, c);
        if (pair != null) confusions[pair] = (confusions[pair] ?? 0) + 1;
      }
    }
  }

  /// Applies confusions seen at least twice. Character-level, so a wrong
  /// rule can bite; that is why one sighting is not enough.
  // ponytail: ceiling is a global substitution; scope it to the field's
  // script (kanji-only names) if a learned pair ever misfires.
  String fix(String s) {
    var out = s;
    for (final e in confusions.entries) {
      if (e.value < 2) continue;
      final parts = e.key.split('→');
      if (parts.length == 2) out = out.replaceAll(parts[0], parts[1]);
    }
    return out;
  }

  static String? _oneCharDiff(String a, String b) {
    if (a.length != b.length || a == b) return null;
    String? pair;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i]) continue;
      if (pair != null) return null; // more than one difference
      pair = '${a[i]}→${b[i]}';
    }
    return pair;
  }
}

extension on List<String>? {
  List<String> get orEmpty => this ?? const [];
}
