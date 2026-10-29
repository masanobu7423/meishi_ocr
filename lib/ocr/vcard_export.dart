import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_mapper.dart';
import 'extractor.dart';
import 'vault_index.dart';

/// Inverse of the note frontmatter written by card_note.dart.
CardFields fieldsFromFrontmatter(Map<String, String> fm) {
  final f = CardFields();
  for (final (k, key) in fieldSpecs) {
    f.set(k, fm[key]);
  }
  return f;
}

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
