import 'card_status.dart';
import 'dates.dart';
import 'contact_mapper.dart' show phoneDigits;
import 'extractor.dart';
import 'vault_index.dart';

export 'dates.dart';

/// One saved card as the history list shows it. Built from the note's
/// frontmatter only, so the vault stays the single source of truth.
class CardSummary {
  final String noteStem; // vault filename without .md
  final String stem; // golden JSON stem (source without .json)
  final String name;
  final String? company, title, memo, imageFront, imageBack, scanned;
  final String? kana, phone, mobile, email;
  final String? category, related, division, qualifications;
  /// 職種 and 信頼度 ('1'–'5'); the search screen filters on these.
  final String? job, trust;
  /// Address-book contact id when the card is linked (registered / imported).
  final String? contactId;
  /// 次回連絡日 (yyyy-mm-dd) when a follow-up is planned.
  final String? nextContact;
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
    this.job,
    this.trust,
    this.contactId,
    this.nextContact,
    this.status = CardStatus.reviewed,
  });

  String get _haystack => _fold([
        name, kana, company, title, memo, phone, mobile, email,
        category, related, division, qualifications, job,
      ].whereType<String>().join(' '));

  /// Case-, width- and kana-insensitive substring match; empty query = all.
  bool matches(String query) => query.trim().isEmpty || _haystack.contains(_fold(query));
}

/// Newest first; non-card notes (index, etc.) are skipped.
List<CardSummary> cardSummaries(Map<String, String> notes) {
  final out = <CardSummary>[];
  for (final (key, fm) in cardNotes(notes)) {
    out.add(CardSummary(
      noteStem: key,
      stem: (fm['source'] ?? key).replaceAll(RegExp(r'\.json$'), ''),
      name: fm['name'] ?? key,
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
      job: fm['job'],
      trust: fm['trust'],
      contactId: fm['contact_id'],
      nextContact: fm['next_contact'],
      status: parseStatus(fm['status']),
    ));
  }
  out.sort((a, b) => (b.scanned ?? '').compareTo(a.scanned ?? ''));
  return out;
}

/// Text search narrowed by 職種 and a minimum 信頼度 (cards without a
/// rating never pass a minimum).
List<CardSummary> searchCards(List<CardSummary> cards, {String query = '', String? job, int minTrust = 0}) => [
      for (final c in cards)
        if (c.matches(query) &&
            (job == null || c.job == job) &&
            (minTrust == 0 || (int.tryParse(c.trust ?? '') ?? 0) >= minTrust))
          c,
    ];


/// Cards whose 次回連絡日 is overdue or within [days] of [today], soonest first.
List<CardSummary> dueCards(List<CardSummary> cards, {required DateTime today, int days = 7}) {
  final limit = DateTime(today.year, today.month, today.day + days);
  return byNextContact(cards).where((c) => !parseYmd(c.nextContact)!.isAfter(limit)).toList();
}

/// Every dated card, soonest first (undated ones dropped).
List<CardSummary> byNextContact(List<CardSummary> cards) =>
    cards.where((c) => parseYmd(c.nextContact) != null).toList()
      ..sort((a, b) => a.nextContact!.compareTo(b.nextContact!));

bool isOverdue(CardSummary c, DateTime today) {
  final d = parseYmd(c.nextContact);
  return d != null && d.isBefore(DateTime(today.year, today.month, today.day));
}

/// Every 職種 in use, most used first (ties keep first-seen order).
List<String> jobsOf(List<CardSummary> cards) {
  final n = <String, int>{};
  for (final c in cards) {
    if (c.job case final j? when j.isNotEmpty) n.update(j, (x) => x + 1, ifAbsent: () => 1);
  }
  return n.keys.toList()..sort((a, b) => n[b]!.compareTo(n[a]!));
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
  const single = ['category', 'division', 'job'];
  const multi = ['related', 'qualifications'];
  final counts = {for (final k in [...single, ...multi]) k: <String, int>{}};
  for (final (_, fm) in cardNotes(notes)) {
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
