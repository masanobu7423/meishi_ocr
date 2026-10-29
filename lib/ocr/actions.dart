/// Where a saved card can take you: phone, mobile, mail, web, map.
/// Pure: builds URIs from the field values; the screen launches them.
class ContactAction {
  final String key, label;
  final Uri uri;
  const ContactAction(this.key, this.label, this.uri);
}

List<ContactAction> contactActions(Map<String, String?> f) {
  String? v(String k) {
    final s = f[k]?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  Uri tel(String s) => Uri(scheme: 'tel', path: s.replaceAll(RegExp(r'[^\d+]'), ''));
  final url = v('url');
  final address = v('address');
  return [
    if (v('phone') != null) ContactAction('phone', '電話', tel(v('phone')!)),
    if (v('mobile') != null) ContactAction('mobile', '携帯', tel(v('mobile')!)),
    if (v('email') != null) ContactAction('email', 'メール', Uri(scheme: 'mailto', path: v('email'))),
    if (url != null)
      ContactAction('url', 'ウェブ',
          Uri.parse(RegExp(r'^https?://', caseSensitive: false).hasMatch(url) ? url : 'https://$url')),
    if (address != null)
      ContactAction('address', '地図', Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}')),
  ];
}

/// The one-tap call from a list row: the mobile first (site people answer
/// it), else the office line; null when the card has neither.
ContactAction? quickCall({String? phone, String? mobile}) {
  final a = contactActions({'phone': phone, 'mobile': mobile});
  return a.where((x) => x.key == 'mobile').firstOrNull ?? a.firstOrNull;
}
