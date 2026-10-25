import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'ocr/extractor.dart';
import 'ocr/merge.dart';
import 'theme.dart';

enum DuplicateAction { merge, separate, replace, editExisting }

class DuplicateDecision {
  final DuplicateAction action;

  /// Field keys whose value should come from the card when merging.
  final Set<String> useCard;

  /// Multi-valued keys whose existing value is kept alongside the card's.
  final Set<String> keepExisting;
  const DuplicateDecision(this.action, {this.useCard = const {}, this.keepExisting = multiValued});
}

/// Field-by-field review of an existing contact against the scanned card.
/// Each differing row has a checkbox "名刺の値を使う" and, for fields that can
/// hold several values, "既存も残す"; a preview line shows the result. Pops
/// with a [DuplicateDecision], or null when the user backs out.
class DuplicateScreen extends StatefulWidget {
  final Contact existing;
  final CardFields card;
  final List<DiffRow> rows;
  const DuplicateScreen({super.key, required this.existing, required this.card, required this.rows});

  @override
  State<DuplicateScreen> createState() => _DuplicateScreenState();
}

class _DuplicateScreenState extends State<DuplicateScreen> {
  /// Default: keep what the phone already has; only empty slots take the card.
  late final Set<String> _useCard = {
    for (final r in widget.rows)
      if (!r.same && r.existing == null && r.card != null) r.key,
  };
  final Set<String> _keepExisting = Set.of(multiValued);

  Iterable<DiffRow> get _differing => widget.rows.where((r) => !r.same);

  void _pop(DuplicateAction a) => Navigator.pop(
      context, DuplicateDecision(a, useCard: Set.of(_useCard), keepExisting: Set.of(_keepExisting)));

  void _all(bool card) => setState(() {
        _useCard.clear();
        if (card) _useCard.addAll(_differing.where((r) => r.card != null).map((r) => r.key));
      });

  Future<void> _confirmReplace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('既存の連絡先を削除しますか？'),
        content: Text('「${widget.existing.displayName ?? ''}」を電話帳から削除し、名刺の内容で登録し直します。削除は元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('中止')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('削除して登録'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _pop(DuplicateAction.replace);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final differing = _differing.length;
    return Scaffold(
      appBar: AppBar(title: const Text('同じ人がいるかもしれません')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, AppSpace.unit * 16),
        children: [
          Text(
            '電話番号またはメールが一致しました。'
            '${differing == 0 ? "内容はすべて同じです。" : "違いは $differing 項目。名刺の値を使う項目にチェックを入れてください。"}',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (differing > 0)
            Wrap(
              spacing: AppSpace.unit,
              children: [
                TextButton(onPressed: () => _all(true), child: const Text('すべて名刺の値にする')),
                TextButton(onPressed: () => _all(false), child: const Text('すべて既存のままにする')),
              ],
            ),
          const SizedBox(height: AppSpace.unit),
          for (final r in widget.rows)
            _DiffCard(
              row: r,
              useCard: _useCard.contains(r.key),
              keepExisting: _keepExisting.contains(r.key),
              onUseCard: r.same || r.card == null
                  ? null
                  : (v) => setState(() => v ? _useCard.add(r.key) : _useCard.remove(r.key)),
              onKeepExisting: !multiValued.contains(r.key) || r.same || r.existing == null || r.card == null
                  ? null
                  : (v) => setState(() => v ? _keepExisting.add(r.key) : _keepExisting.remove(r.key)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.gutter),
          child: Wrap(
            spacing: AppSpace.unit,
            runSpacing: AppSpace.unit,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _pop(DuplicateAction.merge),
                icon: const Icon(Icons.merge),
                label: const Text('選んだ内容で再登録'),
              ),
              OutlinedButton(
                onPressed: () => _pop(DuplicateAction.separate),
                child: const Text('別人として登録'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pop(DuplicateAction.editExisting),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('既存を電話帳アプリで編集'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: _confirmReplace,
                child: const Text('既存を削除して名刺で登録'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One field: both values, the two checkboxes, and the "統合後" preview.
class _DiffCard extends StatelessWidget {
  final DiffRow row;
  final bool useCard, keepExisting;
  final ValueChanged<bool>? onUseCard, onKeepExisting;
  const _DiffCard({
    required this.row,
    required this.useCard,
    required this.keepExisting,
    required this.onUseCard,
    required this.onKeepExisting,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (row.same) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.check, size: AppSize.iconSmall, color: scheme.primary, semanticLabel: '同じ'),
        title: Text(row.label, style: text.labelMedium),
        subtitle: Text('${row.existing}（同じ）'),
      );
    }
    final preview = mergedPreview(row, useCard: useCard, keepExisting: keepExisting);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.unit),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.unit, AppSpace.unit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.label, style: text.labelLarge),
            _value(context, '既存', row.existing),
            _value(context, '名刺', row.card),
            if (onUseCard != null)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: useCard,
                onChanged: (v) => onUseCard!(v ?? false),
                title: const Text('名刺の値を使う'),
              ),
            if (onKeepExisting != null && useCard)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: keepExisting,
                onChanged: (v) => onKeepExisting!(v ?? false),
                title: const Text('既存の値も残す'),
              ),
            Text('統合後: $preview', style: text.bodyMedium?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
    );
  }

  Widget _value(BuildContext context, String side, String? v) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.unit / 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 40, child: Text(side, style: TextStyle(color: scheme.onSurfaceVariant))),
          Expanded(child: Text(v ?? '—', style: v == null ? TextStyle(color: scheme.onSurfaceVariant) : null)),
        ],
      ),
    );
  }
}
