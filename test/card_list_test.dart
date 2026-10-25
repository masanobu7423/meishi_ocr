import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/theme.dart';

final _cards = [
  const CardSummary(noteStem: 'a', stem: 'k01', name: '山田 太郎', company: '株式会社サンライズ', scanned: '2026-10-24'),
  const CardSummary(noteStem: 'b', stem: 'k02', name: '鈴木 一郎', company: 'トビショク商事', scanned: '2026-10-25'),
  const CardSummary(noteStem: 'c', stem: 'k03', name: '佐藤 花子', company: '株式会社サンライズ', scanned: '2026-10-23'),
];

void main() {
  group('sortCards', () {
    test('by date newest first, by company then name, by name', () {
      expect(sortCards(_cards, CardSort.date).map((c) => c.stem), ['k02', 'k01', 'k03']);
      expect(sortCards(_cards, CardSort.company).map((c) => c.stem), ['k02', 'k03', 'k01'],
          reason: 'トビショク商事 < 株式会社サンライズ by code point; within a company by name');
      expect(sortCards(_cards, CardSort.name).map((c) => c.stem), ['k03', 'k01', 'k02']);
    });
  });

  final mixed = [
    const CardSummary(noteStem: 'u', stem: 'u1', name: '未確認 一郎', status: CardStatus.unreviewed, scanned: '2026-10-26'),
    const CardSummary(noteStem: 'r', stem: 'r1', name: '確認 二郎', status: CardStatus.reviewed, scanned: '2026-10-25'),
    const CardSummary(noteStem: 'g', stem: 'g1', name: '登録 三郎', status: CardStatus.registered, scanned: '2026-10-24'),
  ];

  test('filterCards: all / unreviewed / not yet registered', () {
    expect(filterCards(mixed, StatusFilter.all).map((c) => c.stem), ['u1', 'r1', 'g1']);
    expect(filterCards(mixed, StatusFilter.unreviewed).map((c) => c.stem), ['u1']);
    expect(filterCards(mixed, StatusFilter.unregistered).map((c) => c.stem), ['u1', 'r1']);
  });

  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

  testWidgets('long-press selects; the bar offers 修正 for one card and 削除 for all selected', (t) async {
    final deleted = <List<String>>[];
    CardSummary? opened;
    await t.pumpWidget(app(CardList(
      cards: _cards,
      vault: Directory.systemTemp,
      onTap: (c) => opened = c,
      onDelete: (cs) async => deleted.add(cs.map((c) => c.stem).toList()),
    )));
    expect(find.byType(Checkbox), findsNothing);
    await t.longPress(find.text('山田 太郎'));
    await t.pump();
    expect(find.text('1 件を選択中'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
    await t.tap(find.text('修正'));
    await t.pump();
    expect(opened?.stem, 'k01');
    expect(find.byType(Checkbox), findsNothing, reason: 'editing leaves selection mode');

    await t.longPress(find.text('山田 太郎'));
    await t.pump();
    await t.tap(find.text('鈴木 一郎'));
    await t.pump();
    expect(find.text('2 件を選択中'), findsOneWidget);
    expect(find.text('修正'), findsNothing, reason: 'only one card can be edited at a time');
    await t.tap(find.text('すべて選択'));
    await t.pump();
    expect(find.text('3 件を選択中'), findsOneWidget);
    await t.tap(find.text('削除'));
    await t.pump();
    expect(deleted, [['k01', 'k02', 'k03']], reason: 'list order');
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('without onDelete a long-press does nothing', (t) async {
    await t.pumpWidget(app(CardList(cards: _cards, vault: Directory.systemTemp, onTap: (_) {})));
    await t.longPress(find.text('山田 太郎'));
    await t.pump();
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('CardList shows the status of cards that still need work', (t) async {
    await t.pumpWidget(app(CardList(cards: mixed, vault: Directory.systemTemp, onTap: (_) {})));
    expect(find.text('未確認'), findsOneWidget);
    expect(find.text('未登録'), findsOneWidget);
    expect(find.text('登録済'), findsNothing, reason: 'done cards stay quiet');
  });

  testWidgets('ListScreen filter chips narrow the list', (t) async {
    StatusFilter? chosen;
    await t.pumpWidget(app(ListScreen(
      cards: mixed, vault: Directory.systemTemp, onTap: (_) {},
      filter: StatusFilter.unreviewed, onFilter: (f) => chosen = f,
    )));
    expect(find.text('未確認 一郎'), findsOneWidget);
    expect(find.text('確認 二郎'), findsNothing);
    await t.tap(find.text('未登録'));
    expect(chosen, StatusFilter.unregistered);
  });

  testWidgets('CardList shows every card and reports taps', (t) async {
    CardSummary? tapped;
    await t.pumpWidget(app(CardList(cards: _cards, vault: Directory.systemTemp, onTap: (c) => tapped = c)));
    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('佐藤 花子'), findsOneWidget);
    await t.tap(find.text('鈴木 一郎'));
    expect(tapped?.stem, 'k02');
  });

  testWidgets('SearchScreen filters as you type and explains an empty result', (t) async {
    await t.pumpWidget(app(SearchScreen(cards: _cards, vault: Directory.systemTemp, onTap: (_) {})));
    expect(find.text('山田 太郎'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'さんらいず');
    await t.pump();
    expect(find.text('山田 太郎'), findsOneWidget);
    expect(find.text('佐藤 花子'), findsOneWidget);
    expect(find.text('鈴木 一郎'), findsNothing);
    await t.enterText(find.byType(TextField), 'いない');
    await t.pump();
    expect(find.textContaining('合う名刺はありません'), findsOneWidget);
  });

  testWidgets('ListScreen switches sort order with the segmented control', (t) async {
    await t.pumpWidget(app(ListScreen(cards: _cards, vault: Directory.systemTemp, onTap: (_) {})));
    String? firstTitle() => (t.widget<ListTile>(find.byType(ListTile).first).title as Text).data;
    expect(firstTitle(), '鈴木 一郎'); // newest
    await t.tap(find.text('氏名順'));
    await t.pumpAndSettle();
    expect(firstTitle(), '佐藤 花子');
    await t.tap(find.text('会社順'));
    await t.pumpAndSettle();
    expect(find.text('トビショク商事'), findsWidgets);
    expect(firstTitle(), '鈴木 一郎');
  });

  testWidgets('empty list invites the first scan', (t) async {
    await t.pumpWidget(app(ListScreen(cards: const [], vault: Directory.systemTemp, onTap: (_) {})));
    expect(find.textContaining('まだ名刺がありません'), findsOneWidget);
  });
}
