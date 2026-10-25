// 職種: a construction-trade list the user owns (add / rename / delete),
// kept in <root>/jobs.json and carried in backups.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/card_form.dart';
import 'package:meishi_ocr/jobs_screen.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/jobs.dart';
import 'package:meishi_ocr/ocr/learned.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';
import 'package:meishi_ocr/theme.dart';

void main() {
  late Directory tmp;
  late CardStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('meishi_jobs_');
    store = CardStore(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('the default list is construction trades, deduplicated and non-empty', () {
    expect(defaultJobs, containsAll(['鳶', '左官', '鉄筋', '型枠', '大工', '施工管理', 'その他']));
    expect(defaultJobs.toSet().length, defaultJobs.length);
  });

  test('jobCategory maps trade words to the trades', () {
    expect(jobCategory('鳶工事部', null), '鳶');
    expect(jobCategory(null, '左官職長'), '左官');
    expect(jobCategory('鉄筋工事', null), '鉄筋');
    expect(jobCategory('型枠大工', null), '型枠', reason: 'first match in table order');
    expect(jobCategory(null, '現場監督'), '施工管理');
    expect(jobCategory('営業部', null), '営業');
    expect(jobCategory('工事部', '代表取締役'), '経営', reason: 'the president of a trade company');
    expect(jobCategory('安全衛生部', null), isNull, reason: '衛生 is not a trade');
  });

  test('loadJobs falls back to the defaults; saveJobs round-trips and survives a backup', () async {
    expect(await store.loadJobs(), defaultJobs);
    await store.saveJobs(['鳶', '足場', 'オリジナル']);
    expect(await store.loadJobs(), ['鳶', '足場', 'オリジナル']);
    final (zip, _) = await store.backup(now: DateTime(2026, 10, 26, 9));
    final names = ZipDecoder().decodeBytes(await zip.readAsBytes()).map((e) => e.name);
    expect(names, contains('jobs.json'));
    final other = CardStore(await Directory.systemTemp.createTemp('meishi_jobs2_'));
    addTearDown(() => other.root.delete(recursive: true));
    await other.restore(zip);
    expect(await other.loadJobs(), ['鳶', '足場', 'オリジナル']);
  });

  test('a corrupt, empty or non-string jobs.json falls back to the defaults', () async {
    for (final bad in ['{not json', '[]', '[1, 2]', '[""]']) {
      await File('${tmp.path}/jobs.json').writeAsString(bad);
      expect(await store.loadJobs(), defaultJobs, reason: bad);
    }
  });

  test('learn never remembers the user-owned fields (job, trust, category, related)', () {
    final learned = Learned()
      ..learn(
        guess: {'trust': null, 'job': null},
        corrected: {'trust': '4', 'job': '鳶'},
        lines: const [OcrLine('4'), OcrLine('鳶')],
      );
    expect(learned.fieldFor('4'), isNull);
    expect(learned.fieldFor('鳶'), isNull);
  });

  test('defaultJob fills a fresh read and respects the user', () {
    expect(defaultJob(CardFields()..dept = '鳶工事部'), '鳶');
    expect(defaultJob(CardFields()..dept = '鳶工事部'..job = '足場'), '足場');
  });

  Widget app(Widget child) => MaterialApp(theme: appTheme(), home: child);

  testWidgets('JobsScreen adds, renames and deletes entries in the given list', (t) async {
    final got = ['鳶', '左官'];
    await t.pumpWidget(app(JobsScreen(jobs: got)));
    expect(find.text('鳶'), findsOneWidget);
    await t.enterText(find.byType(TextField), '鉄筋');
    await t.tap(find.text('追加'));
    await t.pump();
    expect(got, ['鳶', '左官', '鉄筋']);
    await t.enterText(find.byType(TextField), '鳶');
    await t.tap(find.text('追加'));
    await t.pump();
    expect(got, ['鳶', '左官', '鉄筋'], reason: 'duplicates are not added');
    await t.tap(find.byTooltip('名前を変える').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '鳶工');
    await t.tap(find.text('変更'));
    await t.pumpAndSettle();
    expect(got, ['鳶工', '左官', '鉄筋']);
    await t.tap(find.byTooltip('削除').last);
    await t.pump();
    expect(got, ['鳶工', '左官']);
  });

  testWidgets('CardForm lists the given jobs plus values already in use', (t) async {
    final ctl = {for (final k in CardFields.keys) k: TextEditingController()};
    addTearDown(() {
      for (final c in ctl.values) {
        c.dispose();
      }
    });
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(app(Scaffold(
        body: CardForm(
            controllers: ctl,
            lines: const [],
            jobs: const ['鳶', '左官'],
            suggestions: const {'job': ['左官', '技術開発']}))));
    await t.tap(find.byWidgetPredicate((w) => w is DropdownMenu<String> && w.controller == ctl['job']));
    await t.pumpAndSettle();
    expect(find.text('鳶'), findsOneWidget);
    expect(find.text('技術開発'), findsOneWidget, reason: 'a value in use stays selectable');
    expect(find.text('左官'), findsOneWidget, reason: 'no duplicate entry');
    expect(find.text('施工管理'), findsNothing, reason: 'the default list is not forced');
  });
}
