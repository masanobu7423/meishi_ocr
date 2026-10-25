import 'card_status.dart';
import 'contact_mapper.dart' show phoneDigits;
import 'extractor.dart';
import 'vault_index.dart';

/// One saved card as the history list shows it. Built from the note's
/// frontmatter only, so the vault stays the single source of truth.
class CardSummary {
  final String noteStem; // vault filename without .md
  final String stem; // golden JSON stem (source without .json)
  final String name;
  final String? company, title, memo, imageFront, imageBack, scanned;
  final String? kana, phone, mobile, email;
  final String? category, related, division, qualifications;
  final CardStatus status;

  const CardSummary({
    required this.noteStem,
    required this.stem,
    required this.name,
    this.company,
    this.title,
    this.memo,
    this.imageFront,
    this.imageBack,
    this.scanned,
    this.kana,
    this.phone,
    this.mobile,
    this.email,
    this.category,
    this.related,
    this.division,
    this.qualifications,
    this.status = CardStatus.reviewed,
  });

  String get _haystack => _fold([
        name, kana, company, title, memo, phone, mobile, email,
        category, related, division, qualifications,
      ].whereType<String>().join(' '));

  /// Case-, width- and kana-insensitive substring match; empty query = all.
  bool matches(String query) => query.trim().isEmpty || _haystack.contains(_fold(query));
}

/// Newest first; non-card notes (index, etc.) are skipped.
List<CardSummary> cardSummaries(Map<String, String> notes) {
  final out = <CardSummary>[];
  for (final e in notes.entries) {
    final fm = parseFrontmatter(e.value);
    if (fm['type'] != 'meishi') continue;
    out.add(CardSummary(
      noteStem: e.key,
      stem: (fm['source'] ?? e.key).replaceAll(RegExp(r'\.json$'), ''),
      name: fm['name'] ?? e.key,
      company: fm['company'],
      title: fm['title'],
      memo: fm['memo'],
      imageFront: fm['image_front'],
      imageBack: fm['image_back'],
      scanned: fm['scanned'],
      kana: fm['kana'],
      phone: fm['phone'],
      mobile: fm['mobile'],
      email: fm['email'],
      category: fm['category'],
      related: fm['related'],
      division: fm['division'],
      qualifications: fm['qualifications'],
      status: parseStatus(fm['status']),
    ));
  }
  out.sort((a, b) => (b.scanned ?? '').compareTo(a.scanned ?? ''));
  return out;
}

const _halfKana = 'ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ';
const _fullKana = 'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

/// Search key: half-width ASCII/kana -> full-width kana, hiragana ->
/// katakana, lower case, no spaces or hyphens (so phone numbers match with
/// or without them).
String _fold(String s) {
  var t = normalize(s).toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
  // half-width katakana with (semi-)voiced marks first, then plain
  t = t.replaceAllMapped(RegExp('([$_halfKana])([ﾞﾟ])'), (m) {
    final base = _fullKana[_halfKana.indexOf(m[1]!)];
    final code = base.codeUnitAt(0) + (m[2] == 'ﾞ' ? 1 : 2);
    return String.fromCharCode(code);
  });
  t = t.replaceAllMapped(RegExp('[$_halfKana]'), (m) => _fullKana[_halfKana.indexOf(m[0]!)]);
  // hiragana -> katakana
  t = t.replaceAllMapped(
      RegExp(r'[ぁ-ゖ]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) + 0x60));
  return t;
}

/// Values already used for the user-maintained fields, most used first
/// (ties keep first-seen order), for the form's suggestion chips.
Map<String, List<String>> suggestionsFrom(Map<String, String> notes) {
  const single = ['category', 'division'];
  const multi = ['related', 'qualifications'];
  final counts = {for (final k in [...single, ...multi]) k: <String, int>{}};
  for (final md in notes.values) {
    final fm = parseFrontmatter(md);
    if (fm['type'] != 'meishi') continue;
    for (final k in single) {
      final v = fm[k]?.trim();
      if (v != null && v.isNotEmpty) counts[k]!.update(v, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final k in multi) {
      for (final v in splitNames(fm[k])) {
        counts[k]!.update(v, (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  return {
    for (final e in counts.entries)
      e.key: () {
        final order = e.value.keys.toList();
        final sorted = List.of(order)
          ..sort((a, b) {
            final d = e.value[b]! - e.value[a]!;
            return d != 0 ? d : order.indexOf(a) - order.indexOf(b);
          });
        return sorted;
      }(),
  };
}

/// Stems of cards that share a phone number (digits, +81 folded) or an
/// email (case-insensitive) with another card: the same card scanned twice,
/// or two people on one line. Empty values never match.
Set<String> duplicateStems(List<CardSummary> cards) {
  final byKey = <String, List<String>>{};
  for (final c in cards) {
    final keys = {
      for (final p in [c.phone, c.mobile]) if (p != null) 'p:${phoneDigits(p)}',
      if (c.email != null) 'e:${c.email!.trim().toLowerCase()}',
    }..removeWhere((k) => k.length <= 2);
    for (final k in keys) {
      byKey.putIfAbsent(k, () => []).add(c.stem);
    }
  }
  return {
    for (final stems in byKey.values)
      if (stems.toSet().length > 1) ...stems,
  };
}
