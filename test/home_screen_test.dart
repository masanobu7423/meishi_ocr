import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  final cards = [
    for (var i = 0; i < 7; i++)
      CardSummary(noteStem: 'n$i', stem: 'k$i', name: '名前$i', company: '会社$i', scanned: '2026-10-${20 + i}'),
  ];
  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

  testWidgets('home shows totals, this month, the 5 most recent cards and the primary actions', (t) async {
    final taps = <String>[];
    await t.pumpWidget(app(HomeScreen(
      cards: cards,
      vault: Directory.systemTemp,
      today: DateTime(2026, 10, 26),
      onScan: () => taps.add('scan'),
      onAlbum: () => taps.add('album'),
      onImport: () => taps.add('import'),
      onOpenCard: (c) => taps.add('open ${c.stem}'),
      onSeeAll: () => taps.add('all'),
    )));
    expect(find.text('7'), findsNWidgets(2)); // total and this month
    expect(find.text('今月の取込'), findsOneWidget);
    expect(find.text('名前6'), findsOneWidget); // newest
    expect(find.text('名前1'), findsNothing); // only 5 recent
    await t.tap(find.text('名刺を撮影'));
    await t.tap(find.text('名前6'));
    await t.tap(find.text('すべて見る'));
    expect(taps, ['scan', 'open k6', 'all']);
  });

  testWidgets('home counts cards still to review or register and offers to continue', (t) async {
    final taps = <String>[];
    final mixed = [
      const CardSummary(noteStem: 'u', stem: 'u1', name: 'A', status: CardStatus.unreviewed, scanned: '2026-10-26'),
      const CardSummary(noteStem: 'r', stem: 'r1', name: 'B', status: CardStatus.reviewed, scanned: '2026-10-25'),
      const CardSummary(noteStem: 'g', stem: 'g1', name: 'C', status: CardStatus.registered, scanned: '2026-10-24'),
    ];
    await t.pumpWidget(app(HomeScreen(
      cards: mixed, vault: Directory.systemTemp, today: DateTime(2026, 10, 26),
      onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
      onContinue: (f) => taps.add(f.name),
    )));
    expect(find.text('未確認'), findsOneWidget);
    expect(find.text('未登録'), findsOneWidget);
    await t.tap(find.text('未確認'));
    await t.tap(find.text('未登録'));
    expect(taps, ['unreviewed', 'unregistered']);
  });

  testWidgets('home with no cards explains what to do', (t) async {
    await t.pumpWidget(app(HomeScreen(
      cards: const [], vault: Directory.systemTemp, today: DateTime(2026, 10, 26),
      onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
    )));
    expect(find.textContaining('最初の名刺を撮影'), findsOneWidget);
    expect(find.text('すべて見る'), findsNothing);
  });
}
