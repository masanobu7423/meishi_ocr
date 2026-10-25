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
