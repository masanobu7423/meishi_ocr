import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'card_list.dart';
import 'home_screen.dart';
import 'main.dart';
import 'ocr/card_store.dart';
import 'ocr/history.dart';
import 'ocr/ocr_pipeline.dart';

/// Android: `/sdcard/Android/data/<pkg>/files` (reachable with plain adb pull
/// and the Files app). Elsewhere: app documents.
Future<(CardStore, OcrPipeline)> initStore() async {
  final dir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
      await getApplicationDocumentsDirectory();
  final store = CardStore(dir);
  return (store, OcrPipeline(store));
}

/// Four tabs: ホーム / スキャン / 検索 / 一覧. Home, search and list read the
/// vault; scan writes it and tells the shell to refresh.
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
            onSelected: (v) => v == 'vcard' ? _exportVcard() : _backup(),
            itemBuilder: (_) => const [
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
              ScanPage(key: _scanKey, ready: _ready, onSaved: _reload),
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
