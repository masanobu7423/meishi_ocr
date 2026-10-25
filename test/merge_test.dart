import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/merge.dart';

Contact _existing() => Contact(
      id: '42',
      displayName: '山田 太郎',
      name: Name(last: '山田', first: '太郎'),
      phones: [Phone(number: '+81 90 1234 5678', label: const Label(PhoneLabel.mobile))],
      emails: [Email(address: 'old@example.com')],
      organizations: [Organization(name: '旧社', jobTitle: '課長')],
      notes: [Note(note: '2024 展示会')],
    );

CardFields _card() => CardFields()
  ..name = '山田 太郎'
  ..company = '株式会社サンライズ'
  ..title = '部長'
  ..phone = '03-1234-5678'
  ..mobile = '090-1234-5678'
  ..email = 'taro.yamada@sunrise.co.jp'
  ..memo = '2026-10 商談';

void main() {
  group('contactDiff', () {
    test('lists every field with both sides and whether they agree', () {
      final rows = contactDiff(_existing(), _card());
      final byKey = {for (final r in rows) r.key: r};
      expect(byKey['name']!.existing, '山田 太郎');
      expect(byKey['name']!.card, '山田 太郎');
      expect(byKey['name']!.same, isTrue);
      expect(byKey['mobile']!.existing, '+81 90 1234 5678');
      expect(byKey['mobile']!.same, isTrue, reason: '+81 folds to 0, digits compared');
      expect(byKey['company']!.existing, '旧社');
      expect(byKey['company']!.card, '株式会社サンライズ');
      expect(byKey['company']!.same, isFalse);
      expect(byKey['phone']!.existing, isNull);
      expect(byKey['phone']!.card, '03-1234-5678');
      expect(byKey['email']!.same, isFalse);
    });

    test('address compares the street only: the postal code lives in its own field', () {
      final existing = _existing().copyWith(
          addresses: [Address(street: '東京都渋谷区神宮前1-2-3', postalCode: '150-0001')]);
      final card = _card()
        ..address = '東京都渋谷区神宮前1-2-3'
        ..postal = '150-0001';
      final row = contactDiff(existing, card).firstWhere((r) => r.key == 'address');
      expect(row.same, isTrue);
      expect(row.existing, '東京都渋谷区神宮前1-2-3');
    });

    test('rows where both sides are empty are left out', () {
      final rows = contactDiff(_existing(), _card());
      expect(rows.any((r) => r.key == 'fax'), isFalse);
      expect(rows.any((r) => r.key == 'url'), isFalse);
    });
  });

  group('mergeContact', () {
    test('keeps the existing id, takes card values where chosen, unions multi-values', () {
      final merged = mergeContact(_existing(), _card(),
          useCard: {'company', 'title'}, scannedAt: DateTime(2026, 10, 25));
      expect(merged.id, '42');
      expect(merged.name!.last, '山田');
      expect(merged.organizations.single.name, '株式会社サンライズ');
      expect(merged.organizations.single.jobTitle, '部長');
      // phones: existing mobile kept once (same digits), card landline added
      expect(merged.phones.map((p) => p.number).toList(), ['+81 90 1234 5678', '03-1234-5678']);
      // emails: both kept, no duplicates
      expect(merged.emails.map((e) => e.address).toList(), ['old@example.com', 'taro.yamada@sunrise.co.jp']);
      // notes: old note kept, memo + scan line appended
      expect(merged.notes.single.note, '2024 展示会\n2026-10 商談\n名刺取込 2026-10-25');
    });

    test('a field not chosen keeps the existing value even when the card differs', () {
      final merged = mergeContact(_existing(), _card(), useCard: const {}, scannedAt: DateTime(2026));
      expect(merged.organizations.single.name, '旧社');
      expect(merged.organizations.single.jobTitle, '課長');
    });

    test('an empty existing field is filled from the card without being chosen', () {
      final existing = _existing()..organizations.clear();
      final merged = mergeContact(existing, _card(), useCard: const {}, scannedAt: DateTime(2026));
      expect(merged.organizations.single.name, '株式会社サンライズ');
    });
  });
}
