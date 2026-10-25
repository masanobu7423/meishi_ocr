import 'learned.dart';
import 'ocr_line.dart';
import 'romaji.dart';

/// Structured fields pulled out of a business card.
class CardFields {
  String? name, nameKana, nameRoman, company, dept, title;
  String? phone, mobile, fax, email, url, postal, address;

  /// Free text the user adds (where / when they met); never extracted.
  String? memo;

  /// Construction / real-estate trade fields: licence numbers, the 13-digit
  /// corporate number and qualifications are printed and extracted; the
  /// division (部門), label (区分) and related users are the user's own.
  String? corpNo, constructionLicense, realEstateLicense, qualifications;
  String? division, category, related;

  static const keys = [
    'name', 'nameKana', 'nameRoman', 'company', 'dept', 'title',
    'phone', 'mobile', 'fax', 'email', 'url', 'postal', 'address', 'memo',
    'corpNo', 'constructionLicense', 'realEstateLicense', 'qualifications',
    'division', 'category', 'related',
  ];

  void set(String key, String? v) {
    switch (key) {
      case 'name': name = v;
      case 'nameKana': nameKana = v;
      case 'nameRoman': nameRoman = v;
      case 'company': company = v;
      case 'dept': dept = v;
      case 'title': title = v;
      case 'phone': phone = v;
      case 'mobile': mobile = v;
      case 'fax': fax = v;
      case 'email': email = v;
      case 'url': url = v;
      case 'postal': postal = v;
      case 'address': address = v;
      case 'memo': memo = v;
      case 'corpNo': corpNo = v;
      case 'constructionLicense': constructionLicense = v;
      case 'realEstateLicense': realEstateLicense = v;
      case 'qualifications': qualifications = v;
      case 'division': division = v;
      case 'category': category = v;
      case 'related': related = v;
    }
  }

  Map<String, String?> toJson() => {
        'name': name,
        'nameKana': nameKana,
        'nameRoman': nameRoman,
        'company': company,
        'dept': dept,
        'title': title,
        'phone': phone,
        'mobile': mobile,
        'fax': fax,
        'email': email,
        'url': url,
        'postal': postal,
        'address': address,
        'memo': memo,
        'corpNo': corpNo,
        'constructionLicense': constructionLicense,
        'realEstateLicense': realEstateLicense,
        'qualifications': qualifications,
        'division': division,
        'category': category,
        'related': related,
      };
}

