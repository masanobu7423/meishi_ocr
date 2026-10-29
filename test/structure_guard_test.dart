// Guards for the shared helpers from the 2026-10-29 refactoring: one card-note
// filter, one permission message, one date formatter. Source-level checks keep
// copies from creeping back in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/dates.dart';
import 'package:meishi_ocr/ocr/sync.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';

String _lib() => [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) f.readAsStringSync(),
    ].join('\n');

void main() {
  test('cardNotes yields only card notes, as (stem, frontmatter), in order', () {
    final notes = {
      'b': '---\ntype: meishi\nname: B\n---\n',
      '_名刺一覧': '---\ntype: meishi_index\n---\n',
      'a': '---\ntype: meishi\nname: A\n---\n',
      'x': 'no frontmatter',
    };
    expect([for (final (s, fm) in cardNotes(notes)) '$s=${fm['name']}'], ['b=B', 'a=A']);
  });

  test('ymd / parseYmd live in one place', () {
    expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
    expect(parseYmd('2026-02-30'), isNull);
    final src = _lib();
    expect(RegExp(r'String _ymd\(').hasMatch(src), isFalse, reason: 'use dates.dart ymd');
  });

  test('card notes are selected only through cardNotes', () {
    final src = _lib();
    expect("fm['type'] != 'meishi'".allMatches(src).length, 0);
    expect("['type'] == 'meishi'".allMatches(src).length, 1, reason: 'the one check inside cardNotes');
  });

  test('the missing-permission message is written once and the request goes through one function', () {
    final src = _lib();
    expect(noContactsPermission.allMatches(src).length, 1, reason: 'only the constant itself');
    expect('permissions.request(PermissionType.readWrite)'.allMatches(src).length, 1,
        reason: 'only inside requestContactsAccess');
  });
}
