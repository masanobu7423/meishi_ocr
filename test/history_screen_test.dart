import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/history_screen.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  final cards = [
    const CardSummary(noteStem: 'a', stem: 'k01', name: '山田 太郎', company: '株式会社サンライズ', scanned: '2026-10-24'),
    const CardSummary(noteStem: 'b', stem: 'k02', name: '鈴木 一郎', company: 'トビショク商事', scanned: '2026-10-25'),
  ];
  Widget app(Widget home) => MaterialApp(theme: appTheme(), home: home);

  testWidgets('lists cards, filters by search, pops the tapped card', (t) async {
    CardSummary? picked;
    await t.pumpWidget(app(Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () async {
            picked = await Navigator.push(ctx, MaterialPageRoute(
                builder: (_) => HistoryScreen(cards: cards, vault: Directory.systemTemp)));
          },
          child: const Text('open'),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('保存した名刺（2）'), findsOneWidget);
    expect(find.text('山田 太郎'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'とびしょく');
    await t.pump();
    expect(find.text('山田 太郎'), findsNothing);
    expect(find.text('鈴木 一郎'), findsOneWidget);
    await t.tap(find.text('鈴木 一郎'));
    await t.pumpAndSettle();
    expect(picked?.stem, 'k02');
  });

  testWidgets('empty state invites the first scan', (t) async {
    await t.pumpWidget(app(HistoryScreen(cards: const [], vault: Directory.systemTemp)));
    expect(find.textContaining('まだ名刺がありません'), findsOneWidget);
  });
}
