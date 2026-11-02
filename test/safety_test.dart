// 2026-11-02 round 5: a copy outside the phone (recorded, nudged, restorable
// from any file) and the user's own card, sent in one tap.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_list.dart';
import 'package:meishi_ocr/files.dart';
import 'package:archive/archive.dart';
import 'package:meishi_ocr/home_screen.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/share.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';
import 'package:meishi_ocr/theme.dart';

final _today = DateTime(2026, 11, 2);
const _one = [CardSummary(noteStem: 'a', stem: 'a', name: '山田 太郎', scanned: '2026-10-01')];

Widget _app(Widget child) => MaterialApp(theme: appTheme(), home: Scaffold(body: child));

HomeScreen _home({String? lastExport, VoidCallback? onBackup, String? myCardName, VoidCallback? onSendMine,
        List<CardSummary> cards = _one}) =>
    HomeScreen(
      cards: cards, vault: Directory.systemTemp, today: _today,
      onScan: () {}, onAlbum: () {}, onImport: () {}, onOpenCard: (_) {}, onSeeAll: () {},
      lastExport: lastExport, onBackup: onBackup, myCardName: myCardName, onSendMine: onSendMine,
    );

void main() {
  group('backupNudge', () {
    test('never exported, or 30 days or more ago, with at least one card', () {
      expect(backupNudge(lastExport: null, today: _today, cards: 3), contains('したことがありません'));
      expect(backupNudge(lastExport: '2026-10-03', today: _today, cards: 3), contains('30 日'));
      expect(backupNudge(lastExport: '2026-10-04', today: _today, cards: 3), isNull, reason: '29 days');
      expect(backupNudge(lastExport: null, today: _today, cards: 0), isNull, reason: 'nothing to lose');
      expect(backupNudge(lastExport: 'junk', today: _today, cards: 1), contains('したことがありません'));
    });
  });

  testWidgets('home shows the nudge with a share button only when it is due', (t) async {
    var shared = 0;
    await t.pumpWidget(_app(_home(onBackup: () => shared++)));
    await t.tap(find.widgetWithText(FilledButton, 'バックアップを共有'));
    expect(shared, 1);
    await t.pumpWidget(_app(_home(lastExport: '2026-11-01', onBackup: () => shared++)));
    expect(find.text('バックアップを共有'), findsNothing);
  });

  group('自分の名刺', () {
    test('cardText lists the fields a person needs to reach you, labelled, in reading order', () {
      final f = CardFields()
        ..name = '山田 太郎'
        ..company = '株式会社サンライズ建設'
        ..dept = '工事部'
        ..title = '課長'
        ..mobile = '090-1111-2222'
        ..phone = '03-1234-5678'
        ..email = 'taro@example.co.jp'
        ..postal = '150-0001'
        ..address = '東京都渋谷区神宮前1-2-3'
        ..memo = '内部メモ'
        ..trust = '5';
      expect(cardText(f), '山田 太郎\n株式会社サンライズ建設\n工事部 課長\n携帯: 090-1111-2222\n電話: 03-1234-5678\n'
          'メール: taro@example.co.jp\n住所: 〒150-0001 東京都渋谷区神宮前1-2-3');
      expect(cardText(CardFields()..name = '名前だけ'), '名前だけ');
    });

    test('the vCard of your own card carries contact details only: no memo, ratings, dates or scan note', () {
      final f = CardFields()
        ..name = '山田 太郎'
        ..mobile = '090-1111-2222'
        ..memo = '社内メモ'
        ..trust = '5'
        ..job = '鳶'
        ..nextContact = '2026-11-03'
        ..related = '佐藤';
      final vcf = myCardVcard(f);
      expect(vcf, contains('山田'));
      expect(vcf, contains('090-1111-2222'));
      for (final secret in ['社内メモ', '信頼度', '職種', '次回連絡', '関係者', '佐藤', '名刺取込']) {
        expect(vcf, isNot(contains(secret)), reason: secret);
      }
    });

    testWidgets('home offers 自分の名刺を送る only when one is set', (t) async {
      var sent = 0;
      await t.pumpWidget(_app(_home(lastExport: '2026-11-01', myCardName: '山田 太郎', onSendMine: () => sent++)));
      await t.tap(find.text('自分の名刺を送る（山田 太郎）'));
      expect(sent, 1);
      await t.pumpWidget(_app(_home(lastExport: '2026-11-01')));
      expect(find.textContaining('自分の名刺を送る'), findsNothing);
    });

    testWidgets('the selection bar offers 自分の名刺にする for exactly one card', (t) async {
      final mine = <String>[];
      await t.pumpWidget(_app(CardList(
        cards: const [
          CardSummary(noteStem: 'a', stem: 'a', name: '山田 太郎'),
          CardSummary(noteStem: 'b', stem: 'b', name: '佐藤 花子'),
        ],
        vault: Directory.systemTemp,
        onTap: (_) {},
        onDelete: (_) async {},
        onMakeMine: (c) => mine.add(c.stem),
      )));
      await t.longPress(find.text('山田 太郎'));
      await t.pump();
      await t.tap(find.text('自分の名刺にする'));
      await t.pump();
      expect(mine, ['a']);
      await t.longPress(find.text('山田 太郎'));
      await t.tap(find.text('すべて選択'));
      await t.pump();
      expect(find.text('自分の名刺にする'), findsNothing);
    });
  });

  testWidgets('home with the nudge and the my-card button fits a 360dp phone at 1.3x text', (t) async {
    t.view.physicalSize = const Size(360, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 1600), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(body: _home(onBackup: () {}, myCardName: '長谷川 健太郎', onSendMine: () {})),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  group('pickBackupZip (system file picker)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(filesChannel, null));

    test('returns the copied file, null when cancelled; a failure is reported to the caller', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(filesChannel, (call) async {
        calls.add(call.method);
        return '/cache/restore_pick.zip';
      });
      expect((await pickBackupZip())!.path, '/cache/restore_pick.zip');
      expect(calls, ['pickZip']);
      messenger.setMockMethodCallHandler(filesChannel, (call) async => null);
      expect(await pickBackupZip(), isNull);
      messenger.setMockMethodCallHandler(filesChannel, (call) async => throw PlatformException(code: 'too_large'));
      expect(pickBackupZip(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'too_large')));
    });
  });

  group('share sheet outcome', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    tearDown(() => messenger.setMockMethodCallHandler(share, null));

    test('onShared runs when an app was picked, not when the sheet was dismissed', () async {
      final tmp = await Directory.systemTemp.createTemp('meishi_share_');
      addTearDown(() => tmp.delete(recursive: true));
      final zip = await File('${tmp.path}/b.zip').writeAsBytes([1]);
      var shared = 0;
      messenger.setMockMethodCallHandler(share, (call) async => ''); // dismissed
      expect(await shareFile(zip, mime: 'application/zip', subject: 's', onShared: () => shared++), isTrue);
      expect(shared, 0);
      messenger.setMockMethodCallHandler(share, (call) async => 'com.google.android.apps.docs');
      await shareFile(zip, mime: 'application/zip', subject: 's', onShared: () => shared++);
      expect(shared, 1);
    });
  });

  test('restore reads the zip as a stream; a zip without cards restores nothing', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_restore_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    final other = Archive()..addFile(ArchiveFile.bytes('photos/a.jpg', [1, 2, 3]));
    final zip = await File('${tmp.path}/other.zip').writeAsBytes(ZipEncoder().encodeBytes(other));
    expect(await store.restore(zip), (0, 0));
  });
}
