import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_shell.dart';
import 'capture_screen.dart';
import 'card_form.dart';
import 'duplicate_screen.dart';
import 'ocr/actions.dart';
import 'ocr/burst.dart';
import 'ocr/card_status.dart';
import 'ocr/card_store.dart';
import 'ocr/contact_mapper.dart';
import 'ocr/extractor.dart';
import 'ocr/history.dart';
import 'ocr/learned.dart';
import 'ocr/merge.dart';
import 'ocr/ocr_line.dart';
import 'ocr/ocr_pipeline.dart';
import 'ocr/card_note.dart' show defaultJob;
import 'ocr/jobs.dart';
import 'ocr/review_queue.dart';
import 'ocr/vcard_export.dart' show vcardOfFields;
import 'share.dart';
import 'theme.dart';

// Thin UI over three parts: OcrPipeline (image -> lines, tilt correction),
// extractor (lines -> fields, with learned corrections), CardStore (golden
// JSON, Obsidian vault, images, vCard, logs). HomeShell owns the tabs; this
// file is the スキャン tab: screen state and button handlers only. Look and
// copy follow DESIGN.md.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge on every Android version (15+ does it by itself); the Play
  // Console flags apps that leave it to the OS default on older releases.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(MaterialApp(
    title: '名刺スキャン',
    theme: appTheme(),
    darkTheme: appTheme(brightness: Brightness.dark),
    home: const HomeShell(),
  ));
}

/// One imported card waiting for review.

enum _BurstChoice { shoot, blank, end }

class ScanPage extends StatefulWidget {
  final Future<(CardStore, OcrPipeline)> ready;

  /// Called after anything was written to the store, so lists can refresh.
  final VoidCallback onSaved;

  /// The account new contacts go into (null = device default).
  final Future<Account?> Function() account;
  /// Previously used 区分 / 部門 / 関係者 / 資格 values for the form's chips.
  final Map<String, List<String>> suggestions;
  /// The user's 職種 list for the form's dropdown.
  final List<String> jobs;
  const ScanPage({
    super.key,
    required this.ready,
    required this.onSaved,
    required this.account,
    this.suggestions = const {},
    this.jobs = defaultJobs,
  });

  @override
  State<ScanPage> createState() => ScanPageState();
}

class ScanPageState extends State<ScanPage> {
  final _picker = ImagePicker();
  final _ctl = {for (final k in CardFields.keys) k: TextEditingController()};
  /// Stems of the batch being reviewed; each card is read back from the
  /// store when shown, so edits saved earlier are never lost.
  final _queue = ReviewQueue<String>();

  List<OcrLine>? _front, _back;
  String? _frontPath, _backPath;
  Learned? _learned;
  CardFields? _fields;
  String? _source;
  CardStatus? _status; // of the stored card on screen; null = not saved yet
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
    _fields?.job = defaultJob(_fields!); // 職種 guessed from dept/title; the form can change it
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

