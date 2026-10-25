import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';
import 'package:meishi_ocr/ocr/extractor.dart';

const _note = '''---
type: meishi
name: 山田 太郎
kana: やまだ たろう
company: 株式会社サンライズ
dept: 営業部
title: 部長
phone: 03-1234-5678
mobile: 090-1234-5678
email: taro.yamada@sunrise.co.jp
postal: 150-0001
address: 東京都渋谷区神宮前1-2-3
scanned: 2026-10-24
tags: [名刺]
---
# 山田 太郎
''';
const _index = '''---
type: meishi_index
count: 1
---
''';

void main() {
  test('fieldsFromFrontmatter maps note keys back onto CardFields', () {
    final f = fieldsFromFrontmatter({
      'name': '山田 太郎', 'kana': 'やまだ たろう', 'roman': 'Taro Yamada',
      'company': 'X', 'dept': 'D', 'title': 'T', 'phone': '1', 'mobile': '2',
      'fax': '3', 'email': 'e', 'url': 'u', 'postal': 'p', 'address': 'a',
      'corp_no': 'c', 'construction_license': 'cl', 'real_estate_license': 'rl',
      'qualifications': 'q', 'division': 'dv', 'category': 'ct', 'related': 'r',
      'job': 'j', 'trust': '4', 'contact_id': '42',
    }).toJson();
    expect(f, {
      'name': '山田 太郎', 'nameKana': 'やまだ たろう', 'nameRoman': 'Taro Yamada',
      'company': 'X', 'dept': 'D', 'title': 'T', 'phone': '1', 'mobile': '2',
      'fax': '3', 'email': 'e', 'url': 'u', 'postal': 'p', 'address': 'a', 'memo': null,
      'corpNo': 'c', 'constructionLicense': 'cl', 'realEstateLicense': 'rl',
      'qualifications': 'q', 'division': 'dv', 'category': 'ct', 'related': 'r',
      'job': 'j', 'trust': '4', 'contactId': '42',
    });
  });

  test('vcardOfFields makes one VCARD per card', () {
    final vcf = vcardOfFields([
      CardFields()..name = '山田 太郎'..phone = '03-1234-5678',
      CardFields()..name = '佐藤 花子'..email = 'hanako@example.com',
    ], scannedAt: DateTime(2026, 10, 25));
    expect('BEGIN:VCARD'.allMatches(vcf).length, 2);
    expect(vcf, contains('N:山田;太郎;'));
    expect(vcf, contains('hanako@example.com'));
    expect(vcardOfFields(const []), '');
  });

  test('vcardOfNotes exports one VCARD per card note and skips the index', () {
    final vcf = vcardOfNotes({'山田_太郎_2026-10-24': _note, '_名刺一覧': _index, 'b': _note});
    expect('BEGIN:VCARD'.allMatches(vcf).length, 2);
    expect(vcf, contains('N:山田;太郎;'));
    expect(vcf, contains('FN:山田 太郎'));
    expect(vcf, contains('ORG:株式会社サンライズ;営業部'));
    expect(vcf, contains('TITLE:部長'));
    expect(vcf, contains('03-1234-5678'));
    expect(vcf, contains('taro.yamada@sunrise.co.jp'));
    expect(vcf, contains('150-0001'));
  });

  test('vcardOfNotes with no card notes is empty', () {
    expect(vcardOfNotes({'_名刺一覧': _index}), '');
  });
}
