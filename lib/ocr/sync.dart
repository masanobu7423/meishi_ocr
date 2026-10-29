import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_mapper.dart';
import 'extractor.dart';
import 'history.dart';

/// "Google 同期" without any network code: contacts written into the Google
/// account on the device are synced by Android itself. This module only
/// decides which account to write to and which saved cards still need
/// writing.

/// The one message for a missing contacts permission (banner or toast).
const noContactsPermission = '連絡先の権限がありません。端末の設定でこのアプリに連絡先を許可してください';

/// Asks for read/write contacts access (the system dialog the first time);
/// true when granted.
Future<bool> requestContactsAccess() async =>
    await FlutterContacts.permissions.request(PermissionType.readWrite) == PermissionStatus.granted;

bool isGoogle(Account a) => a.type == 'com.google';

/// Stable identity for persisting the choice. The plugin's `id` is not
/// unique on every device (one phone returned the same id for all accounts).
String accountKey(Account a) => '${a.type}|${a.name}';

/// Google accounts first, then the rest in the order the device gave.
List<Account> sortedAccounts(List<Account> accounts) =>
    [...accounts.where(isGoogle), ...accounts.where((a) => !isGoogle(a))];

/// The account to register into: the one the user chose (if it still
/// exists), else the first Google account, else null = device default.
Account? preferredAccount(List<Account> accounts, {String? savedKey}) {
  if (savedKey != null) {
    final saved = accounts.where((a) => accountKey(a) == savedKey);
    if (saved.isNotEmpty) return saved.first;
  }
  final google = accounts.where(isGoogle);
  return google.isEmpty ? null : google.first;
}

enum SyncAction { create, skipExisting, skipNoName }

class SyncItem {
  final CardFields card;
  final SyncAction action;
  const SyncItem(this.card, this.action);
}

/// One-way push plan: every saved card not yet in the address book (by
/// phone / email, same rule as the duplicate check) gets created; cards
/// created earlier in the same plan count as existing.
List<SyncItem> syncPlan(List<CardFields> cards, List<Contact> existing) {
  final known = List.of(existing);
  final plan = <SyncItem>[];
  for (final c in cards) {
    if (c.name == null || c.name!.trim().isEmpty) {
      plan.add(SyncItem(c, SyncAction.skipNoName));
    } else if (findDuplicate(c, known) != null) {
      plan.add(SyncItem(c, SyncAction.skipExisting));
    } else {
      plan.add(SyncItem(c, SyncAction.create));
      known.add(toContact(c, scannedAt: DateTime.now()));
    }
  }
  return plan;
}

enum ImportAction { create, skipLinked, skipExisting, skipNoName }

class ImportItem {
  final Contact contact;
  final ImportAction action;
  const ImportItem(this.contact, this.action);
}

/// Pull plan: which address-book contacts become new cards. Linked ones
/// (a card carries their id) and ones a card already matches by phone /
/// email are skipped, as are contacts without a name.
List<ImportItem> importPlan(List<Contact> contacts, List<CardSummary> cards) {
  final linked = {for (final c in cards) if (c.contactId != null) c.contactId!};
  final keys = <String>{
    for (final c in cards) ...[
      for (final p in [c.phone, c.mobile]) if (p != null && p.isNotEmpty) phoneDigits(p),
      if (c.email != null && c.email!.isNotEmpty) c.email!.toLowerCase(),
    ],
  };
  return [
    for (final c in contacts)
      ImportItem(
        c,
        c.id != null && linked.contains(c.id)
            ? ImportAction.skipLinked
            : (c.displayName ?? '').trim().isEmpty
                ? ImportAction.skipNoName
                : c.phones.any((p) => keys.contains(phoneDigits(p.number))) ||
                        c.emails.any((e) => keys.contains(e.address.toLowerCase()))
                    ? ImportAction.skipExisting
                    : ImportAction.create,
      ),
  ];
}
