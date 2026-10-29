import 'card_status.dart';
import 'fields.dart';
import 'vault_index.dart';
import 'vcard_export.dart';

/// Every card as CSV for Excel or another CRM: the form's columns in the
/// form's order with Japanese headers, then 状態 / 取込日 / ノート; newest
/// first; every cell quoted (quotes doubled); CRLF; a BOM so Excel reads
/// UTF-8 without an import wizard.
String csvOfNotes(Map<String, String> notes) => csvAndRows(notes).$1;

/// (csv, number of card rows).
(String, int) csvAndRows(Map<String, String> notes) {
  final rows = <(String, List<String>)>[];
  for (final (key, fm) in cardNotes(notes)) {
    final j = fieldsFromFrontmatter(fm).toJson();
    final scanned = fm['scanned'] ?? '';
    rows.add((scanned, [
      for (final k in fieldOrder) j[k] ?? '',
      parseStatus(fm['status']).label,
      scanned,
      key,
    ]));
  }
  rows.sort((a, b) => b.$1.compareTo(a.$1));
  // A leading = + - @ would make Excel evaluate the cell (phone numbers
  // starting with + included): a leading apostrophe keeps it text.
  String q(String s) => '"${(RegExp(r'^[=+\-@\t\r]').hasMatch(s) ? "'$s" : s).replaceAll('"', '""')}"';
  final header = [for (final k in fieldOrder) fieldLabels[k]!, '状態', '取込日', 'ノート'];
  final lines = [header, for (final r in rows) r.$2];
  return ('\uFEFF${lines.map((r) => r.map(q).join(',')).join('\r\n')}\r\n', rows.length);
}
