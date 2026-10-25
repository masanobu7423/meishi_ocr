// 建設業許可・宅建免許・法人番号・資格・部門: machine-readable patterns the
// extractor must pull out before the phone / name heuristics run.
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

OcrLine l(String t, {double h = 18, double w = 300}) => OcrLine(t, width: w, height: h);

void main() {
  test('construction card: licences, corporate number and qualifications', () {
    final f = extract([
      l('株式会社サンライズ建設', h: 28),
      l('建設業許可 東京都知事許可（般-5）第123456号', h: 14, w: 420),
      l('宅地建物取引業 東京都知事（3）第45678号', h: 14, w: 380),
      l('法人番号 1234567890123', h: 14),
      l('1級建築施工管理技士 一級建築士', h: 14),
      l('工事部 現場監督', h: 20),
      l('山田 太郎', h: 56),
      l('〒150-0001 東京都渋谷区神宮前1-2-3', h: 16, w: 400),
      l('TEL 03-1234-5678', h: 16),
    ]);
    expect(f.constructionLicense, '東京都知事許可(般-5)第123456号');
    expect(f.realEstateLicense, '東京都知事(3)第45678号');
    expect(f.corpNo, '1234567890123');
    expect(f.qualifications, '1級建築施工管理技士 / 1級建築士');
    expect(f.name, '山田 太郎');
    expect(f.company, '株式会社サンライズ建設');
    expect(f.dept, '工事部');
    expect(f.title, '現場監督');
    expect(f.phone, '03-1234-5678');
    expect(f.fax, isNull, reason: 'licence numbers are not phone numbers');
    expect(f.address, '東京都渋谷区神宮前1-2-3');
  });

  test('invoice registration number T+13 digits is the corporate number', () {
    final f = extract([l('登録番号 T1234567890123'), l('山田 太郎', h: 50)]);
    expect(f.corpNo, '1234567890123');
    expect(f.company, isNull, reason: 'the number line must not become the company');
  });

  test('national licence with 特 and a minus sign, full-width digits', () {
    final f = extract([l('国土交通大臣許可（特−２）第９８７６号'), l('佐藤 花子', h: 50)]);
    expect(f.constructionLicense, '国土交通大臣許可(特-2)第9876号');
    expect(f.realEstateLicense, isNull);
  });

  test('qualification variants are normalised and de-duplicated', () {
    final f = extract([
      l('２級土木施工管理技士補・宅地建物取引士'),
      l('1級建築施工管理技士'),
      l('1級建築施工管理技士'),
      l('鈴木 一郎', h: 50),
    ]);
    expect(f.qualifications, '2級土木施工管理技士補 / 宅地建物取引士 / 1級建築施工管理技士');
  });

  test('a ten-digit phone is never mistaken for a corporate number', () {
    final f = extract([l('TEL 0312345678'), l('田中 健二', h: 50)]);
    expect(f.corpNo, isNull);
    // ponytail: unhyphenated numbers are hyphenated by digit count, not by
    // area code; only the digits are asserted here.
    expect(f.phone?.replaceAll('-', ''), '0312345678');
  });

  test('許可 printed only in the label still yields the licence, not an address', () {
    final f = extract([l('建設業許可 東京都知事（般-5）第123456号'), l('山田 太郎', h: 50)]);
    expect(f.constructionLicense, '東京都知事許可(般-5)第123456号');
    expect(f.address, isNull);
  });

  test('一級建築士事務所 in a company name is not a qualification', () {
    final f = extract([l('一級建築士事務所 株式会社サンライズ設計', h: 28), l('山田 太郎', h: 50)]);
    expect(f.company, '一級建築士事務所 株式会社サンライズ設計');
    expect(f.qualifications, isNull);
  });

  test('技術士補 and 測量士補 are whole qualifications', () {
    final f = extract([l('測量士補・技術士補'), l('山田 太郎', h: 50)]);
    expect(f.qualifications, '測量士補 / 技術士補');
    expect(f.company, isNull);
  });

  test('13 digits inside a URL are part of the URL, not a corporate number', () {
    final f = extract([l('https://example.co.jp/p/1234567890123'), l('山田 太郎', h: 50)]);
    expect(f.corpNo, isNull);
    expect(f.url, 'https://example.co.jp/p/1234567890123');
  });

  test('new keys round-trip through set/toJson', () {
    final f = CardFields()
      ..set('division', '建築事業部')
      ..set('category', '協力会社')
      ..set('related', '山田, 鈴木');
    final j = f.toJson();
    expect(j['division'], '建築事業部');
    expect(j['category'], '協力会社');
    expect(j['related'], '山田, 鈴木');
    expect(CardFields.keys, containsAll(['corpNo', 'constructionLicense', 'realEstateLicense',
        'qualifications', 'division', 'category', 'related']));
  });
}
