// Two saved cards of one person (a new card after a promotion or a move)
// become one: the newer card wins, the older fills its gaps and leaves its
// notes, contacts and old title behind as history. Pure.
import 'card_status.dart';
import 'dates.dart';
import 'vault_index.dart' show splitNames;

/// Comma lists: both cards' values, newer first, each once.
const _lists = {'related', 'qualifications'};

/// The merged field values (CardFields.toJson keys). [olderScanned] dates
/// the history line, e.g. 「旧: 株式会社A 営業部 課長（2025-04-01 の名刺）」.
Map<String, String?> mergeCards(
    {required Map<String, String?> newer, required Map<String, String?> older, String? olderScanned}) {
  String? v(Map<String, String?> m, String k) {
    final s = m[k]?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  final out = <String, String?>{for (final k in {...newer.keys, ...older.keys}) k: v(newer, k) ?? v(older, k)};
  for (final k in _lists) {
    final all = {...splitNames(newer[k]), ...splitNames(older[k])};
    out[k] = all.isEmpty ? null : all.join(', ');
  }
  // The later of the two contacts, whichever card it was logged on.
  final dates = [newer['lastContact'], older['lastContact']].where((d) => parseYmd(d) != null).toList()..sort();
  out['lastContact'] = dates.lastOrNull;
  // One line (frontmatter values hold no line break): newer memo, older memo,
  // then where the person used to be when that differs.
  String role(Map<String, String?> m) => [v(m, 'company'), v(m, 'dept'), v(m, 'title')].whereType<String>().join(' ');
  final was = role(older);
  out['memo'] = {
    ?v(newer, 'memo'),
    ?v(older, 'memo'),
    if (was.isNotEmpty && was != role(newer)) '旧: $was${olderScanned == null ? '' : '（$olderScanned の名刺）'}',
  }.join(' / ');
  if (out['memo']!.isEmpty) out['memo'] = null;
  return out;
}

/// The more advanced of the two: 登録済 > 確認済 > 未確認.
CardStatus mergedStatus(CardStatus a, CardStatus b) => a.index >= b.index ? a : b;
