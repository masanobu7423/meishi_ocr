import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'card_list.dart';
import 'home_screen.dart';
import 'main.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/history.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/sync.dart';
import 'ocr/vault_index.dart';
import 'ocr/vcard_export.dart';

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

  Future<List<CardSummary>> _load() async {
    final (store, _) = await _ready;
    return cardSummaries(await store.notes());
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
    final perm = await FlutterContacts.permissions.request(PermissionType.readWrite);
    if (perm != PermissionStatus.granted) {
      _toast('連絡先の権限がありません。端末の設定でこのアプリに連絡先を許可してください');
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
    final perm = await FlutterContacts.permissions.request(PermissionType.readWrite);
    if (perm != PermissionStatus.granted) {
      _toast('連絡先の権限がありません。端末の設定でこのアプリに連絡先を許可してください');
      return;
    }
    final account = await _resolveAccount();
    final (store, _) = await _ready;
    final cards = [
      for (final md in (await store.notes()).values)
        if (parseFrontmatter(md)['type'] == 'meishi') fieldsFromFrontmatter(parseFrontmatter(md)),
    ];
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
      await FlutterContacts.create(toContact(p.card, scannedAt: DateTime.now()), account: account);
      done++;
    }
    if (mounted) _toast('$done 件を電話帳に登録しました');
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

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    _resolveAccount();
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
              'vcard' => _exportVcard(),
              _ => _backup(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('登録先のアカウント')),
              PopupMenuItem(value: 'sync', child: Text('未登録の名刺を電話帳に登録')),
              PopupMenuItem(value: 'vcard', child: Text('全件を vCard に書き出す')),
              PopupMenuItem(value: 'backup', child: Text('バックアップを作る')),
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
                onSeeAll: () => _go(3),
              ),
              ScanPage(key: _scanKey, ready: _ready, onSaved: _reload, account: _resolveAccount),
              SearchScreen(cards: cards, vault: store.vaultDir, onTap: _open),
              ListScreen(cards: cards, vault: store.vaultDir, onTap: _open),
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
