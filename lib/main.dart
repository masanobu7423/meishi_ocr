import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_shell.dart';
import 'capture_screen.dart';
import 'card_form.dart';
import 'duplicate_screen.dart';
import 'ocr/actions.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart';
import 'ocr/history.dart';
import 'ocr/learned.dart';
import 'ocr/merge.dart';
import 'ocr/ocr_line.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/review_queue.dart';
import 'theme.dart';

// Thin UI over three parts: OcrPipeline (image -> lines, tilt correction),
// extractor (lines -> fields, with learned corrections), CardStore (golden
// JSON, Obsidian vault, images, vCard, logs). HomeShell owns the tabs; this
// file is the スキャン tab: screen state and button handlers only. Look and
// copy follow DESIGN.md.
void main() => runApp(MaterialApp(
      title: '名刺スキャン',
      theme: appTheme(),
      darkTheme: appTheme(brightness: Brightness.dark),
      home: const HomeShell(),
    ));

/// One imported card waiting for review.
typedef QueuedCard = ({String stem, List<OcrLine> front, String imagePath});

class ScanPage extends StatefulWidget {
  final Future<(CardStore, OcrPipeline)> ready;

  /// Called after anything was written to the store, so lists can refresh.
  final VoidCallback onSaved;

  /// The account new contacts go into (null = device default).
  final Future<Account?> Function() account;
  const ScanPage({super.key, required this.ready, required this.onSaved, required this.account});

  @override
  State<ScanPage> createState() => ScanPageState();
}

class ScanPageState extends State<ScanPage> {
  final _picker = ImagePicker();
  final _ctl = {for (final k in CardFields.keys) k: TextEditingController()};
  final _queue = ReviewQueue<QueuedCard>();

  List<OcrLine>? _front, _back;
  String? _frontPath, _backPath;
  Learned? _learned;
  CardFields? _fields;
  String? _source;
  String? _progress; // non-null while OCR runs
  String? _error; // what happened + what to do

  Future<(CardStore, OcrPipeline, Learned)> get _ready async {
    final (store, ocr) = await widget.ready;
    _learned ??= await store.loadLearned();
    return (store, ocr, _learned!);
  }

