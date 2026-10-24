import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/ocr_line.dart';

void main() {
  late Directory tmp;
  late CardStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('meishi_store_');
    store = CardStore(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  final front = [const OcrLine('山田 太郎', width: 200, height: 50)];
  final expected = {'name': '山田 太郎', 'company': '株式会社サンライズ', 'phone': '03-1234-5678'};

  test('saveCard writes golden JSON, the card note and the index', () async {
    final file = await store.saveCard(
        stem: 'c1', front: front, back: const [], expected: expected,
        scannedAt: DateTime(2026, 10, 25));
    expect(file.path, endsWith('golden/c1.json'));
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(j['expected'], expected);
    expect(j['vertical'], isFalse);
    expect((j['front'] as List).single['text'], '山田 太郎');

    final note = File('${tmp.path}/vault/山田_太郎_2026-10-25.md');
    expect(await note.readAsString(), contains('company: 株式会社サンライズ'));
    final index = await File('${tmp.path}/vault/_名刺一覧.md').readAsString();
    expect(index, contains('count: 1'));
    expect(index, contains('[[株式会社サンライズ]] (1)'));
  });

  test('exportVcard writes one VCARD per saved card', () async {
    await store.saveCard(stem: 'c1', front: front, back: const [], expected: expected,
        scannedAt: DateTime(2026, 10, 25));
    await store.saveCard(stem: 'c2', front: front, back: const [],
        expected: {...expected, 'name': '鈴木 一郎'}, scannedAt: DateTime(2026, 10, 25));
    final (file, count) = await store.exportVcard();
    expect(count, 2);
    expect(await file.readAsString(), contains('FN:鈴木 一郎'));
  });

  test('inbox is created by the store and lists only images', () async {
    final inbox = await store.inbox();
    expect(inbox.existsSync(), isTrue);
    await File('${inbox.path}/a.jpg').writeAsString('');
    await File('${inbox.path}/b.PNG').writeAsString('');
    await File('${inbox.path}/notes.txt').writeAsString('');
    expect((await store.inboxImages()).map((f) => f.uri.pathSegments.last), ['a.jpg', 'b.PNG']);
  });

  test('appendError appends one line per failure', () async {
    await store.appendError('x.jpg', 'boom');
    await store.appendError('y.jpg', 'bang');
    final log = await File('${tmp.path}/log/errors.txt').readAsLines();
    expect(log.length, 2);
    expect(log.last, endsWith('y.jpg: bang'));
  });
}
