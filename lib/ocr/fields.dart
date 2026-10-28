// The form's field table: labels and order, shared with the CSV export
// (pure Dart, no widgets). DESIGN.md §7: the keys never reach the screen.

/// User-facing labels for CardFields keys (DESIGN.md §7: never show the keys).
const fieldLabels = <String, String>{
  'name': '氏名',
  'nameKana': 'ふりがな',
  'nameRoman': 'ローマ字',
  'company': '会社',
  'division': '部門',
  'dept': '部署',
  'title': '役職',
  'job': '職種',
  'trust': '信頼度',
  'nextContact': '次回連絡日',
  'phone': '電話',
  'mobile': '携帯',
  'fax': 'FAX',
  'email': 'メール',
  'url': 'URL',
  'postal': '郵便番号',
  'address': '住所',
  'corpNo': '法人番号',
  'constructionLicense': '建設業許可',
  'realEstateLicense': '宅建業免許',
  'qualifications': '資格',
  'category': '区分',
  'related': '関係者',
  'memo': 'メモ（会った場所・日付など）',
};

/// Fields in the order a person reads a card: who, where, how to reach,
/// the trade data printed small at the bottom, then the user's own tags.
const fieldOrder = [
  'name', 'nameKana', 'company', 'division', 'dept', 'title', 'job',
  'phone', 'mobile', 'email', 'postal', 'address', 'fax', 'url',
  'corpNo', 'constructionLicense', 'realEstateLicense', 'qualifications',
  'category', 'trust', 'nextContact', 'related', 'nameRoman', 'memo',
];
