import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/sync.dart';

void main() {
  final accounts = [
    const Account(id: 'local', name: 'Phone', type: 'vnd.sec.contact.phone'),
    const Account(id: 'g1', name: 'taro@gmail.com', type: 'com.google'),
    const Account(id: 'g2', name: 'work@gmail.com', type: 'com.google'),
  ];

  group('preferredAccount', () {
    test('uses the saved account (by type|name, ids are not unique everywhere)', () {
      expect(preferredAccount(accounts, savedKey: 'com.google|work@gmail.com')?.id, 'g2');
      expect(accountKey(accounts[2]), 'com.google|work@gmail.com');
    });
    test('falls back to the first Google account', () {
      expect(preferredAccount(accounts)?.id, 'g1');
      expect(preferredAccount(accounts, savedKey: 'gone|x')?.id, 'g1');
    });
    test('null (device default) when there is no Google account', () {
      expect(preferredAccount([accounts.first]), isNull);
    });
    test('isGoogle tells the two kinds apart; sortedAccounts puts Google first', () {
      expect(isGoogle(accounts[1]), isTrue);
      expect(isGoogle(accounts[0]), isFalse);
      expect(sortedAccounts(accounts).map((a) => a.id), ['g1', 'g2', 'local']);
    });
  });

  group('syncPlan', () {
    final existing = [
      Contact(displayName: 'A', phones: [Phone(number: '090-1111-2222')]),
    ];
    test('creates cards that are not in the address book, skips the rest with a reason', () {
      final plan = syncPlan([
        CardFields()..name = '新規 太郎'..mobile = '080-0000-0000',
        CardFields()..name = '既存 花子'..mobile = '+81 90 1111 2222',
        CardFields()..company = '名無し株式会社',
      ], existing);
      expect(plan.map((p) => p.action), [SyncAction.create, SyncAction.skipExisting, SyncAction.skipNoName]);
      expect(plan.where((p) => p.action == SyncAction.create).single.card.name, '新規 太郎');
    });
    test('a card created earlier in the same run is not created twice', () {
      final plan = syncPlan([
        CardFields()..name = 'A'..email = 'x@example.com',
        CardFields()..name = 'A again'..email = 'X@EXAMPLE.com',
      ], const []);
      expect(plan.map((p) => p.action), [SyncAction.create, SyncAction.skipExisting]);
    });
  });
}
