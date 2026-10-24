import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'card_note.dart';
import 'extractor.dart';
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
  }) async {
    final now = scannedAt ?? DateTime.now();
    final vertical = isVertical(front);
    final vault = await _dir('vault').create(recursive: true);
    // The card images live with the notes so Obsidian can embed them, and
    // they survive the camera's temp files being cleaned.
    final images = <String, String>{};
    for (final (side, img) in [('front', frontImage), ('back', backImage)]) {
      if (img == null) continue;
      final ext = img.path.split('.').last.toLowerCase();
      final rel = 'images/${stem}_$side.$ext';
      await Directory('${vault.path}/images').create(recursive: true);
      await img.copy('${vault.path}/$rel');
      images[side] = rel;
    }
    final golden = await _dir('golden').create(recursive: true);
    final file = File('${golden.path}/$stem.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert({
      'strict': false,
      'vertical': vertical,
      if (images.isNotEmpty) 'images': images,
      'front': front.map((l) => l.toJson()).toList(),
      if (frontRaw != null) 'frontRaw': frontRaw.map((l) => l.toJson()).toList(),
      'back': back.map((l) => l.toJson()).toList(),
      'expected': expected,
    }));
    final fields = fieldsFromJson(expected);
    await File('${vault.path}/${cardNoteFilename(fields, now)}').writeAsString(cardNoteMarkdown(
        fields, scannedAt: now, vertical: vertical, source: '$stem.json', images: images));
    await File('${vault.path}/_名刺一覧.md').writeAsString(buildIndex(await _notes(vault)));
    return file;
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
    final f = File('${root.path}/golden/$stem.json');
    if (!f.existsSync()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    List<OcrLine> lines(String k) => [
          for (final e in (j[k] as List? ?? const [])) OcrLine.fromJson(e as Map<String, dynamic>)
        ];
    final images = (j['images'] as Map?)?.cast<String, String>() ?? const {};
    File? img(String side) =>
        images[side] == null ? null : File('${root.path}/vault/${images[side]}');
    return StoredCard(
      stem: stem,
      front: lines('front'),
      back: lines('back'),
      expected: (j['expected'] as Map).cast<String, String?>(),
      frontImage: img('front'),
      backImage: img('back'),
    );
  }

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
    final learned = File('${root.path}/learned.json');
    if (learned.existsSync()) {
      archive.add(ArchiveFile.bytes('learned.json', await learned.readAsBytes()));
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
  final Map<String, String?> expected;
  final File? frontImage, backImage;
  const StoredCard({
    required this.stem,
    required this.front,
    required this.back,
    required this.expected,
    this.frontImage,
    this.backImage,
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
  ..memo = j['memo'];
