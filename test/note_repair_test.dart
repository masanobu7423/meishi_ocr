// R0 follow-up: notes written before the line-break fix lost everything
// after a break; the golden JSON kept it. repairNotes rebuilds those notes
// once, from the JSON.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';

void main() {
  test('a note cut at a line break is rebuilt from the JSON; other notes are left alone', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_repair_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(stem: 'pb_1', front: const [], back: const [],
        expected: {'name': '山田 太郎', 'address': '東京都渋谷区1-2\nサンライズビル5F'},
        status: CardStatus.registered, scannedAt: DateTime(2026, 10, 1));
    await store.saveCard(stem: 'k2', front: const [], back: const [],
        expected: {'name': '佐藤 花子'}, scannedAt: DateTime(2026, 10, 2));
    // What the old writer left behind: the street cut at the break.
    final note = File('${tmp.path}/vault/山田_太郎_2026-10-01.md');
    await note.writeAsString((await note.readAsString()).replaceFirst(' / サンライズビル5F', ''));
    final other = File('${tmp.path}/vault/佐藤_花子_2026-10-02.md');
    final before = other.lastModifiedSync();

    expect(await store.repairNotes(), 1);
    final fm = parseFrontmatter(await note.readAsString());
    expect(fm['address'], '東京都渋谷区1-2 / サンライズビル5F');
    expect((fm['status'], fm['scanned']), ('登録済', '2026-10-01'), reason: 'status and scan date kept');
    expect(other.lastModifiedSync(), before, reason: 'cards without a line break are not rewritten');
  });

  test('a broken card JSON is logged and skipped; the rest are still repaired', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_repair2_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(stem: 'a', front: const [], back: const [],
        expected: {'name': 'A', 'memo': 'x\ny'}, scannedAt: DateTime(2026, 10, 1));
    await File('${tmp.path}/golden/broken.json').writeAsString('{not json');
    expect(await store.repairNotes(), 1);
    expect(await File('${tmp.path}/log/errors.txt').readAsString(), contains('repairNotes broken'));
  });

  test('purging a card from the trash also drops its lines from the corrections log', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_corr_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    final log = await File('${tmp.path}/log/corrections.jsonl').create(recursive: true);
    await log.writeAsString('{"stem":"gone","changes":{}}\n{"stem":"kept","changes":{}}\n');
    await store.saveCard(stem: 'gone', front: const [], back: const [], expected: {'name': 'A'});
    await store.deleteCard('gone', now: DateTime(2026, 10, 1));
    expect(await store.purgeTrash(now: DateTime(2026, 11, 2)), 1);
    expect(await log.readAsString(), '{"stem":"kept","changes":{}}\n');
  });
}
