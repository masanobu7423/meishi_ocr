import 'package:flutter/material.dart';

import 'ocr/address.dart';
import 'ocr/extractor.dart';
import 'ocr/fields.dart';
import 'ocr/dates.dart';
import 'ocr/jobs.dart';
import 'ocr/ocr_line.dart';
import 'ocr/vault_index.dart' show splitNames;
import 'theme.dart';

export 'ocr/fields.dart' show fieldLabels, fieldOrder;



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
  /// Reference date for the 次回連絡日 picker; null = now.
  final DateTime? today;
  /// 「カレンダーに登録」 under a set 次回連絡日; null hides the button.
  final void Function(String date)? onCalendar;
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
    this.today,
    this.onCalendar,
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

  /// 次回連絡日: read-only field, the platform date picker fills it,
  /// the suffix clears it. Stored as yyyy-mm-dd so Obsidian can sort on it.
  Widget _date(String k, TextTheme text, ColorScheme scheme) {
    final c = widget.controllers[k]!;
    final today = widget.today ?? DateTime.now();
    // Listens to the controller: a date set by the picker, the clear button or
    // the caller shows / hides the suffix and the calendar button at once.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, v, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dateField(c, today, text, scheme),
          if (widget.onCalendar != null && parseYmd(v.text) != null)
            TextButton.icon(
              onPressed: () => widget.onCalendar!(v.text.trim()),
              icon: const Icon(Icons.event_available_outlined, size: AppSize.iconSmall),
              label: const Text('カレンダーに登録'),
            ),
        ],
      ),
    );
  }

  Widget _dateField(TextEditingController c, DateTime today, TextTheme text, ColorScheme scheme) {
    return TextField(
      controller: c,
      readOnly: true,
      decoration: InputDecoration(
        labelText: fieldLabels['nextContact'],
        helperText: '次に連絡する日。ホームと一覧の「連絡予定」に出ます（空欄でも保存できます）',
        helperStyle: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: c.text.isEmpty
            ? null
            : IconButton(
                tooltip: '日付を消す',
                icon: const Icon(Icons.clear),
                onPressed: c.clear, // the ValueListenableBuilder redraws
              ),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: parseYmd(c.text) ?? today,
          // Wide enough for any stored date (restored / hand-edited notes).
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) c.text = ymd(picked); // the ValueListenableBuilder redraws
      },
    );
  }

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
              'nextContact' => _date(k, text, scheme),
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
