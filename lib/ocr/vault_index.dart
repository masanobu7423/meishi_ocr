// Aggregate note over the card notes in the vault: one table of all cards
// plus 会社別 / 職種別 / 地域別 groupings with wiki links, so Obsidian's
// graph and backlinks give the "who do I know at X / in Y" view.

/// Reads the flat `key: value` frontmatter our notes (and FastaLife's) use.
Map<String, String> parseFrontmatter(String md) {
  if (!md.startsWith('---\n')) return const {};
  final end = md.indexOf('\n---', 4);
  if (end < 0) return const {};
  final fm = <String, String>{};
  for (final line in md.substring(4, end).split('\n')) {
    final i = line.indexOf(': ');
    if (i > 0) fm[line.substring(0, i)] = line.substring(i + 2).trim();
  }
  return fm;
}

/// The card notes only (`type: meishi`), as (note stem, frontmatter), in
/// map order: every reader of the vault goes through here.
Iterable<(String, Map<String, String>)> cardNotes(Map<String, String> notes) sync* {
  for (final e in notes.entries) {
    final fm = parseFrontmatter(e.value);
    if (fm['type'] == 'meishi') yield (e.key, fm);
  }
}

/// [notes] maps note stem (filename without .md) -> markdown, in display order.
String buildIndex(Map<String, String> notes) {
  final cards = [for (final (stem, fm) in cardNotes(notes)) (stem: stem, fm: fm)];
  String link(({String stem, Map<String, String> fm}) c) =>
      '[[${c.stem}|${c.fm['name'] ?? c.stem}]]';
  String opt(String? v) => v == null || v.isEmpty ? '—' : v;

  final b = StringBuffer()
    ..write('---\ntype: meishi_index\ncount: ${cards.length}\n---\n')
    ..write('# 名刺一覧\n\n| 氏名 | 会社 | 職種 | 信頼度 | 地域 | 取込日 |\n|---|---|---|---|---|---|\n');
  for (final c in cards) {
    final co = c.fm['company'];
    b.write('| ${link(c)} | ${co == null ? '—' : '[[$co]]'} | ${opt(c.fm['job'])} | ${opt(c.fm['trust'])} | '
        '${opt(c.fm['pref'])} | ${opt(c.fm['scanned'])} |\n');
  }

  void section(String title, Iterable<String?> Function(Map<String, String> fm) values,
      String Function(String) label) {
    final groups = <String?, List<String>>{};
    for (final c in cards) {
      final vs = values(c.fm).toList();
      for (final v in vs.isEmpty ? const <String?>[null] : vs) {
        groups.putIfAbsent(v, () => []).add(link(c));
      }
    }
    final keys = groups.keys.toList()
      ..sort((x, y) {
        if (x == null) return 1;
        if (y == null) return -1;
        return groups[y]!.length.compareTo(groups[x]!.length);
      });
    b.write('\n## $title\n\n');
    for (final k in keys) {
      b.write('- ${k == null ? '未分類' : label(k)} (${groups[k]!.length}): ${groups[k]!.join(', ')}\n');
    }
  }

  section('会社別', (fm) => [fm['company']], (k) => '[[$k]]');
  section('職種別', (fm) => [fm['job']], (k) => '[[職種_$k]]');
  section('地域別', (fm) => [fm['pref']], (k) => '[[$k]]');
  section('信頼度別', (fm) => [fm['trust']], (k) => '[[信頼度_$k]]');
  section('区分別', (fm) => [fm['category']], (k) => '[[区分_$k]]');
  section('関係者別', (fm) => splitNames(fm['related']), (k) => '[[$k]]');
  final due = [
    for (final c in cards)
      if ((c.fm['next_contact'] ?? '').isNotEmpty) (c.fm['next_contact']!, link(c)),
  ]..sort((x, y) => x.$1.compareTo(y.$1));
  if (due.isNotEmpty) {
    b.write('\n## 連絡予定\n\n');
    for (final (d, l) in due) {
      b.write('- $d: $l\n');
    }
  }
  b.write('\n#名刺 #名刺_索引\n');
  return b.toString();
}

/// "a, b / c" -> [a, b, c]: the list fields (related users, qualifications)
/// are typed free-form with commas or slashes.
List<String> splitNames(String? s) => s == null
    ? const []
    : s.split(RegExp(r'[,/;、，／]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
