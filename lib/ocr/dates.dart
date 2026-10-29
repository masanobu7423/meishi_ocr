/// `yyyy-mm-dd` of a date: the form every stored date uses (golden JSON,
/// note frontmatter, file names, the contact note line).
String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `yyyy-mm-dd` → date; anything else (empty, slashes, junk, 2026-02-30) → null.
DateTime? parseYmd(String? s) {
  final t = s?.trim() ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return null;
  final d = DateTime.tryParse(t);
  // DateTime normalises 2026-02-30 to March 2: only a real date counts.
  return d != null && ymd(d) == t ? d : null;
}
