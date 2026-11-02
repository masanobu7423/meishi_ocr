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
  for (final (key, fm) in cardNotes(notes)) {
    contacts.add(toContact(fieldsFromFrontmatter(fm),
        scannedAt: DateTime.tryParse(fm['scanned'] ?? '') ?? DateTime.now(),
        source: key));
  }
  return contacts.isEmpty ? '' : FlutterContacts.vCard.exportAll(contacts);
}

/// vCard 3.0 text for these cards (one VCARD each), for sharing.
String vcardOfFields(List<CardFields> cards, {DateTime? scannedAt}) => cards.isEmpty
    ? ''
    : FlutterContacts.vCard.exportAll([
        for (final c in cards) toContact(c, scannedAt: scannedAt ?? DateTime.now()),
      ]);

/// The user's own card as plain text for LINE / SMS: the lines a person
/// needs to reach you, labelled, in reading order (no memo or ratings).
String cardText(CardFields f) {
  String? v(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  final role = [v(f.dept), v(f.title)].whereType<String>().join(' ');
  final address = [if (v(f.postal) != null) '〒${v(f.postal)}', ?v(f.address)].join(' ');
  return [
    ?v(f.name),
    ?v(f.company),
    if (role.isNotEmpty) role,
    if (v(f.mobile) != null) '携帯: ${v(f.mobile)}',
    if (v(f.phone) != null) '電話: ${v(f.phone)}',
    if (v(f.email) != null) 'メール: ${v(f.email)}',
    if (address.isNotEmpty) '住所: $address',
  ].join('\n');
}

/// Fields that are about the person, not the user's own notes on them.
const _privateFields = {'memo', 'category', 'related', 'job', 'trust', 'contactId', 'nextContact', 'lastContact'};

/// The user's own card as a vCard for someone else: contact details only.
/// No memo, ratings, follow-up dates or the 名刺取込 note line.
String myCardVcard(CardFields f) {
  final public = CardFields();
  for (final k in CardFields.keys) {
    if (!_privateFields.contains(k)) public.set(k, f.toJson()[k]);
  }
  return FlutterContacts.vCard.exportAll([toContact(public, scannedAt: DateTime.now()).copyWith(notes: const [])]);
}
