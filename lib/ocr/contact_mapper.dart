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
      if (f.company != null || f.title != null || f.dept != null)
        Organization(name: f.company, jobTitle: f.title, departmentName: f.dept),
    ],
    notes: [Note(note: '名刺取込 ${_ymd(scannedAt)}${source == null ? '' : ' ($source)'}')],
  );
}

String _digits(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.startsWith('81') && d.length > 10 ? '0${d.substring(2)}' : d;
}

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
