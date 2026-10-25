/// Japanese address split into the parts the review form shows separately
/// (都道府県 / 市区町村 / 町名・丁目 / 番地・号 / 建物名 / 号室・階). The full
/// `address` string stays the source of truth for contacts and notes; these
/// parts are derived from it and joined back when edited.
library;

const prefectures = [
  '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
  '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
  '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県',
  '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県',
  '鳥取県', '島根県', '岡山県', '広島県', '山口県',
  '徳島県', '香川県', '愛媛県', '高知県',
  '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
];

typedef AddressParts = ({
  String? pref,
  String? city,
  String? town,
  String? block,
  String? building,
  String? room,
});

const _empty = (pref: null, city: null, town: null, block: null, building: null, room: null);

// ponytail: 市+区, then 郡+町村 (not when 郡 is part of a city name such as
// 蒲郡市 / 大和郡山市), else the first 市区町村 (lazy, so 市川市 and 町田市 come
// out whole). Known misses: 四日市市 -> 四日市, 大町市 -> 大町, 杵島郡大町町 ->
// 杵島郡大町. Only the 市区 tag is affected; the address text stays intact.
final _city = RegExp(r'^(.{1,6}?市.{1,6}?区|[^市]{1,6}?郡(?!市)[^市]{1,6}?[町村]|.{1,6}?[市区町村])');
// Town: up to and including N丁目 when it comes before any space (a building
// name may contain 丁目 too), else the run before the first digit.
final _town = RegExp(r'^([^\s]*?\d+丁目|[^\d\s]+)');
final _block = RegExp(r'^\s*(\d+(?:[-−‐]\d+)*(?:番地?\d*号?)?)');
final _room = RegExp(r'\s*(B?\d+F|\d+階|\d+号室)$');

String? _nz(String? s) => s == null || s.isEmpty ? null : s;

AddressParts splitAddress(String? address) {
  var s = (address ?? '').trim();
  if (s.isEmpty) return _empty;
  String? pref;
  for (final p in prefectures) {
    if (s.startsWith(p)) {
      pref = p;
      s = s.substring(p.length);
      break;
    }
  }
  String? take(RegExp re) {
    final m = re.firstMatch(s);
    if (m == null) return null;
    s = s.substring(m.end);
    return m[1];
  }
  final city = take(_city);
  final town = take(_town);
  final block = take(_block);
  s = s.trim();
  final rm = _room.firstMatch(s);
  final room = rm?[1];
  if (rm != null) s = s.substring(0, rm.start).trim();
  return (pref: pref, city: city, town: town, block: block, building: _nz(s), room: room);
}

/// Inverse of [splitAddress]: `都道府県市区町村町名番地 建物名号室`.
String joinAddress(AddressParts p) {
  final head = [p.pref, p.city, p.town, p.block].whereType<String>().join('');
  final tail = [p.building, p.room].whereType<String>().join('');
  return [head, tail].where((x) => x.isNotEmpty).join(' ');
}
