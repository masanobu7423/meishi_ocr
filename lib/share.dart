import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'ocr/card_note.dart';

/// The only place the share_plus plugin is touched, so screens stay testable.
/// False when the sheet could not open (no app to share with, plugin error).
Future<bool> _share(XFile file, String subject) async {
  try {
    await SharePlus.instance.share(ShareParams(files: [file], subject: subject));
    return true;
  } catch (_) {
    return false;
  }
}

/// A vCard built in memory as `<name>.vcf`; the plugin hands it over through
/// its own temp folder, so nothing is left in the app's data.
Future<bool> shareVcard(String name, String vcf) => _share(
    XFile.fromData(utf8.encode(vcf), mimeType: 'text/vcard', name: '${safeFileStem(name)}.vcf'),
    '名刺: $name');

/// An existing file (the all-cards vCard, a backup zip) to the share sheet.
Future<bool> shareFile(File file, {required String mime, required String subject}) =>
    _share(XFile(file.path, mimeType: mime), subject);
