import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/extractor.dart';

void main() {
  final f = CardFields()
    ..name = '山田 太郎'
    ..nameKana = 'やまだ たろう'
    ..company = '株式会社サンライズ'
    ..dept = '営業部'
    ..title = '部長'
    ..phone = '03-1234-5678'
    ..mobile = '090-1234-5678'
    ..email = 'taro.yamada@sunrise.co.jp'
    ..postal = '150-0001'
    ..address = '東京都渋谷区神宮前1-2-3 サンライズビル5F';
  final when = DateTime(2026, 10, 24);

  test('markdown has flat frontmatter, inline tags without /, wiki links', () {
    final md = cardNoteMarkdown(f, scannedAt: when, source: 's01.jpg');
    expect(md, startsWith('---\ntype: meishi\nname: 山田 太郎\n'));
    expect(md, contains('pref: 東京都\ncity: 渋谷区\n'));
    expect(md, contains('job: 営業\n'));
    expect(md, contains('tags: [名刺, 会社_サンライズ, 職種_営業, 役職_部長, 部署_営業部, '
        '地域_東京都, 市区_渋谷区, 市外局番_03, ドメイン_sunrise_co_jp, 取込_2026-10]\n'));
    expect(md, contains('- 会社: [[株式会社サンライズ]]\n'));
    expect(md, contains('- 住所: 〒150-0001 [[東京都]]渋谷区神宮前1-2-3 サンライズビル5F\n'));
    expect(md, endsWith('#名刺 #会社_サンライズ #職種_営業 #役職_部長 #部署_営業部 '
        '#地域_東京都 #市区_渋谷区 #市外局番_03 #ドメイン_sunrise_co_jp #取込_2026-10\n'));
    // FastaLife's tag regex: no '/', '.', '@' or spaces may survive tagify.
    expect(RegExp(r'#\S+').allMatches(md).map((m) => m[0]!),
        everyElement(matches(RegExp(r'^#[\w぀-ゟ゠-ヿ一-鿿-]+$'))));
  });

  test('memo goes into the frontmatter and the body', () {
    final md = cardNoteMarkdown(f..memo = '2026-10-24 展示会で名刺交換', scannedAt: when);
    expect(md, contains('memo: 2026-10-24 展示会で名刺交換\n'));
    expect(md, contains('- メモ: 2026-10-24 展示会で名刺交換\n'));
  });

  test('filename is sanitized and dated', () {
    expect(cardNoteFilename(f, when), '山田_太郎_2026-10-24.md');
    expect(cardNoteFilename(CardFields(), when), '名無し_2026-10-24.md');
  });

  test('jobCategory maps dept/title words', () {
    expect(jobCategory('プロダクト開発本部', 'シニアエンジニア'), '技術開発');
    expect(jobCategory(null, '代表取締役社長'), '経営');
    expect(jobCategory(null, null), isNull);
  });
}
