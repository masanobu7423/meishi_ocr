import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/contact_mapper.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';

// 職種 (job) is the user's own classification, pre-filled from dept/title;
// 信頼度 (trust) is 1–5. Both are flat frontmatter keys so an Obsidian base
// or Dataview query can group and sort by them.
void main() {
  final when = DateTime(2026, 10, 26);

  test('job and trust round-trip through JSON and frontmatter', () {
    final f = CardFields()
      ..name = '山田 太郎'
      ..job = '施工管理'
      ..trust = '4';
    expect(CardFields.keys, containsAll(['job', 'trust']));
    final back = fieldsFromJson(f.toJson());
    expect((back.job, back.trust), ('施工管理', '4'));
    final fm = parseFrontmatter(cardNoteMarkdown(f, scannedAt: when));
    expect((fm['job'], fm['trust']), ('施工管理', '4'));
    final again = fieldsFromFrontmatter(fm);
    expect((again.job, again.trust), ('施工管理', '4'));
  });

  test('the note keeps the derived job when none is set, and tags the trust level', () {
    final derived = CardFields()
      ..name = '山田 太郎'
      ..dept = '営業部';
    expect(parseFrontmatter(cardNoteMarkdown(derived, scannedAt: when))['job'], '営業');
    final own = CardFields()
      ..name = '山田 太郎'
      ..dept = '営業部'
      ..job = '不動産'
      ..trust = '5';
    final md = cardNoteMarkdown(own, scannedAt: when);
    expect(parseFrontmatter(md)['job'], '不動産', reason: 'the user wins over the heuristic');
    expect(md, contains('#職種_不動産'));
    expect(md, contains('#信頼度_5'));
    expect(md, contains('信頼度'));
  });

  test('defaultJob pre-fills a fresh read from dept/title and leaves a set value alone', () {
    final f = CardFields()..title = '現場監督';
    expect(defaultJob(f), '施工管理');
    expect(defaultJob(CardFields()..job = '営業'..title = '現場監督'), '営業');
    expect(defaultJob(CardFields()), isNull);
  });

  test('the vault index has a 信頼度別 section and a 信頼度 column', () {
    final note = cardNoteMarkdown(
        CardFields()
          ..name = '山田 太郎'
          ..job = '営業'
          ..trust = '4',
        scannedAt: when);
    final idx = buildIndex({'山田_太郎_2026-10-26': note});
    expect(idx, contains('## 信頼度別'));
    expect(idx, contains('- [[信頼度_4]] (1): [[山田_太郎_2026-10-26|山田 太郎]]'));
    expect(idx, contains('| 氏名 | 会社 | 職種 | 信頼度 | 地域 | 取込日 |'));
  });

  test('CardSummary carries job and trust; searchCards filters by job and minimum trust', () {
    CardSummary c(String stem, String? job, String? trust) =>
        CardSummary(noteStem: stem, stem: stem, name: stem, job: job, trust: trust);
    final cards = [c('a', '営業', '5'), c('b', '施工管理', '3'), c('c', '営業', null), c('d', null, '4')];
    expect(searchCards(cards, job: '営業').map((x) => x.stem), ['a', 'c']);
    expect(searchCards(cards, minTrust: 4).map((x) => x.stem), ['a', 'd']);
    expect(searchCards(cards, job: '営業', minTrust: 4).map((x) => x.stem), ['a']);
    expect(searchCards(cards, query: 'b').map((x) => x.stem), ['b']);
    expect(searchCards(cards).length, 4);
    final parsed = cardSummaries({
      'x': '---\ntype: meishi\nname: 山田 太郎\njob: 営業\ntrust: 4\ntags: [名刺]\n---\n',
    }).single;
    expect((parsed.job, parsed.trust), ('営業', '4'));
    expect(parsed.matches('営業'), isTrue, reason: 'the job is searchable text too');
    expect(jobsOf(cards), ['営業', '施工管理'], reason: 'most used first');
  });

  test('the contact note lists job and trust', () {
    final c = toContact(
        CardFields()
          ..name = '山田 太郎'
          ..job = '営業'
          ..trust = '4',
        scannedAt: when);
    expect(c.notes.single.note, contains('職種: 営業'));
    expect(c.notes.single.note, contains('信頼度: 4'));
  });
}