  @override
  void dispose() {
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
        final (store, _, _) = await _ready;
        await store.appendError('document_scanner', e);
      } finally {
        scanner.close();
      }
    }
    if (!mounted) return null;
    return Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(label: label)));
  }

  /// Camera or album for the front (true) or back side.
  Future<void> shoot(bool front, ImageSource source) async {
    final (_, ocr, _) = await _ready;
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

  /// A saved card chosen on the home / search / list tab: show it with its
  /// saved values (not a fresh extraction) and images.
  Future<void> loadStoredCard(CardSummary picked) async {
    final (store, _, _) = await _ready;
    final card = await store.loadCard(picked.stem);
    if (!mounted) return;
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

  // ---- save / register -----------------------------------------------------

  /// Save the reviewed fields; whatever the user changed against the
  /// extractor's guess is learned for the next card and logged.
  Future<void> _saveReviewed({bool quiet = false}) async {
    final (store, _, learned) = await _ready;
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
    final before = jsonEncode(learned.toJson());
    learned.learn(guess: guess, corrected: corrected, lines: [..._front!, ...?_back]);
    final learnedSomething = jsonEncode(learned.toJson()) != before;
    if (learnedSomething) await store.saveLearned(learned);
    await store.appendCorrection(stem, guess, corrected);
    widget.onSaved();
    if (!quiet && mounted) _toast('保存しました${learnedSomething ? "。修正を次回から反映します" : ""}');
  }

  /// Delete the stored card (JSON, note, photos) after confirmation. The
  /// address book is not touched.
  Future<void> _deleteCard() async {
    final stem = _source?.replaceAll('.json', '');
    if (stem == null) return;
    final name = _ctl['name']!.text.trim();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('「${name.isEmpty ? "この名刺" : name}」を削除しますか？'),
        content: const Text('保存した読み取り結果と写真を削除します。電話帳に登録した連絡先は残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除する')),
        ],
      ),
    );
    if (go != true) return;
    final (store, _, _) = await _ready;
    final removed = await store.deleteCard(stem);
    if (!mounted) return;
    setState(() {
      _queue.clear();
      _front = _back = null;
      _frontPath = _backPath = null;
      _source = null;
      _fields = null;
      _error = null;
      for (final c in _ctl.values) {
        c.clear();
      }
    });
    widget.onSaved();
    _toast(removed ? '削除しました' : 'この名刺はすでに削除されています');
  }

  /// Register the reviewed card in the device address book. A phone/email
  /// match against an existing contact opens the side-by-side screen.
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
    if (dup != null) {
      final done = await _resolveDuplicate(dup.id!, fields);
      if (!done) return;
    } else {
      await _saveReviewed(quiet: true);
      await FlutterContacts.create(toContact(fields, scannedAt: DateTime.now(), source: _source),
          account: await widget.account());
      if (!mounted) return;
      _toast('電話帳に登録しました');
    }
    if (!mounted) return;
    setState(() => _error = null);
    // Batch review: move on to the next card by itself.
    if (_queue.current != null && _queue.next()) setState(_showQueued);
  }

  /// Returns true when something was written (merge / separate / replace).
  Future<bool> _resolveDuplicate(String id, CardFields fields) async {
    final full = await FlutterContacts.get(id, properties: ContactProperties.all);
    if (full == null) return false;
    if (!mounted) return false;
    final decision = await Navigator.push<DuplicateDecision>(
      context,
      MaterialPageRoute(
          builder: (_) => DuplicateScreen(existing: full, card: fields, rows: contactDiff(full, fields))),
    );
    if (decision == null) return false;
    final now = DateTime.now();
    switch (decision.action) {
      case DuplicateAction.merge:
        await _saveReviewed(quiet: true);
        final merged = mergeContact(full, fields,
            useCard: decision.useCard, keepExisting: decision.keepExisting, scannedAt: now);
        await FlutterContacts.update(merged);
        if (!mounted) return true;
        final changed = decision.useCard.length;
        // Undo = write the pre-merge snapshot back; it is still in memory.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('「${full.displayName ?? ''}」を更新しました（$changed 項目を名刺の値に）'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () async {
              await FlutterContacts.update(full);
              if (mounted) _toast('統合前の内容に戻しました');
            },
          ),
        ));
        return true;
      case DuplicateAction.separate:
        await _saveReviewed(quiet: true);
        await FlutterContacts.create(toContact(fields, scannedAt: now, source: _source),
            account: await widget.account());
        if (mounted) _toast('別の連絡先として登録しました');
        return true;
      case DuplicateAction.replace:
        await _saveReviewed(quiet: true);
        await FlutterContacts.delete(id);
        await FlutterContacts.create(toContact(fields, scannedAt: now, source: _source),
            account: await widget.account());
        if (mounted) _toast('既存の連絡先を削除し、名刺の内容で登録しました');
        return true;
      case DuplicateAction.editExisting:
        await FlutterContacts.native.showEditor(id);
        if (mounted) _toast('電話帳アプリでの編集を終えたら、もう一度「電話帳に登録」を押してください');
        return false;
    }
  }

  // ---- batch ---------------------------------------------------------------

  /// Every image in inbox is OCR'd as a front side, saved with the
  /// extractor's guess, and queued on screen for review / registration.
  Future<void> importInbox() async {
    final (store, ocr, _) = await _ready;
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
    widget.onSaved();
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

  /// Phone / mail / web / map: hand the URI to the matching app.
  Future<void> _launch(ContactAction a) async {
    final ok = await launchUrl(a.uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _error = '${a.label}を開けるアプリが見つかりません');
    }
  }

  void _viewPhoto(String path, String label) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => _PhotoViewer(path: path, label: label)));

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCard = _front != null;
    return Scaffold(
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
                onShoot: () => shoot(true, ImageSource.camera),
                onAlbum: () => shoot(true, ImageSource.gallery),
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
              onBackShoot: () => shoot(false, ImageSource.camera),
              onBackAlbum: () => shoot(false, ImageSource.gallery),
              onViewPhoto: _viewPhoto,
            ),
            _ActionRow(actions: contactActions(_reviewed()), onTap: _launch),
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
                      onPressed: () => shoot(true, ImageSource.camera),
                    ),
                    if (_source != null)
                      IconButton(
                        tooltip: 'この名刺を削除',
                        icon: const Icon(Icons.delete_outline),
                        color: scheme.error,
                        onPressed: _progress == null ? _deleteCard : null,
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

/// Scan tab with nothing scanned yet.
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

/// Phone / mobile / mail / web / map chips for the card on screen.
class _ActionRow extends StatelessWidget {
  final List<ContactAction> actions;
  final ValueChanged<ContactAction> onTap;
  const _ActionRow({required this.actions, required this.onTap});

  static const _icons = {
    'phone': Icons.call,
    'mobile': Icons.smartphone,
    'email': Icons.mail_outline,
    'url': Icons.language,
    'address': Icons.map_outlined,
  };

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
      child: Wrap(
        spacing: AppSpace.unit,
        runSpacing: AppSpace.unit / 2,
        children: [
          for (final a in actions)
            ActionChip(
              avatar: Icon(_icons[a.key], size: AppSize.iconSmall),
              label: Text(a.label),
              tooltip: '${a.label}を開く',
              onPressed: () => onTap(a),
            ),
        ],
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom view of one card photo.
class _PhotoViewer extends StatelessWidget {
  final String path, label;
  const _PhotoViewer({required this.path, required this.label});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.scrim,
        appBar: AppBar(
          title: Text('$labelの写真'),
          backgroundColor: Theme.of(context).colorScheme.scrim,
          foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Image.file(File(path), fit: BoxFit.contain, semanticLabel: '$labelの写真'),
          ),
        ),
      );
}

/// The card photos (the one memorable element, DESIGN.md §1) and batch nav.
class _CardHeader extends StatelessWidget {
  final String? frontPath, backPath, queueLabel;
  final VoidCallback onPrev, onNext, onBackShoot, onBackAlbum;
  final void Function(String path, String label) onViewPhoto;
  const _CardHeader({
    required this.frontPath,
    required this.backPath,
    required this.queueLabel,
    required this.onPrev,
    required this.onNext,
    required this.onBackShoot,
    required this.onBackAlbum,
    required this.onViewPhoto,
  });

  Widget _thumb(BuildContext context, String? path, String label) {
    final scheme = Theme.of(context).colorScheme;
    final exists = path != null && File(path).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Material(
        color: scheme.surfaceContainerHigh,
        child: InkWell(
          onTap: exists ? () => onViewPhoto(path, label) : null,
          child: SizedBox(
            height: AppSize.thumb,
            child: exists
                ? Semantics(
                    label: '$labelの写真（タップで拡大）',
                    image: true,
                    button: true,
                    child: Image.file(File(path), fit: BoxFit.cover, width: double.infinity),
                  )
                : Center(
                    child: Text('$labelなし', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
          ),
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