  /// Burst mode (Android only): the document scanner keeps taking pages
  /// until the user taps done (up to [_burstLimit]); every page is a front
  /// side, OCR'd, saved with the extractor's guess and queued for review,
  /// exactly like the folder import.
  /// 続けて撮影: the in-app camera stays open (ML Kit's scanner cannot show
  /// which side is next, and on the Galaxy S25 its second page went black).
  /// Every capture is copied into the inbox; 「まとめて取込」 reads it later.
  Future<void> shootMany() async {
    final (store, ocr, _) = await _ready;
    if (ocr.busy) return;
    final paired = await showDialog<bool>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('続けて撮影'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, false),
            child: const ListTile(
              leading: Icon(Icons.crop_portrait),
              title: Text('表だけ'),
              subtitle: Text('1 枚ごとに表面を撮ります'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, true),
            child: const ListTile(
              leading: Icon(Icons.flip),
              title: Text('表と裏を交互に'),
              subtitle: Text('表、裏、表、裏…の順に撮ります。裏がない名刺は「白地で保管」'),
            ),
          ),
        ],
      ),
    );
    if (paired == null || !mounted) return;
    final session = BurstSession(paired: paired);
    // Same scanner as 「表を撮影」 (card-sized tracking, perspective fix,
    // auto-capture), one page per session. Google's screen takes no buttons,
    // so the side, 白地で保管 and 撮影を終了 live in a prompt between pages.
    var sessions = 0;
    while (mounted) {
      final choice = await _burstPrompt(session);
      if (choice == null || choice == _BurstChoice.end) break;
      if (choice == _BurstChoice.blank) {
        final stem = session.blankStem();
        if (stem != null) await store.stashBlankBack(stem);
        continue;
      }
      if (sessions++ > 0) await _waitForScannerToClose();
      final paths = await _captureOnePage();
      if (paths == null) {
        // The scanner is unavailable on this device: the in-app camera takes over.
        if (!mounted) return;
        await Navigator.push<BurstSession>(
          context,
          MaterialPageRoute(
            builder: (_) => CaptureScreen(
              label: '',
              burst: session,
              onPage: (path, name) => store.stashCapture(File(path), name),
              onBlank: store.stashBlankBack,
              statsLog: File('${store.root.path}/log/shutter.txt'),
            ),
          ),
        );
        break;
      }
      if (paths.isEmpty) continue; // closed the scanner: back to the prompt
      await store.stashCapture(File(paths.first), session.nextName(DateTime.now()));
    }
    final summary = session.summary;
    if (!mounted || summary == null) return;
    _toast(summary);
    // 自動取り込み: read the folder now that shooting is over (never mid-burst).
    await importInbox();
  }

  /// Between pages: which side is next, with the actions Google's scanner
  /// cannot show. Null = dismissed (treated as end).
  Future<_BurstChoice?> _burstPrompt(BurstSession s) => showDialog<_BurstChoice>(
        context: context,
        barrierDismissible: false,
        builder: (c) {
          final back = s.side == CardSide.back;
          return AlertDialog(
            title: Text(s.title),
            content: Text(back
                ? '裏面をスキャナーで撮ります。印字がなければ「白地で保管」。'
                : s.cards == 0
                    ? 'スキャナーが開きます。名刺を枠に入れると自動で撮れます。'
                    : '${s.cards} 枚保存済み。次の名刺の表面を撮るか、ここで終了できます。'),
            actions: [
              if (back)
                TextButton(
                  onPressed: () => Navigator.pop(c, _BurstChoice.blank),
                  child: const Text('白地で保管'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(c, _BurstChoice.end),
                  child: const Text('撮影を終了'),
                ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, _BurstChoice.shoot),
                icon: const Icon(Icons.camera_alt),
                label: Text(back ? '裏面を撮影' : '表面を撮影'),
              ),
            ],
          );
        },
      );

  /// One page with the ML Kit scanner. Empty list = the user closed it;
  /// null = the scanner could not start (fall back to the in-app camera).
  Future<List<String>?> _captureOnePage() async {
    final scanner = DocumentScanner(
        options: DocumentScannerOptions(
            pageLimit: 1, mode: ScannerMode.base, isGalleryImport: true));
    try {
      return (await scanner.scanDocument()).images ?? const [];
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) return const [];
      final (store, _, _) = await _ready;
      await store.appendError('document_scanner burst', e);
      return null;
    } finally {
      await scanner.close();
    }
  }

  /// The scanner's result arrives before its delegate activity has finished;
  /// launching the next session right away fails inside Google's delegate
  /// ("Failed to handle result") and leaves a black screen. Wait until our
  /// activity is back in front, then a little longer for the delegate to go.
  Future<void> _waitForScannerToClose() async {
    for (var i = 0; i < 30; i++) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
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
        _status = null;
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
  Future<void> loadStoredCard(CardSummary picked) => _showStoredCard(picked.stem, name: picked.name);

  /// Cards deleted elsewhere: drop them from the queue and clear the screen
  /// if one of them is open, so a later 保存 cannot recreate it.
  void forget(Set<String> stems) {
    if (!mounted) return;
    setState(() {
      _queue.items.removeWhere(stems.contains);
      if (_queue.items.isEmpty) _queue.clear();
      if (stems.contains(_source?.replaceAll('.json', ''))) _clearCard();
    });
  }

  Future<void> _showStoredCard(String stem, {String? name, bool keepQueue = false}) async {
    final (store, _, _) = await _ready;
    final card = await store.loadCard(stem);
    if (!mounted) return;
    if (card == null) {
      setState(() => _error = '「${name ?? stem}」の読み取りデータが見つかりません。ノートは残っています');
      return;
    }
    setState(() {
      if (!keepQueue) _queue.clear();
      _front = card.front;
      _back = card.back.isEmpty ? null : card.back;
      _frontPath = card.frontImage?.path;
      _backPath = card.backImage?.path;
      _source = '${card.stem}.json';
      _status = card.status;
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
  Future<void> _saveReviewed({bool quiet = false, CardStatus? status}) async {
    final (store, _, learned) = await _ready;
    final stem = _source?.replaceAll('.json', '') ??
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final guess = _fields?.toJson() ?? const <String, String?>{};
    final corrected = _reviewed();
    // Saving from the form means the card was looked at; a registered card
    // stays registered when edited again.
    final st = status ?? (_status == CardStatus.registered ? CardStatus.registered : CardStatus.reviewed);
    final f = await store.saveCard(
        stem: stem,
        front: _front!,
        back: _back ?? const [],
        expected: corrected,
        frontImage: _frontPath == null ? null : File(_frontPath!),
        backImage: _backPath == null ? null : File(_backPath!),
        status: st);
    _source = f.uri.pathSegments.last;
    _status = st;
    _fields = fieldsFromJson(corrected); // the saved values are the new baseline
    final before = jsonEncode(learned.toJson());
    learned.learn(guess: guess, corrected: corrected, lines: [..._front!, ...?_back]);
    final learnedSomething = jsonEncode(learned.toJson()) != before;
    if (learnedSomething) await store.saveLearned(learned);
    await store.appendCorrection(stem, guess, corrected);
    widget.onSaved();
    if (!quiet && mounted) _toast('保存しました${learnedSomething ? "。修正を次回から反映します" : ""}');
    if (!quiet) await _pushToContact(fieldsFromJson(corrected));
  }

  /// The card on screen is now in the address book: status only, no
  /// re-learning (the corrections were learned when it was saved).
  Future<void> _markRegistered({String? contactId}) async {
    final stem = _source?.replaceAll('.json', '');
    if (stem == null) return;
    final (store, _, _) = await _ready;
    await store.setStatus(stem, CardStatus.registered, contactId: contactId);
    _status = CardStatus.registered;
    if (contactId != null) _ctl['contactId']!.text = contactId; // the form's hidden link
    widget.onSaved();
  }

  /// Edits of a linked, registered card go to the address book too (the
  /// device then syncs the Google account). Problems are reported, never
  /// fatal: the card itself is already saved.
  Future<void> _pushToContact(CardFields fields) async {
    final id = fields.contactId;
    if (id == null || id.isEmpty || _status != CardStatus.registered || fields.name == null) return;
    try {
      if (!await FlutterContacts.permissions.has(PermissionType.readWrite)) {
        if (mounted) _toast('電話帳は更新していません（連絡先の権限がありません）');
        return;
      }
      final full = await FlutterContacts.get(id, properties: ContactProperties.all);
      if (full == null) {
        if (mounted) _toast('電話帳に元の連絡先が見つかりません（削除された可能性）');
        return;
      }
      await FlutterContacts.update(applyCard(full, fields, scannedAt: DateTime.now()));
      if (mounted) _toast('電話帳の連絡先も更新しました');
    } catch (e) {
      if (mounted) _toast('電話帳の更新に失敗しました: $e');
    }
  }

  /// The linked contact's current values into the form (what was edited in
  /// Google / the phone book); 保存 then makes them the card's.
  Future<void> _pullFromContact() async {
    final id = _ctl['contactId']!.text.trim();
    if (id.isEmpty) return;
    final perm = await FlutterContacts.permissions.request(PermissionType.readWrite);
    if (perm != PermissionStatus.granted) {
      setState(() => _error = '連絡先の権限がありません。端末の設定でこのアプリに連絡先を許可してください');
      return;
    }
    final Contact? full;
    try {
      full = await FlutterContacts.get(id, properties: ContactProperties.all);
    } catch (e) {
      if (mounted) setState(() => _error = '電話帳を読めませんでした: $e');
      return;
    }
    if (!mounted) return;
    if (full == null) {
      setState(() => _error = '電話帳に元の連絡先が見つかりません（削除された可能性）');
      return;
    }
    final theirs = fieldsFromContact(full).toJson();
    // The contact's department is "<division> <dept>" (toContact); take the
    // division back off so a pull + push does not stack it.
    final division = _ctl['division']!.text.trim();
    if (division.isNotEmpty && (theirs['dept'] ?? '').startsWith('$division ')) {
      theirs['dept'] = theirs['dept']!.substring(division.length + 1);
    }
    var n = 0;
    for (final k in fieldOrder) {
      final v = theirs[k];
      final mine = _ctl[k]!.text.trim();
      // The reading is stored in katakana; a hiragana reading is not a difference.
      if (v == null || v.isEmpty || v == mine || (k == 'nameKana' && hiraToKata(normalize(mine)) == v)) continue;
      _ctl[k]!.text = v;
      n++;
    }
    setState(() => _error = null);
    _toast(n == 0 ? '電話帳と同じ内容です' : '電話帳から $n 項目を取り込みました。「保存」で確定します');
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
    setState(_clearCard);
    widget.onSaved();
    _toast(removed ? '削除しました' : 'この名刺はすでに削除されています');
  }

  /// The card on screen (as edited) as a vCard through the share sheet.
  Future<void> _shareCard() async {
    final fields = fieldsFromJson(_reviewed());
    if (fields.name == null) {
      setState(() => _error = '氏名が空です。共有する前に氏名を入れてください');
      return;
    }
    // ponytail: the vCard NOTE carries today's date even for a stored card; fine for sharing.
    if (!await shareVcard(fields.name!, vcardOfFields([fields])) && mounted) {
      setState(() => _error = '共有できませんでした');
    }
  }

  /// Drop an unsaved read (a single scan that went wrong) and go back to
  /// the empty state; nothing in the store is touched.
  Future<void> _discard() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この読み取りを破棄しますか？'),
        content: const Text('保存していない内容と写真は消えます。もう一度撮影できます。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('破棄する')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(_clearCard);
    _toast('破棄しました');
  }

  /// Back to the empty scan screen (the learned data stays).
  void _clearCard() {
    _queue.clear();
    _front = _back = null;
    _frontPath = _backPath = null;
    _source = null;
    _status = null;
    _fields = null;
    _error = null;
    for (final c in _ctl.values) {
      c.clear();
    }
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
      final id = await FlutterContacts.create(toContact(fields, scannedAt: DateTime.now(), source: _source),
          account: await widget.account());
      await _markRegistered(contactId: id);
      if (!mounted) return;
      _toast('電話帳に登録しました');
    }
    if (!mounted) return;
    setState(() => _error = null);
    // Batch review: a registered card leaves the queue; show the next one.
    if (_queue.current != null) {
      _queue.removeCurrent();
      if (_queue.current != null) await _showQueued();
    }
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
        await _markRegistered(contactId: full.id);
        final stem = _source?.replaceAll('.json', '');
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
              final (store, _, _) = await _ready;
              if (stem != null) await store.setStatus(stem, CardStatus.reviewed);
              if (mounted) {
                setState(() => _status = CardStatus.reviewed);
                widget.onSaved();
                _toast('統合前の内容に戻しました');
              }
            },
          ),
        ));
        return true;
      case DuplicateAction.separate:
        await _saveReviewed(quiet: true);
        final id = await FlutterContacts.create(toContact(fields, scannedAt: now, source: _source),
            account: await widget.account());
        await _markRegistered(contactId: id);
        if (mounted) _toast('別の連絡先として登録しました');
        return true;
      case DuplicateAction.replace:
        await _saveReviewed(quiet: true);
        await FlutterContacts.delete(id);
        final created = await FlutterContacts.create(toContact(fields, scannedAt: now, source: _source),
            account: await widget.account());
        await _markRegistered(contactId: created);
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
    await _importCards(pairInboxFiles(files));
  }

  /// OCR every inbox card (front, plus back when present), save it as 未確認
  /// with the extractor's guess, remove its files from the inbox, and queue
  /// it for review now or later from the list. Unreadable ones stay in the
  /// folder so they can be retaken.
  Future<void> _importCards(List<InboxCard> cards) async {
    final (store, ocr, learned) = await _ready;
    _queue.clear();
    var saved = 0, levelled = 0, skipped = 0;
    for (final (i, c) in cards.indexed) {
      setState(() => _progress = '読み取り中 ${i + 1}/${cards.length}');
      final r = await ocr.recognize(c.front.path, front: true);
      if (r.lines.isEmpty) {
        skipped++;
        continue;
      }
      if (r.deskewedBy != null) levelled++;
      final back = c.back == null ? null : await ocr.recognize(c.back!.path, front: false);
      final guess = extract(r.lines, back: back?.lines ?? const [], learned: learned);
      guess.job = defaultJob(guess);
      await store.saveCard(
          stem: c.stem,
          front: r.lines,
          frontRaw: r.rawLines,
          back: back?.lines ?? const [],
          expected: guess.toJson(),
          frontImage: c.front,
          backImage: c.back,
          status: CardStatus.unreviewed);
      await c.front.delete(); // the vault now holds the copies
      await c.back?.delete();
      saved++;
      _queue.items.add(c.stem);
    }
    await _showQueued();
    if (mounted) setState(() => _progress = null);
    widget.onSaved();
    final unread = skipped == 0 ? '' : '。$skipped 枚は文字を読み取れず、取込フォルダに残しました';
    _toast(saved == 0
        ? '読み取れた名刺がありません$unread'
        : '$saved 枚を取り込みました${levelled == 0 ? "" : "（$levelled 枚は傾きを補正）"}$unread。'
            '1 枚ずつ確認して登録してください。あとで一覧の「未確認」からも続けられます');
  }

  /// Show the queue's current card from the store (saved values and
  /// status), keeping the queue for the arrows.
  Future<void> _showQueued() async {
    final stem = _queue.current;
    if (stem != null) await _showStoredCard(stem, keepQueue: true);
  }

  Future<void> _move(bool forward) async {
    if (forward ? _queue.next() : _queue.prev()) await _showQueued();
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
                onBurst: Platform.isAndroid ? shootMany : null,
              ),
            )
          else
            // Photos and chips scroll with the form: a fixed header plus the
            // keyboard overflowed in landscape.
            Expanded(
              child: CardForm(
                key: ValueKey(_frontPath),
                controllers: _ctl,
                lines: [...?_front, ...?_back],
                missing: _missing,
                suggestions: widget.suggestions,
                jobs: widget.jobs,
                header: Column(
                  children: [
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
                    if (_ctl['contactId']!.text.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _progress == null ? _pullFromContact : null,
                          icon: const Icon(Icons.sync, size: AppSize.iconSmall),
                          label: const Text('電話帳の内容を取り込む'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
                    IconButton(
                      tooltip: 'この名刺を共有',
                      icon: const Icon(Icons.share_outlined),
                      onPressed: _progress == null ? _shareCard : null,
                    ),
                    IconButton(
                      // Stored card: delete it. Fresh read: discard it.
                      tooltip: _source != null ? 'この名刺を削除' : 'この読み取りを破棄',
                      icon: const Icon(Icons.delete_outline),
                      color: scheme.error,
                      onPressed: _progress != null
                          ? null
                          : _source != null
                              ? _deleteCard
                              : _discard,
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
  final VoidCallback? onBurst; // null where the document scanner is unavailable
  const _EmptyState({required this.onShoot, required this.onAlbum, this.onBurst});

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
            if (onBurst != null) ...[
              const SizedBox(height: AppSpace.unit),
              OutlinedButton.icon(
                onPressed: onBurst,
                icon: const Icon(Icons.burst_mode_outlined),
                label: const Text('続けて撮影'),
              ),
            ],
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
      padding: const EdgeInsets.only(top: AppSpace.unit, bottom: AppSpace.unit),
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
      padding: const EdgeInsets.only(top: AppSpace.unit, bottom: AppSpace.unit),
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
          // A back that exists (maybe the blank stand-in from a burst) can be
          // replaced; saving overwrites the stored image.
          if (backPath != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onBackShoot,
                  icon: const Icon(Icons.camera_alt, size: AppSize.iconSmall),
                  label: const Text('裏を撮り直す'),
                ),
                IconButton(
                  tooltip: '裏をアルバムから選び直す',
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: onBackAlbum,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
