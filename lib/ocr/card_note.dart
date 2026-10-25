import 'address.dart';
import 'card_status.dart';
import 'extractor.dart';
import 'vault_index.dart' show splitNames;

/// Obsidian-style note for one card, in the same dialect FastaLife's vault
/// parser (ObsidianEngine) reads: flat `key: value` frontmatter, `tags: [..]`
/// on one line, inline `#tag` without `/` (nested tags are not parsed there),
/// and `[[wiki links]]` for the entities worth a backlink graph.

final _tagBad = RegExp(r'[^\w぀-ゟ゠-ヿ一-鿿-]');
final _corp = RegExp(r'株式会社|有限会社|合同会社|\(株\)|㈱|Co\.,? ?Ltd\.?|Inc\.?|Corp(?:oration)?\.?|LLC|K\.K\.',
    caseSensitive: false);

/// `#tag`-safe: anything outside letters/kana/kanji/digits/-/_ becomes `_`.
String tagify(String s) =>
    normalize(s).replaceAll(_tagBad, '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');

/// Coarse job category from department/title words; first match wins.
/// ponytail: regex table; extend from real golden cards rather than guessing.
String? jobCategory(String? dept, String? title) {
  final s = '${dept ?? ''} ${title ?? ''}';
  const table = <String, String>{
    // Management first (a trade company's president is 経営), then the
    // construction trades (the audience): a word names its trade.
    '代表|取締役|社長|会長|役員|CEO|CTO|CFO|COO|President': '経営',
    '鳶|とび': '鳶', '足場': '足場', '鉄筋': '鉄筋', '型枠': '型枠', '大工': '大工', '左官': '左官',
    '鉄骨': '鉄骨', '溶接': '溶接', '土木': '土木', '舗装': '舗装', '解体': '解体', '重機|クレーン': '重機',
    '電気': '電気', '配管': '配管', '空調': '空調', '設備|給排水': '設備', '塗装': '塗装', '防水': '防水',
    '内装': '内装', '板金': '板金', '屋根|瓦': '屋根', '測量': '測量',
    '施工|現場|工事|監督|工務': '施工管理', '設計|建築士|意匠|構造': '設計', '不動産|宅建|仲介': '不動産',
    '営業': '営業', '販売|店': '販売', '開発|エンジニア|技術|システム|SE|IT': '技術開発',
    '製造|工場|生産': '製造', '人事|総務|経理|財務|法務|管理': '管理',
    'マーケ|広報|宣伝|PR': 'マーケティング', '企画': '企画', 'デザイン|Design': 'デザイン',
    'コンサル': 'コンサルティング', '研究|R&D': '研究', '購買|調達': '調達', '医|看護|薬': '医療',
  };
  for (final e in table.entries) {
    if (RegExp(e.key).hasMatch(s)) return e.value;
  }
  return null;
}

/// The job to show: the user's own, else the dept/title heuristic.
String? defaultJob(CardFields f) => f.job ?? jobCategory(f.dept, f.title);

