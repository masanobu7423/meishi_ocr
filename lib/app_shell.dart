import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'card_list.dart';
import 'home_screen.dart';
import 'main.dart';
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

  Future<List<CardSummary>> _load() async {
    final (store, _) = await _ready;
    final notes = await store.notes();
    _suggestions = suggestionsFrom(notes);
    _jobs = await store.loadJobs();
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
    if (!await shareFile(zip, mime: 'application/zip', subject: '名刺スキャンのバックアップ') && mounted) {
      _toast('共有できませんでした');
    }
  }

  /// Selected on the home / search / list screens: confirm once, delete
  /// each (JSON, note, photos), leave the address book alone.
  Future<void> _deleteCards(List<CardSummary> cards) async {
    if (cards.isEmpty) return;
    final label = cards.length == 1 ? '「${cards.single.name}」' : '${cards.length} 件';
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$labelを削除しますか？'),
        content: const Text('保存した読み取り結果と写真を削除します。電話帳に登録した連絡先は残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除する')),
        ],
      ),
    );
    if (go != true) return;
    final (store, _) = await _ready;
    var n = 0;
    for (final c in cards) {
      if (await store.deleteCard(c.stem)) n++;
    }
    _scanKey.currentState?.forget(cards.map((c) => c.stem).toSet());
    _reload();
    if (mounted) _toast('$n 件を削除しました');
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
    final (store, _) = await _ready;
    final settings = await store.loadSettings();
    await store.saveSettings({...settings, 'accountKey': accountKey(picked)});
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
    if (zips.isEmpty) {
      _toast('バックアップがありません。メニューで作るか、zip を ${store.root.path}/backup に置いてください');
      return;
    }
    final picked = await showDialog<File>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('バックアップから復元'),
        children: [
          for (final z in zips)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(backupLabel(z)),
              onTap: () => Navigator.pop(c, z),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('復元しますか？'),
        content: Text('${backupLabel(picked)} のバックアップの名刺を取り込みます。'
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
      result = await store.restore(picked);
    } catch (e) {
      await store.appendError('restore ${picked.path}', e);
      if (mounted) _toast('復元できませんでした。zip が壊れているか、バックアップの形式ではありません');
      return;
    }
    _reload();
    if (!mounted) return;
    final (written, failed) = result;
    _toast(failed == 0
        ? '$written ファイルを復元しました'
        : '$written ファイルを復元、$failed ファイルは書き込めませんでした（log/errors.txt に記録）');
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
            onSelected: (v) => switch (v) {
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
              _ => _backup(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('登録先のアカウント')),
              PopupMenuItem(value: 'sync', child: Text('未登録の名刺を電話帳に登録')),
              PopupMenuItem(value: 'import_contacts', child: Text('電話帳から取り込む')),
              PopupMenuItem(value: 'jobs', child: Text('職種の一覧を編集')),
              PopupMenuItem(value: 'share_vcard', child: Text('全件を vCard で共有')),
              PopupMenuItem(value: 'vcard', child: Text('全件を vCard に書き出す')),
              PopupMenuItem(value: 'share_csv', child: Text('全件を CSV で共有（Excel 用）')),
              PopupMenuItem(value: 'share_ics', child: Text('連絡予定をカレンダーに書き出す（ics）')),
              PopupMenuItem(value: 'share_backup', child: Text('バックアップを共有')),
              PopupMenuItem(value: 'backup', child: Text('バックアップを作る')),
              PopupMenuItem(value: 'restore', child: Text('バックアップから復元')),
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
                  cards: cards, vault: store.vaultDir, onTap: _open, onDelete: _deleteCards, onShare: _shareCards),
              ListScreen(
                cards: cards,
                vault: store.vaultDir,
                onTap: _open,
                onDelete: _deleteCards,
                onShare: _shareCards,
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
