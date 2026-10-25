import 'package:flutter_contacts/flutter_contacts.dart';

import 'extractor.dart';
import 'romaji.dart';

/// ひらがな -> カタカナ (contacts' phonetic fields are katakana by convention).
String hiraToKata(String s) => s.replaceAllMapped(RegExp(r'[ぁ-ゖ]'),
    (m) => String.fromCharCode(m[0]!.codeUnitAt(0) + 0x60));

String _ymd(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Card fields -> a contact ready for `FlutterContacts.create`.
/// Japanese cards print family name first; the reading comes from printed
/// kana when present, else from the romaji line.
Contact toContact(CardFields f, {required DateTime scannedAt, String? source}) {
  final parts = (f.name ?? '').trim().split(RegExp(r'\s+'));
  final kana = f.nameKana != null
      ? hiraToKata(normalize(f.nameKana!))
      : (f.nameRoman != null ? kanaName(f.nameRoman!) : null);
  final kparts = kana?.split(' ');
  return Contact(
    // Platforms recompute this on create; the vCard writer uses it for FN,
    // and without it FN comes out Western-ordered ("太郎 山田").
    displayName: parts.join(' '),
    name: Name(
      last: parts.first,
      first: parts.length > 1 ? parts.sublist(1).join(' ') : null,
      phoneticLast: kparts?.first,
      phoneticFirst: kparts != null && kparts.length > 1 ? kparts.sublist(1).join(' ') : null,
    ),
    phones: [
      if (f.phone != null) Phone(number: f.phone!, label: const Label(PhoneLabel.work)),
      if (f.mobile != null) Phone(number: f.mobile!, label: const Label(PhoneLabel.mobile)),
      if (f.fax != null) Phone(number: f.fax!, label: const Label(PhoneLabel.workFax)),
    ],
    emails: [
      if (f.email != null) Email(address: f.email!, label: const Label(EmailLabel.work)),
    ],
    websites: [if (f.url != null) Website(url: f.url!)],
    addresses: [
      if (f.address != null)
        Address(street: f.address, postalCode: f.postal, label: const Label(AddressLabel.work)),
    ],
    organizations: [
      if (f.company != null || f.title != null || f.dept != null || f.division != null)
        Organization(
            name: f.company,
            jobTitle: f.title,
            departmentName: [f.division, f.dept].whereType<String>().join(' ').nullIfEmpty),
    ],
    // Contacts have no fields for trade data, so it travels in the note,
    // one labelled line each, in a fixed order the sync can rely on.
    notes: [
      Note(
          note: [
        if (f.memo != null) f.memo!,
        if (f.category != null) '区分: ${f.category}',
        if (f.job != null) '職種: ${f.job}',
        if (f.trust != null) '信頼度: ${f.trust}',
        if (f.related != null) '関係者: ${f.related}',
        if (f.corpNo != null) '法人番号: ${f.corpNo}',
        if (f.constructionLicense != null) '建設業許可: ${f.constructionLicense}',
        if (f.realEstateLicense != null) '宅建業免許: ${f.realEstateLicense}',
        if (f.qualifications != null) '資格: ${f.qualifications}',
        '名刺取込 ${_ymd(scannedAt)}${source == null ? '' : ' ($source)'}',
      ].join('\n')),
    ],
  );
}

/// The note lines toContact writes, by card key (the reverse of the list above).
const _noteKeys = {
  '区分': 'category', '職種': 'job', '信頼度': 'trust', '関係者': 'related', '法人番号': 'corpNo',
  '建設業許可': 'constructionLicense', '宅建業免許': 'realEstateLicense', '資格': 'qualifications',
};

String? _first(Iterable<String?> xs) => xs.where((s) => s != null && s.trim().isNotEmpty).firstOrNull?.trim();

bool _isFax(PhoneLabel l) => l == PhoneLabel.workFax || l == PhoneLabel.homeFax || l == PhoneLabel.otherFax;
bool _isMobile(PhoneLabel l) => l == PhoneLabel.mobile || l == PhoneLabel.workMobile;

/// An address-book contact as card fields: the reverse of [toContact], so a
/// contact can become a card (import) or refresh one (pull). First value of
/// each kind; the labelled note lines go back to their fields, the rest is
/// the memo, and the `名刺取込` link line is dropped.
CardFields fieldsFromContact(Contact c) {
  final n = c.name;
  final org = c.organizations.firstOrNull;
  final adr = c.addresses.firstOrNull;
  final f = CardFields()
    ..contactId = c.id
    ..name = _first([c.displayName, [n?.last, n?.first].whereType<String>().join(' ')])
    ..nameKana = _first([[n?.phoneticLast, n?.phoneticFirst].whereType<String>().join(' ')])
    ..company = _first([org?.name])
    ..dept = _first([org?.departmentName])
    ..title = _first([org?.jobTitle])
    ..phone = _first(c.phones.where((p) => !_isMobile(p.label.label) && !_isFax(p.label.label)).map((p) => p.number))
    ..mobile = _first(c.phones.where((p) => _isMobile(p.label.label)).map((p) => p.number))
    ..fax = _first(c.phones.where((p) => _isFax(p.label.label)).map((p) => p.number))
    ..email = _first(c.emails.map((e) => e.address))
    ..url = _first(c.websites.map((w) => w.url))
    ..postal = _first([adr?.postalCode])
    ..address = _first([adr?.street]);
  final memo = <String>[];
  for (final line in c.notes.map((x) => x.note).join('\n').split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('名刺取込')) continue;
    final m = RegExp(r'^([^:：]+)[:：]\s*(.+)$').firstMatch(t);
    final key = m == null ? null : _noteKeys[m.group(1)!.trim()];
    if (key != null) {
      f.set(key, m!.group(2)!.trim());
    } else {
      memo.add(t);
    }
  }
  f.memo = memo.isEmpty ? null : memo.join('\n');
  return f;
}

