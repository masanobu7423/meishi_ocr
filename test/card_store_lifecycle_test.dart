// Editing, deleting and restoring saved cards (CardStore).
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

void main() {
  late Directory tmp;
  late CardStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('meishi_life_');
    store = CardStore(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  final front = [const OcrLine('山田 太郎', width: 200, height: 50)];
  final yamada = {'name': '山田 太郎', 'company': '株式会社サンライズ'};
  final oct25 = DateTime(2026, 10, 25);

  Future<void> save(String stem, Map<String, String?> expected, {File? image, DateTime? at}) =>
      store.saveCard(
          stem: stem, front: front, back: const [], expected: expected, frontImage: image, scannedAt: at);
  Future<File> saveAs(String stem, CardStatus status, {DateTime? at}) =>
      store.saveCard(stem: stem, front: front, back: const [], expected: yamada, status: status, scannedAt: at);

  test('saving the same stem again replaces its note and keeps the scan date', () async {
    await save('c1', yamada, at: oct25);
    await save('c1', {...yamada, 'name': '山田 次郎'}); // edited later, no date given
    final notes = await store.notes();
    expect(notes.keys, ['山田_次郎_2026-10-25']);
    expect(notes.values.single, contains('scanned: 2026-10-25'));
    expect(notes.values.single, contains('name: 山田 次郎'));
  });

  test('deleteCard removes the JSON, note, images and index entry', () async {
    final img = await File('${tmp.path}/f.jpg').writeAsBytes([1, 2]);
    await save('c1', yamada, image: img, at: oct25);
    await save('c2', {'name': '佐藤 花子'}, at: oct25);
    expect(await store.deleteCard('c1'), isTrue);
    expect(File('${tmp.path}/golden/c1.json').existsSync(), isFalse);
    expect(File('${tmp.path}/vault/山田_太郎_2026-10-25.md').existsSync(), isFalse);
    expect(File('${tmp.path}/vault/images/c1_front.jpg').existsSync(), isFalse);
    expect((await store.notes()).keys, ['佐藤_花子_2026-10-25']);
    expect(await File('${tmp.path}/vault/_名刺一覧.md').readAsString(), contains('count: 1'));
    expect(await store.deleteCard('missing'), isFalse);
  });

  test('restore rebuilds a fresh store from a backup zip', () async {
    final img = await File('${tmp.path}/f.jpg').writeAsBytes([1, 2]);
    await save('c1', yamada, image: img, at: oct25);
    await File('${tmp.path}/learned.json').writeAsString('{"x":1}');
    final (zip, _) = await store.backup(now: DateTime(2026, 10, 25, 9, 30));

    final tmp2 = await Directory.systemTemp.createTemp('meishi_restore_');
    addTearDown(() => tmp2.delete(recursive: true));
    final other = CardStore(tmp2);
    // golden/c1.json, the note, images/c1_front.jpg, the index, learned.json
    expect(await other.restore(zip), (5, 0));
    expect((await other.notes()).keys, ['山田_太郎_2026-10-25']);
    expect((await other.loadCard('c1'))!.frontImage!.existsSync(), isTrue);
    expect(await File('${tmp2.path}/learned.json').readAsString(), '{"x":1}');
    expect(await File('${tmp2.path}/vault/_名刺一覧.md').readAsString(), contains('count: 1'));
  });

  test('restore keeps the existing learned.json and skips foreign entries', () async {
    await File('${tmp.path}/learned.json').writeAsString('{"mine":1}');
    final a = Archive()
      ..add(ArchiveFile.bytes('../evil.txt', [1]))
      ..add(ArchiveFile.bytes('settings.json', [1]))
      ..add(ArchiveFile.bytes('learned.json', utf8.encode('{"theirs":1}')))
      ..add(ArchiveFile.bytes('golden/ok.json', utf8.encode('{"expected":{}}')));
    final zip = await File('${tmp.path}/x.zip').writeAsBytes(ZipEncoder().encodeBytes(a));
    expect(await store.restore(zip), (1, 0));
    expect(File('${tmp.parent.path}/evil.txt').existsSync(), isFalse);
    expect(File('${tmp.path}/settings.json').existsSync(), isFalse);
    expect(await File('${tmp.path}/learned.json').readAsString(), '{"mine":1}');
    expect(File('${tmp.path}/golden/ok.json').existsSync(), isTrue);
  });

  test('re-saving removes every older note with the same source', () async {
    await save('c1', yamada, at: oct25);
    // A duplicate left behind by the old behaviour (same source, other date).
    final dup = File('${tmp.path}/vault/山田_太郎_2026-11-01.md');
    await dup.writeAsString((await store.notes()).values.single.replaceAll('2026-10-25', '2026-11-01'));
    await save('c1', yamada);
    expect((await store.notes()).keys, ['山田_太郎_2026-10-25']);
    expect(await store.deleteCard('c1'), isTrue);
    expect(await store.notes(), isEmpty);
  });

  test('deleteCard ignores image paths outside vault/images and bad stems', () async {
    await File('${tmp.path}/settings.json').writeAsString('{}');
    await Directory('${tmp.path}/golden').create();
    await File('${tmp.path}/golden/evil.json').writeAsString(
        jsonEncode({'expected': {}, 'images': {'front': '../settings.json'}}));
    expect(await store.deleteCard('evil'), isTrue);
    expect(File('${tmp.path}/settings.json').existsSync(), isTrue);
    expect(await store.deleteCard('../settings'), isFalse);
    expect(await store.loadCard('../settings'), isNull);
  });

  test('restore reports entries it could not write and keeps going', () async {
    await Directory('${tmp.path}/vault').create();
    await File('${tmp.path}/vault/images').writeAsString('not a directory');
    final a = Archive()
      ..add(ArchiveFile.bytes('vault/images/x.jpg', [1]))
      ..add(ArchiveFile.bytes('golden/ok.json', utf8.encode('{"expected":{}}')));
    final zip = await File('${tmp.path}/x.zip').writeAsBytes(ZipEncoder().encodeBytes(a));
    expect(await store.restore(zip), (1, 1));
    expect(File('${tmp.path}/golden/ok.json').existsSync(), isTrue);
    expect(await File('${tmp.path}/log/errors.txt').readAsString(), contains('vault/images/x.jpg'));
  });

  test('status is stored in the JSON and the note; default reviewed; legacy JSON reviewed', () async {
    final f = await saveAs('c1', CardStatus.unreviewed, at: oct25);
    expect(jsonDecode(await f.readAsString())['status'], 'unreviewed');
    expect((await store.notes()).values.single, contains('status: 未確認\n'));
    expect((await store.loadCard('c1'))!.status, CardStatus.unreviewed);

    await save('c2', {'name': '佐藤 花子'}, at: oct25);
    expect((await store.loadCard('c2'))!.status, CardStatus.reviewed);

    await File('${tmp.path}/golden/old.json').writeAsString(jsonEncode({'expected': {'name': 'x'}}));
    expect((await store.loadCard('old'))!.status, CardStatus.reviewed);
  });

  test('setStatus changes only the status; a re-save from the vault image keeps its bytes', () async {
    final img = await File('${tmp.path}/f.jpg').writeAsBytes([1, 2, 3]);
    await save('c1', yamada, image: img, at: oct25);
    expect(await store.setStatus('c1', CardStatus.registered), isTrue);
    final c = (await store.loadCard('c1'))!;
    expect(c.status, CardStatus.registered);
    expect(c.expected['name'], '山田 太郎');
    expect(await c.frontImage!.readAsBytes(), [1, 2, 3]);
    expect((await store.notes()).values.single, contains('status: 登録済\nsource: c1.json'));
    // The review screen re-saves with the vault copy as the source image:
    // copying a file onto itself must not truncate it.
    await store.saveCard(stem: 'c1', front: front, back: const [], expected: yamada, frontImage: c.frontImage);
    expect(await (await store.loadCard('c1'))!.frontImage!.readAsBytes(), [1, 2, 3]);
    expect(await store.setStatus('missing', CardStatus.registered), isFalse);
  });

  test('stashCapture copies a burst page into the inbox under the given name', () async {
    final src = await File('${tmp.path}/cache_page.jpg').writeAsBytes([9, 8, 7]);
    final f = await store.stashCapture(src, 'shot_1_front');
    expect(f.path.replaceAll('\\', '/'), endsWith('/inbox/shot_1_front.jpg'));
    expect(await f.readAsBytes(), [9, 8, 7]);
    expect((await store.inboxImages()).map((x) => x.uri.pathSegments.last), ['shot_1_front.jpg']);
  });

  test('backups lists zip files newest first', () async {
    expect(await store.backups(), isEmpty);
    await store.backup(now: DateTime(2026, 10, 24, 8, 0));
    await store.backup(now: DateTime(2026, 10, 25, 9, 30));
    expect((await store.backups()).map((f) => f.uri.pathSegments.last),
        ['meishi_backup_2026-10-25_0930.zip', 'meishi_backup_2026-10-24_0800.zip']);
  });
}
