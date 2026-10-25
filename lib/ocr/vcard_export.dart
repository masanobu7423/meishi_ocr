import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_mapper.dart';
import 'extractor.dart';
import 'vault_index.dart';

/// Inverse of the note frontmatter written by card_note.dart.
CardFields fieldsFromFrontmatter(Map<String, String> fm) => CardFields()
  ..name = fm['name']
  ..nameKana = fm['kana']
  ..nameRoman = fm['roman']
  ..company = fm['company']
  ..dept = fm['dept']
  ..title = fm['title']
  ..phone = fm['phone']
  ..mobile = fm['mobile']
  ..fax = fm['fax']
  ..email = fm['email']
  ..url = fm['url']
  ..postal = fm['postal']
  ..address = fm['address']
  ..memo = fm['memo']
  ..corpNo = fm['corp_no']
  ..constructionLicense = fm['construction_license']
  ..realEstateLicense = fm['real_estate_license']
  ..qualifications = fm['qualifications']
  ..division = fm['division']
  ..category = fm['category']
  ..job = fm['job']
  ..trust = fm['trust']
  ..related = fm['related'];

/// One vCard 3.0 file for every card note in the vault, so the whole batch
/// can be imported into Google Contacts / iCloud / another phone at once.
String vcardOfNotes(Map<String, String> notes) {
  final contacts = <Contact>[];
  for (final e in notes.entries) {
    final fm = parseFrontmatter(e.value);
    if (fm['type'] != 'meishi') continue;
    contacts.add(toContact(fieldsFromFrontmatter(fm),
        scannedAt: DateTime.tryParse(fm['scanned'] ?? '') ?? DateTime.now(),
        source: e.key));
  }
  return contacts.isEmpty ? '' : FlutterContacts.vCard.exportAll(contacts);
}

/// vCard 3.0 text for these cards (one VCARD each), for sharing.
String vcardOfFields(List<CardFields> cards, {DateTime? scannedAt}) => cards.isEmpty
    ? ''
    : FlutterContacts.vCard.exportAll([
        for (final c in cards) toContact(c, scannedAt: scannedAt ?? DateTime.now()),
      ]);
