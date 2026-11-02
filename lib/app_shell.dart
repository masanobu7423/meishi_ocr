import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'card_list.dart';
import 'choice_sheet.dart';
import 'files.dart';
import 'home_screen.dart';
import 'main.dart';
import 'ocr/actions.dart';
import 'ocr/card_merge.dart';
import 'ocr/card_status.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart' show CardFields;
import 'ocr/history.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/sync.dart';
import 'ocr/vault_index.dart';
import 'ocr/vcard_export.dart';
import 'jobs_screen.dart';
import 'ocr/ics_export.dart';
import 'ocr/jobs.dart';
import 'share.dart';
import 'theme.dart';

/// Android: `/sdcard/Android/data/<pkg>/files` (reachable with plain adb pull
/// and the Files app). Elsewhere: app documents.
Future<(CardStore, OcrPipeline)> initStore() async {
  final dir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
      await getApplicationDocumentsDirectory();
  final store = CardStore(dir);
  return (store, OcrPipeline(store));
}

/// Four tabs: ホーム / スキャン / 検索 / 一覧. Home, search and list read the
/// vault; scan writes it and tells the shell to refresh. The shell also owns
/// the "which account do registrations go to" choice (Google sync happens
/// through the OS once contacts live in the Google account).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Future<(CardStore, OcrPipeline)> _ready = initStore();
  final _scanKey = GlobalKey<ScanPageState>();
  int _tab = 0;
  int _refresh = 0;
  late Future<List<CardSummary>> _cards = _load();
  Account? _account;
  bool _accountResolved = false;

  Map<String, List<String>> _suggestions = const {};
  List<String> _jobs = defaultJobs;
  StatusFilter _listFilter = StatusFilter.all;
  /// settings.json: the day a backup last left the phone, and 自分の名刺's stem.
  String? _lastExport, _myCard;

  Future<void> _setSetting(String key, Object value) async {
    final (store, _) = await _ready;
    await store.saveSettings({...await store.loadSettings(), key: value});
  }

  /// 自分の名刺にする (one card selected in the list).
  Future<void> _makeMine(CardSummary c) async {
    await _setSetting('myCard', c.stem);
    if (!mounted) return;
    setState(() => _myCard = c.stem);
    _toast('「${c.name}」を自分の名刺にしました。ホームの「自分の名刺を送る」で渡せます');
  }

  /// 自分の名刺を送る: as text (LINE, SMS) or as a vCard (mail, contacts).
  Future<void> _sendMine() async {
    final (store, _) = await _ready;
    final stored = _myCard == null ? null : await store.loadCard(_myCard!);
    if (!mounted) return;
    if (stored == null) {
      _toast('自分の名刺が見つかりません。一覧で選び直してください');
      return;
    }
    final f = fieldsFromJson(stored.expected);
    final how = await showChoiceSheet(context, '自分の名刺を送る', const [
      Choice('text', Icons.chat_outlined, 'テキストで送る', 'LINE や SMS に、氏名・会社・電話・メールを文字で貼ります'),
      Choice('vcard', Icons.contact_page_outlined, '連絡先ファイル（vCard）で送る', 'メールで送ると、相手がそのまま電話帳に登録できます'),
    ]);
    if (how == null) return;
    final name = f.name ?? '自分の名刺';
    final ok = how == 'text'
        ? await shareMessage(cardText(f), subject: '名刺: $name')
        : await shareVcard(name, myCardVcard(f));
    if (!ok && mounted) _toast('共有できませんでした');
  }

  Future<List<CardSummary>> _load() async {
    final (store, _) = await _ready;
    final notes = await store.notes();
    _suggestions = suggestionsFrom(notes);
    _jobs = await store.loadJobs();
    final settings = await store.loadSettings();
    _lastExport = settings['lastExport'] as String?;
    _myCard = settings['myCard'] as String?;
    return cardSummaries(notes);
  }

  void _reload() => setState(() {
        _refresh++;
        _cards = _load();
      });

  void _go(int tab) => setState(() {
        if (_tab != tab && tab != 1) _cards = _load(); // leaving scan -> fresh data
        _tab = tab;
      });

  Future<void> _open(CardSummary c) async {
    _go(1);
    await _scanKey.currentState?.loadStoredCard(c);
  }

  /// The 職種 list behind the form's dropdown: add / rename / delete.
  Future<void> _editJobs() async {
    final (store, _) = await _ready;
    if (!mounted) return;
    final edited = List.of(_jobs);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobsScreen(jobs: edited)));
    if (listEquals(edited, _jobs)) return;
    try {
      await store.saveJobs(edited);
    } catch (e) {
      if (mounted) _toast('職種の一覧を保存できませんでした: $e');
      return;
    }
    _reload(); // re-reads jobs.json (an empty list falls back to the defaults)
  }

  /// The row's call button: the mobile first, else the office line.
  Future<void> _call(CardSummary c) async {
    final a = quickCall(phone: c.phone, mobile: c.mobile);
    if (a == null) return;
    if (!await launchUrl(a.uri, mode: LaunchMode.externalApplication) && mounted) {
      _toast('電話アプリを開けません');
    }
  }

  /// 連絡済み: today becomes the 最終連絡日 of the selected cards, and a sheet
  /// asks for the next 次回連絡日 (none / 1 week … 3 months). The phone
  /// book's note follows the next time the card is saved, as for any edit.
  Future<void> _followedUp(List<CardSummary> cards) async {
    final today = DateTime.now();
    String on(FollowUp f) => ymd(followUpDate(today, f));
    final picked = await showChoiceSheet<String>(context, '次の連絡予定', [
      const Choice('none', Icons.event_busy_outlined, '次の予定なし', '次回連絡日を消します'),
      Choice(FollowUp.week.name, Icons.event_outlined, '1 週間後', on(FollowUp.week)),
      Choice(FollowUp.twoWeeks.name, Icons.event_outlined, '2 週間後', on(FollowUp.twoWeeks)),
      Choice(FollowUp.month.name, Icons.event_outlined, '1 か月後', on(FollowUp.month)),
      Choice(FollowUp.threeMonths.name, Icons.event_outlined, '3 か月後', on(FollowUp.threeMonths)),
    ]);
    if (picked == null) return; // dismissed: nothing recorded
    final next = FollowUp.values.where((f) => f.name == picked).map(on).firstOrNull;
    final (store, _) = await _ready;
    var n = 0;
    for (final c in cards) {
      try {
        if (await store.setFollowUp(c.stem, last: ymd(today), next: next)) n++;
      } catch (e) {
        await store.appendError('setFollowUp ${c.stem}', e);
      }
    }
    if (!mounted) return;
    _reload();
    _scanKey.currentState?.refreshFollowUp({for (final c in cards) c.stem}, last: ymd(today), next: next);
    final count = n == cards.length ? '$n 件' : '${cards.length} 件中 $n 件';
    // The contact's note keeps its 次回連絡 line until the card is saved again.
    final linked = cards.any((c) => c.status == CardStatus.registered);
    _toast('$countを連絡済みにしました${next == null ? "" : "（次回 $next）"}${linked ? "。電話帳のメモは、その名刺を次に保存したときに更新されます" : ""}');
  }

  /// The menu: four rarely used groups. Exports and backups open a sheet
  /// that says what each one is for.
  Future<void> _menu(String v) async {
    final sheet = switch (v) {
      'phonebook' => ('電話帳', const [
          Choice('sync', Icons.person_add_alt_outlined, '未登録の名刺を電話帳に登録',
              '確認済みで電話帳にない名刺を、登録先のアカウントにまとめて入れます'),
          Choice('import_contacts', Icons.contacts_outlined, '電話帳から取り込む',
              '電話帳の連絡先を名刺として取り込み、職種や信頼度で探せるようにします'),
        ]),
      'export' => ('書き出し・共有', const [
          Choice('share_csv', Icons.table_chart_outlined, '全件を CSV で共有', 'Excel で開く一覧表。メールやドライブに送れます'),
          Choice('share_vcard', Icons.contact_page_outlined, '全件を vCard で共有', '別のスマホやパソコンの連絡先アプリに読み込めます'),
          Choice('share_ics', Icons.event_outlined, '連絡予定を共有（ics）', '次回連絡日をカレンダーアプリにまとめて読み込めます'),
          Choice('vcard', Icons.save_alt_outlined, '全件を vCard でアプリのフォルダに保存', 'パソコンにつないで取り出すとき用'),
        ]),
      'backup' => ('バックアップ', const [
          Choice('share_backup', Icons.cloud_upload_outlined, 'バックアップを共有', 'ドライブやメールに保存。機種変更やアンインストールに備えます'),
          Choice('backup', Icons.archive_outlined, 'バックアップを作る', 'アプリのフォルダに保存します（毎日 1 回は自動で作ります）'),
          Choice('restore', Icons.restore, 'バックアップから復元', '保存したバックアップの名刺を取り込みます'),
          Choice('trash', Icons.restore_from_trash_outlined, '削除した名刺を戻す', '削除してから 7 日以内の名刺を元に戻せます'),
        ]),
      _ => null,
    };
    final picked = sheet == null ? v : await showChoiceSheet(context, sheet.$1, sheet.$2);
    if (!mounted) return;
    await switch (picked) {
      'account' => _chooseAccount(),
      'sync' => _syncAll(),
      'import_contacts' => _importContacts(),
      'vcard' => _exportVcard(),
      'share_vcard' => _shareAllVcard(),
      'share_csv' => _shareCsv(),
      'share_ics' => _shareIcs(),
      'share_backup' => _shareBackup(),
      'jobs' => _editJobs(),
      'restore' => _restore(),
      'trash' => _showTrash(),
      'backup' => _backup(),
      _ => Future<void>.value(),
    };
  }

  /// Selected cards as one vCard through the system share sheet.
  Future<void> _shareCards(List<CardSummary> cards) async {
    if (cards.isEmpty) return;
    final (store, _) = await _ready;
    final notes = await store.notes();
    final vcf = vcardOfNotes({for (final c in cards) c.noteStem: ?notes[c.noteStem]});
    final name = cards.length == 1 ? cards.single.name : '名刺${cards.length}件';
    if (vcf.isEmpty || !await shareVcard(name, vcf)) {
      if (mounted) _toast('共有できませんでした');
    }
  }

  /// Every card as one vCard, handed to the share sheet (Drive, mail, …).
  Future<void> _shareAllVcard() async {
    final (store, _) = await _ready;
    final (file, n) = await store.exportVcard();
    if (n == 0) {
      if (mounted) _toast('共有できる名刺がありません');
      return;
    }
    if (!await shareFile(file, mime: 'text/vcard', subject: '名刺 $n 件 (vCard)') && mounted) _toast('共有できませんでした');
  }

  /// Every 次回連絡日 as an iCalendar file: import once into any calendar.
  Future<void> _shareIcs() async {
    final (store, _) = await _ready;
    final dated = byNextContact(cardSummaries(await store.notes()));
    if (dated.isEmpty) {
      if (mounted) _toast('次回連絡日を入れた名刺がありません');
      return;
    }
    if (!await shareText('連絡予定.ics', 'text/calendar', icsOfCards(dated), subject: '名刺スキャン 連絡予定 ${dated.length} 件') &&
        mounted) {
      _toast('共有できませんでした');
    }
  }

  /// Every card as CSV (Excel-ready) to the share sheet.
  Future<void> _shareCsv() async {
    final (store, _) = await _ready;
    final (file, n) = await store.exportCsv();
    if (n == 0) {
      if (mounted) _toast('共有できる名刺がありません');
      return;
    }
    if (!await shareFile(file, mime: 'text/csv', subject: '名刺 $n 件 (CSV)') && mounted) _toast('共有できませんでした');
  }

  /// A fresh backup zip to the share sheet: the way to get it off the phone.
  Future<void> _shareBackup() async {
    final (store, _) = await _ready;
    final (zip, n) = await store.backup();
    if (n == 0) {
      if (mounted) _toast('バックアップする名刺がありません');
      return;
    }
    // Gone through (not cancelled): the copy is off the phone, the home nudge rests.
    final today = ymd(DateTime.now());
    var shared = false;
    final ok = await shareFile(zip, mime: 'application/zip', subject: '名刺スキャンのバックアップ',
        onShared: () => shared = true);
    if (shared) {
      await _setSetting('lastExport', today);
      if (mounted) setState(() => _lastExport = today);
    }
    if (!ok && mounted) _toast('共有できませんでした');
  }

  /// Selected on the home / search / list screens: confirm once, delete
  /// each (JSON, note, photos), leave the address book alone.
  Future<void> _deleteCards(List<CardSummary> cards) async {
    if (cards.isEmpty) return;
    // No confirmation: deleting moves to the trash, and the SnackBar undoes it.
    final (store, _) = await _ready;
    final gone = <String>[];
    for (final c in cards) {
      if (await store.deleteCard(c.stem)) gone.add(c.stem);
    }
    _scanKey.currentState?.forget(cards.map((c) => c.stem).toSet());
    _reload();
    if (!mounted) return;
    if (gone.isEmpty) {
      _toast('削除できませんでした');
      return;
    }
    _undoToast('${gone.length} 件を削除しました', () async {
      var back = 0;
      for (final stem in gone) {
        if (await store.undelete(stem)) back++;
      }
      if (back < gone.length && mounted) _toast('同じ名前の名刺が新しく保存されているため、${gone.length - back} 件は戻せませんでした');
    });
  }

  /// まとめる: two cards of one person become the newer one (取込日), the
  /// older goes to the trash; both steps are undone by 元に戻す.
  Future<void> _merge(CardSummary a, CardSummary b) async {
    final (newer, older) = (a.scanned ?? '').compareTo(b.scanned ?? '') >= 0 ? (a, b) : (b, a);
    final (store, _) = await _ready;
    final n = await store.loadCard(newer.stem), o = await store.loadCard(older.stem);
    if (!mounted) return;
    if (n == null || o == null) {
      _toast('まとめられませんでした。名刺が見つかりません');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('2 枚を 1 枚にまとめますか？'),
        content: Text('新しい名刺（${newer.scanned ?? "日付なし"}「${newer.name}」）の内容を優先し、空いている項目を古い名刺'
            '（${older.scanned ?? "日付なし"}「${older.name}」）で埋めます。メモ・関係者は合わせ、古い会社や役職はメモに「旧:」で残します。'
            '古い名刺は削除した名刺に移ります。電話帳の連絡先はそのままです。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('まとめる')),
        ],
      ),
    );
    if (go != true) return;
    final merged = mergeCards(newer: n.expected, older: o.expected, olderScanned: older.scanned);
    // The older card's phone-book link (and 登録済) carry over, so the next 保存
    // of this card brings the old contact up to date, instead of 未登録を登録
    // creating a second contact.
    final inherited = (n.expected['contactId'] ?? '').isEmpty && (o.expected['contactId'] ?? '').isNotEmpty;
    await store.replaceFields(newer.stem, merged, mergedStatus(n.status, o.status));
    await store.deleteCard(older.stem);
    // An open form would save the pre-merge values back: clear it.
    _scanKey.currentState?.forget({newer.stem, older.stem});
    _reload();
    if (!mounted) return;
    _undoToast(
        '「${newer.name}」の名刺を 1 枚にまとめました${inherited ? '。電話帳の連絡先は、この名刺を開いて保存すると新しい内容になります' : ''}',
        () async {
      // Edited since (a 連絡済み, a 保存): keep that; only bring the old card back.
      final now = await store.loadCard(newer.stem);
      if (now != null && mapEquals(now.expected, merged)) {
        await store.replaceFields(newer.stem, n.expected, n.status);
      } else if (mounted) {
        _toast('まとめた後に変更があるため、古い名刺だけ戻しました');
      }
      await store.undelete(older.stem);
    });
  }

  /// 削除した名刺を戻す: the trash (7 days), one card at a time.
  Future<void> _showTrash() async {
    final (store, _) = await _ready;
    final items = await store.trashed();
    if (!mounted) return;
    if (items.isEmpty) {
      _toast('削除した名刺はありません（7 日たつと完全に消えます）');
      return;
    }
    final stem = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('削除した名刺を戻す'),
        children: [
          for (final t in items)
            ListTile(
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: Text(t.name),
              subtitle: Text('${ymd(t.at)} に削除'),
              onTap: () => Navigator.pop(c, t.stem),
            ),
        ],
      ),
    );
    if (stem == null) return;
    final ok = await store.undelete(stem);
    _reload();
    if (mounted) _toast(ok ? '名刺を元に戻しました' : '同じ名前の名刺が新しく保存されているため、戻せませんでした');
  }

  /// A SnackBar with 元に戻す; the undo reloads the lists when done. An
  /// action SnackBar would stay forever by default: it times out, except for
  /// screen-reader users, who need the time to reach the action.
  void _undoToast(String message, Future<void> Function() undo) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 8),
      persist: MediaQuery.accessibleNavigationOf(context),
      action: SnackBarAction(
        label: '元に戻す',
        onPressed: () async {
          await undo();
          _reload();
        },
      ),
    ));
  }

  // ---- account / sync ------------------------------------------------------

  /// Resolves the target account once contacts permission is available;
  /// without permission the device default is used silently.
  Future<Account?> _resolveAccount() async {
    if (_accountResolved) return _account;
    if (!await FlutterContacts.permissions.has(PermissionType.read)) return null;
    final (store, _) = await _ready;
    final saved = (await store.loadSettings())['accountKey'] as String?;
    _account = preferredAccount(await FlutterContacts.accounts.getAll(), savedKey: saved);
    _accountResolved = true;
    if (mounted) setState(() {});
    return _account;
  }

  String? get _accountLabel => !_accountResolved
      ? null
      : _account == null
          ? '端末の既定（Google 同期なし）'
          : '${_account!.name}（${isGoogle(_account!) ? "Google" : _account!.type}）';

  Future<void> _chooseAccount() async {
    if (!await requestContactsAccess()) {
      _toast(noContactsPermission);
      return;
    }
    final accounts = sortedAccounts(await FlutterContacts.accounts.getAll());
    if (!mounted) return;
    final current = _account == null ? null : accountKey(_account!);
    final picked = await showDialog<Account?>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('登録先のアカウント'),
        children: [
          for (final a in accounts)
            ListTile(
              leading: Icon(accountKey(a) == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  semanticLabel: accountKey(a) == current ? '選択中' : null),
              title: Text(a.name),
              subtitle: Text(isGoogle(a) ? 'Google（自動で同期されます）' : a.type),
              onTap: () => Navigator.pop(c, a),
            ),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('アカウントが見つかりません。端末の設定で Google アカウントを追加してください'),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _setSetting('accountKey', accountKey(picked));
    setState(() {
      _account = picked;
      _accountResolved = true;
    });
  }

  /// One-way push: every saved card not yet in the address book is created
  /// in the chosen account; already-present ones (phone / email match) and
  /// nameless ones are skipped and counted.
  Future<void> _syncAll() async {
    if (!await requestContactsAccess()) {
      _toast(noContactsPermission);
      return;
    }
    final account = await _resolveAccount();
    final (store, _) = await _ready;
    // Only cards someone has looked at: a burst capture is still a guess.
    final stems = <CardFields, String>{};
    for (final (_, fm) in cardNotes(await store.notes())) {
      if (parseStatus(fm['status']) == CardStatus.unreviewed) continue;
      stems[fieldsFromFrontmatter(fm)] = (fm['source'] ?? '').replaceAll(RegExp(r'\.json$'), '');
    }
    final cards = stems.keys.toList();
    final existing = await FlutterContacts.getAll(properties: {ContactProperty.phone, ContactProperty.email});
    final plan = syncPlan(cards, existing);
    final creates = plan.where((p) => p.action == SyncAction.create).toList();
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('未登録の名刺を電話帳に登録'),
        content: Text('${creates.length} 件を登録します（既存 ${plan.where((p) => p.action == SyncAction.skipExisting).length} 件、'
            '氏名なし ${plan.where((p) => p.action == SyncAction.skipNoName).length} 件は飛ばします）。\n'
            '登録先: ${_accountLabel ?? "端末の既定"}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('登録する')),
        ],
      ),
    );
    if (go != true) return;
    var done = 0;
    for (final p in creates) {
      final id = await FlutterContacts.create(toContact(p.card, scannedAt: DateTime.now()), account: account);
      final stem = stems[p.card];
      if (stem != null && stem.isNotEmpty) await store.setStatus(stem, CardStatus.registered, contactId: id);
      done++;
    }
    _reload();
    if (mounted) _toast('$done 件を電話帳に登録しました');
  }

  /// Pull: contacts of the chosen account (the Google one, synced by the
  /// device) become cards, so the app holds the whole address book and can
  /// group it by 職種 / 信頼度. Linked and matching contacts are skipped.
  Future<void> _importContacts() async {
    if (!await requestContactsAccess()) {
      _toast(noContactsPermission);
      return;
    }
    final account = await _resolveAccount();
    final (store, _) = await _ready;
    final cards = cardSummaries(await store.notes());
    // allProperties = everything but photos (not used for a card).
    final contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties, account: account);
    final plan = importPlan(contacts, cards);
    final creates = plan.where((p) => p.action == ImportAction.create).toList();
    int n(ImportAction a) => plan.where((p) => p.action == a).length;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('電話帳から取り込む'),
        content: Text('${creates.length} 件を名刺として取り込みます（登録済 ${n(ImportAction.skipLinked)} 件、'
            '同じ電話・メールの名刺あり ${n(ImportAction.skipExisting)} 件、氏名なし ${n(ImportAction.skipNoName)} 件は飛ばします）。\n'
            '取込元: ${_accountLabel ?? "端末の既定"}\n写真はありません。取り込んだ名刺は登録済になり、修正すると電話帳にも反映されます'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('取り込む')),
        ],
      ),
    );
    if (go != true) return;
    var done = 0;
    for (final p in creates) {
      final f = fieldsFromContact(p.contact);
      await store.saveCard(
          stem: 'pb_${p.contact.id}', front: const [], back: const [], expected: f.toJson(),
          status: CardStatus.registered);
      done++;
    }
    _reload();
    if (mounted) _toast('$done 件を電話帳から取り込みました');
  }

  Future<void> _exportVcard() async {
    final (store, _) = await _ready;
    final (file, n) = await store.exportVcard();
    if (mounted) _toast('$n 件を vCard に書き出しました（${file.path}）');
  }

  Future<void> _backup() async {
    final (store, _) = await _ready;
    final (file, n) = await store.backup();
    if (mounted) _toast('$n ファイルをバックアップしました（${file.path}）');
  }

  /// Pick a zip from `<root>/backup/` (made here, or copied in with the
  /// Files app) and unpack it over the current store.
  Future<void> _restore() async {
    final (store, _) = await _ready;
    final zips = await store.backups();
    if (!mounted) return;
    // A zip from Drive / Downloads (the new phone after a model change), or
    // one of the automatic backups in the app folder.
    final choice = await showDialog<Object>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('バックアップから復元'),
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('ファイルから選ぶ'),
            subtitle: const Text('ドライブやダウンロードに保存したバックアップ（.zip）'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
          for (final z in zips)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(backupLabel(z)),
              onTap: () => Navigator.pop(c, z),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final fromFile = choice == 'pick';
    final File? picked;
    try {
      // The picker copies the zip off Drive after it closes: show that work.
      picked = fromFile ? await _busy(pickBackupZip()) : choice as File;
    } on PlatformException catch (e) {
      if (mounted) {
        _toast(e.code == 'too_large'
            ? 'ファイルが大きすぎます（512MB まで）。名刺スキャンのバックアップ（.zip）を選んでください'
            : 'ファイルを読み込めませんでした。もう一度選ぶか、端末に保存してから選んでください');
      }
      return;
    }
    if (picked == null) return;
    try {
      await _restoreFrom(store, picked, fromFile);
    } finally {
      // The picker's copy lives in the cache; the app-folder backups stay.
      if (fromFile && picked.existsSync()) await picked.delete();
    }
  }

  Future<void> _restoreFrom(CardStore store, File picked, bool fromFile) async {
    if (!mounted) return;
    final label = fromFile ? '選んだファイル' : '${backupLabel(picked)} ';
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('復元しますか？'),
        content: Text('$labelのバックアップの名刺を取り込みます。'
            '同じ名刺は上書きし、ほかの名刺はそのまま残ります。電話帳は変わりません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('復元する')),
        ],
      ),
    );
    if (go != true) return;
    final (int written, int failed) result;
    try {
      // A backup from before 2026-11-02 brings back notes cut at a line break.
      result = await _busy(store.restore(picked).then((r) async {
        await store.repairNotes();
        return r;
      }));
    } catch (e) {
      await store.appendError('restore ${picked.path}', e);
      if (mounted) _toast('復元できませんでした。zip が壊れているか、バックアップの形式ではありません');
      return;
    }
    _reload();
    if (!mounted) return;
    final (written, failed) = result;
    _toast(written == 0 && failed == 0
        ? 'このファイルには名刺のバックアップが入っていません'
        : failed == 0
        ? '$written ファイルを復元しました'
        : '$written ファイルを復元、$failed ファイルは書き込めませんでした（log/errors.txt に記録）');
  }

  /// [work] under a modal 読み込み中… (restore and the picker's copy take
  /// seconds; without it the screen looks frozen and gets tapped again).
  Future<T> _busy<T>(Future<T> work) async {
    final nav = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [CircularProgressIndicator(), SizedBox(width: AppSpace.gutter), Text('読み込み中…')]),
        ),
      ),
    );
    try {
      return await work;
    } finally {
      nav.pop();
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    _resolveAccount();
    // Unattended daily backup (5 kept): the app's folder dies with an
    // uninstall, so the zips are at least there to copy out.
    _ready.then((r) async {
      try {
        await r.$1.autoBackup();
      } catch (e) {
        await r.$1.appendError('autoBackup', e);
      }
      try {
        await r.$1.purgeTrash(); // deleted more than 7 days ago: gone for good
      } catch (e) {
        await r.$1.appendError('purgeTrash', e);
      }
      // Once: rebuild notes cut at a line break before 2026-11-02 (R0).
      try {
        if ((await r.$1.loadSettings())['notesRepaired'] != true) {
          final n = await r.$1.repairNotes();
          await _setSetting('notesRepaired', true);
          if (n > 0 && mounted) _reload();
        }
      } catch (e) {
        await r.$1.appendError('repairNotes', e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['名刺スキャン', 'スキャン', '検索', '一覧'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 1)
            IconButton(
              tooltip: 'フォルダの画像をまとめて取り込む',
              icon: const Icon(Icons.folder_open),
              onPressed: () => _scanKey.currentState?.importInbox(),
            ),
          PopupMenuButton<String>(
            tooltip: 'その他',
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'phonebook', child: Text('電話帳と同期')),
              PopupMenuItem(value: 'export', child: Text('書き出し・共有')),
              PopupMenuItem(value: 'backup', child: Text('バックアップ')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'account', child: Text('登録先のアカウント')),
              PopupMenuItem(value: 'jobs', child: Text('職種の一覧を編集')),
            ],
          ),
        ],
      ),
      body: FutureBuilder(
        future: Future.wait([_ready, _cards]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? Center(child: Text('保存先を開けません: ${snap.error}'))
                : const Center(child: CircularProgressIndicator());
          }
          final (store, _) = snap.data![0] as (CardStore, OcrPipeline);
          final cards = snap.data![1] as List<CardSummary>;
          return IndexedStack(
            index: _tab,
            children: [
              HomeScreen(
                key: ValueKey('home$_refresh'),
                cards: cards,
                vault: store.vaultDir,
                today: DateTime.now(),
                accountLabel: _accountLabel,
                onChangeAccount: _chooseAccount,
                onScan: () {
                  _go(1);
                  _scanKey.currentState?.shoot(true, ImageSource.camera);
                },
                onAlbum: () {
                  _go(1);
                  _scanKey.currentState?.shoot(true, ImageSource.gallery);
                },
                onImport: () {
                  _go(1);
                  _scanKey.currentState?.importInbox();
                },
                onOpenCard: _open,
                onDelete: _deleteCards,
                onShare: _shareCards,
                onCall: _call,
                onFollowedUp: _followedUp,
                lastExport: _lastExport,
                onBackup: _shareBackup,
                // A deleted 自分の名刺 simply stops showing the button.
                myCardName: cards.where((c) => c.stem == _myCard).firstOrNull?.name,
                onSendMine: _sendMine,
                onSeeAll: () => _go(3),
                onContinue: (f) {
                  setState(() => _listFilter = f);
                  _go(3);
                },
              ),
              ScanPage(
                key: _scanKey,
                ready: _ready,
                onSaved: _reload,
                account: _resolveAccount,
                suggestions: _suggestions,
                jobs: _jobs,
              ),
              SearchScreen(
                  cards: cards,
                  vault: store.vaultDir,
                  onTap: _open,
                  onCall: _call,
                  onDelete: _deleteCards,
                  onShare: _shareCards,
                  onFollowedUp: _followedUp),
              ListScreen(
                cards: cards,
                vault: store.vaultDir,
                onTap: _open,
                onDelete: _deleteCards,
                onShare: _shareCards,
                onFollowedUp: _followedUp,
                onCall: _call,
                onMakeMine: _makeMine,
                onMerge: _merge,
                filter: _listFilter,
                onFilter: (f) => setState(() => _listFilter = f),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ホーム'),
          NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner), label: 'スキャン'),
          NavigationDestination(icon: Icon(Icons.search), label: '検索'),
          NavigationDestination(icon: Icon(Icons.view_list_outlined), selectedIcon: Icon(Icons.view_list), label: '一覧'),
        ],
      ),
    );
  }
}

/// `meishi_backup_2026-10-25_1745.zip` -> `2026-10-25 17:45`; other names
/// are shown as they are.
String backupLabel(File zip) {
  final name = zip.uri.pathSegments.last;
  final m = RegExp(r'(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})\.zip$').firstMatch(name);
  return m == null ? name : '${m[1]} ${m[2]}:${m[3]}';
}
