import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/contact_mapper.dart';
import 'package:meishi_ocr/ocr/extractor.dart';

CardFields _card() => CardFields()
  ..name = '山田 太郎'
  ..nameKana = 'やまだ たろう'
  ..nameRoman = 'Taro Yamada'
  ..company = '株式会社サンライズ'
  ..dept = '営業部'
  ..title = '部長'
  ..phone = '03-1234-5678'
  ..mobile = '090-1234-5678'
  ..fax = '03-1234-5679'
  ..email = 'taro.yamada@sunrise.co.jp'
  ..url = 'https://www.sunrise.co.jp'
  ..postal = '150-0001'
  ..address = '東京都渋谷区神宮前1-2-3 サンライズビル5F';

void main() {
  group('toContact', () {
    test('splits a Japanese name family-first and uses printed kana as phonetic', () {
      final c = toContact(_card(), scannedAt: DateTime(2026, 10, 25), source: 'x.json');
      expect(c.name!.last, '山田');
      expect(c.name!.first, '太郎');
      expect(c.name!.phoneticLast, 'ヤマダ');
      expect(c.name!.phoneticFirst, 'タロウ');
    });
    test('derives phonetic from romaji when no kana is printed', () {
      final c = toContact(_card()..nameKana = null, scannedAt: DateTime(2026));
      expect(c.name!.phoneticLast, 'ヤマダ');
      expect(c.name!.phoneticFirst, 'タロ');
    });
    test('maps phones with labels, org, email, website, work address, note', () {
      final c = toContact(_card(), scannedAt: DateTime(2026, 10, 25), source: 'x.json');
      expect(c.phones.map((p) => (p.number, p.label.label)), [
        ('03-1234-5678', PhoneLabel.work),
        ('090-1234-5678', PhoneLabel.mobile),
        ('03-1234-5679', PhoneLabel.workFax),
      ]);
      expect(c.organizations.single.name, '株式会社サンライズ');
      expect(c.organizations.single.departmentName, '営業部');
      expect(c.organizations.single.jobTitle, '部長');
      expect(c.emails.single.address, 'taro.yamada@sunrise.co.jp');
      expect(c.emails.single.label.label, EmailLabel.work);
      expect(c.websites.single.url, 'https://www.sunrise.co.jp');
      expect(c.addresses.single.postalCode, '150-0001');
      expect(c.addresses.single.street, '東京都渋谷区神宮前1-2-3 サンライズビル5F');
      expect(c.addresses.single.label.label, AddressLabel.work);
      expect(c.notes.single.note, '名刺取込 2026-10-25 (x.json)');
    });
  });

  group('findDuplicate', () {
    final existing = [
      Contact(displayName: '別人', phones: [Phone(number: '06-0000-0000')]),
      Contact(displayName: '山田太郎', phones: [Phone(number: '+81 90 1234 5678')]),
      Contact(displayName: 'メール一致', emails: [Email(address: 'TARO.YAMADA@sunrise.co.jp')]),
    ];
    test('matches on normalized phone digits, +81 included', () {
      expect(findDuplicate(_card(), existing)?.displayName, '山田太郎');
    });
    test('matches on case-insensitive email when phones differ', () {
      final card = _card()
        ..mobile = null
        ..phone = null
        ..fax = null;
      expect(findDuplicate(card, existing)?.displayName, 'メール一致');
    });
    test('returns null when nothing matches', () {
      expect(findDuplicate(CardFields()..phone = '011-111-1111', existing), isNull);
    });
  });
}
