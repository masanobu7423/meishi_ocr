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
    organizations: [Organization(name: '旧社')],
  );
  final card = CardFields()
    ..name = '山田 太郎'
    ..company = '株式会社サンライズ'
    ..mobile = '090-1234-5678'
    ..phone = '03-1234-5678';

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

  testWidgets('shows both sides, lets the user pick the card value, and merges', (t) async {
    final result = await open(t);
    expect(find.text('同じ人がいるかもしれません'), findsOneWidget);
    expect(find.text('旧社'), findsOneWidget);
    expect(find.text('株式会社サンライズ'), findsOneWidget);
    expect(find.textContaining('同じ）'), findsWidgets); // mobile agrees
    await t.tap(find.text('株式会社サンライズ'));
    await t.pump();
    await t.tap(find.text('選んだ内容で統合'));
    await t.pumpAndSettle();
    expect(result()?.action, DuplicateAction.merge);
    expect(result()?.useCard, contains('company'));
    expect(result()?.useCard, contains('phone'), reason: 'empty on the phone -> taken from the card by default');
    expect(result()?.useCard, isNot(contains('mobile')));
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
