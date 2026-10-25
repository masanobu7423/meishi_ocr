import 'package:flutter_contacts/flutter_contacts.dart';

import 'contact_mapper.dart';
import 'extractor.dart';

/// One field compared between an existing contact and the scanned card.
class DiffRow {
  final String key, label;
  final String? existing, card;
  final bool same;
  const DiffRow(this.key, this.label, this.existing, this.card, this.same);
}

const _labels = {
  'name': '氏名',
  'company': '会社',
  'dept': '部署',
  'title': '役職',
  'phone': '電話',
  'mobile': '携帯',
  'fax': 'FAX',
  'email': 'メール',
  'url': 'URL',
  'address': '住所',
};

String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// The existing contact's values in CardFields terms (first of each kind).
Map<String, String?> _existingValues(Contact c) {
  final n = c.name;
  String? phoneOf(bool Function(PhoneLabel) pick) => c.phones
      .cast<Phone?>()
      .firstWhere((p) => pick(p!.label.label), orElse: () => null)
      ?.number;
  final org = c.organizations.isEmpty ? null : c.organizations.first;
  final adr = c.addresses.isEmpty ? null : c.addresses.first;
  return {
    'name': _blank(c.displayName) ??
        _blank([n?.last, n?.first].whereType<String>().where((s) => s.isNotEmpty).join(' ')),
    'company': _blank(org?.name),
    'dept': _blank(org?.departmentName),
    'title': _blank(org?.jobTitle),
    'phone': phoneOf((l) => l != PhoneLabel.mobile && l != PhoneLabel.workFax && l != PhoneLabel.homeFax && l != PhoneLabel.otherFax),
    'mobile': phoneOf((l) => l == PhoneLabel.mobile || l == PhoneLabel.workMobile),
    'fax': phoneOf((l) => l == PhoneLabel.workFax || l == PhoneLabel.homeFax || l == PhoneLabel.otherFax),
    'email': c.emails.isEmpty ? null : c.emails.first.address,
    'url': c.websites.isEmpty ? null : c.websites.first.url,
    // Street only: the card's address field has no postal code either.
    'address': _blank(adr?.street),
  };
}

bool _sameValue(String key, String? a, String? b) {
  if (a == null || b == null) return a == b;
  switch (key) {
    case 'phone':
    case 'mobile':
    case 'fax':
      return phoneDigits(a) == phoneDigits(b);
    case 'email':
    case 'url':
      return a.toLowerCase() == b.toLowerCase();
    default:
      return normalize(a).replaceAll(' ', '') == normalize(b).replaceAll(' ', '');
  }
}

/// Field-by-field comparison; rows empty on both sides are dropped.
List<DiffRow> contactDiff(Contact existing, CardFields card) {
  final ev = _existingValues(existing);
  final cv = card.toJson();
  return [
    for (final e in _labels.entries)
      if (_blank(ev[e.key]) != null || _blank(cv[e.key]) != null)
        DiffRow(e.key, e.value, _blank(ev[e.key]), _blank(cv[e.key]),
            _sameValue(e.key, _blank(ev[e.key]), _blank(cv[e.key]))),
  ];
}

/// The existing contact updated from the card. Single-valued fields take
/// the card's value when the key is in [useCard] or the existing value is
/// empty; multi-valued ones (phones, emails, websites, addresses) are the
/// union without duplicates; notes are concatenated.
Contact mergeContact(Contact existing, CardFields card,
    {required Set<String> useCard, required DateTime scannedAt}) {
  final ev = _existingValues(existing);
  final cv = card.toJson();
  String? pick(String key) =>
      (useCard.contains(key) || _blank(ev[key]) == null) ? _blank(cv[key]) ?? _blank(ev[key]) : _blank(ev[key]);

  final fromCard = toContact(card, scannedAt: scannedAt);

  final name = pick('name');
  final parts = (name ?? '').trim().split(RegExp(r'\s+'));
  final keepName = !useCard.contains('name') && _blank(ev['name']) != null;

  final org = existing.organizations.isEmpty ? Organization() : existing.organizations.first;
  final mergedOrg = org.copyWith(
    name: pick('company'),
    departmentName: pick('dept'),
    jobTitle: pick('title'),
  );

  List<T> union<T>(List<T> a, List<T> b, String Function(T) key) {
    final seen = a.map(key).toSet();
    return [...a, for (final x in b) if (seen.add(key(x))) x];
  }

  final noteText = [
    ...existing.notes.map((n) => n.note),
    ...fromCard.notes.map((n) => n.note),
  ].where((s) => s.trim().isNotEmpty).join('\n');

  return existing.copyWith(
    name: keepName
        ? existing.name
        : Name(
            last: parts.first,
            first: parts.length > 1 ? parts.sublist(1).join(' ') : null,
            phoneticLast: fromCard.name?.phoneticLast ?? existing.name?.phoneticLast,
            phoneticFirst: fromCard.name?.phoneticFirst ?? existing.name?.phoneticFirst,
          ),
    phones: union(existing.phones, fromCard.phones, (p) => phoneDigits(p.number)),
    emails: union(existing.emails, fromCard.emails, (e) => e.address.toLowerCase()),
    websites: union(existing.websites, fromCard.websites, (w) => w.url.toLowerCase()),
    addresses: union(existing.addresses, fromCard.addresses, (a) => normalize(a.street ?? '')),
    organizations: [mergedOrg],
    notes: noteText.isEmpty ? const [] : [Note(note: noteText)],
  );
}