/// The card written onto an existing contact (push). Single-valued data
/// (name, organization) is the card's; multi-valued lists keep the card's
/// entries first and then whatever else the contact had (a second phone or
/// e-mail added in Google survives); the note is the card's lines plus the
/// contact's free lines the card does not carry. Identity (id, photo,
/// platform data) stays.
Contact applyCard(Contact existing, CardFields f, {required DateTime scannedAt}) {
  final c = toContact(f, scannedAt: scannedAt);
  List<T> union<T>(List<T> mine, List<T> theirs, String Function(T) key) {
    final seen = mine.map(key).toSet();
    return [...mine, for (final t in theirs) if (seen.add(key(t))) t];
  }
  final myNote = c.notes.single.note;
  final myLines = myNote.split('\n').map((l) => l.trim()).toSet();
  final extra = [
    for (final line in existing.notes.map((n) => n.note).join('\n').split('\n'))
      if (line.trim().isNotEmpty && !myLines.contains(line.trim()) && !_isOurLine(line.trim())) line.trim(),
  ];
  return existing.copyWith(
    displayName: c.displayName,
    name: c.name,
    phones: union(c.phones, existing.phones, (p) => phoneDigits(p.number)),
    emails: union(c.emails, existing.emails, (e) => e.address.toLowerCase()),
    websites: union(c.websites, existing.websites, (w) => w.url.toLowerCase()),
    addresses: union(c.addresses, existing.addresses, (a) => normalize(a.street ?? '').replaceAll(' ', '')),
    organizations: c.organizations,
    notes: [Note(note: [myNote, ...extra].join('\n'))],
  );
}

/// A note line this app wrote: a labelled field or the 名刺取込 link line.
bool _isOurLine(String t) =>
    t.startsWith('名刺取込') || _noteKeys.keys.any((k) => t.startsWith('$k:') || t.startsWith('$k：'));

/// Digits only, +81 folded to a leading 0, for comparing phone numbers.
String phoneDigits(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.startsWith('81') && d.length > 10 ? '0${d.substring(2)}' : d;
}

String _digits(String s) => phoneDigits(s);

/// First existing contact sharing a phone number (digits compared, +81 folded
/// to 0) or an email (case-insensitive) with the card. Name is deliberately
/// not used: merging two different 田中さん is worse than one duplicate.
Contact? findDuplicate(CardFields f, List<Contact> existing) {
  final phones = {for (final p in [f.phone, f.mobile, f.fax]) if (p != null) _digits(p)};
  final email = f.email?.toLowerCase();
  for (final c in existing) {
    if (c.phones.any((p) => phones.contains(_digits(p.number)))) return c;
    if (email != null && c.emails.any((e) => e.address.toLowerCase() == email)) return c;
  }
  return null;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