String _ymd(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// A name as a file stem (FastaLife's sanitizer set); `名無し` when empty.
String safeFileStem(String? name) {
  final s = (name ?? '').replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  return s.isEmpty ? '名無し' : s;
}

/// Safe vault filename: `<name>_<yyyy-mm-dd>.md`.
String cardNoteFilename(CardFields f, DateTime scannedAt) => '${safeFileStem(f.name)}_${_ymd(scannedAt)}.md';

/// [images] maps 'front' / 'back' to paths relative to the vault root
/// (e.g. `images/c1_front.jpg`); they become Obsidian embeds.
String cardNoteMarkdown(CardFields f,
    {required DateTime scannedAt,
    bool vertical = false,
    String? source,
    Map<String, String> images = const {},
    CardStatus status = CardStatus.reviewed}) {
  final addr = splitAddress(f.address);
  final pref = addr.pref;
  final city = addr.city;
  final quals = splitNames(f.qualifications);
  final related = splitNames(f.related);
  final job = defaultJob(f);
  final companyShort = f.company?.replaceAll(_corp, '').trim();
  final areaCode = (f.phone ?? f.fax)?.split('-').first;
  final domain = f.email?.split('@').last;

  final tags = <String>[
    '名刺',
    if (companyShort != null && companyShort.isNotEmpty) '会社_${tagify(companyShort)}',
    if (job != null) '職種_$job',
    if (f.title != null) '役職_${tagify(f.title!)}',
    if (f.dept != null) '部署_${tagify(f.dept!)}',
    if (f.category != null) '区分_${tagify(f.category!)}',
    if (f.trust != null) '信頼度_${tagify(f.trust!)}',
    if (f.division != null) '部門_${tagify(f.division!)}',
    for (final q in quals) '資格_${tagify(q)}',
    for (final r in related) '関係者_${tagify(r)}',
    if (pref != null) '地域_$pref',
    if (city != null) '市区_${tagify(city)}',
    if (areaCode != null) '市外局番_$areaCode',
    if (domain != null) 'ドメイン_${tagify(domain)}',
    '取込_${_ymd(scannedAt).substring(0, 7)}',
    if (vertical) '縦書き',
  ];

  String fm(String k, String? v) => v == null || v.isEmpty ? '' : '$k: $v\n';
  final b = StringBuffer()
    ..write('---\n')
    ..write('type: meishi\n')
    ..write(fm('name', f.name))
    ..write(fm('kana', f.nameKana))
    ..write(fm('roman', f.nameRoman))
    ..write(fm('company', f.company))
    ..write(fm('dept', f.dept))
    ..write(fm('title', f.title))
    ..write(fm('job', job))
    ..write(fm('phone', f.phone))
    ..write(fm('mobile', f.mobile))
    ..write(fm('fax', f.fax))
    ..write(fm('email', f.email))
    ..write(fm('url', f.url))
    ..write(fm('postal', f.postal))
    ..write(fm('pref', pref))
    ..write(fm('city', city))
    ..write(fm('town', addr.town))
    ..write(fm('block', addr.block))
    ..write(fm('building', addr.building))
    ..write(fm('room', addr.room))
    ..write(fm('address', f.address))
    ..write(fm('memo', f.memo))
    ..write(fm('corp_no', f.corpNo))
    ..write(fm('construction_license', f.constructionLicense))
    ..write(fm('real_estate_license', f.realEstateLicense))
    ..write(fm('qualifications', f.qualifications))
    ..write(fm('division', f.division))
    ..write(fm('category', f.category))
    ..write(fm('related', f.related))
    ..write(fm('trust', f.trust))
    ..write(fm('contact_id', f.contactId))
    ..write('scanned: ${_ymd(scannedAt)}\n')
    ..write('vertical: $vertical\n')
    ..write('status: ${status.label}\n')
    ..write(fm('source', source))
    ..write(fm('image_front', images['front']))
    ..write(fm('image_back', images['back']))
    ..write('tags: [${tags.join(', ')}]\n')
    ..write('---\n')
    ..write('# ${f.name ?? '名無し'}\n\n');
  if (f.nameKana != null || f.nameRoman != null) {
    b.write('- 読み: ${[f.nameKana, f.nameRoman].whereType<String>().join(' / ')}\n');
  }
  if (f.company != null) b.write('- 会社: [[${f.company}]]\n');
  if (f.dept != null || f.title != null) {
    b.write('- 部署/役職: ${[f.dept, f.title].whereType<String>().join(' ')}\n');
  }
  if (job != null) b.write('- 職種: [[職種_$job]]\n');
  if (f.division != null) b.write('- 部門: ${f.division}\n');
  if (f.category != null) b.write('- 区分: [[区分_${tagify(f.category!)}]]\n');
  if (f.trust != null) b.write('- 信頼度: [[信頼度_${tagify(f.trust!)}]]\n');
  if (related.isNotEmpty) b.write('- 関係者: ${related.map((r) => '[[$r]]').join(', ')}\n');
  final phones = [
    if (f.phone != null) 'TEL ${f.phone}',
    if (f.mobile != null) '携帯 ${f.mobile}',
    if (f.fax != null) 'FAX ${f.fax}',
  ];
  if (phones.isNotEmpty) b.write('- 電話: ${phones.join(' / ')}\n');
  if (f.email != null) b.write('- メール: ${f.email}\n');
  if (f.url != null) b.write('- URL: ${f.url}\n');
  if (f.address != null) {
    final rest = pref == null ? f.address! : f.address!.substring(pref.length);
    b.write('- 住所: ${f.postal == null ? '' : '〒${f.postal} '}'
        '${pref == null ? '' : '[[$pref]]'}$rest\n');
  }
  if (f.constructionLicense != null) b.write('- 建設業許可: ${f.constructionLicense}\n');
  if (f.realEstateLicense != null) b.write('- 宅建業免許: ${f.realEstateLicense}\n');
  if (f.corpNo != null) b.write('- 法人番号: ${f.corpNo}\n');
  if (f.qualifications != null) b.write('- 資格: ${f.qualifications}\n');
  if (f.memo != null) b.write('- メモ: ${f.memo}\n');
  if (images.isNotEmpty) {
    b.write('\n');
    for (final side in ['front', 'back']) {
      if (images[side] != null) b.write('![[${images[side]}]]\n');
    }
  }
  b
    ..write('\n')
    ..write(tags.map((t) => '#$t').join(' '))
    ..write('\n');
  return b.toString();
}
