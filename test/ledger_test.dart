// 2026-10-29 round 2: the search tab as a partner ledger (call, group by
// company, prefecture), home tiles that wrap, 連絡済み, the menu sheets.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/choice_sheet.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/actions.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/theme.dart';

const _ledger = [
  CardSummary(noteStem: 'a', stem: 'a', name: '山田 太郎', company: 'サンライズ建設', mobile: '090-1111-2222',
      phone: '03-1111-0000', pref: '東京都', job: '鳶', scanned: '2026-10-20'),
  CardSummary(noteStem: 'b', stem: 'b', name: '佐藤 花子', company: 'サンライズ建設', phone: '03-1111-0000',
      pref: '東京都', job: '左官', scanned: '2026-10-21'),
  CardSummary(noteStem: 'c', stem: 'c', name: '鈴木 一郎', company: '大阪鉄筋', pref: '大阪府', job: '鉄筋',
      scanned: '2026-10-22'),
];

Widget _app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

void main() {
  group('quickCall', () {
    test('prefers the mobile, falls back to the office line, null without numbers', () {
      expect(quickCall(phone: '03-1111-0000', mobile: '090-1111-2222')!.uri.toString(), 'tel:09011112222');
      expect(quickCall(phone: '03-1111-0000', mobile: ' ')!.label, '電話');
      expect(quickCall(), isNull);
    });
  });

  test('pref is read from the note, searchable as a filter, and listed most used first', () {
    final md = cardNoteMarkdown(CardFields()
      ..name = '山田 太郎'
      ..address = '大阪府大阪市北区1-1', scannedAt: DateTime(2026, 10, 29));
    expect(cardSummaries({'n': md}).single.pref, '大阪府');
    expect(searchCards(_ledger, pref: '東京都').map((c) => c.stem), ['a', 'b']);
    expect(prefsOf(_ledger), ['東京都', '大阪府']);
    expect(jobsOf(_ledger), ['鳶', '左官', '鉄筋'], reason: 'jobsOf still works after sharing the counter');
  });

  testWidgets('a row with a number has a call button that reports the card; one without has none', (t) async {
    final called = <String>[];
    await t.pumpWidget(_app(CardList(
        cards: _ledger, vault: Directory.systemTemp, onTap: (_) {}, onCall: (c) => called.add(c.stem))));
    expect(find.byTooltip('携帯に電話'), findsOneWidget);
    expect(find.byTooltip('電話'), findsOneWidget);
    await t.tap(find.byTooltip('携帯に電話'));
    expect(called, ['a']);
  });

  testWidgets('group by company puts a header with the head count above each company', (t) async {
    await t.pumpWidget(_app(CardList(
        cards: _ledger, vault: Directory.systemTemp, onTap: (_) {}, groupByCompany: true)));
    expect(find.text('サンライズ建設（2 人）'), findsOneWidget);
    expect(find.text('大阪鉄筋（1 人）'), findsOneWidget);
  });

  testWidgets('the search tab filters by prefecture and can group by company', (t) async {
    await t.pumpWidget(_app(SearchScreen(cards: _ledger, vault: Directory.systemTemp, onTap: (_) {})));
    await t.tap(find.widgetWithText(FilterChip, '大阪府'));
    await t.pump();
    expect(find.text('鈴木 一郎'), findsOneWidget);
    expect(find.text('山田 太郎'), findsNothing);
    await t.tap(find.widgetWithText(FilterChip, '大阪府'));
    await t.tap(find.text('会社でまとめる'));
    await t.pump();
    expect(find.text('サンライズ建設（2 人）'), findsOneWidget);
  });

  testWidgets('home tiles wrap two per row: four tiles on a 360dp phone at 1.3x text do not overflow', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final cards = [
      const CardSummary(noteStem: 'u', stem: 'u', name: 'A', status: CardStatus.unreviewed, phone: '03-1'),
      const CardSummary(noteStem: 'r', stem: 'r', name: 'B', phone: '03-1', nextContact: '2026-10-28'),
    ];
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: HomeScreen(
            cards: cards, vault: Directory.systemTemp, today: DateTime(2026, 10, 29),
            onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
            onContinue: (_) {},
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    for (final l in ['未確認', '未登録', '連絡予定', '重複']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(t.getTopLeft(find.text('連絡予定')).dy, greaterThan(t.getTopLeft(find.text('未確認')).dy),
        reason: 'the third tile starts a second row');
  });

  testWidgets('連絡済み appears only when a selected card has a date, and hands over only dated cards', (t) async {
    final done = <List<String>>[];
    await t.pumpWidget(_app(CardList(
      cards: const [
        CardSummary(noteStem: 'x', stem: 'x', name: '期日 あり', nextContact: '2026-11-01'),
        CardSummary(noteStem: 'y', stem: 'y', name: '期日 なし'),
      ],
      vault: Directory.systemTemp,
      onTap: (_) {},
      onDelete: (_) async {},
      onFollowedUp: (cs) async => done.add([for (final c in cs) c.stem]),
    )));
    await t.longPress(find.text('期日 なし'));
    await t.pump();
    expect(find.text('連絡済み'), findsNothing);
    await t.tap(find.text('すべて選択'));
    await t.pump();
    await t.tap(find.text('連絡済み'));
    await t.pump();
    expect(done, [['x']]);
  });

  test('setNextContact clears the date in JSON and note, keeping status and scan date', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_ledger_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(stem: 'k', front: const [], back: const [],
        expected: (CardFields()
              ..name = '山田 太郎'
              ..nextContact = '2026-11-01')
            .toJson(),
        status: CardStatus.registered, scannedAt: DateTime(2026, 10, 1));
    expect(await store.setNextContact('k', null), isTrue);
    final c = await store.loadCard('k');
    expect((c!.expected['nextContact'], c.status), (null, CardStatus.registered));
    final fm = parseFrontmatter((await store.notes()).values.single);
    expect(fm['next_contact'], isNull);
    expect(fm['scanned'], '2026-10-01');
    expect(await store.setNextContact('missing', null), isFalse);
  });

  testWidgets('a choice sheet lists titled options with their purpose and returns the tapped one', (t) async {
    String? picked;
    await t.pumpWidget(_app(Builder(
      builder: (context) => TextButton(
        onPressed: () async => picked = await showChoiceSheet<String>(context, '書き出し・共有', const [
          Choice('csv', Icons.table_chart_outlined, 'CSV で共有', 'Excel で開く'),
          Choice('ics', Icons.event_outlined, '連絡予定を共有（ics）', 'カレンダーに読み込む'),
        ]),
        child: const Text('open'),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('書き出し・共有'), findsOneWidget);
    expect(find.text('Excel で開く'), findsOneWidget);
    await t.tap(find.text('連絡予定を共有（ics）'));
    await t.pumpAndSettle();
    expect(picked, 'ics');
  });

  testWidgets('a row with a call button, a due date and a status fits a 360dp phone at 1.3x text', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: CardList(
            cards: const [
              CardSummary(noteStem: 'a', stem: 'a', name: '長谷川 健太郎', company: '株式会社サンライズ建設工業',
                  mobile: '090-1111-2222', nextContact: '2026-10-01', scanned: '2026-10-20'),
            ],
            vault: Directory.systemTemp,
            onTap: (_) {},
            onCall: (_) {},
            today: DateTime(2026, 10, 29),
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.byTooltip('携帯に電話'), findsOneWidget);
  });

  testWidgets('a short search body (keyboard open) hides the chip rows instead of overflowing', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 280,
              child: SearchScreen(cards: _ledger, vault: Directory.systemTemp, onTap: (_) {}),
            ),
          ),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.widgetWithText(FilterChip, '鳶'), findsNothing);
    expect(find.text('3 件'), findsOneWidget, reason: 'the count stays visible');
  });
}
