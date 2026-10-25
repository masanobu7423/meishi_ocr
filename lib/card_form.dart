import 'package:flutter/material.dart';

import 'ocr/address.dart';
import 'ocr/extractor.dart';
import 'ocr/jobs.dart';
import 'ocr/ocr_line.dart';
import 'ocr/vault_index.dart' show splitNames;
import 'theme.dart';

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
  'category', 'trust', 'related', 'nameRoman', 'memo',
];

/// 区分 choices. Values typed by hand or used before are offered too.
/// 信頼度 scale; stored as the digit so Obsidian can sort on it.
const trustLevels = ['1', '2', '3', '4', '5'];

const categoryChoices = ['元請', '下請', '協力会社', '取引先', '顧客', '設計事務所', '官公庁', 'その他'];

/// Comma-separated multi-value fields: a suggestion chip appends.
const listFields = {'related', 'qualifications'};

const _partLabels = {
  'pref': '都道府県',
  'city': '市区町村',
  'town': '町名・丁目',
  'block': '番地・号',
  'building': '建物名',
  'room': '号室・階',
};

/// The review form: one text field per card field (区分 and 都道府県 are
/// dropdowns, the address also edits as parts), the OCR lines as chips that
/// drop into whichever field was last focused, and previously used values
/// as chips under the list fields. Pure UI, no IO, so it is widget-testable
/// without plugins.
class CardForm extends StatefulWidget {
  final Map<String, TextEditingController> controllers;
  final List<OcrLine> lines;
  final Set<String> missing;
  final Map<String, List<String>> suggestions;
  /// 職種 choices (the user's list); values already in use are appended.
  final List<String> jobs;
  /// Scrolls with the fields (photos, queue arrows, action chips), so a
  /// short screen (landscape with the keyboard up) never overflows.
  final Widget? header;
  const CardForm({
    super.key,
    required this.controllers,
    required this.lines,
    this.missing = const {},
    this.suggestions = const {},
    this.jobs = defaultJobs,
    this.header,
  });

