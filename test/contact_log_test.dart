// 2026-11-02 round 3: the contact log. 最終連絡日 (lastContact) is recorded
// by 連絡済み, which also asks for the next follow-up; the ledger finds
// people not contacted for a while; home lists the due follow-ups.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_form.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/contact_mapper.dart';
import 'package:meishi_ocr/ocr/csv_export.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/theme.dart';

final _today = DateTime(2026, 11, 2);

Widget _app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

void main() {
  group('最終連絡日 travels everywhere a field goes', () {
    final f = CardFields()
      ..name = '山田 太郎'
      ..lastContact = '2026-10-30';

    test('note frontmatter, summary, CSV header and contact note round trip', () {
      final md = cardNoteMarkdown(f, scannedAt: DateTime(2026, 10, 1));
      expect(parseFrontmatter(md)['last_contact'], '2026-10-30');
      expect(cardSummaries({'n': md}).single.lastContact, '2026-10-30');
      expect(csvOfNotes({'n': md}).split('\r\n').first, contains('"最終連絡日"'));
      final contact = toContact(f, scannedAt: DateTime(2026, 10, 1));
      expect(contact.notes.single.note, contains('最終連絡: 2026-10-30'));
      expect(fieldsFromContact(contact).lastContact, '2026-10-30');
    });
  });

  group('follow-up dates', () {
    test('weeks add days; months keep the day or clamp to the month end', () {
      expect(ymd(followUpDate(_today, FollowUp.week)), '2026-11-09');
      expect(ymd(followUpDate(_today, FollowUp.twoWeeks)), '2026-11-16');
      expect(ymd(followUpDate(_today, FollowUp.month)), '2026-12-02');
      expect(ymd(followUpDate(DateTime(2027, 1, 31), FollowUp.month)), '2027-02-28');
      expect(ymd(followUpDate(DateTime(2026, 11, 30), FollowUp.threeMonths)), '2027-02-28');
      expect(ymd(followUpDate(DateTime(2028, 1, 31), FollowUp.month)), '2028-02-29', reason: 'leap year');
    });

    test('dormant = last contact (or the scan date) older than the window; undated never counts', () {
      const old = CardSummary(noteStem: 'a', stem: 'a', name: 'A', scanned: '2026-06-01');
      const recentScan = CardSummary(noteStem: 'b', stem: 'b', name: 'B', scanned: '2026-10-20');
      const talked = CardSummary(noteStem: 'c', stem: 'c', name: 'C', scanned: '2026-01-01', lastContact: '2026-10-25');
      const undated = CardSummary(noteStem: 'd', stem: 'd', name: 'D');
      expect([old, recentScan, talked, undated].where((c) => isDormant(c, _today)).map((c) => c.stem), ['a']);
      expect(searchCards([old, recentScan, talked], dormantOn: _today).map((c) => c.stem), ['a']);
    });

    test('exactly 90 days counts as ご無沙汰 (the label says 90 日以上); 89 does not', () {
      const day90 = CardSummary(noteStem: 'a', stem: 'a', name: 'A', lastContact: '2026-08-04');
      const day89 = CardSummary(noteStem: 'b', stem: 'b', name: 'B', lastContact: '2026-08-05');
      expect(isDormant(day90, _today), isTrue);
      expect(isDormant(day89, _today), isFalse);
    });

    test('pulling from the phone book never moves the contact log backwards', () {
      // 連絡済み does not write to the phone book, so its note can be older.
      final current = {'name': '山田 太郎', 'lastContact': '2026-11-02', 'nextContact': ''};
      expect(pullChanges(current, {'lastContact': '2026-09-01', 'nextContact': '2026-10-01'}), isEmpty,
          reason: 'an older last contact, and a follow-up already done, are stale');
      expect(pullChanges(current, {'lastContact': '2026-11-05', 'nextContact': '2026-12-01'}),
          {'lastContact': '2026-11-05', 'nextContact': '2026-12-01'});
      expect(pullChanges({'name': 'X'}, {'lastContact': '2026-09-01', 'nextContact': '2026-10-01'}),
          {'lastContact': '2026-09-01', 'nextContact': '2026-10-01'}, reason: 'nothing logged here yet');
    });
  });

  test('setFollowUp records the last contact and the next date, keeping status and scan date', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_log_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(stem: 'k', front: const [], back: const [],
        expected: (CardFields()
              ..name = '山田 太郎'
              ..nextContact = '2026-11-01')
            .toJson(),
        status: CardStatus.registered, scannedAt: DateTime(2026, 10, 1));
    expect(await store.setFollowUp('k', last: '2026-11-02', next: '2026-12-02'), isTrue);
    final c = await store.loadCard('k');
    expect((c!.expected['lastContact'], c.expected['nextContact'], c.status),
        ('2026-11-02', '2026-12-02', CardStatus.registered));
    final fm = parseFrontmatter((await store.notes()).values.single);
    expect((fm['last_contact'], fm['next_contact'], fm['scanned']), ('2026-11-02', '2026-12-02', '2026-10-01'));
    expect(await store.setFollowUp('k', last: '2026-11-03', next: null), isTrue);
    expect((await store.loadCard('k'))!.expected['nextContact'], isNull);
    expect(await store.setFollowUp('missing', last: '2026-11-02', next: null), isFalse);
  });

  testWidgets('the form has a 最終連絡日 date field next to 次回連絡日, without a calendar button', (t) async {
    final ctl = {for (final k in CardFields.keys) k: TextEditingController()};
    addTearDown(() {
      for (final x in ctl.values) {
        x.dispose();
      }
    });
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(_app(CardForm(controllers: ctl, lines: const [], today: _today, onCalendar: (_) {})));
    expect(find.text('最終連絡日'), findsOneWidget);
    await t.tap(find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['lastContact']));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(ctl['lastContact']!.text, '2026-11-02');
    expect(find.text('カレンダーに登録'), findsNothing, reason: 'only a future follow-up goes to the calendar');
  });

  testWidgets('rows show the last contact; the ledger narrows to dormant cards', (t) async {
    const cards = [
      CardSummary(noteStem: 'a', stem: 'a', name: '久しぶり 太郎', scanned: '2026-05-01'),
      CardSummary(noteStem: 'b', stem: 'b', name: '最近 花子', scanned: '2026-05-01', lastContact: '2026-10-30'),
    ];
    await t.pumpWidget(_app(SearchScreen(cards: cards, vault: Directory.systemTemp, onTap: (_) {}, today: _today)));
    expect(find.text('最終連絡 10/30'), findsOneWidget);
    await t.tap(find.text('ご無沙汰（90 日以上）'));
    await t.pump();
    expect(find.text('久しぶり 太郎'), findsOneWidget);
    expect(find.text('最近 花子'), findsNothing);
  });

  testWidgets('home lists the three soonest follow-ups with call buttons', (t) async {
    final called = <String>[];
    final cards = [
      for (final (i, d) in ['2026-11-05', '2026-10-30', '2026-11-01', '2026-11-08'].indexed)
        CardSummary(noteStem: 'n$i', stem: 's$i', name: '予定$i', mobile: '090-0000-000$i', nextContact: d,
            scanned: '2026-09-0${i + 1}', status: CardStatus.registered),
    ];
    await t.pumpWidget(_app(HomeScreen(
      cards: cards, vault: Directory.systemTemp, today: _today,
      onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
      onContinue: (_) {}, onCall: (c) => called.add(c.stem),
    )));
    expect(find.text('連絡予定の相手'), findsOneWidget);
    final due = find.descendant(of: find.byKey(const ValueKey('home-due')), matching: find.byType(ListTile));
    expect(due, findsNWidgets(3));
    expect(find.descendant(of: find.byKey(const ValueKey('home-due')), matching: find.text('予定3')), findsNothing,
        reason: '11/08 is the fourth');
    await t.tap(find.descendant(of: find.byKey(const ValueKey('home-due')), matching: find.byTooltip('携帯に電話')).first);
    expect(called, ['s1'], reason: 'soonest first: 10/30 (overdue)');
  });

  testWidgets('home due list fits a 360dp phone at 1.3x text', (t) async {
    t.view.physicalSize = const Size(360, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 1600), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: HomeScreen(
            cards: const [
              CardSummary(noteStem: 'a', stem: 'a', name: '長谷川 健太郎', company: '株式会社サンライズ建設工業',
                  mobile: '090-1111-2222', nextContact: '2026-10-01', lastContact: '2026-09-01', scanned: '2026-09-01'),
            ],
            vault: Directory.systemTemp, today: _today,
            onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
            onContinue: (_) {}, onCall: (_) {},
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('連絡済み is offered in the search tab too', (t) async {
    final done = <String>[];
    await t.pumpWidget(_app(SearchScreen(
      cards: const [CardSummary(noteStem: 'x', stem: 'x', name: '期日 あり', nextContact: '2026-11-01')],
      vault: Directory.systemTemp,
      onTap: (_) {},
      onDelete: (_) async {},
      onFollowedUp: (cs) async => done.addAll(cs.map((c) => c.stem)),
    )));
    await t.longPress(find.text('期日 あり'));
    await t.pump();
    await t.tap(find.text('連絡済み'));
    await t.pump();
    expect(done, ['x']);
  });

  testWidgets('連絡済み is offered for any selected card, not only dated ones (it records the contact)', (t) async {
    final done = <String>[];
    await t.pumpWidget(_app(CardList(
      cards: const [CardSummary(noteStem: 'y', stem: 'y', name: '期日 なし')],
      vault: Directory.systemTemp,
      onTap: (_) {},
      onDelete: (_) async {},
      onFollowedUp: (cs) async => done.addAll(cs.map((c) => c.stem)),
    )));
    await t.longPress(find.text('期日 なし'));
    await t.pump();
    await t.tap(find.text('連絡済み'));
    await t.pump();
    expect(done, ['y']);
  });
}
