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

/// Fields that can hold several values on a contact.
const multiValued = {'phone', 'mobile', 'fax', 'email', 'url', 'address'};

/// What a field will hold after the merge, for the preview line.
/// [useCard]: take the card's value. [keepExisting]: for multi-valued fields,
/// also keep the contact's current value (ignored for single-valued ones).
String mergedPreview(DiffRow r, {required bool useCard, required bool keepExisting}) {
  if (r.same) return r.existing ?? r.card ?? '—';
  final values = <String>[];
  if (multiValued.contains(r.key)) {
    if ((!useCard || keepExisting) && r.existing != null) values.add(r.existing!);
    if (useCard && r.card != null) values.add(r.card!);
  } else {
    final v = useCard ? (r.card ?? r.existing) : r.existing;
    if (v != null) values.add(v);
  }
  return values.isEmpty ? '—' : values.join(' / ');
}

/// The existing contact updated from the card.
/// - single-valued fields (name, company, dept, title): the card's value
///   when the key is in [useCard] or the existing value is empty;
/// - multi-valued fields: the card's value only when chosen; the existing
///   value stays unless the key was dropped from [keepExisting]
///   (default: keep everything); duplicates folded;
/// - notes concatenated.
Contact mergeContact(Contact existing, CardFields card,
    {required Set<String> useCard, Set<String>? keepExisting, required DateTime scannedAt}) {
  final keep = keepExisting ?? multiValued;
  final ev = _existingValues(existing);
  final cv = card.toJson();
  String? pick(String key) =>
      (useCard.contains(key) || _blank(ev[key]) == null) ? _blank(cv[key]) ?? _blank(ev[key]) : _blank(ev[key]);

  final fromCard = toContact(card, scannedAt: scannedAt);

  String phoneKind(Phone p) {
    final l = p.label.label;
    if (l == PhoneLabel.mobile || l == PhoneLabel.workMobile) return 'mobile';
    if (l == PhoneLabel.workFax || l == PhoneLabel.homeFax || l == PhoneLabel.otherFax) return 'fax';
    return 'phone';
  }

  /// Existing values of [kind] (unless dropped) + card values (if chosen), deduped.
  List<T> combine<T>(String kind, List<T> ex, List<T> fromCardList, String Function(T) key) {
    final out = <T>[];
    final seen = <String>{};
    void addAll(Iterable<T> xs) {
      for (final x in xs) {
        if (seen.add(key(x))) out.add(x);
      }
    }
    if (!useCard.contains(kind) || keep.contains(kind)) addAll(ex);
    if (useCard.contains(kind)) addAll(fromCardList);
    return out;
  }

  final phones = <Phone>[
    for (final kind in ['phone', 'mobile', 'fax'])
      ...combine(
        kind,
        existing.phones.where((p) => phoneKind(p) == kind).toList(),
        fromCard.phones.where((p) => phoneKind(p) == kind).toList(),
        (p) => phoneDigits(p.number),
      ),
  ];

  final name = pick('name');
  final parts = (name ?? '').trim().split(RegExp(r'\s+'));
  final keepName = !useCard.contains('name') && _blank(ev['name']) != null;

  final org = existing.organizations.isEmpty ? Organization() : existing.organizations.first;
  final mergedOrg = org.copyWith(
    name: pick('company'),
    departmentName: pick('dept'),
    jobTitle: pick('title'),
  );

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
    phones: phones,
    emails: combine('email', existing.emails, fromCard.emails, (e) => e.address.toLowerCase()),
    websites: combine('url', existing.websites, fromCard.websites, (w) => w.url.toLowerCase()),
    addresses: combine('address', existing.addresses, fromCard.addresses, (a) => normalize(a.street ?? '')),
    organizations: [mergedOrg],
    notes: noteText.isEmpty ? const [] : [Note(note: noteText)],
  );
}
