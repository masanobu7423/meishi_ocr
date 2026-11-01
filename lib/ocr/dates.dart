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

/// The next follow-up a 連絡済み can schedule.
enum FollowUp { week, twoWeeks, month, threeMonths }

/// [from] + the step; months keep the day or clamp to the month's end
/// (1/31 + 1 month = 2/28), never spill into the month after.
DateTime followUpDate(DateTime from, FollowUp step) => switch (step) {
      FollowUp.week => DateTime(from.year, from.month, from.day + 7),
      FollowUp.twoWeeks => DateTime(from.year, from.month, from.day + 14),
      FollowUp.month => _addMonths(from, 1),
      FollowUp.threeMonths => _addMonths(from, 3),
    };

DateTime _addMonths(DateTime d, int n) {
  final lastDay = DateTime(d.year, d.month + n + 1, 0).day; // day 0 = last day of the month before
  return DateTime(d.year, d.month + n, d.day < lastDay ? d.day : lastDay);
}
