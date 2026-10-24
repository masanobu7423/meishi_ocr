import 'extractor.dart';
import 'vault_index.dart';

/// One saved card as the history list shows it. Built from the note's
/// frontmatter only, so the vault stays the single source of truth.
class CardSummary {
  final String noteStem; // vault filename without .md
  final String stem; // golden JSON stem (source without .json)
  final String name;
  final String? company, title, memo, imageFront, imageBack, scanned;

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
  });

  String get _haystack => _fold('$name ${company ?? ''} ${title ?? ''} ${memo ?? ''}');

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
    ));
  }
  out.sort((a, b) => (b.scanned ?? '').compareTo(a.scanned ?? ''));
  return out;
}

const _halfKana = 'ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ';
const _fullKana = 'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

/// Search key: half-width ASCII/kana -> full-width kana, hiragana ->
/// katakana, lower case, no spaces.
String _fold(String s) {
  var t = normalize(s).toLowerCase().replaceAll(' ', '');
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
