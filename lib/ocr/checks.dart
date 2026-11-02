// Mechanical checks on card fields: they catch OCR misreads (a dropped
// digit, ',' for '.') and a construction licence due for renewal, with no
// network and no dictionary. They only advise; saving is never blocked.
import 'contact_mapper.dart' show phoneDigits;
import 'extractor.dart' show normalize;

/// Why a value looks wrong. [misread] = probably an OCR error (red);
/// false = the value is fine but needs attention (licence renewal).
class FieldIssue {
  final String text;
  final bool misread;
  const FieldIssue(this.text, {this.misread = true});
}

/// 法人番号: 13 digits, the first is 9 − (Σ digit × (1 or 2)) mod 9 over
/// the other 12 counted from the right (国税庁の算式).
bool validCorpNo(String digits) {
  if (!RegExp(r'^\d{13}$').hasMatch(digits)) return false;
  var sum = 0;
  for (var n = 1; n <= 12; n++) {
    sum += int.parse(digits[13 - n]) * (n.isOdd ? 1 : 2);
  }
  return int.parse(digits[0]) == 9 - sum % 9;
}

/// Prefixes whose numbers have 11 digits (0800 starts with 080); every
/// other number has 10.
const _elevenDigits = ['020', '050', '060', '070', '080', '090'];

/// The issue with one field's value, or null when it passes (or the field
/// is not checked). [today] enables the date-dependent licence check.
FieldIssue? fieldIssue(String key, String? value, {DateTime? today}) {
  final v = normalize(value ?? '');
  if (v.isEmpty) return null;
  switch (key) {
    case 'corpNo':
      final d = v.replaceFirst(RegExp(r'^T'), '').replaceAll(RegExp(r'[\s-]'), '');
      if (!RegExp(r'^\d{13}$').hasMatch(d)) return FieldIssue('法人番号は 13 桁の数字です（いま ${d.length} 文字）');
      return validCorpNo(d) ? null : const FieldIssue('法人番号の検査用数字が合いません。1 文字ずつ写真と見比べてください');
    case 'phone' || 'mobile' || 'fax':
      final number = v
          .split(RegExp(r'内線|ext|(?<![A-Za-z])[xX]\s*\d', caseSensitive: false))
          .first
          // +81 (0)3-…, 0081-3-…: the same Japanese number written for abroad.
          .replaceFirst(RegExp(r'^\D*(?:\+|00)\s*81\s*(?:\(0\))?'), '+81 ');
      if (RegExp(r'^\D*\+(?!81)').hasMatch(number)) return null; // foreign, even after a TEL label
      final d = phoneDigits(number);
      if (!d.startsWith('0')) return const FieldIssue('0 から始まる番号ではありません。市外局番が抜けていないか確認してください');
      final want = _elevenDigits.any(d.startsWith) ? 11 : 10;
      return d.length == want
          ? null
          : FieldIssue('桁数が合いません（いま ${d.length} 桁。携帯・050 は 11 桁、固定電話は 10 桁）');
    case 'email':
      return RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$').hasMatch(v)
          ? null
          : const FieldIssue('メールアドレスの形になっていません。「,」や空白、全角の文字がないか確認してください');
    case 'postal':
      final d = v.replaceAll(RegExp(r'\D'), '');
      return d.length == 7 ? null : FieldIssue('郵便番号は 7 桁です（いま ${d.length} 桁）');
    case 'constructionLicense':
      return today == null ? null : _licence(v, today);
  }
  return null;
}

/// （般-5）: the permit year in the era of the grant; permits run 5 years.
/// Small numbers are 令和, large ones 平成 (a 平成 permit has run out).
FieldIssue? _licence(String v, DateTime today) {
  final m = RegExp(r'[(（]\s*[般特]\s*[-－ー]\s*(\d{1,2})\s*[)）]').firstMatch(v);
  if (m == null) return null; // a format we do not know: say nothing
  final n = int.parse(m[1]!);
  final reiwa = n <= today.year - 2018;
  final granted = reiwa ? 2018 + n : 1988 + n;
  final era = '${reiwa ? '令和' : '平成'}$n年';
  final ends = granted + 5;
  if (ends < today.year) {
    return FieldIssue('$eraの許可です（5 年ごとに更新）。更新済みか、最新の許可番号を確認してください', misread: false);
  }
  if (ends == today.year) return FieldIssue('$eraの許可で、今年が更新の目安です（5 年ごと）', misread: false);
  return null;
}

/// Checked fields with an issue, in field order; empty when all pass.
Map<String, FieldIssue> cardIssues(Map<String, String?> values, {DateTime? today}) => {
      for (final k in checkedFields) k: ?fieldIssue(k, values[k], today: today),
    };

/// Fields [fieldIssue] knows how to check.
const checkedFields = ['phone', 'mobile', 'email', 'postal', 'fax', 'corpNo', 'constructionLicense'];
