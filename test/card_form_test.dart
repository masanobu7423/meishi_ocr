import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_form.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  late Map<String, TextEditingController> ctl;
  setUp(() => ctl = {for (final k in CardFields.keys) k: TextEditingController()});
  tearDown(() {
    for (final c in ctl.values) {
      c.dispose();
    }
  });

  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

  testWidgets('shows Japanese labels, never the field keys', (t) async {
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [])));
    expect(find.text('氏名'), findsOneWidget);
    expect(find.text('会社'), findsOneWidget);
    expect(find.text('name'), findsNothing);
    expect(find.text('company'), findsNothing);
  });

  testWidgets('tapping an OCR chip fills the last focused field', (t) async {
    await t.pumpWidget(app(CardForm(
      controllers: ctl,
      lines: const [OcrLine('株式会社サンライズ'), OcrLine('営業部　部長')],
    )));
    await t.tap(find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['title']));
    await t.pump();
    // The chips sit below 13 fields: scroll them into view first.
    final heading = find.textContaining('「役職」に入れる');
    await t.scrollUntilVisible(heading, 200, scrollable: find.byType(Scrollable).first);
    expect(heading, findsOneWidget);
    final chip = find.widgetWithText(ActionChip, '営業部　部長');
    await t.ensureVisible(chip);
    await t.pumpAndSettle();
    await t.tap(chip);
    await t.pump();
    expect(ctl['title']!.text, '営業部 部長', reason: 'ideographic space is normalized');
    expect(ctl['name']!.text, isEmpty);
  });

  testWidgets('a missing core field gets a helper that says what to do', (t) async {
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [], missing: const {'email'})));
    expect(find.textContaining('読み取れませんでした'), findsOneWidget);
  });

  testWidgets('survives 2x text scaling without overflow', (t) async {
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: app(CardForm(controllers: ctl, lines: const [OcrLine('長い行のテキストがここに入ります')])),
    ));
    expect(t.takeException(), isNull);
  });
}
