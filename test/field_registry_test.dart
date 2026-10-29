// Guard for the field registry: every CardFields key must survive every
// storage path, and every form field must have a label. Adding a field and
// forgetting one place fails here, not in a user's backup.
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/fields.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';

/// A distinct, format-valid value per key (dates must parse, trust is a digit).
String _sample(String k) => switch (k) {
      'nextContact' => '2026-11-03',
      'trust' => '4',
      'name' => '山田 太郎',
      'address' => '東京都千代田区千代田1-1',
      _ => 'v_$k',
    };

CardFields _full() {
  final f = CardFields();
  for (final k in CardFields.keys) {
    f.set(k, _sample(k));
  }
  return f;
}

void main() {
  test('set and toJson cover every key, and unknown keys are ignored', () {
    final j = _full().toJson();
    expect(j.keys, CardFields.keys);
    for (final k in CardFields.keys) {
      expect(j[k], _sample(k), reason: k);
    }
    expect((CardFields()..set('nope', 'x')).toJson().values.whereType<String>(), isEmpty);
  });

  test('every key survives the golden JSON round trip', () {
    expect(fieldsFromJson(_full().toJson()).toJson(), _full().toJson());
  });

  test('every key survives the note frontmatter round trip', () {
    final md = cardNoteMarkdown(_full(), scannedAt: DateTime(2026, 10, 29));
    final back = fieldsFromFrontmatter(parseFrontmatter(md)).toJson();
    for (final k in CardFields.keys) {
      expect(back[k], _sample(k), reason: '$k was lost on the way through the note');
    }
  });

  test('typed accessors read and write the same values as set / toJson', () {
    final f = CardFields()
      ..name = 'A'
      ..nextContact = '2026-11-03';
    expect(f.toJson()['name'], 'A');
    f.set('company', 'B');
    expect(f.company, 'B');
    expect(f.nextContact, '2026-11-03');
  });

  test('each typed accessor reads and writes its own key (no copy-paste slips)', () {
    final f = CardFields()
      ..name = 'name'
      ..nameKana = 'nameKana'
      ..nameRoman = 'nameRoman'
      ..company = 'company'
      ..dept = 'dept'
      ..title = 'title'
      ..phone = 'phone'
      ..mobile = 'mobile'
      ..fax = 'fax'
      ..email = 'email'
      ..url = 'url'
      ..postal = 'postal'
      ..address = 'address'
      ..memo = 'memo'
      ..corpNo = 'corpNo'
      ..constructionLicense = 'constructionLicense'
      ..realEstateLicense = 'realEstateLicense'
      ..qualifications = 'qualifications'
      ..division = 'division'
      ..category = 'category'
      ..related = 'related'
      ..job = 'job'
      ..trust = 'trust'
      ..contactId = 'contactId'
      ..nextContact = 'nextContact';
    expect(f.toJson(), {for (final k in CardFields.keys) k: k});
    expect([f.name, f.nameKana, f.nameRoman, f.company, f.dept, f.title, f.phone, f.mobile, f.fax, f.email, f.url, f.postal, f.address, f.memo, f.corpNo, f.constructionLicense, f.realEstateLicense, f.qualifications, f.division, f.category, f.related, f.job, f.trust, f.contactId, f.nextContact], CardFields.keys);
  });

  test('every form field is a CardFields key with a Japanese label', () {
    for (final k in fieldOrder) {
      expect(CardFields.keys, contains(k), reason: k);
      expect(fieldLabels[k], isNotNull, reason: '$k has no label');
    }
    expect(fieldOrder.toSet().length, fieldOrder.length, reason: 'no duplicates');
  });
}
