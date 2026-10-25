import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_mapper.dart';
import 'extractor.dart';

/// "Google 同期" without any network code: contacts written into the Google
/// account on the device are synced by Android itself. This module only
/// decides which account to write to and which saved cards still need
/// writing.

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
