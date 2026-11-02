import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'ocr/card_note.dart';

/// The only place the share_plus plugin is touched, so screens stay testable.
/// False when the sheet could not open (no app to share with, plugin error).
/// [onShared] runs when the user went through with it (not on cancel; an
/// "unavailable" answer counts, since the platform could not tell).
Future<bool> _share(ShareParams params, {void Function()? onShared}) async {
  try {
    final r = await SharePlus.instance.share(params);
    if (r.status != ShareResultStatus.dismissed) onShared?.call();
    return true;
  } catch (_) {
    return false;
  }
}

/// Plain text (the user's own card for LINE / SMS) to the share sheet.
Future<bool> shareMessage(String text, {required String subject}) =>
    _share(ShareParams(text: text, subject: subject));

/// A vCard built in memory as `<name>.vcf`; the plugin hands it over through
/// its own temp folder, so nothing is left in the app's data.
Future<bool> shareVcard(String name, String vcf) =>
    shareText('${safeFileStem(name)}.vcf', 'text/vcard', vcf, subject: '名刺: $name');

/// Any text built in memory as a file ([fileName] with its extension).
Future<bool> shareText(String fileName, String mime, String content, {required String subject}) =>
    _share(ShareParams(files: [XFile.fromData(utf8.encode(content), mimeType: mime, name: fileName)], subject: subject));

/// An existing file (the all-cards vCard, a backup zip) to the share sheet.
Future<bool> shareFile(File file, {required String mime, required String subject, void Function()? onShared}) =>
    _share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: subject), onShared: onShared);
