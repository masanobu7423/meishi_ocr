import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_screen.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart';
import 'ocr/ocr_line.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/review_queue.dart';

// ponytail: Phase 0 spike grown into a thin UI over three pure-ish parts:
// OcrPipeline (image -> lines, tilt correction), extractor (lines -> fields),
// CardStore (golden JSON, Obsidian vault, vCard, logs). This file only holds
// screen state and button handlers.
void main() => runApp(const MaterialApp(home: SpikePage()));

/// One imported card waiting for review.
typedef QueuedCard = ({String stem, List<OcrLine> front});

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _picker = ImagePicker();
  final _ctl = {for (final k in CardFields.keys) k: TextEditingController()};
  final _queue = ReviewQueue<QueuedCard>();
  late final Future<(CardStore, OcrPipeline)> _ready = _init();

  List<OcrLine>? _front, _back;
  CardFields? _fields;
  String _target = 'name';
  String _status = '表を撮影してください（長押しでギャラリー）';
  String? _source;

  /// Android: `/sdcard/Android/data/<pkg>/files` (reachable with plain adb pull
  /// and the Files app). Elsewhere: app documents.
  Future<(CardStore, OcrPipeline)> _init() async {
    final dir = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
        await getApplicationDocumentsDirectory();
    final store = CardStore(dir);
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
    _fields = _front == null ? null : extract(_front!, _back ?? const []);
    final j = _fields?.toJson() ?? const {};
    for (final k in CardFields.keys) {
      _ctl[k]!.text = j[k] ?? '';
    }
  }

  Map<String, String?> _reviewed() => {
        for (final k in CardFields.keys)
          k: _ctl[k]!.text.trim().isEmpty ? null : _ctl[k]!.text.trim(),
      };

  String _warnings() {
    if (_front == null || _fields == null) return '';
    return [
      if (isVertical(_front!)) '縦書き: OCR 精度低下、要手動確認',
      if (missingCore(_fields!).isNotEmpty) '未取得: ${missingCore(_fields!).join(', ')}',
    ].join('　');
  }

  // ---- capture -------------------------------------------------------------

  /// Android: ML Kit document scanner (edge detection + perspective
  /// correction before capture). Elsewhere, or if the scanner fails: the
  /// in-app camera with the card guide.
  Future<String?> _capture(String label) async {
    if (Platform.isAndroid) {
      final scanner = DocumentScanner(
          options: DocumentScannerOptions(pageLimit: 1, mode: ScannerMode.base));
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
    setState(() => _status = 'OCR中...');
    final r = await ocr.recognize(path, front: front);
    setState(() {
      if (front) {
        _front = r.lines;
      } else {
        _back = r.lines;
      }
      _refill();
      _status = '${front ? "表" : "裏"}: ${r.lines.length} 行認識'
          '${r.deskewedBy == null ? "" : "（傾き ${r.deskewedBy!.toStringAsFixed(1)}° を補正）"}';
    });
  }

  // ---- save / register -----------------------------------------------------

  Future<void> _saveReviewed() async {
    final (store, _) = await _ready;
    final f = await store.saveCard(
        stem: _source?.replaceAll('.json', '') ??
            DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-'),
        front: _front!,
        back: _back ?? const [],
        expected: _reviewed());
    _source = f.uri.pathSegments.last;
    setState(() => _status = '保存: ${f.path}');
  }

  /// Register the reviewed card in the device address book. Phone/email
  /// matches against existing contacts are shown first; no silent merge.
  Future<void> _registerContact() async {
    final fields = fieldsFromJson(_reviewed());
    if (fields.name == null) {
      setState(() => _status = '氏名が空です');
      return;
    }
    final perm = await FlutterContacts.permissions.request(PermissionType.readWrite);
    if (perm != PermissionStatus.granted) {
      setState(() => _status = '連絡先の権限がありません');
      return;
    }
    final existing = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email});
    final dup = findDuplicate(fields, existing);
    if (dup != null && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('重複の可能性'),
          content: Text('既存の連絡先「${dup.displayName ?? ''}」と電話番号またはメールが一致します。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('別人として追加')),
          ],
        ),
      );
      if (go != true) return;
    }
    final id = await FlutterContacts.create(
        toContact(fields, scannedAt: DateTime.now(), source: _source));
    setState(() => _status = '電話帳に登録しました (id $id)');
  }

  // ---- batch ---------------------------------------------------------------

  /// Every image in inbox is OCR'd as a front side, saved with the
  /// extractor's guess, and queued on screen for review / registration.
  Future<void> _importInbox() async {
    final (store, ocr) = await _ready;
    if (ocr.busy) return;
    final files = await store.inboxImages();
    _queue.items.clear();
    var levelled = 0;
    for (final f in files) {
      final stem = f.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), '');
      setState(() => _status = 'OCR中: $stem');
      final r = await ocr.recognize(f.path, front: true);
      if (r.lines.isEmpty) continue;
      if (r.deskewedBy != null) levelled++;
      _front = r.lines;
      _back = null;
      _refill();
      await store.saveCard(
          stem: stem, front: r.lines, frontRaw: r.rawLines, back: const [], expected: _fields!.toJson());
      _queue.items.add((stem: stem, front: r.lines));
    }
    _showQueued();
    setState(() => _status = 'inbox: ${_queue.items.length}/${files.length} 件を取込'
        '${levelled == 0 ? "" : "（$levelled 件は傾き補正）"}。画面で確認して登録してください');
  }

  void _showQueued() {
    final c = _queue.current;
    if (c == null) return;
    _front = c.front;
    _back = null;
    _source = '${c.stem}.json';
    _refill();
  }

  void _move(bool forward) {
    if (forward ? _queue.next() : _queue.prev()) setState(_showQueued);
  }

  Future<void> _exportVcard() async {
    final (store, _) = await _ready;
    final (file, n) = await store.exportVcard();
    setState(() => _status = 'vCard: $n 件を ${file.path} に出力');
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final warn = _warnings();
    final lines = [...?_front, ...?_back];
    return Scaffold(
      appBar: AppBar(
        title: const Text('名刺OCR スパイク'),
        actions: [
          IconButton(
            tooltip: 'inbox を一括取込',
            icon: const Icon(Icons.folder_open),
            onPressed: _importInbox,
          ),
          IconButton(
            tooltip: 'vault を vCard に出力',
            icon: const Icon(Icons.contact_page_outlined),
            onPressed: _exportVcard,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShootButton('表', (s) => _shoot(true, s)),
                _ShootButton('裏', (s) => _shoot(false, s)),
                FilledButton(
                  onPressed: _front == null ? null : _saveReviewed,
                  child: const Text('JSON保存'),
                ),
                FilledButton.tonal(
                  onPressed: _front == null ? null : _registerContact,
                  child: const Text('電話帳に登録'),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SelectableText(_status)),
          if (_queue.current != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '前の名刺',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _move(false),
                ),
                Text('レビュー ${_queue.label}: ${_queue.current!.stem}'),
                IconButton(
                  tooltip: '次の名刺',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _move(true),
                ),
              ],
            ),
          if (warn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(warn, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                // Field rows: pick the target with the chip, type or tap an OCR line below.
                for (final k in CardFields.keys)
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: ChoiceChip(
                          label: Text(k, style: const TextStyle(fontSize: 12)),
                          selected: _target == k,
                          onSelected: (_) => setState(() => _target = k),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctl[k],
                          decoration: const InputDecoration(isDense: true),
                          onTap: () => setState(() => _target = k),
                        ),
                      ),
                    ],
                  ),
                if (lines.isNotEmpty) ...[
                  const Divider(),
                  Text('OCR 行をタップ → 「$_target」に入れる',
                      style: Theme.of(context).textTheme.labelMedium),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final l in lines)
                        ActionChip(
                          label: Text('[${l.height.round()}] ${l.text}',
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => _ctl[_target]!.text = normalize(l.text)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShootButton extends StatelessWidget {
  final String label;
  final void Function(ImageSource) onPick;
  const _ShootButton(this.label, this.onPick);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onLongPress: () => onPick(ImageSource.gallery),
        child: OutlinedButton(
          onPressed: () => onPick(ImageSource.camera),
          child: Text('$labelを撮影'),
        ),
      );
}
