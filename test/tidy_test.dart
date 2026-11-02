// 2026-11-02 round 6: tidying that can be undone. Deleting moves a card to
// trash/ (7 days, restorable); two cards of one person merge into one,
// keeping the old card's notes and its old title as history.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/ocr/card_merge.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/theme.dart';

Widget _app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

void main() {
  group('trash', () {
    late Directory tmp;
    late CardStore store;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('meishi_trash_');
      store = CardStore(tmp);
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> save(String stem, String name, {File? image}) => store.saveCard(
        stem: stem, front: const [], back: const [], expected: (CardFields()..name = name).toJson(),
        frontImage: image, scannedAt: DateTime(2026, 10, 1));

    test('delete moves JSON, note and photo to trash; undelete puts them back', () async {
      final img = await File('${tmp.path}/shot.jpg').writeAsBytes([0xFF, 0xD8, 7]);
      await save('k1', '山田 太郎', image: img);
      expect(await store.deleteCard('k1'), isTrue);
      expect(File('${tmp.path}/golden/k1.json').existsSync(), isFalse);
      expect(await store.notes(), isEmpty, reason: 'gone from the vault (and Obsidian)');
      final t = await store.trashed();
      expect(t.map((e) => (e.stem, e.name)), [('k1', '山田 太郎')]);
      expect(await store.undelete('k1'), isTrue);
      expect(File('${tmp.path}/golden/k1.json').existsSync(), isTrue);
      expect(await File('${tmp.path}/vault/images/k1_front.jpg').readAsBytes(), [0xFF, 0xD8, 7]);
      expect((await store.notes()).length, 1);
      expect(await store.trashed(), isEmpty);
      expect(await store.undelete('k1'), isFalse, reason: 'nothing left to restore');
    });

    test('undelete refuses rather than overwrite a card saved meanwhile under the same note name', () async {
      await save('k1', '山田 太郎');
      await store.deleteCard('k1');
      await save('k2', '山田 太郎'); // same name, same day: same note file name
      expect(await store.undelete('k1'), isFalse);
      final notes = await store.notes();
      expect(notes.length, 1);
      expect(parseFrontmatter(notes.values.single)['source'], 'k2.json', reason: 'the new card is untouched');
      expect((await store.trashed()).map((e) => e.stem), ['k1'], reason: 'still in the trash');
    });

    test('trash is not backed up, and is purged after 7 days', () async {
      await save('k1', 'A');
      await save('k2', 'B');
      await store.deleteCard('k1', now: DateTime(2026, 10, 20));
      await store.deleteCard('k2', now: DateTime(2026, 10, 30));
      final (zip, _) = await store.backup();
      expect(String.fromCharCodes(await zip.readAsBytes()), isNot(contains('trash/')));
      expect(await store.purgeTrash(now: DateTime(2026, 11, 2)), 1, reason: 'k1 is 13 days old, k2 only 3');
      expect((await store.trashed()).map((e) => e.stem), ['k2']);
    });

    test('replaceFields rewrites the data and status, keeping the scan date', () async {
      await save('k1', '旧');
      expect(await store.replaceFields('k1', (CardFields()..name = '新').toJson(), CardStatus.registered), isTrue);
      final c = await store.loadCard('k1');
      expect((c!.expected['name'], c.status), ('新', CardStatus.registered));
      expect(cardSummaries(await store.notes()).single.scanned, '2026-10-01');
    });
  });

  group('mergeCards', () {
    final older = {
      'name': '山田 太郎', 'company': '株式会社A', 'dept': '営業部', 'title': '課長', 'phone': '03-1111-2222',
      'email': 'old@a.co.jp', 'memo': '展示会で名刺交換', 'related': '佐藤, 鈴木', 'trust': '4',
      'lastContact': '2026-10-30', 'contactId': '42', 'fax': '03-1111-3333',
    };
    final newer = {
      'name': '山田 太郎', 'company': '株式会社B', 'dept': '工事部', 'title': '部長', 'phone': '03-9999-0000',
      'email': 'taro@b.co.jp', 'memo': '昇進', 'related': '鈴木, 高橋', 'lastContact': '2026-09-01', 'fax': '',
    };

    test('the newer card wins, gaps come from the older, notes and lists are combined', () {
      final m = mergeCards(newer: newer, older: older, olderScanned: '2025-04-01');
      expect((m['company'], m['title'], m['phone'], m['email']), ('株式会社B', '部長', '03-9999-0000', 'taro@b.co.jp'));
      expect(m['fax'], '03-1111-3333', reason: 'empty on the newer card');
      expect(m['trust'], '4');
      expect(m['contactId'], '42', reason: 'the phone-book link is kept');
      expect(m['lastContact'], '2026-10-30', reason: 'the later contact');
      expect(m['related'], '鈴木, 高橋, 佐藤');
      expect(m['memo'], '昇進 / 展示会で名刺交換 / 旧: 株式会社A 営業部 課長（2025-04-01 の名刺）',
          reason: 'one line: frontmatter values cannot hold a line break');
    });

    test('no history line when company, department and title are the same; memo not doubled', () {
      final m = mergeCards(newer: {...older, 'phone': '090-1'}, older: older, olderScanned: '2025-04-01');
      expect(m['memo'], '展示会で名刺交換');
      expect(m['phone'], '090-1');
    });

    test('status: the more advanced of the two', () {
      expect(mergedStatus(CardStatus.unreviewed, CardStatus.registered), CardStatus.registered);
      expect(mergedStatus(CardStatus.reviewed, CardStatus.unreviewed), CardStatus.reviewed);
    });
  });

  testWidgets('the selection bar offers まとめる for exactly two cards', (t) async {
    final merged = <List<String>>[];
    await t.pumpWidget(_app(CardList(
      cards: const [
        CardSummary(noteStem: 'a', stem: 'a', name: '山田 太郎'),
        CardSummary(noteStem: 'b', stem: 'b', name: '山田 太郎（新）'),
        CardSummary(noteStem: 'c', stem: 'c', name: '佐藤 花子'),
      ],
      vault: Directory.systemTemp,
      onTap: (_) {},
      onDelete: (_) async {},
      onMerge: (a, b) async => merged.add([a.stem, b.stem]),
    )));
    await t.longPress(find.text('山田 太郎'));
    await t.pump();
    expect(find.text('まとめる'), findsNothing, reason: 'one card');
    await t.tap(find.text('山田 太郎（新）'));
    await t.pump();
    await t.tap(find.text('まとめる'));
    await t.pump();
    expect(merged, [['a', 'b']]);
  });

  testWidgets('the 重複 filter explains how to merge', (t) async {
    await t.pumpWidget(_app(ListScreen(
      cards: const [
        CardSummary(noteStem: 'x', stem: 'x', name: '二重 太郎', phone: '03-1111-2222'),
        CardSummary(noteStem: 'y', stem: 'y', name: '二重 次郎', phone: '03-1111-2222'),
      ],
      vault: Directory.systemTemp,
      onTap: (_) {},
      filter: StatusFilter.duplicate,
      onMerge: (_, _) async {},
    )));
    expect(find.textContaining('「まとめる」'), findsOneWidget);
  });
}
