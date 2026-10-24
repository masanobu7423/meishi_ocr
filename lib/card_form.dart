import 'package:flutter/material.dart';

import 'ocr/extractor.dart';
import 'ocr/ocr_line.dart';
import 'theme.dart';

/// User-facing labels for CardFields keys (DESIGN.md §7: never show the keys).
const fieldLabels = <String, String>{
  'name': '氏名',
  'nameKana': 'ふりがな',
  'nameRoman': 'ローマ字',
  'company': '会社',
  'dept': '部署',
  'title': '役職',
  'phone': '電話',
  'mobile': '携帯',
  'fax': 'FAX',
  'email': 'メール',
  'url': 'URL',
  'postal': '郵便番号',
  'address': '住所',
};

/// Fields in the order a person reads a card: who, where, how to reach.
const fieldOrder = [
  'name', 'nameKana', 'company', 'dept', 'title',
  'phone', 'mobile', 'email', 'postal', 'address', 'fax', 'url', 'nameRoman',
];

/// The review form: one text field per card field, plus the OCR lines as
/// chips that drop into whichever field was last focused. Pure UI, no IO,
/// so it is widget-testable without plugins.
class CardForm extends StatefulWidget {
  final Map<String, TextEditingController> controllers;
  final List<OcrLine> lines;
  final Set<String> missing;

  const CardForm({
    super.key,
    required this.controllers,
    required this.lines,
    this.missing = const {},
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

  @override
  void dispose() {
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.unit, AppSpace.gutter, AppSpace.unit * 12),
      children: [
        for (final k in fieldOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.unit),
            child: TextField(
              controller: widget.controllers[k],
              focusNode: _focus[k],
              decoration: InputDecoration(
                labelText: fieldLabels[k],
                helperText: widget.missing.contains(k) ? '読み取れませんでした。下の文字をタップするか入力してください' : null,
                helperStyle: text.labelSmall?.copyWith(color: scheme.error),
                suffixIcon: _target == k
                    ? Icon(Icons.edit, size: AppSize.iconSmall, color: scheme.primary, semanticLabel: '入力先')
                    : null,
              ),
            ),
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
