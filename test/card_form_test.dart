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

  /// A tall surface so the lazy ListView builds every field at once.
  void tall(WidgetTester t) {
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('shows Japanese labels, never the field keys', (t) async {
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [])));
    expect(find.text('氏名'), findsOneWidget);
    expect(find.text('会社'), findsOneWidget);
    expect(find.text('name'), findsNothing);
    expect(find.text('company'), findsNothing);
  });

  testWidgets('tapping an OCR chip fills the last focused field', (t) async {
    tall(t);
    await t.pumpWidget(app(CardForm(
      controllers: ctl,
      lines: const [OcrLine('株式会社サンライズ'), OcrLine('営業部　部長')],
    )));
    await t.tap(find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['title']));
    await t.pump();
    expect(find.textContaining('「役職」に入れる'), findsOneWidget);
    await t.tap(find.widgetWithText(ActionChip, '営業部　部長'));
    await t.pump();
    expect(ctl['title']!.text, '営業部 部長', reason: 'ideographic space is normalized');
    expect(ctl['name']!.text, isEmpty);
  });

  testWidgets('a missing core field gets a helper that says what to do', (t) async {
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [], missing: const {'email'})));
    expect(find.textContaining('読み取れませんでした'), findsOneWidget);
  });

  testWidgets('trade fields have Japanese labels', (t) async {
    tall(t);
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [])));
    for (final label in ['建設業許可', '宅建業免許', '法人番号', '資格', '部門', '区分', '関係者']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('区分 is a dropdown; picking an entry writes the controller', (t) async {
    tall(t);
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [])));
    final menu = find.byWidgetPredicate((w) => w is DropdownMenu<String> && w.controller == ctl['category']);
    await t.tap(menu);
    await t.pumpAndSettle();
    await t.tap(find.text('協力会社').last);
    await t.pumpAndSettle();
    expect(ctl['category']!.text, '協力会社');
  });

  testWidgets('address parts rebuild the address, and the address re-splits the parts', (t) async {
    tall(t);
    ctl['address']!.text = '東京都渋谷区神宮前1-2-3 サンライズビル5F';
    await t.pumpWidget(app(CardForm(controllers: ctl, lines: const [])));
    await t.tap(find.text('住所の内訳'));
    await t.pumpAndSettle();
    final city = find.widgetWithText(TextField, '渋谷区');
    await t.enterText(city, '新宿区');
    await t.pump();
    expect(ctl['address']!.text, '東京都新宿区神宮前1-2-3 サンライズビル5F');

    final address = find.byWidgetPredicate((w) => w is TextField && w.controller == ctl['address']);
    await t.enterText(address, '大阪府大阪市北区梅田2-4-9 ブリーゼタワー12階');
    await t.pump();
    expect(find.widgetWithText(TextField, '大阪市北区'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12階'), findsOneWidget);
  });

  testWidgets('suggestion chips append related users', (t) async {
    tall(t);
    await t.pumpWidget(app(CardForm(
      controllers: ctl,
      lines: const [],
      suggestions: const {'related': ['鈴木', '佐藤'], 'division': ['建築事業部']},
    )));
    await t.tap(find.widgetWithText(InputChip, '鈴木'));
    await t.pump();
    await t.tap(find.widgetWithText(InputChip, '佐藤'));
    await t.pump();
    expect(ctl['related']!.text, '鈴木, 佐藤');
    await t.tap(find.widgetWithText(InputChip, '建築事業部'));
    await t.pump();
    expect(ctl['division']!.text, '建築事業部', reason: 'single-value fields are replaced');
  });

  testWidgets('a tall header scrolls with the form instead of overflowing a short screen', (t) async {
    // Landscape phone with the keyboard up leaves ~150dp for the body.
    t.view.physicalSize = const Size(900, 150);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(app(CardForm(
      controllers: ctl,
      lines: const [OcrLine('株式会社サンライズ')],
      header: const SizedBox(height: 300, child: Text('写真と操作')),
    )));
    expect(t.takeException(), isNull, reason: 'no RenderFlex overflow');
    expect(find.text('写真と操作'), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await t.pump();
    expect(find.text('氏名'), findsOneWidget, reason: 'the fields come into view by scrolling');
  });

  testWidgets('survives 2x text scaling without overflow', (t) async {
    tall(t); // builds the dropdowns, address parts and chips too
    ctl['address']!.text = '東京都渋谷区神宮前1-2-3 サンライズビル5F';
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: app(CardForm(controllers: ctl, lines: const [OcrLine('長い行のテキストがここに入ります')])),
    ));
    expect(t.takeException(), isNull);
  });
}
