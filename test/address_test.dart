import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/address.dart';

void main() {
  test('47 prefectures, Hokkaido first, Okinawa last', () {
    expect(prefectures.length, 47);
    expect(prefectures.first, '北海道');
    expect(prefectures.last, '沖縄県');
    expect(prefectures, contains('東京都'));
  });

  test('splits a typical Tokyo address with building and floor', () {
    final p = splitAddress('東京都渋谷区神宮前1-2-3 サンライズビル5F');
    expect(p.pref, '東京都');
    expect(p.city, '渋谷区');
    expect(p.town, '神宮前');
    expect(p.block, '1-2-3');
    expect(p.building, 'サンライズビル');
    expect(p.room, '5F');
  });

  test('splits 市+区, 丁目/番/号 and a room number', () {
    final p = splitAddress('神奈川県横浜市中区本町1丁目2番3号 ABCタワー 1201号室');
    expect(p.city, '横浜市中区');
    expect(p.town, '本町1丁目');
    expect(p.block, '2番3号');
    expect(p.building, 'ABCタワー');
    expect(p.room, '1201号室');
  });

  test('splits 郡+町 and a numbered town name', () {
    expect(splitAddress('北海道札幌市北区北8条西5丁目1-1').town, '北8条西5丁目');
    final p = splitAddress('沖縄県島尻郡与那原町与那原123');
    expect(p.city, '島尻郡与那原町');
    expect(p.town, '与那原');
    expect(p.block, '123');
    expect(p.building, isNull);
  });

  test('丁目 inside a building name does not swallow the block', () {
    final p = splitAddress('東京都千代田区丸の内1-2-3 丸の内2丁目ビル 5F');
    expect(p.town, '丸の内');
    expect(p.block, '1-2-3');
    expect(p.building, '丸の内2丁目ビル');
    expect(p.room, '5F');
  });

  test('cities whose names contain 郡 are not split as districts', () {
    expect(splitAddress('愛知県蒲郡市神明町2-2').city, '蒲郡市');
    expect(splitAddress('奈良県大和郡山市北郡山町1').city, '大和郡山市');
    expect(splitAddress('愛知県愛知郡東郷町春木1').city, '愛知郡東郷町');
  });

  test('unknown prefix leaves pref null but keeps the text', () {
    final p = splitAddress('渋谷区神宮前1-2-3');
    expect(p.pref, isNull);
    expect(p.city, '渋谷区');
    expect(splitAddress(null).pref, isNull);
    expect(splitAddress('').town, isNull);
  });

  test('joinAddress rebuilds the string and round-trips', () {
    const s = '東京都渋谷区神宮前1-2-3 サンライズビル5F';
    expect(joinAddress(splitAddress(s)), s);
    expect(joinAddress((pref: '大阪府', city: '大阪市北区', town: null, block: null, building: null, room: null)),
        '大阪府大阪市北区');
    expect(joinAddress((pref: null, city: null, town: null, block: null, building: null, room: null)), '');
  });
}