  @override
  State<CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<CardForm> {
  String _target = 'name';
  late final Map<String, FocusNode> _focus = {
    for (final k in fieldOrder)
      k: FocusNode(debugLabel: k)
        ..addListener(() {
          if (_focus[k]!.hasFocus && _target != k) setState(() => _target = k);
        }),
  };
  final _parts = {for (final k in _partLabels.keys) k: TextEditingController()};
  bool _syncing = false; // address <-> parts, never both ways at once

  TextEditingController get _address => widget.controllers['address']!;

  @override
  void initState() {
    super.initState();
    _splitIntoParts();
    _address.addListener(_onAddress);
    for (final c in _parts.values) {
      c.addListener(_onParts);
    }
  }

  @override
  void dispose() {
    _address.removeListener(_onAddress);
    for (final f in _focus.values) {
      f.dispose();
    }
    for (final c in _parts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _splitIntoParts() {
    final p = splitAddress(_address.text);
    final values = {
      'pref': p.pref, 'city': p.city, 'town': p.town,
      'block': p.block, 'building': p.building, 'room': p.room,
    };
    for (final e in values.entries) {
      final c = _parts[e.key]!;
      if (c.text != (e.value ?? '')) c.text = e.value ?? '';
    }
  }

  void _onAddress() {
    if (_syncing) return;
    _syncing = true;
    _splitIntoParts();
    _syncing = false;
  }

  void _onParts() {
    if (_syncing) return;
    _syncing = true;
    String? v(String k) => _parts[k]!.text.trim().isEmpty ? null : _parts[k]!.text.trim();
    _address.text = joinAddress((
      pref: v('pref'), city: v('city'), town: v('town'),
      block: v('block'), building: v('building'), room: v('room'),
    ));
    _syncing = false;
  }

  void _apply(String k, String value) {
    final c = widget.controllers[k]!;
    if (listFields.contains(k) && c.text.trim().isNotEmpty) {
      if (!splitNames(c.text).contains(value)) c.text = '${c.text.trim()}, $value';
    } else {
      c.text = value;
    }
    setState(() {});
  }

  Widget _text(String k, TextTheme text, ColorScheme scheme) => TextField(
        controller: widget.controllers[k],
        focusNode: _focus[k],
        decoration: InputDecoration(
          labelText: fieldLabels[k],
          helperText: widget.missing.contains(k)
              ? '読み取れませんでした。下の文字をタップするか入力してください'
              : listFields.contains(k)
                  ? '複数はカンマで区切る'
                  : null,
          helperStyle: text.labelSmall?.copyWith(
              color: widget.missing.contains(k) ? scheme.error : scheme.onSurfaceVariant),
          suffixIcon: _target == k
              ? Icon(Icons.edit, size: AppSize.iconSmall, color: scheme.primary, semanticLabel: '入力先')
              : null,
        ),
      );

  Widget _chips(String k) {
    final sug = widget.suggestions[k] ?? const [];
    if (sug.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.unit / 2),
      child: Wrap(
        spacing: AppSpace.unit,
        runSpacing: AppSpace.unit / 2,
        children: [
          for (final v in sug)
            InputChip(label: Text(v), tooltip: '「${fieldLabels[k]}」に入れる', onPressed: () => _apply(k, v)),
        ],
      ),
    );
  }

  Widget _dropdown(String label, TextEditingController c, List<String> entries, {bool typeable = false}) =>
      DropdownMenu<String>(
        controller: c,
        label: Text(label),
        expandedInsets: EdgeInsets.zero,
        enableFilter: false,
        requestFocusOnTap: typeable,
        menuHeight: AppSize.thumb * 4,
        dropdownMenuEntries: [for (final e in entries) DropdownMenuEntry(value: e, label: e)],
      );

  /// 信頼度 1–5 as segments; tapping the chosen one again clears it.
  Widget _trust(TextTheme text, ColorScheme scheme) {
    final c = widget.controllers['trust']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fieldLabels['trust']!, style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpace.unit / 2),
        SegmentedButton<String>(
          segments: [for (final n in trustLevels) ButtonSegment(value: n, label: Text(n))],
          selected: {if (c.text.trim().isNotEmpty) c.text.trim()},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => c.text = s.isEmpty ? '' : s.first),
        ),
        const SizedBox(height: AppSpace.unit / 2),
        Text('1 要注意 ／ 3 ふつう ／ 5 とても高い（未設定のままでも保存できます）',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _addressParts() => ExpansionTile(
        title: const Text('住所の内訳'),
        subtitle: const Text('都道府県・市区町村・丁目・番地・建物・号室に分けて直せます'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpace.unit),
        children: [
          _dropdown(_partLabels['pref']!, _parts['pref']!, prefectures),
          for (final k in _partLabels.keys.where((k) => k != 'pref'))
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.unit),
              child: TextField(
                controller: _parts[k],
                decoration: InputDecoration(labelText: _partLabels[k]),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final categories = [
      ...categoryChoices,
      ...?widget.suggestions['category']?.where((v) => !categoryChoices.contains(v)),
    ];
    final jobs = [...widget.jobs, ...?widget.suggestions['job']?.where((v) => !widget.jobs.contains(v))];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.unit, AppSpace.gutter, AppSpace.unit * 12),
      children: [
        if (widget.header != null) widget.header!,
        for (final k in fieldOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.unit),
            child: switch (k) {
              'category' => _dropdown(fieldLabels[k]!, widget.controllers[k]!, categories, typeable: true),
              'job' => _dropdown(fieldLabels[k]!, widget.controllers[k]!, jobs, typeable: true),
              'trust' => _trust(text, scheme),
              'address' => Column(children: [_text(k, text, scheme), _addressParts()]),
              _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_text(k, text, scheme), _chips(k)],
                ),
            },
          ),
        if (widget.lines.isNotEmpty) ...[
          const SizedBox(height: AppSpace.unit),
          Text('読み取った文字（タップで「${fieldLabels[_target]}」に入れる）', style: text.titleSmall),
          const SizedBox(height: AppSpace.unit),
          Wrap(
            spacing: AppSpace.unit,
            runSpacing: AppSpace.unit / 2,
            children: [
              for (final l in widget.lines)
                ActionChip(
                  label: Text(l.text),
                  tooltip: '「${fieldLabels[_target]}」に入れる',
                  onPressed: () =>
                      setState(() => widget.controllers[_target]!.text = normalize(l.text)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
