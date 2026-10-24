import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_screen.dart';
import 'card_form.dart';
import 'history_screen.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart';
import 'ocr/history.dart';
import 'ocr/learned.dart';
import 'ocr/ocr_line.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/review_queue.dart';
import 'theme.dart';

// Thin UI over three parts: OcrPipeline (image -> lines, tilt correction),
// extractor (lines -> fields, with learned corrections), CardStore (golden
// JSON, Obsidian vault, images, vCard, logs). This file holds screen state
// and button handlers only. Look and copy follow DESIGN.md.
void main() => runApp(MaterialApp(
      title: '名刺スキャン',
      theme: appTheme(),
      darkTheme: appTheme(brightness: Brightness.dark),
      home: const ScanPage(),
    ));

/// One imported card waiting for review.
typedef QueuedCard = ({String stem, List<OcrLine> front, String imagePath});

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _picker = ImagePicker();
  final _ctl = {for (final k in CardFields.keys) k: TextEditingController()};
  final _queue = ReviewQueue<QueuedCard>();
  late final Future<(CardStore, OcrPipeline)> _ready = _init();

  List<OcrLine>? _front, _back;
  String? _frontPath, _backPath;
  Learned _learned = Learned();
  CardFields? _fields;
  String? _source;
  String? _progress; // non-null while OCR runs
  String? _error; // what happened + what to do

  /// Android: `/sdcard/Android/data/<pkg>/files` (reachable with plain adb pull
  /// and the Files app). Elsewhere: app documents.
  Future<(CardStore, OcrPipeline)> _init() async {
    final dir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
    final store = CardStore(dir);
    _learned = await store.loadLearned();
    return (store, OcrPipeline(store));
  }

  @override
  void dispose() {
    _ready.then((r) => r.$2.dispose());
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _refill() {
    _fields = _front == null
        ? null
        : extract(_front!, back: _back ?? const [], learned: _learned);
    final j = _fields?.toJson() ?? const {};
    for (final k in CardFields.keys) {
      _ctl[k]!.text = j[k] ?? '';
    }
  }

  Map<String, String?> _reviewed() => {
        for (final k in CardFields.keys)
          k: _ctl[k]!.text.trim().isEmpty ? null : _ctl[k]!.text.trim(),
      };

  Set<String> get _missing => _fields == null ? const {} : missingCore(_fields!).toSet();

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // ---- capture -------------------------------------------------------------

  /// Android: ML Kit document scanner (edge detection + perspective
  /// correction before capture, album import included). Elsewhere, or if
  /// the scanner fails: the in-app camera with the card guide.
  Future<String?> _capture(String label) async {
    if (Platform.isAndroid) {
      final scanner = DocumentScanner(
          options: DocumentScannerOptions(
              pageLimit: 1, mode: ScannerMode.base, isGalleryImport: true));
      try {
        final r = await scanner.scanDocument();
        final path = r.images?.firstOrNull;
        if (path != null) return path;
      } catch (e) {
        final (store, _) = await _ready;
        await store.appendError('document_scanner', e);
      } finally {
        scanner.close();
      }
    }
    if (!mounted) return null;
    return Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(label: label)));
  }

  Future<void> _shoot(bool front, ImageSource source) async {
    final (store, ocr) = await _ready;
    if (ocr.busy) return;
    final path = source == ImageSource.camera
        ? await _capture(front ? '表' : '裏')
        : (await _picker.pickImage(source: source))?.path;
    if (path == null) return;
    setState(() {
      _progress = '${front ? "表" : "裏"}を読み取り中…';
      _error = null;
    });
    final r = await ocr.recognize(path, front: front);
    setState(() {
      _progress = null;
      if (front) {
        _front = r.lines;
        _frontPath = path;
        _back = null;
        _backPath = null;
        _source = null; // a new card, not the queued one
        _queue.clear(); // leaving the batch; its label and auto-advance no longer apply
      } else {
        _back = r.lines;
        _backPath = path;
      }
      _refill();
      if (r.lines.isEmpty) {
        _error = '文字を読み取れませんでした。明るい場所で、名刺を枠に合わせて撮り直してください';
      }
    });
  }

  // ---- save / register -----------------------------------------------------

  /// Save the reviewed fields; whatever the user changed against the
  /// extractor's guess is learned for the next card and logged.
  Future<void> _saveReviewed({bool quiet = false}) async {
    final (store, _) = await _ready;
    final stem = _source?.replaceAll('.json', '') ??
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final guess = _fields?.toJson() ?? const <String, String?>{};
    final corrected = _reviewed();
    final f = await store.saveCard(
        stem: stem,
        front: _front!,
        back: _back ?? const [],
        expected: corrected,
        frontImage: _frontPath == null ? null : File(_frontPath!),
        backImage: _backPath == null ? null : File(_backPath!));
    _source = f.uri.pathSegments.last;
    final before = jsonEncode(_learned.toJson());
    _learned.learn(guess: guess, corrected: corrected, lines: [..._front!, ...?_back]);
    final learnedSomething = jsonEncode(_learned.toJson()) != before;
    if (learnedSomething) await store.saveLearned(_learned);
    await store.appendCorrection(stem, guess, corrected);
    if (!quiet && mounted) _toast('保存しました${learnedSomething ? "。修正を次回から反映します" : ""}');
  }

  /// Register the reviewed card in the device address book. Phone/email
  /// matches against existing contacts are shown first; no silent merge.
  Future<void> _registerContact() async {
    final fields = fieldsFromJson(_reviewed());
    if (fields.name == null) {
      setState(() => _error = '氏名が空です。読み取った文字をタップするか入力してください');
      return;
    }
    final perm = await FlutterContacts.permissions.request(PermissionType.readWrite);
    if (perm != PermissionStatus.granted) {
      setState(() => _error = '連絡先の権限がありません。端末の設定でこのアプリに連絡先を許可してください');
      return;
    }
    final existing = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email});
    final dup = findDuplicate(fields, existing);
    if (dup != null && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('同じ人がいるかもしれません'),
          content: Text('既存の連絡先「${dup.displayName ?? ''}」と電話番号またはメールが一致します。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('別人として登録')),
          ],
        ),
      );
      if (go != true) return;
    }
    await _saveReviewed(quiet: true);
    await FlutterContacts.create(toContact(fields, scannedAt: DateTime.now(), source: _source));
    if (!mounted) return;
    _toast('電話帳に登録しました');
    setState(() => _error = null);
    // Batch review: move on to the next card by itself.
    if (_queue.current != null && _queue.next()) setState(_showQueued);
  }

  // ---- batch ---------------------------------------------------------------

  /// Every image in inbox is OCR'd as a front side, saved with the
  /// extractor's guess, and queued on screen for review / registration.
  Future<void> _importInbox() async {
    final (store, ocr) = await _ready;
    if (ocr.busy) return;
    final files = await store.inboxImages();
    if (files.isEmpty) {
      _toast('取込フォルダに画像がありません（${(await store.inbox()).path}）');
      return;
    }
    _queue.clear();
    var levelled = 0;
    for (final (i, f) in files.indexed) {
      final stem = f.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), '');
      setState(() => _progress = '読み取り中 ${i + 1}/${files.length}: $stem');
      final r = await ocr.recognize(f.path, front: true);
      if (r.lines.isEmpty) continue;
      if (r.deskewedBy != null) levelled++;
      _front = r.lines;
      _back = null;
      _refill();
      await store.saveCard(
          stem: stem,
          front: r.lines,
          frontRaw: r.rawLines,
          back: const [],
          expected: _fields!.toJson(),
          frontImage: f);
      _queue.items.add((stem: stem, front: r.lines, imagePath: f.path));
    }
    _showQueued();
    setState(() => _progress = null);
    _toast('${_queue.items.length} 枚を取り込みました'
        '${levelled == 0 ? "" : "（$levelled 枚は傾きを補正）"}。1 枚ずつ確認して登録してください');
  }

  void _showQueued() {
    final c = _queue.current;
    if (c == null) return;
    _front = c.front;
    _frontPath = c.imagePath;
    _back = null;
    _backPath = null;
    _source = '${c.stem}.json';
    _error = null;
    _refill();
  }

  void _move(bool forward) {
    if (forward ? _queue.next() : _queue.prev()) setState(_showQueued);
  }

  Future<void> _exportVcard() async {
    final (store, _) = await _ready;
    final (file, n) = await store.exportVcard();
    _toast('$n 件を vCard に書き出しました（${file.path}）');
  }

  Future<void> _backup() async {
    final (store, _) = await _ready;
    final (file, n) = await store.backup();
    _toast('$n ファイルをバックアップしました（${file.path}）');
  }

  /// History: pick a saved card and bring it back into the review screen
  /// with its saved values (not a fresh extraction), images included.
  Future<void> _openHistory() async {
    final (store, _) = await _ready;
    final cards = cardSummaries(await store.notes());
    if (!mounted) return;
    final picked = await Navigator.push<CardSummary>(
        context, MaterialPageRoute(builder: (_) => HistoryScreen(cards: cards, vault: store.vaultDir)));
    if (picked == null) return;
    final card = await store.loadCard(picked.stem);
    if (card == null) {
      setState(() => _error = '「${picked.name}」の読み取りデータが見つかりません。ノートは残っています');
      return;
    }
    setState(() {
      _queue.clear();
      _front = card.front;
      _back = card.back.isEmpty ? null : card.back;
      _frontPath = card.frontImage?.path;
      _backPath = card.backImage?.path;
      _source = '${card.stem}.json';
      _error = null;
      _fields = fieldsFromJson(card.expected);
      for (final k in CardFields.keys) {
        _ctl[k]!.text = card.expected[k] ?? '';
      }
    });
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCard = _front != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('名刺スキャン'),
        actions: [
          IconButton(
            tooltip: '保存した名刺を探す',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'フォルダの画像をまとめて取り込む',
            icon: const Icon(Icons.folder_open),
            onPressed: _progress == null ? _importInbox : null,
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
      body: Column(
        children: [
          if (_progress != null)
            ListTile(
              leading: const SizedBox(
                  width: AppSize.iconSmall,
                  height: AppSize.iconSmall,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text(_progress!),
            ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              backgroundColor: scheme.errorContainer,
              contentTextStyle: TextStyle(color: scheme.onErrorContainer),
              actions: [
                TextButton(onPressed: () => setState(() => _error = null), child: const Text('閉じる')),
              ],
            ),
          if (!hasCard)
            Expanded(
              child: _EmptyState(
                onShoot: () => _shoot(true, ImageSource.camera),
                onAlbum: () => _shoot(true, ImageSource.gallery),
              ),
            )
          else ...[
            _CardHeader(
              frontPath: _frontPath,
              backPath: _backPath,
              // The file stem is a dev name (DESIGN.md §7): show position only.
              queueLabel: _queue.current == null ? null : '${_queue.label} 枚目を確認中',
              onPrev: () => _move(false),
              onNext: () => _move(true),
              onBackShoot: () => _shoot(false, ImageSource.camera),
              onBackAlbum: () => _shoot(false, ImageSource.gallery),
            ),
            Expanded(
              child: CardForm(
                key: ValueKey(_frontPath),
                controllers: _ctl,
                lines: [...?_front, ...?_back],
                missing: _missing,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: hasCard
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, AppSpace.unit, AppSpace.gutter, AppSpace.unit),
                child: Row(
                  children: [
                    IconButton.outlined(
                      tooltip: '次の名刺を撮影',
                      icon: const Icon(Icons.add_a_photo_outlined),
                      onPressed: () => _shoot(true, ImageSource.camera),
                    ),
                    const SizedBox(width: AppSpace.unit),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _progress == null ? _saveReviewed : null,
                        child: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.unit),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _progress == null ? _registerContact : null,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('電話帳に登録'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// First screen: nothing scanned yet.
class _EmptyState extends StatelessWidget {
  final VoidCallback onShoot, onAlbum;
  const _EmptyState({required this.onShoot, required this.onAlbum});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.gutter * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: AppSize.hero, color: scheme.primary, semanticLabel: '名刺'),
            const SizedBox(height: AppSpace.gutter),
            Text('名刺を撮影するか、アルバムから選んでください',
                style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.unit),
            Text('読み取った内容を確認してから電話帳に登録します。通信は使いません。',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.gutter * 2),
            FilledButton.icon(
              onPressed: onShoot,
              icon: const Icon(Icons.camera_alt),
              label: const Text('表を撮影'),
            ),
            const SizedBox(height: AppSpace.unit),
            OutlinedButton.icon(
              onPressed: onAlbum,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('アルバムから選ぶ'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card photos (the one memorable element, DESIGN.md §1) and batch nav.
class _CardHeader extends StatelessWidget {
  final String? frontPath, backPath, queueLabel;
  final VoidCallback onPrev, onNext, onBackShoot, onBackAlbum;
  const _CardHeader({
    required this.frontPath,
    required this.backPath,
    required this.queueLabel,
    required this.onPrev,
    required this.onNext,
    required this.onBackShoot,
    required this.onBackAlbum,
  });

  Widget _thumb(BuildContext context, String? path, String label) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Container(
        color: scheme.surfaceContainerHigh,
        height: AppSize.thumb,
        child: path != null && File(path).existsSync()
            ? Semantics(
                label: '$labelの写真',
                image: true,
                child: Image.file(File(path), fit: BoxFit.cover, width: double.infinity),
              )
            : Center(
                child: Text('$labelなし', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
      child: Column(
        children: [
          if (queueLabel != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(tooltip: '前の名刺', icon: const Icon(Icons.chevron_left), onPressed: onPrev),
                Flexible(child: Text(queueLabel!, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: '次の名刺', icon: const Icon(Icons.chevron_right), onPressed: onNext),
              ],
            ),
          Row(
            children: [
              Expanded(child: _thumb(context, frontPath, '表')),
              const SizedBox(width: AppSpace.unit),
              Expanded(
                child: backPath != null
                    ? _thumb(context, backPath, '裏')
                    // Wrap, not Row: at 2x text on a narrow phone the two
                    // controls do not fit side by side.
                    : Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onBackShoot,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('裏を撮影'),
                          ),
                          IconButton(
                            tooltip: '裏をアルバムから',
                            icon: const Icon(Icons.photo_library_outlined),
                            onPressed: onBackAlbum,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
