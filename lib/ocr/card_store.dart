import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'card_note.dart';
import 'card_status.dart';
import 'extractor.dart';
import 'jobs.dart';
import 'learned.dart';
import 'ocr_line.dart';
import 'vault_index.dart';
import 'vcard_export.dart';

/// Everything the app writes under one root directory:
///
/// ```
/// <root>/inbox/    images dropped in for batch import (created by the app)
/// <root>/golden/   raw OCR lines + reviewed fields, one JSON per card
/// <root>/vault/    Obsidian notes, _名刺一覧.md index, _名刺.vcf export
/// <root>/log/      errors.txt
/// ```
///
/// Pure dart:io so it is testable with a temp directory.
class CardStore {
  final Directory root;
  CardStore(this.root);

  Directory _dir(String name) => Directory('${root.path}/$name');

  /// The app must create inbox itself: a dir made by `adb shell mkdir` is not
  /// readable by the app on Android 11+ (scoped storage ownership).
  Future<Directory> inbox() => _dir('inbox').create(recursive: true);

  /// Copies a scanner page into the inbox as `<name>.<ext>`, to be read
  /// later by the folder import.
  Future<File> stashCapture(File src, String name) async {
    final ext = src.path.split('.').last.toLowerCase();
    return src.copy('${(await inbox()).path}/$name.$ext');
  }

  /// A white card-shaped image as `<stem>_back.png`: the back of a one-sided
  /// card in a front/back burst, so the pairing stays aligned. It can be
  /// replaced from the review screen later.
  Future<File> stashBlankBack(String stem) async {
    final blank = img.Image(width: 1200, height: 720)..clear(img.ColorRgb8(255, 255, 255));
    return File('${(await inbox()).path}/${stem}_back.png').writeAsBytes(img.encodePng(blank));
  }