/// Full-width ASCII -> half-width, ideographic space -> space, collapse runs,
/// and the digit confusions FastaLife's blood-test parser learned to fix:
/// `1O2` -> `102`, `1l2` -> `112`, `O3-` -> `03-`.
String normalize(String s) => s
    .replaceAllMapped(RegExp(r'[！-～]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0))
    .replaceAll('　', ' ')
    // long-vowel mark read in place of a hyphen, only between digits (keeps マネージャー intact)
    .replaceAllMapped(RegExp(r'(\d)ー(?=\d)'), (m) => '${m[1]}-')
    .replaceAllMapped(RegExp(r'(\d)[Oo](\d)'), (m) => '${m[1]}0${m[2]}')
    .replaceAllMapped(RegExp(r'(\d)[lI](\d)'), (m) => '${m[1]}1${m[2]}')
    .replaceAllMapped(RegExp(r'(?<![A-Za-z])O(?=\d{1,3}-)'), (m) => '0')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _email = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+');
final _url = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);
final _postal = RegExp(r'〒\s*(\d{3})-?(\d{4})');
// A line that is nothing but "150-0001" (no 〒). Anchored so 090-1234 inside a
// phone number never qualifies.
final _postalBare = RegExp(r'^(\d{3})-(\d{4})$');
// +81 3-1234-5678 / +81-90-… / +81 (0)3-… -> domestic form before matching.
final _intl = RegExp(r'\+81[-\s]?\(?0?\)?[-\s]?');
final _phone =
    RegExp(r'(?<!\d)(0\d{1,4})[-.\s()]*(\d{1,4})[-.\s()]*(\d{3,4})(?!\d)');
final _fax = RegExp(r'fax', caseSensitive: false);
final _label = RegExp(
    r'\b(TEL|FAX|PHONE|MOBILE|E-?MAIL|MAIL|URL|HP|WEB)\b\s*[:.]?|(電話|携帯|メール)\s*[:.]?',
    caseSensitive: false);
final _company = RegExp(
    r'株式会社|有限会社|合同会社|\(株\)|㈱|\bInc\b|Co\.,? ?Ltd|\bCorp(?:oration)?\b|\bLLC\b|K\.K\.|Company',
    caseSensitive: false);
final _title = RegExp(
    r'代表取締役|取締役|執行役員|社長|会長|専務|常務|部長|次長|課長|係長|主任|室長|所長|支店長|工場長|現場監督|現場代理人|監理技術者|主任技術者|職長|マネージャー|リーダー|エンジニア|デザイナー|コンサルタント|ディレクター|プロデューサー|担当|CEO|CTO|CFO|COO|President|Director|Manager|Engineer');
// 建設業許可 / 宅建業免許: issuer, (特|般)-renewal count, number. The 宅建
// form has only the count in parentheses, so it never matches a 許可 line.
const _issuer = r'(国土交通大臣|[一-龥]{2,3}[都道府県]?知事)';
// 許可 may sit only in the label ("建設業許可 東京都知事（般-5）…"), so it is
// optional here; (特|般) keeps the 宅建 form from matching.
final _constr = RegExp(
    '$_issuer\\s*(?:許可)?\\s*\\(?\\s*(特|般)\\s*[-−‐ー]?\\s*(\\d{1,2})\\s*\\)?\\s*第?\\s*(\\d+)\\s*号?');
final _takken = RegExp('$_issuer\\s*(?:免許)?\\s*\\(\\s*(\\d{1,2})\\s*\\)\\s*第?\\s*(\\d+)\\s*号?');
// 法人番号 is 13 digits; the invoice registration number is T + the same 13.
final _corpNo = RegExp(r'(?<![\dA-Za-z])T?(\d{13})(?!\d)');
final _qual = RegExp(
    r'[12一二]級\s*(?:建築|土木|電気工事|管工事|造園|建設機械|電気通信工事)\s*施工管理技士補?'
    // "一級建築士事務所" is a company type, not a person's qualification.
    r'|[12一二]級建築士(?!事務所)|木造建築士(?!事務所)|宅地建物取引士|技術士補?|測量士補?|建築設備士|[12一二]級[^\s・/,、]{1,8}技能士');
final _licenseWords =
    RegExp(r'建設業許可|許可番号|宅地建物取引業者?(?:免許)?|宅建業免許|免許番号|法人番号|登録番号|適格請求書発行事業者');
final _deptSuffix = r'本部|事業部|支店|営業所|部|課|室|係|グループ|チーム|センター|研究所';
final _dept = RegExp('($_deptSuffix)\$');
final _deptAny = RegExp('($_deptSuffix)');
final _prefecture = RegExp(r'^(東京都|北海道|京都府|大阪府|.{2,3}県)');
final _kanaOnly = RegExp(r'^[぀-ゟ゠-ヿ\s]+$');
final _latinOnly = RegExp(r"^[A-Za-z .\-']+$");
final _cjk = RegExp(r'[぀-ヿ一-鿿]');
final _digit = RegExp(r'\d');

/// True when most multi-character lines are taller than wide, i.e. ML Kit
/// returned vertical (縦書き) columns as single "lines". Field accuracy on
/// such cards is low (digits in a column come back as garbage), so callers
/// should flag the card for manual review rather than trust the fields.
bool isVertical(List<OcrLine> lines) {
  final multi = lines.where((l) => l.text.trim().length >= 3).toList();
  if (multi.length < 2) return false;
  final tall = multi.where((l) => l.height > 1.5 * l.width).length;
  return tall * 2 >= multi.length;
}

/// Core fields a usable contact needs; empty list = nothing to review.
List<String> missingCore(CardFields f) => [
      if (f.name == null) 'name',
      if (f.company == null) 'company',
      if (f.phone == null && f.mobile == null) 'phone',
      if (f.email == null) 'email',
    ];

class _L {
  final OcrLine src;
  final bool front;
  String rest;
  bool used = false;
  _L(this.src, this.front) : rest = normalize(src.text);
  double get h => src.height;
}

/// Extracts card fields from the front (Japanese model) and optional back
/// (Latin model) OCR lines.
///
/// Order matters: machine-readable patterns first (they are unambiguous and
/// their removal shrinks the pool), then keyword lines, then "the biggest
/// remaining text is the name", which is the single most reliable rule on
/// Japanese cards.
CardFields extract(List<OcrLine> front,
        {List<OcrLine> back = const [], Learned? learned}) =>
    extractWith(front, back, learned);

/// [learned] adds the user's corrections: remembered lines, extra title /
/// department words, and character fixes (see learned.dart).
CardFields extractWith(List<OcrLine> front, List<OcrLine> back, Learned? learned) {
  final f = CardFields();
  final titleRe = _withTerms(_title, learned?.terms['title']);
  final deptLearned = learned?.terms['dept'].orEmpty ?? const <String>[];
  final pool = [
    for (final l in front) _L(l, true),
    for (final l in back) _L(l, false),
  ];

  // 1. Patterns: email, url, postal, phone/fax/mobile.
  _L? postalLine;
  for (final l in pool) {
    // ML Kit's Japanese model emits "taro. yamada@sunr ise. co. jp" (spaces
    // after dots, and inside words on photos). An address/URL never contains
    // whitespace, so drop the labels and then every space on such lines.
    // ponytail: '@' read as 'ê' on a dark card; fix only inside an email shape.
    l.rest = l.rest.replaceAllMapped(
        RegExp(r'([\w.+-]+)\s*[êéè]\s*([\w-]+(?:\.\s*[\w-]+)+)'),
        (m) => '${m[1]}@${m[2]}');
    if (l.rest.contains('@') || _url.hasMatch(l.rest)) {
      l.rest = l.rest.replaceAll(_label, '').replaceAll(RegExp(r'\s+'), '');
    }
    // Trade licences, corporate number and qualifications come before the
    // phone rule: their digits must never be read as numbers to call.
    final cm = _constr.firstMatch(l.rest);
    if (cm != null) {
      f.constructionLicense ??= '${cm[1]}許可(${cm[2]}-${cm[3]})第${cm[4]}号';
      l.rest = l.rest.replaceFirst(_constr, '');
    }
    final tm = _takken.firstMatch(l.rest);
    if (tm != null) {
      f.realEstateLicense ??= '${tm[1]}(${tm[2]})第${tm[3]}号';
      l.rest = l.rest.replaceFirst(_takken, '');
    }
    // Not on a URL line: a 13-digit path segment is part of the URL.
    final nm = _url.hasMatch(l.rest) ? null : _corpNo.firstMatch(l.rest);
    if (nm != null) {
      f.corpNo ??= nm[1];
      l.rest = l.rest.replaceFirst(_corpNo, '');
    }
    for (final m in _qual.allMatches(l.rest)) {
      final q = m[0]!
          .replaceAll(RegExp(r'\s'), '')
          .replaceFirst(RegExp('^一'), '1')
          .replaceFirst(RegExp('^二'), '2');
      final have = f.qualifications?.split(' / ') ?? const [];
      if (!have.contains(q)) f.qualifications = [...have, q].join(' / ');
    }
    l.rest = l.rest.replaceAll(_qual, '').replaceAll(_licenseWords, '');
    // "FAX: 019-62 3-1235": on labelled phone lines a space between digits is noise.
    if (RegExp(r'TEL|FAX|PHONE|MOBILE|電話|携帯', caseSensitive: false).hasMatch(l.rest)) {
      l.rest = l.rest.replaceAllMapped(RegExp(r'(\d)\s+(?=[\d-])'), (m) => m[1]!);
    }
    for (final m in _email.allMatches(l.rest)) {
      f.email ??= m[0]!.toLowerCase();
    }
    l.rest = l.rest.replaceAll(_email, '');
    for (final m in _url.allMatches(l.rest)) {
      // ponytail: lowercasing the path too; fine for business-card URLs.
      f.url ??= m[0]!.toLowerCase();
    }
    l.rest = l.rest.replaceAll(_url, '');
    final pm = _postal.firstMatch(l.rest) ?? _postalBare.firstMatch(l.rest);
    if (pm != null) {
      f.postal ??= '${pm[1]}-${pm[2]}';
      postalLine ??= l;
      l.rest = l.rest.replaceAll(_postal, '').replaceAll(_postalBare, '');
    }
    l.rest = l.rest.replaceAll(_intl, '0');
    var cursor = 0;
    for (final m in _phone.allMatches(l.rest)) {
      final digits = '${m[1]}${m[2]}${m[3]}';
      if (digits.length < 10 || digits.length > 11) continue;
      final label = l.rest.substring(cursor, m.start);
      cursor = m.end;
      final num = '${m[1]}-${m[2]}-${m[3]}';
      if (_fax.hasMatch(label)) {
        f.fax ??= num;
      } else if (RegExp(r'^0[789]0').hasMatch(num)) {
        f.mobile ??= num;
      } else {
        f.phone ??= num;
      }
    }
    // "Mobi le" -> "Mobile" before label removal, or the fragment survives as
    // a Latin line and gets picked as the roman name.
    l.rest = fixRomanSpacing(l.rest.replaceAll(_phone, '')).replaceAll(_label, '');
    l.rest = normalize(l.rest).replaceAll(RegExp(r'^[:\s/|・、,]+|[:\s/|・、,]+$'), '');
    if (l.rest.isEmpty) l.used = true;
  }

  // 1b. Line memory: lines the user previously moved into a field go there
  //     before any heuristic can misplace them.
  if (learned != null) {
    final taken = <String>{};
    for (final l in pool.where((l) => !l.used)) {
      final k = learned.fieldFor(l.rest);
      if (k != null && !taken.contains(k)) {
        f.set(k, l.rest);
        taken.add(k);
        l.used = true;
      }
    }
  }

  // 2. Address: the postal line's remainder plus the following line, or a
  //    line that starts with a prefecture.
  // ponytail: one-line lookahead; add building/floor detection if golden
  // cards show addresses wrapping over 3+ lines.
  final frontLines = pool.where((l) => l.front).toList();
  _L? seed = postalLine ??
      frontLines.cast<_L?>().firstWhere(
          (l) => !l!.used && _prefecture.hasMatch(l.rest),
          orElse: () => null);
  if (seed != null) {
    final parts = <String>[seed.rest];
    seed.used = true;
    final i = pool.indexOf(seed);
    if (i + 1 < pool.length) {
      final next = pool[i + 1];
      if (!next.used &&
          next.front == seed.front &&
          !_company.hasMatch(next.rest) &&
          !_title.hasMatch(next.rest) &&
          !_kanaOnly.hasMatch(next.rest)) {
        parts.add(next.rest);
        next.used = true;
      }
    }
    f.address = parts.where((p) => p.isNotEmpty).join(' ');
    if (f.address!.isEmpty) f.address = null;
  }

  // 3. Keyword lines on the front: company (prefer the Japanese line when a
  //    card carries both "NEXTWAVE Inc." and "ネクストウェーブ株式会社"),
  //    then title / department tokens.
  final companyLines =
      frontLines.where((l) => !l.used && _company.hasMatch(l.rest)).toList();
  final companyLine = companyLines.cast<_L?>().firstWhere(
      (l) => _cjk.hasMatch(l!.rest),
      orElse: () => companyLines.isEmpty ? null : companyLines.first);
  if (f.company == null && companyLine != null) {
    f.company = companyLine.rest;
    companyLine.used = true;
  }
  void addTitle(String t) => f.title = f.title == null ? t : '${f.title} $t';
  void addDept(String t) => f.dept = f.dept == null ? t : '${f.dept} $t';
  for (final l in frontLines.where((l) => !l.used)) {
    final tokens = l.rest.split(' ');
    final leftover = <String>[];
    for (final t in tokens) {
      final tm = titleRe.firstMatch(t);
      if (tm != null) {
        // OCR drops the space in "営業課 課長" / "開発本部 シニアエンジニア":
        // split at the last department suffix before the title word.
        final prefix = t.substring(0, tm.start);
        final dm = _deptAny.allMatches(prefix).lastOrNull;
        if (dm != null) {
          addDept(prefix.substring(0, dm.end));
          addTitle(t.substring(dm.end));
        } else {
          addTitle(t);
        }
      } else if (_dept.hasMatch(t) || deptLearned.contains(t)) {
        addDept(t);
      } else {
        leftover.add(t);
      }
    }
    if (leftover.length < tokens.length) {
      l.rest = leftover.join(' ');
      if (l.rest.isEmpty) l.used = true;
    }
  }

  // 4. Name = tallest remaining CJK line on the front. Kana-only line = reading.
  final remaining = frontLines.where((l) => !l.used).toList();
  _L? tallest(Iterable<_L> xs) =>
      xs.isEmpty ? null : xs.reduce((a, b) => b.h > a.h ? b : a);
  final nameLine = f.name != null
      ? null
      : tallest(remaining.where((l) =>
          _cjk.hasMatch(l.rest) &&
          !_kanaOnly.hasMatch(l.rest) &&
          !_digit.hasMatch(l.rest)));
  if (nameLine != null) {
    // Tilted shots sometimes end the name with a stray '、' or '.'.
    f.name = nameLine.rest.replaceAll(RegExp(r'[、。,.・:;]+$'), '').trim();
    nameLine.used = true;
    final kana = tallest(remaining.where(
        (l) => !l.used && _kanaOnly.hasMatch(l.rest) && l.h < nameLine.h));
    if (kana != null) {
      f.nameKana = kana.rest;
      kana.used = true;
    }
  }

  // ponytail: company without a 株式会社-style keyword = tallest remaining CJK
  // line that is not the name. Replace with a logo/position heuristic if the
  // golden set shows this picking departments.
  f.company ??= tallest(remaining.where(
          (l) => !l.used && _cjk.hasMatch(l.rest) && !_digit.hasMatch(l.rest)))
      ?.rest;

  // 5. Roman name: tallest Latin-only line on the back, else on the front,
  //    skipping company-looking lines.
  // A romanised person name has lower-case letters ("Taro Yamada",
  // "SUZUKI Ichiro"); an all-caps Latin line is a logo or company name
  // (seen on a real card: "PINES DIRECT" landed in nameRoman).
  bool roman(_L l) =>
      !l.used &&
      _latinOnly.hasMatch(l.rest) &&
      !_company.hasMatch(l.rest) &&
      RegExp(r'[a-z]').hasMatch(l.rest);
  final romanLine =
      tallest(pool.where((l) => !l.front && roman(l))) ?? tallest(remaining.where(roman));
  if (romanLine != null) f.nameRoman = fixRomanSpacing(romanLine.rest);

  // 6. Learned character confusions on the free-text fields.
  if (learned != null) {
    if (f.name != null) f.name = learned.fix(f.name!);
    if (f.company != null) f.company = learned.fix(f.company!);
  }
  return f;
}

RegExp _withTerms(RegExp base, List<String>? terms) => terms == null || terms.isEmpty
    ? base
    : RegExp('${base.pattern}|${terms.map(RegExp.escape).join('|')}');

extension on List<String>? {
  List<String> get orEmpty => this ?? const [];
}
