// CSV for Excel / other CRMs: one row per card, Japanese headers, BOM.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/csv_export.dart';

const _a = '''---
type: meishi
name: 山田 太郎
company: 株式会社サンライズ
title: 部長
phone: 03-1234-5678
memo: 展示会で交換, 要フォロー
job: 鳶
trust: 4
next_contact: 2026-11-03
status: 登録済
scanned: 2026-10-24
source: k01.json
tags: [名刺]
---
''';
const _b = '''---
type: meishi
name: 鈴木 "一郎"
company: トビショク商事
scanned: 2026-10-25
source: k02.json
tags: [名刺]
---
''';

void main() {
  test('csvOfNotes: BOM, Japanese header, newest first, every field quoted with quotes doubled', () {
    final csv = csvOfNotes({'a': _a, '_名刺一覧': '---\ntype: meishi_index\n---\n', 'b': _b});
    expect(csv.codeUnitAt(0), 0xFEFF, reason: 'Excel needs the BOM to read UTF-8');
    final lines = csv.substring(1).split('\r\n').where((l) => l.isNotEmpty).toList();
    expect(lines.length, 3);
    expect(lines[0], startsWith('"氏名","ふりがな","会社"'));
    expect(lines[0], endsWith('"状態","取込日","ノート"'));
    expect(lines[1], contains('"鈴木 ""一郎"""'), reason: 'newest first; quotes doubled');
    expect(lines[2], contains('"展示会で交換, 要フォロー"'));
    expect(lines[2], contains('"鳶"'));
    expect(lines[2], contains('"4","2026-11-03"'), reason: '信頼度 then 次回連絡日');
    expect(lines[2], contains('"2026-11-03"'));
    expect(lines[2], endsWith('"登録済","2026-10-24","a"'));
    expect(lines[1], contains('"確認済"'), reason: 'legacy notes without status are reviewed');
    expect(csvOfNotes(const {}), isNot(contains('\r\n"')), reason: 'header only');
    expect(csvAndRows(const {}).$2, 0);
  });

  test('cells that Excel would evaluate get a leading apostrophe', () {
    const risky = '''---
type: meishi
name: =HYPERLINK("http://x")
mobile: +81-90-1234-5678
memo: -memo
tags: [名刺]
---
''';
    final csv = csvOfNotes({'r': risky});
    expect(csv, contains('"\'=HYPERLINK(""http://x"")"'));
    expect(csv, contains('"\'+81-90-1234-5678"'));
    expect(csv, contains('"\'-memo"'));
  });

  test('exportCsv writes vault/_名刺.csv and counts the cards', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_csv_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(
        stem: 'k01', front: const [], back: const [], expected: {'name': '山田 太郎'}, status: CardStatus.reviewed);
    final (file, n) = await store.exportCsv();
    expect(file.path.replaceAll('\\', '/'), endsWith('vault/_名刺.csv'));
    expect(n, 1);
    expect(utf8.decode(await file.readAsBytes()), contains('山田 太郎'));
  });
}
