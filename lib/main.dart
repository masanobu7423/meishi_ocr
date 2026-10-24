import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'ocr/card_note.dart';
import 'ocr/extractor.dart';
import 'ocr/ocr_line.dart';

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

  Future<List<OcrLine>> _ocr(bool front, String path) async {
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
    final x = await _picker.pickImage(source: source);
    if (x == null) return;
    setState(() => _status = 'OCR中...');
    final lines = await _ocr(front, x.path);
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
    final fields = CardFields();
    final j = fields.toJson(); // key order
    for (final k in j.keys) {
      _setField(fields, k, expected[k]);
    }
    final now = DateTime.now();
    final vault = await Directory('$out/vault').create(recursive: true);
    await File('${vault.path}/${cardNoteFilename(fields, now)}').writeAsString(
        cardNoteMarkdown(fields, scannedAt: now, vertical: vertical, source: '$stem.json'));
    return file;
  }

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
    final expected = {
      for (final k in CardFields.keys)
        k: _ctl[k]!.text.trim().isEmpty ? null : _ctl[k]!.text.trim(),
    };
    final f = await _save(expected);
    setState(() => _status = '保存: ${f.path}');
  }

  /// Batch: every image in `<out>/inbox` is treated as a front side; the
  /// extractor's own guess is written as `expected` for later correction.
  Future<void> _importInbox() async {
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
    for (final f in files) {
      setState(() => _status = 'OCR中: ${f.uri.pathSegments.last}');
      _front = await _ocr(true, f.path);
      _back = null;
      _refill();
      await _save(_fields!.toJson(),
          f.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), ''));
    }
    setState(() => _status = 'inbox: ${files.length} 件を golden/ に保存');
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
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SelectableText(_status)),
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
