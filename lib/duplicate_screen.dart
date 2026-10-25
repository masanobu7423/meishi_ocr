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
  const DuplicateDecision(this.action, [this.useCard = const {}]);
}

/// Side-by-side review of an existing contact and the scanned card. Pops
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
      if (r.existing == null && r.card != null) r.key,
  };

  void _pop(DuplicateAction a) => Navigator.pop(context, DuplicateDecision(a, Set.of(_useCard)));

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
    final differing = widget.rows.where((r) => !r.same).length;
    return Scaffold(
      appBar: AppBar(title: const Text('同じ人がいるかもしれません')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, AppSpace.unit * 14),
        children: [
          Text(
            '電話番号またはメールが一致しました。項目ごとに残す方を選んでください'
            '${differing == 0 ? "（すべて同じ内容です）" : "（違いは $differing 項目）"}',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.unit),
          Row(
            children: [
              const SizedBox(width: 72),
              Expanded(child: Text('既存の連絡先', style: text.labelLarge, textAlign: TextAlign.center)),
              Expanded(child: Text('この名刺', style: text.labelLarge, textAlign: TextAlign.center)),
            ],
          ),
          for (final r in widget.rows) _DiffRowTile(
            row: r,
            useCard: _useCard.contains(r.key),
            onPick: r.same ? null : (card) => setState(() => card ? _useCard.add(r.key) : _useCard.remove(r.key)),
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
                label: const Text('選んだ内容で統合'),
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

class _DiffRowTile extends StatelessWidget {
  final DiffRow row;
  final bool useCard;
  final void Function(bool card)? onPick;
  const _DiffRowTile({required this.row, required this.useCard, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget side(String? value, bool selected, bool isCard) {
      final empty = value == null;
      return Expanded(
        child: Semantics(
          button: onPick != null,
          selected: selected,
          label: '${isCard ? "この名刺" : "既存"}の${row.label}',
          child: InkWell(
            onTap: onPick == null || empty ? null : () => onPick!(isCard),
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.all(AppSpace.unit),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.small),
                color: selected ? scheme.primaryContainer : null,
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
              ),
              child: Text(empty ? '—' : value,
                  style: text.bodyMedium?.copyWith(color: empty ? scheme.onSurfaceVariant : null)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.unit / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 72, child: Text(row.label, style: text.labelMedium)),
          if (row.same)
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.check, size: AppSize.iconSmall, color: scheme.primary, semanticLabel: '同じ'),
                  const SizedBox(width: AppSpace.unit / 2),
                  Expanded(child: Text('${row.existing}（同じ）', style: text.bodyMedium)),
                ],
              ),
            )
          else ...[
            side(row.existing, !useCard && row.existing != null, false),
            const SizedBox(width: AppSpace.unit),
            side(row.card, useCard, true),
          ],
        ],
      ),
    );
  }
}
