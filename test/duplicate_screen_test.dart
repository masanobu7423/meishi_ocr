import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/duplicate_screen.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/merge.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  final existing = Contact(
    id: '42',
    displayName: '山田 太郎',
    name: Name(last: '山田', first: '太郎'),
    phones: [Phone(number: '090-1234-5678', label: const Label(PhoneLabel.mobile))],
    emails: [Email(address: 'old@example.com')],
    organizations: [Organization(name: '旧社')],
  );
  final card = CardFields()
    ..name = '山田 太郎'
    ..company = '株式会社サンライズ'
    ..mobile = '090-1234-5678'
    ..phone = '03-1234-5678'
    ..email = 'taro.yamada@sunrise.co.jp';

  /// Opens the screen via a route so Navigator.pop returns the decision.
  Future<DuplicateDecision? Function()> open(WidgetTester t) async {
    DuplicateDecision? result;
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => DuplicateScreen(existing: existing, card: card, rows: contactDiff(existing, card))));
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    return () => result;
  }

  /// The cards sit in a lazy ListView: scroll the field into view first.
  Future<Finder> checkboxIn(WidgetTester t, String fieldLabel, String title) async {
    await t.scrollUntilVisible(find.text(fieldLabel), 150, scrollable: find.byType(Scrollable).first);
    await t.pump();
    final f = find.descendant(
      of: find.ancestor(of: find.text(fieldLabel), matching: find.byType(Card)),
      matching: find.widgetWithText(CheckboxListTile, title),
    );
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    return f;
  }

  testWidgets('checkboxes pick the card value and the preview follows', (t) async {
    final result = await open(t);
    expect(find.text('同じ人がいるかもしれません'), findsOneWidget);
    expect(find.textContaining('同じ）'), findsWidgets); // name and mobile agree
    // company: existing kept by default
    expect(find.text('統合後: 旧社'), findsOneWidget);
    await t.tap(await checkboxIn(t, '会社', '名刺の値を使う'));
    await t.pump();
    expect(find.text('統合後: 株式会社サンライズ'), findsOneWidget);
    // email: multi-valued -> both kept, then drop the existing one
    await t.tap(await checkboxIn(t, 'メール', '名刺の値を使う'));
    await t.pump();
    expect(find.text('統合後: old@example.com / taro.yamada@sunrise.co.jp'), findsOneWidget);
    await t.tap(await checkboxIn(t, 'メール', '既存の値も残す'));
    await t.pump();
    expect(find.text('統合後: taro.yamada@sunrise.co.jp'), findsOneWidget);
    await t.tap(find.text('選んだ内容で再登録'));
    await t.pumpAndSettle();
    final d = result();
    expect(d?.action, DuplicateAction.merge);
    expect(d?.useCard, containsAll(['company', 'email', 'phone']));
    expect(d?.useCard, isNot(contains('mobile')));
    expect(d?.keepExisting, isNot(contains('email')));
    expect(d?.keepExisting, contains('phone'));
  });

  testWidgets('"すべて名刺の値にする" checks every differing field with a card value', (t) async {
    final result = await open(t);
    await t.tap(find.text('すべて名刺の値にする'));
    await t.pump();
    await t.tap(find.text('選んだ内容で再登録'));
    await t.pumpAndSettle();
    expect(result()?.useCard, containsAll(['company', 'email', 'phone']));
  });

  testWidgets('replacing the existing contact asks for confirmation first', (t) async {
    final result = await open(t);
    await t.tap(find.text('既存を削除して名刺で登録'));
    await t.pumpAndSettle();
    expect(find.textContaining('元に戻せません'), findsOneWidget);
    await t.tap(find.text('削除して登録'));
    await t.pumpAndSettle();
    expect(result()?.action, DuplicateAction.replace);
  });

  testWidgets('separate registration needs no confirmation', (t) async {
    final result = await open(t);
    await t.tap(find.text('別人として登録'));
    await t.pumpAndSettle();
    expect(result()?.action, DuplicateAction.separate);
  });
}
