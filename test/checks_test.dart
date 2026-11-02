// 2026-11-02 round 4: mechanical checks that catch OCR misreads (and a
// construction licence due for renewal) without a network or a dictionary.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_form.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/checks.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/theme.dart';

final _today = DateTime(2026, 11, 2);

Widget _app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

void main() {
  group('法人番号', () {
    test('13 digits whose check digit matches (国税庁 7000012050002)', () {
      expect(validCorpNo('7000012050002'), isTrue);
      expect(validCorpNo('7000012050003'), isFalse);
      expect(fieldIssue('corpNo', '7000012050002'), isNull);
      expect(fieldIssue('corpNo', 'T7000012050002'), isNull, reason: 'the invoice T prefix is fine');
      expect(fieldIssue('corpNo', '8000012050002')!.misread, isTrue);
      expect(fieldIssue('corpNo', '700001205000')!.text, contains('13 桁'));
    });
  });

  group('電話・携帯・FAX', () {
    test('fixed lines have 10 digits, mobiles / 050 / 0800 have 11; all start with 0', () {
      for (final ok in ['03-1234-5678', '0120-123-456', '090-1234-5678', '050-1234-5678', '0800-123-4567',
          '+81 90-1234-5678', '(03)1234-5678', '０３－１２３４－５６７８']) {
        expect(fieldIssue('phone', ok), isNull, reason: ok);
      }
      expect(fieldIssue('phone', '03-1234-567')!.text, contains('9 桁'));
      expect(fieldIssue('mobile', '090-123-4567'), isNotNull);
      expect(fieldIssue('fax', '1234-5678'), isNotNull, reason: 'no leading 0: area code missing');
    });

    test('labels, 020 / 060 (11 digits) and +81 (0) / 0081 forms are not misjudged', () {
      for (final ok in ['FAX 03-1234-5678', 'Fax03-1234-5678', '020-1234-5678', '060-1234-5678',
          '+81 (0)3-1234-5678', '0081-3-1234-5678']) {
        expect(fieldIssue('fax', ok), isNull, reason: ok);
      }
    });

    test('extensions and foreign numbers are not judged', () {
      expect(fieldIssue('phone', '03-1234-5678 内線 123'), isNull);
      expect(fieldIssue('phone', '03-1234-5678 ext.45'), isNull);
      expect(fieldIssue('phone', '+1 415 555 0172'), isNull);
      expect(fieldIssue('phone', 'TEL +1 415 555 0172'), isNull);
    });
  });

  test('メール: a name, an @ and a dotted domain; commas, spaces and full-width text are flagged', () {
    expect(fieldIssue('email', 'taro.yamada@example.co.jp'), isNull);
    expect(fieldIssue('email', 'taro@example,co.jp'), isNotNull);
    expect(fieldIssue('email', 'taro @example.co.jp'), isNotNull);
    expect(fieldIssue('email', 'taro@example'), isNotNull);
    expect(fieldIssue('email', 'たろう@example.co.jp'), isNotNull);
  });

  test('郵便番号: 7 digits, with or without 〒 and hyphen', () {
    expect(fieldIssue('postal', '〒150-0001'), isNull);
    expect(fieldIssue('postal', '１５０－０００１'), isNull);
    expect(fieldIssue('postal', '150-001')!.text, contains('6 桁'));
  });

  group('建設業許可', () {
    String lic(String n) => '東京都知事許可(般-$n)第123456号';
    test('the renewal year comes from the year in （般-n）: 5 years, 令和 for small n, 平成 for large', () {
      expect(fieldIssue('constructionLicense', lic('5'), today: _today), isNull, reason: 'R5 = 2023, valid to 2028');
      final due = fieldIssue('constructionLicense', lic('3'), today: _today)!;
      expect((due.misread, due.text.contains('今年')), (false, true), reason: 'R3 = 2021, renewal 2026');
      final past = fieldIssue('constructionLicense', lic('2'), today: _today)!;
      expect((past.misread, past.text.contains('更新済みか')), (false, true), reason: 'R2 = 2020, ran out 2025');
      expect(fieldIssue('constructionLicense', '国土交通大臣許可（特－30）第012345号', today: _today), isNotNull,
          reason: 'H30 = 2018; full-width brackets and dash');
    });

    test('without today (list summaries) the licence is not judged; unknown formats are left alone', () {
      expect(fieldIssue('constructionLicense', lic('2')), isNull);
      expect(fieldIssue('constructionLicense', '許可番号 123456', today: _today), isNull);
    });
  });

  test('cardIssues lists only the fields with an issue; empty and unchecked fields are skipped', () {
    final f = CardFields()
      ..name = '山田 太郎'
      ..email = 'taro@example,co.jp'
      ..phone = '03-1234-5678'
      ..postal = '';
    expect(cardIssues(f.toJson()).keys, ['email']);
  });

  testWidgets('the form explains an issue under the field and lists it at the top; tapping goes there', (t) async {
    final ctl = {for (final k in CardFields.keys) k: TextEditingController()};
    addTearDown(() {
      for (final x in ctl.values) {
        x.dispose();
      }
    });
    ctl['email']!.text = 'taro@example,co.jp';
    await t.pumpWidget(_app(CardForm(controllers: ctl, lines: const [], today: _today)));
    expect(find.textContaining('メールアドレスの形'), findsOneWidget);
    final jump = find.widgetWithText(ActionChip, 'メール');
    expect(jump, findsOneWidget);
    await t.tap(jump);
    await t.pumpAndSettle();
    final email = t.widget<TextField>(find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['email']));
    expect(email.focusNode!.hasFocus, isTrue);
    ctl['email']!.text = 'taro@example.co.jp';
    await t.pump();
    expect(find.textContaining('メールアドレスの形'), findsNothing);
    expect(find.widgetWithText(ActionChip, 'メール'), findsNothing, reason: 'fixed: the summary goes away');
  });

  testWidgets('a licence due for renewal is noted under its field but is not a 要確認 (not a misread)', (t) async {
    final ctl = {for (final k in CardFields.keys) k: TextEditingController()};
    addTearDown(() {
      for (final x in ctl.values) {
        x.dispose();
      }
    });
    ctl['constructionLicense']!.text = '東京都知事許可(般-2)第123456号';
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(_app(CardForm(controllers: ctl, lines: const [], today: _today)));
    expect(find.textContaining('更新済みか'), findsOneWidget);
    expect(find.text('要確認'), findsNothing);
  });

  testWidgets('the issue summary survives 2x text on a 360dp phone', (t) async {
    final ctl = {for (final k in CardFields.keys) k: TextEditingController()};
    addTearDown(() {
      for (final x in ctl.values) {
        x.dispose();
      }
    });
    ctl['email']!.text = 'x';
    ctl['phone']!.text = '03-1';
    ctl['corpNo']!.text = '1';
    ctl['postal']!.text = '1';
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(2)),
        child: Scaffold(body: CardForm(controllers: ctl, lines: const [], today: _today)),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  group('要確認 on saved cards', () {
    final bad = cardNoteMarkdown(CardFields()
      ..name = '誤読 太郎'
      ..email = 'taro@example,co.jp', scannedAt: DateTime(2026, 10, 1));
    final good = cardNoteMarkdown(CardFields()
      ..name = '正しい 花子'
      ..email = 'hanako@example.co.jp', scannedAt: DateTime(2026, 10, 2));

    test('cards imported from the phone book (no OCR) are never flagged as misread', () {
      final md = cardNoteMarkdown(CardFields()
        ..name = '海外 太郎'
        ..postal = '94043', scannedAt: DateTime(2026, 10, 1), source: 'pb_42.json');
      expect(cardSummaries({'p': md}).single.needsCheck, isFalse);
    });

    test('summaries know which cards need a check, and the list filter keeps only those', () {
      final cards = cardSummaries({'a': bad, 'b': good});
      expect({for (final c in cards) c.name: c.needsCheck}, {'誤読 太郎': true, '正しい 花子': false});
      expect(filterCards(cards, StatusFilter.needsCheck).map((c) => c.name), ['誤読 太郎']);
    });

    testWidgets('home shows a 要確認 tile only when a card needs a check; rows carry a pill', (t) async {
      final picked = <StatusFilter>[];
      final cards = cardSummaries({'a': bad, 'b': good});
      await t.pumpWidget(_app(HomeScreen(
        cards: cards, vault: Directory.systemTemp, today: _today,
        onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
        onContinue: picked.add,
      )));
      await t.tap(find.text('要確認'));
      expect(picked, [StatusFilter.needsCheck]);
      await t.pumpWidget(_app(ListScreen(cards: cards, vault: Directory.systemTemp, onTap: (_) {})));
      expect(find.text('要確認'), findsNWidgets(2), reason: 'the segment label and the row pill');
    });
  });
}
