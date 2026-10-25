import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/actions.dart';

void main() {
  test('builds one action per reachable field, in a fixed order', () {
    final a = contactActions({
      'phone': '03-1234-5678',
      'mobile': '090-1234-5678',
      'email': 'taro@example.com',
      'url': 'www.sunrise.co.jp',
      'postal': '150-0001',
      'address': '東京都渋谷区神宮前1-2-3 サンライズビル5F',
    });
    expect(a.map((x) => x.label), ['電話', '携帯', 'メール', 'ウェブ', '地図']);
    expect(a[0].uri.toString(), 'tel:0312345678');
    expect(a[1].uri.toString(), 'tel:09012345678');
    expect(a[2].uri.toString(), 'mailto:taro@example.com');
    expect(a[3].uri.toString(), 'https://www.sunrise.co.jp', reason: 'scheme added when missing');
    expect(a[4].uri.scheme, 'geo');
    expect(a[4].uri.toString(), contains('q='));
    expect(a[4].uri.queryParameters['q'], '東京都渋谷区神宮前1-2-3 サンライズビル5F');
  });

  test('fax is not an action; empty values are skipped', () {
    final a = contactActions({'fax': '03-0000-0000', 'url': '', 'address': null});
    expect(a, isEmpty);
  });

  test('a full URL keeps its scheme', () {
    expect(contactActions({'url': 'http://example.com/x'}).single.uri.toString(), 'http://example.com/x');
  });
}
