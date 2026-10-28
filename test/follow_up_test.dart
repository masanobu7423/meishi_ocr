// 次回連絡日 (next contact date): a follow-up reminder the app keeps per card.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_form.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/contact_mapper.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  final today = DateTime(2026, 10, 28);
  CardSummary c(String stem, String? next, {String? scanned}) =>
      CardSummary(noteStem: stem, stem: stem, name: stem, nextContact: next, scanned: scanned ?? '2026-10-01');
  final cards = [c('a', '2026-10-20'), c('b', '2026-11-03'), c('c', null), c('d', '2026-10-28'), c('e', '2026-12-01')];

  test('parseYmd reads yyyy-mm-dd and rejects junk; dueCards = overdue or within the window, soonest first', () {
    expect(parseYmd('2026-10-28'), DateTime(2026, 10, 28));
    expect(parseYmd('2026/10/28'), isNull);
    expect(parseYmd(''), isNull);
    expect(parseYmd('2026-13-45'), isNull, reason: 'not a real date');
    expect(parseYmd('2026-02-30'), isNull);
    expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
    expect(dueCards(cards, today: today).map((x) => x.stem), ['a', 'd', 'b'], reason: '7-day window by default');
    expect(dueCards(cards, today: today, days: 0).map((x) => x.stem), ['a', 'd']);
    expect(isOverdue(cards[0], today), isTrue);
    expect(isOverdue(cards[3], today), isFalse, reason: 'today is not overdue');
  });

  test('the 連絡予定 filter lists every dated card soonest first', () {
    expect(filterCards(cards, StatusFilter.due).map((x) => x.stem), ['a', 'd', 'b', 'e']);
  });

  test('nextContact round-trips JSON, frontmatter, summary and the contact note', () {
    final f = CardFields()
      ..name = '山田 太郎'
      ..nextContact = '2026-11-03';
    expect(fieldsFromJson(f.toJson()).nextContact, '2026-11-03');
    final md = cardNoteMarkdown(f, scannedAt: today);
    expect(parseFrontmatter(md)['next_contact'], '2026-11-03');
    expect(fieldsFromFrontmatter(parseFrontmatter(md)).nextContact, '2026-11-03');
    expect(cardSummaries({'x': md}).single.nextContact, '2026-11-03');
    expect(toContact(f, scannedAt: today).notes.single.note, contains('次回連絡: 2026-11-03'));
    final idx = buildIndex({'山田_太郎_2026-10-28': md});
    expect(idx, contains('## 連絡予定'));
    expect(idx, contains('- 2026-11-03: [[山田_太郎_2026-10-28|山田 太郎]]'));
  });

  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

  testWidgets('home shows a 連絡予定 tile with the due count and opens the list on it', (t) async {
    StatusFilter? opened;
    await t.pumpWidget(app(HomeScreen(
      cards: cards, vault: Directory.systemTemp, today: today,
      onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
      onContinue: (f) => opened = f,
    )));
    expect(find.text('連絡予定'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await t.tap(find.text('連絡予定'));
    expect(opened, StatusFilter.due);
  });

  testWidgets('list rows show the due date, overdue in red words, and the segment filters', (t) async {
    await t.pumpWidget(app(ListScreen(cards: cards, vault: Directory.systemTemp, onTap: (_) {}, today: today)));
    expect(find.text('期限切れ 10/20'), findsOneWidget);
    expect(find.text('連絡 11/03'), findsOneWidget);
    await t.tap(find.text('連絡予定'));
    await t.pumpAndSettle();
    expect(find.text('c'), findsNothing, reason: 'undated cards are hidden');
    String? firstTitle() => (t.widget<ListTile>(find.byType(ListTile).first).title as Text).data;
    expect(firstTitle(), 'a', reason: 'soonest first, whatever the sort control says');
  });

  testWidgets('the form has a 次回連絡日 field: the date picker fills it, the clear button empties it', (t) async {
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
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [], today: today)));
    expect(find.text('次回連絡日'), findsOneWidget);
    await t.tap(find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['nextContact']));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(ctl['nextContact']!.text, '2026-10-28');
    await t.tap(find.byTooltip('日付を消す'));
    await t.pump();
    expect(ctl['nextContact']!.text, isEmpty);
  });
}
