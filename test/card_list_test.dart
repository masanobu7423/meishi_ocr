import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_list.dart';
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

  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

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