  Future<List<File>> inboxImages() async => (await inbox())
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Writes `golden/<stem>.json`, the card's Obsidian note and the refreshed
  /// index. [expected] holds the reviewed (or extractor-guessed) fields.
  Future<File> saveCard({
    required String stem,
    required List<OcrLine> front,
    required List<OcrLine> back,
    required Map<String, String?> expected,
    List<OcrLine>? frontRaw,
    File? frontImage,
    File? backImage,
    DateTime? scannedAt,
    CardStatus status = CardStatus.reviewed,
  }) async {
    final vertical = isVertical(front);
    final vault = await _dir('vault').create(recursive: true);
    // Saving an already-saved card (edited later) replaces its note and
    // keeps the original scan date instead of adding a second note.
    final olds = await _notesFor(vault, stem);
    final firstScan = olds.map((o) => o.$2).whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isBefore(a) ? b : a);
    final now = scannedAt ?? firstScan ?? DateTime.now();
    // The card images live with the notes so Obsidian can embed them, and
    // they survive the camera's temp files being cleaned.
    final images = <String, String>{};
    for (final (side, img) in [('front', frontImage), ('back', backImage)]) {
      if (img == null) continue;
      final ext = img.path.split('.').last.toLowerCase();
      final rel = 'images/${stem}_$side.$ext';
      await Directory('${vault.path}/images').create(recursive: true);
      final dest = File('${vault.path}/$rel');
      // Re-saving a stored card passes the vault copy itself as the source;
      // copying a file onto itself truncates it on Linux/Android.
      if (!_samePath(img, dest)) {
        // A retaken side may change format (blank .png -> photo .jpg).
        for (final old in Directory('${vault.path}/images').listSync().whereType<File>()) {
          if (old.uri.pathSegments.last.startsWith('${stem}_$side.') && !_samePath(old, dest)) {
            await old.delete();
          }
        }
        await img.copy(dest.path);
      }
      images[side] = rel;
    }
    final golden = await _dir('golden').create(recursive: true);
    final file = File('${golden.path}/$stem.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert({
      'strict': false,
      'vertical': vertical,
      'status': status.name,
      if (images.isNotEmpty) 'images': images,
      'front': front.map((l) => l.toJson()).toList(),
      if (frontRaw != null) 'frontRaw': frontRaw.map((l) => l.toJson()).toList(),
      'back': back.map((l) => l.toJson()).toList(),
      'expected': expected,
    }));
    final fields = fieldsFromJson(expected);
    final note = File('${vault.path}/${cardNoteFilename(fields, now)}');
    await note.writeAsString(cardNoteMarkdown(fields,
        scannedAt: now, vertical: vertical, source: '$stem.json', images: images, status: status));
    for (final (f, _) in olds) {
      // Same folder, so compare names: listSync and our path differ in separators on Windows.
      if (f.uri.pathSegments.last != note.uri.pathSegments.last) await f.delete();
    }
    await _writeIndex(vault);
    return file;
  }

  static bool _samePath(File a, File b) =>
      a.absolute.path.replaceAll('\\', '/') == b.absolute.path.replaceAll('\\', '/');

  /// Changes only the status of a stored card (its data, images and scan
  /// date stay). False when nothing is stored under [stem].
  Future<bool> setStatus(String stem, CardStatus status, {String? contactId}) async {
    final c = await loadCard(stem);
    if (c == null) return false;
    await saveCard(
      stem: stem,
      front: c.front,
      frontRaw: c.frontRaw,
      back: c.back,
      expected: {...c.expected, 'contactId': ?contactId},
      frontImage: c.frontImage,
      backImage: c.backImage,
      status: status,
    );
    return true;
  }

  /// A stem names one file inside golden/; anything that could leave the
  /// folder (separators, `..`) is rejected. Same for image paths in JSON,
  /// which must stay under vault/images.
  static bool _safeStem(String stem) =>
      stem.isNotEmpty && !stem.contains(RegExp(r'[/\\]')) && !stem.contains('..');
  static bool _safeImage(Object? rel) =>
      rel is String && rel.startsWith('images/') && !rel.split('/').contains('..');

  Future<void> _writeIndex(Directory vault) async =>
      File('${vault.path}/_名刺一覧.md').writeAsString(buildIndex(await _notes(vault)));

  /// Every note written for [stem] (normally one; the old re-save bug could
  /// leave several), each with its scan date.
  Future<List<(File, DateTime?)>> _notesFor(Directory vault, String stem) async {
    final out = <(File, DateTime?)>[];
    for (final f in vault.listSync().whereType<File>()) {
      if (!f.path.endsWith('.md') || f.uri.pathSegments.last.startsWith('_')) continue;
      final fm = parseFrontmatter(await f.readAsString());
      if (fm['source'] == '$stem.json') out.add((f, DateTime.tryParse(fm['scanned'] ?? '')));
    }
    return out;
  }

  /// Removes a saved card: its JSON, notes and images. False if nothing
  /// was stored under [stem].
  Future<bool> deleteCard(String stem) async {
    if (!_safeStem(stem)) return false;
    final json = File('${root.path}/golden/$stem.json');
    final vault = await _dir('vault').create(recursive: true);
    final olds = await _notesFor(vault, stem);
    if (!json.existsSync() && olds.isEmpty) return false;
    if (json.existsSync()) {
      final j = jsonDecode(await json.readAsString()) as Map<String, dynamic>;
      for (final rel in (j['images'] as Map?)?.values ?? const []) {
        final img = File('${vault.path}/$rel');
        if (_safeImage(rel) && img.existsSync()) await img.delete();
      }
      await json.delete();
    }
    for (final (f, _) in olds) {
      await f.delete();
    }
    await _writeIndex(vault);
    return true;
  }

  /// Unpacks a zip made by [backup] into this store: same paths are
  /// overwritten, other cards are kept, and learned.json / jobs.json are only
  /// added when the store has none. Entries outside vault/, golden/ and those
  /// are ignored. Returns (files written, files that failed); failures are
  /// logged to log/errors.txt.
  Future<(int, int)> restore(File zip) async {
    var written = 0, failed = 0;
    for (final e in ZipDecoder().decodeBytes(await zip.readAsBytes())) {
      if (!e.isFile) continue;
      final rel = e.name.replaceAll('\\', '/');
      final inside = rel.startsWith('vault/') || rel.startsWith('golden/') || _rootFiles.contains(rel);
      if (!inside || rel.split('/').contains('..')) continue;
      final out = File('${root.path}/$rel');
      if (_rootFiles.contains(rel) && out.existsSync()) continue;
      try {
        await out.create(recursive: true);
        await out.writeAsBytes(e.content);
        written++;
      } catch (err) {
        failed++;
        await appendError('restore $rel', err);
      }
    }
    await _writeIndex(await _dir('vault').create(recursive: true));
    return (written, failed);
  }

  /// Unattended safety net: one backup per calendar day while there are
  /// cards, keeping the newest [keep] zips. Returns the new zip, or null
  /// when nothing was done.
  Future<File?> autoBackup({DateTime? now, int keep = 5}) async {
    final t = now ?? DateTime.now();
    final golden = _dir('golden');
    if (!golden.existsSync() || golden.listSync().whereType<File>().isEmpty) return null;
    final existing = await backups();
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    if (existing.isNotEmpty && existing.first.uri.pathSegments.last.contains(day(t))) return null;
    final (zip, _) = await backup(now: t);
    for (final old in (await backups()).skip(keep)) {
      await old.delete();
    }
    return zip;
  }

  /// Backup zips in `<root>/backup/`, newest first.
  Future<List<File>> backups() async {
    final d = _dir('backup');
    if (!d.existsSync()) return const [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  Directory get vaultDir => _dir('vault');

  /// Every card note (stem -> markdown), for the history list.
  Future<Map<String, String>> notes() async => _notes(await vaultDir.create(recursive: true));

  Future<Map<String, String>> _notes(Directory vault) async {
    final files = vault
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md') && !f.uri.pathSegments.last.startsWith('_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return {
      for (final f in files)
        f.uri.pathSegments.last.replaceAll(RegExp(r'\.md$'), ''): await f.readAsString(),
    };
  }

  /// `vault/_名刺.vcf` with every card note; returns the file and the count.
  Future<(File, int)> exportVcard() async {
    final vault = await _dir('vault').create(recursive: true);
    final vcf = vcardOfNotes(await _notes(vault));
    final file = File('${vault.path}/_名刺.vcf');
    await file.writeAsString(vcf);
    return (file, 'BEGIN:VCARD'.allMatches(vcf).length);
  }

  /// Reads a saved card back for the history screen; null if missing.
  Future<StoredCard?> loadCard(String stem) async {
    if (!_safeStem(stem)) return null;
    final f = File('${root.path}/golden/$stem.json');
    if (!f.existsSync()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    List<OcrLine> lines(String k) => [
          for (final e in (j[k] as List? ?? const [])) OcrLine.fromJson(e as Map<String, dynamic>)
        ];
    final images = (j['images'] as Map?)?.cast<String, String>() ?? const {};
    File? img(String side) =>
        _safeImage(images[side]) ? File('${root.path}/vault/${images[side]}') : null;
    return StoredCard(
      stem: stem,
      front: lines('front'),
      frontRaw: j['frontRaw'] == null ? null : lines('frontRaw'),
      back: lines('back'),
      expected: (j['expected'] as Map).cast<String, String?>(),
      frontImage: img('front'),
      backImage: img('back'),
      status: parseStatus(j['status'] as String?),
    );
  }

  /// Small user preferences (`<root>/settings.json`), e.g. the account to
  /// register contacts into.
  Future<Map<String, dynamic>> loadSettings() async {
    final f = File('${root.path}/settings.json');
    if (!f.existsSync()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      await appendError('settings.json', e);
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) =>
      File('${root.path}/settings.json').writeAsString(jsonEncode(settings));

  /// The user's 職種 list (`<root>/jobs.json`); the defaults until saved or
  /// when the saved list is empty.
  Future<List<String>> loadJobs() async {
    final f = File('${root.path}/jobs.json');
    if (!f.existsSync()) return defaultJobs;
    try {
      final j = jsonDecode(await f.readAsString());
      final l = [if (j is List) for (final v in j) if (v is String && v.isNotEmpty) v];
      if (l.isNotEmpty) return l; // an emptied list means "back to the defaults"
    } catch (e) {
      await appendError('jobs.json', e);
    }
    return defaultJobs;
  }

  Future<void> saveJobs(List<String> jobs) =>
      File('${root.path}/jobs.json').writeAsString(const JsonEncoder.withIndent(' ').convert(jobs));

  /// Rules learned from the user's corrections (`<root>/learned.json`).
  Future<Learned> loadLearned() async {
    final f = File('${root.path}/learned.json');
    if (!f.existsSync()) return Learned();
    try {
      return Learned.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      await appendError('learned.json', e);
      return Learned();
    }
  }

  Future<void> saveLearned(Learned learned) => File('${root.path}/learned.json')
      .writeAsString(const JsonEncoder.withIndent(' ').convert(learned.toJson()));

  /// One JSON line per reviewed card that differed from the extractor's
  /// guess: the raw material for future rules and for new golden fixtures.
  Future<void> appendCorrection(
      String stem, Map<String, String?> guess, Map<String, String?> corrected) async {
    final changes = {
      for (final k in corrected.keys)
        if (corrected[k] != guess[k]) k: {'from': guess[k], 'to': corrected[k]},
    };
    if (changes.isEmpty) return;
    final log = await File('${root.path}/log/corrections.jsonl').create(recursive: true);
    await log.writeAsString(
        '${jsonEncode({'at': DateTime.now().toIso8601String(), 'stem': stem, 'changes': changes})}\n',
        mode: FileMode.append);
  }

  /// Settings files next to the folders; backed up, restored only when missing.
  static const _rootFiles = ['learned.json', 'jobs.json'];

  /// `backup/meishi_backup_<date>_<time>.zip` with vault (notes + images),
  /// golden JSON and learned.json. Returns the file and the entry count.
  /// Everything needed to rebuild the history on another phone; the zip is
  /// in the app's external folder for the Files app / adb to pick up.
  Future<(File, int)> backup({DateTime? now}) async {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}';
    final archive = Archive();
    for (final dir in ['vault', 'golden']) {
      final d = _dir(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(root.path.length + 1).replaceAll('\\', '/');
        archive.add(ArchiveFile.bytes(rel, await f.readAsBytes()));
      }
    }
    for (final name in _rootFiles) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) archive.add(ArchiveFile.bytes(name, await f.readAsBytes()));
    }
    final out = File('${(await _dir('backup').create(recursive: true)).path}/meishi_backup_$stamp.zip');
    await out.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return (out, archive.length);
  }

  Future<void> appendError(String source, Object error) =>
      appendLog('errors.txt', '$source: $error');

  Future<void> appendLog(String file, String line) async {
    final log = await File('${root.path}/log/$file').create(recursive: true);
    await log.writeAsString('${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append);
  }
}

/// A card as read back from the store.
class StoredCard {
  final String stem;
  final List<OcrLine> front, back;
  final List<OcrLine>? frontRaw;
  final Map<String, String?> expected;
  final File? frontImage, backImage;
  final CardStatus status;
  const StoredCard({
    required this.stem,
    required this.front,
    this.frontRaw,
    required this.back,
    required this.expected,
    this.frontImage,
    this.backImage,
    this.status = CardStatus.reviewed,
  });
}

/// `CardFields.toJson()` keys back onto a CardFields.
CardFields fieldsFromJson(Map<String, String?> j) => CardFields()
  ..name = j['name']
  ..nameKana = j['nameKana']
  ..nameRoman = j['nameRoman']
  ..company = j['company']
  ..dept = j['dept']
  ..title = j['title']
  ..phone = j['phone']
  ..mobile = j['mobile']
  ..fax = j['fax']
  ..email = j['email']
  ..url = j['url']
  ..postal = j['postal']
  ..address = j['address']
  ..memo = j['memo']
  ..corpNo = j['corpNo']
  ..constructionLicense = j['constructionLicense']
  ..realEstateLicense = j['realEstateLicense']
  ..qualifications = j['qualifications']
  ..division = j['division']
  ..category = j['category']
  ..related = j['related']
  ..job = j['job']
  ..trust = j['trust']
  ..contactId = j['contactId'];
