import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_contacts/flutter_contacts.dart';

import 'ocr/card_note.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart';
import 'ocr/ocr_line.dart';
import 'ocr/review_queue.dart';
import 'ocr/vault_index.dart';
import 'ocr/vcard_export.dart';

/// One imported card waiting for review.
typedef QueuedCard = ({String stem, List<OcrLine> front});

// ponytail: Phase 0 spike. One screen: shoot front/back (or batch-import
// images dropped into `<out>/inbox`), run on-device OCR, review fields by
// tapping OCR lines into them, dump raw lines + corrected fields to golden
// JSON. No contacts write.
void main() => runApp(const MaterialApp(home: SpikePage()));

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _picker = ImagePicker();
  final _jp = TextRecognizer(script: TextRecognitionScript.japanese);
  final _latin = TextRecognizer(script: TextRecognitionScript.latin);
  final _ctl = {for (final k in CardFields.keys) k: TextEditingController()};

  List<OcrLine>? _front, _back;
  CardFields? _fields;
  String _target = 'name';
  String _status = '表を撮影してください（長押しでギャラリー）';
  final _queue = ReviewQueue<QueuedCard>();
  // ML Kit must not be called concurrently (FastaLife's OcrService learned
  // this the hard way: native SIGSEGV), and two overlapping imports also
  // interleave their state. One job at a time.
  bool _busy = false;

  @override
  void dispose() {
    _jp.close();
    _latin.close();
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Android: `/sdcard/Android/data/<pkg>/files` (reachable with plain adb pull
  /// and the Files app). Elsewhere: app documents.
  Future<Directory> _outDir() async =>
      (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
      await getApplicationDocumentsDirectory();

  /// Runs ML Kit on one image. A failure (unreadable file, native error)
  /// returns an empty list and is appended to `<out>/log/errors.txt` so a
  /// batch of 30 does not die on card 7.
  Future<List<OcrLine>> _ocr(bool front, String path) async {
    try {
      final rec =
          await (front ? _jp : _latin).processImage(InputImage.fromFilePath(path));
      return [
        for (final b in rec.blocks)
          for (final l in b.lines)
            OcrLine(l.text,
                left: l.boundingBox.left,
                top: l.boundingBox.top,
                width: l.boundingBox.width,
                height: l.boundingBox.height),
      ];
    } catch (e) {
      final log = await File('${(await _outDir()).path}/log/errors.txt')
          .create(recursive: true);
      await log.writeAsString('${DateTime.now().toIso8601String()} $path: $e\n',
          mode: FileMode.append);
      setState(() => _status = 'OCR 失敗: ${path.split('/').last} ($e)');
      return const [];
    }
  }

  void _refill() {
    _fields = _front == null ? null : extract(_front!, _back ?? const []);
    final j = _fields?.toJson() ?? const {};
    for (final k in CardFields.keys) {
      _ctl[k]!.text = j[k] ?? '';
    }
  }

  String _warnings() {
    if (_front == null || _fields == null) return '';
    final w = <String>[
      if (isVertical(_front!)) '縦書き: OCR 精度低下、要手動確認',
      if (missingCore(_fields!).isNotEmpty) '未取得: ${missingCore(_fields!).join(', ')}',
    ];
    return w.join('　');
  }

  Future<void> _shoot(bool front, ImageSource source) async {
    if (_busy) return;
    final x = await _picker.pickImage(source: source);
    if (x == null) return;
    _busy = true;
    setState(() => _status = 'OCR中...');
    final lines = await _ocr(front, x.path);
    _busy = false;
    setState(() {
      if (front) {
        _front = lines;
      } else {
        _back = lines;
      }
      _refill();
      _status = '${front ? "表" : "裏"}: ${lines.length} 行認識';
    });
  }

  /// Writes the golden JSON (raw lines + fields) and the Obsidian note built
  /// from the same fields into `<out>/vault/`.
  Future<File> _save(Map<String, String?> expected, [String? stem]) async {
    final out = (await _outDir()).path;
    final dir = await Directory('$out/golden').create(recursive: true);
    stem ??= DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final vertical = isVertical(_front!);
    final file = File('${dir.path}/$stem.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert({
      'strict': false,
      'vertical': vertical,
      'front': _front!.map((l) => l.toJson()).toList(),
      'back': (_back ?? const []).map((l) => l.toJson()).toList(),
      'expected': expected,
    }));
    final fields = _toFields(expected);
    final now = DateTime.now();
    final vault = await Directory('$out/vault').create(recursive: true);
    await File('${vault.path}/${cardNoteFilename(fields, now)}').writeAsString(
        cardNoteMarkdown(fields, scannedAt: now, vertical: vertical, source: '$stem.json'));
    await _rebuildIndex(vault);
    return file;
  }

  /// `_名刺一覧.md`: table + 会社別/職種別/地域別, rebuilt from every note's frontmatter.
  Future<void> _rebuildIndex(Directory vault) async {
    final files = vault
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md') && !f.uri.pathSegments.last.startsWith('_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final notes = {
      for (final f in files)
        f.uri.pathSegments.last.replaceAll(RegExp(r'\.md$'), ''): await f.readAsString(),
    };
    await File('${vault.path}/_名刺一覧.md').writeAsString(buildIndex(notes));
  }

  CardFields _toFields(Map<String, String?> values) {
    final fields = CardFields();
    for (final k in CardFields.keys) {
      _setField(fields, k, values[k]);
    }
    return fields;
  }

  Map<String, String?> _reviewed() => {
        for (final k in CardFields.keys)
          k: _ctl[k]!.text.trim().isEmpty ? null : _ctl[k]!.text.trim(),
      };

  /// Register the reviewed card in the device address book. Phone/email
  /// matches against existing contacts are shown first; no silent merge.
  Future<void> _registerContact() async {
    final fields = _toFields(_reviewed());
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

  String? _source;

  static void _setField(CardFields f, String k, String? v) {
    switch (k) {
      case 'name': f.name = v;
      case 'nameKana': f.nameKana = v;
      case 'nameRoman': f.nameRoman = v;
      case 'company': f.company = v;
      case 'dept': f.dept = v;
      case 'title': f.title = v;
      case 'phone': f.phone = v;
      case 'mobile': f.mobile = v;
      case 'fax': f.fax = v;
      case 'email': f.email = v;
      case 'url': f.url = v;
      case 'postal': f.postal = v;
      case 'address': f.address = v;
    }
  }

  /// Save with the reviewed (hand-corrected) field values.
  Future<void> _saveReviewed() async {
    final f = await _save(_reviewed());
    _source = f.uri.pathSegments.last;
    setState(() => _status = '保存: ${f.path}');
  }

  /// Batch: every image in `<out>/inbox` is treated as a front side; the
  /// extractor's own guess is written as `expected` for later correction and
  /// the cards are queued on screen for review / registration one by one.
  Future<void> _importInbox() async {
    if (_busy) return;
    _busy = true;
    try {
      await _importInboxLocked();
    } finally {
      _busy = false;
    }
  }

  Future<void> _importInboxLocked() async {
    // The app must create inbox itself: a dir made by `adb shell mkdir` is not
    // readable by the app on Android 11+ (scoped storage ownership).
    final inbox =
        await Directory('${(await _outDir()).path}/inbox').create(recursive: true);
    final files = inbox
            .listSync()
            .whereType<File>()
            .where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false)
                .hasMatch(f.path))
            .toList();
    _queue.items.clear();
    for (final f in files) {
      setState(() => _status = 'OCR中: ${f.uri.pathSegments.last}');
      final stem = f.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), '');
      final lines = await _ocr(true, f.path);
      if (lines.isEmpty) continue;
      _front = lines;
      _back = null;
      _refill();
      await _save(_fields!.toJson(), stem);
      _queue.items.add((stem: stem, front: lines));
    }
    _showQueued();
    setState(() => _status = 'inbox: ${_queue.items.length}/${files.length} 件を取込。'
        '画面で確認して登録してください');
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

  /// `vault/_名刺.vcf`: every card note as vCard 3.0 for import elsewhere.
  Future<void> _exportVcard() async {
    final vault = await Directory('${(await _outDir()).path}/vault').create(recursive: true);
    final notes = {
      for (final f in vault.listSync().whereType<File>())
        if (f.path.endsWith('.md'))
          f.uri.pathSegments.last.replaceAll(RegExp(r'\.md$'), ''): await f.readAsString(),
    };
    final vcf = vcardOfNotes(notes);
    final out = File('${vault.path}/_名刺.vcf');
    await out.writeAsString(vcf);
    setState(() => _status = 'vCard: ${'BEGIN:VCARD'.allMatches(vcf).length} 件を ${out.path} に出力');
  }

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
