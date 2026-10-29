import 'dart:io';

import 'package:flutter/material.dart';

import 'card_list.dart';
import 'ocr/card_status.dart';
import 'ocr/history.dart';
import 'theme.dart';

/// ホーム: how many cards, what came in this month, the five most recent,
/// and the actions that start work. Pure UI over summaries.
class HomeScreen extends StatelessWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final DateTime today;
  final VoidCallback onScan, onAlbum, onImport, onSeeAll;
  final ValueChanged<CardSummary> onOpenCard;

  /// Where registrations go, e.g. "taro@gmail.com（Google）"; null = unknown.
  final String? accountLabel;
  final VoidCallback? onChangeAccount;
  /// Opens the list filtered to what still needs work (未確認 / 未登録).
  final ValueChanged<StatusFilter>? onContinue;
  /// Long-press selection, deletion and sharing in the recent list.
  final Future<void> Function(List<CardSummary>)? onDelete, onShare;

  const HomeScreen({
    super.key,
    required this.cards,
    required this.vault,
    required this.today,
    required this.onScan,
    required this.onAlbum,
    required this.onImport,
    required this.onOpenCard,
    required this.onSeeAll,
    this.accountLabel,
    this.onChangeAccount,
    this.onContinue,
    this.onDelete,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final month = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final thisMonth = cards.where((c) => (c.scanned ?? '').startsWith(month)).length;
    final recent = sortCards(cards, CardSort.date).take(5).toList();
    final due = dueCards(cards, today: today).length;
    final dups = duplicateStems(cards).length;
    Widget tile(String label, int n, String unit, StatusFilter f) => InkWell(
          borderRadius: BorderRadius.circular(AppRadius.large),
          onTap: () => onContinue!(f),
          child: _Stat(label: label, value: '$n', unit: unit),
        );
    final todo = [
      tile('未確認', cards.where((c) => c.status == CardStatus.unreviewed).length, '枚', StatusFilter.unreviewed),
      tile('未登録', cards.where((c) => c.status != CardStatus.registered).length, '枚', StatusFilter.unregistered),
      if (due > 0) tile('連絡予定', due, '件', StatusFilter.due),
      if (dups > 0) tile('重複', dups, '枚', StatusFilter.duplicate),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpace.gutter),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(label: '保存した名刺', value: '${cards.length}', unit: '枚'),
            ),
            const SizedBox(width: AppSpace.unit),
            Expanded(
              child: _Stat(label: '今月の取込', value: '$thisMonth', unit: '枚'),
            ),
          ],
        ),
        // What still needs work, two tiles per row so four never squeeze a
        // 360dp phone. 連絡予定 and 重複 only appear when there is something.
        if (onContinue != null)
          for (var i = 0; i < todo.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.unit),
              child: Row(
                children: [
                  Expanded(child: todo[i]),
                  const SizedBox(width: AppSpace.unit),
                  Expanded(child: i + 1 < todo.length ? todo[i + 1] : const SizedBox()),
                ],
              ),
            ),
        const SizedBox(height: AppSpace.gutter),
        FilledButton.icon(
          onPressed: onScan,
          icon: const Icon(Icons.camera_alt),
          label: const Text('名刺を撮影'),
        ),
        const SizedBox(height: AppSpace.unit),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAlbum,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('アルバムから'),
              ),
            ),
            const SizedBox(width: AppSpace.unit),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.folder_open),
                label: const Text('まとめて取込'),
              ),
            ),
          ],
        ),
        if (accountLabel != null) ...[
          const SizedBox(height: AppSpace.unit),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_sync_outlined, color: scheme.onSurfaceVariant, semanticLabel: '同期'),
            title: Text('登録先: $accountLabel', style: text.bodyMedium),
            subtitle: Text('Google アカウントに登録すると、端末が自動で Google の連絡先と同期します',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: onChangeAccount == null ? null : const Icon(Icons.chevron_right),
            onTap: onChangeAccount,
          ),
        ],
        const SizedBox(height: AppSpace.gutter * 1.5),
        if (cards.isEmpty)
          Text('最初の名刺を撮影すると、ここに最近の名刺が並びます。',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
        else ...[
          Row(
            children: [
              Expanded(child: Text('最近の名刺', style: text.titleMedium)),
              TextButton(onPressed: onSeeAll, child: const Text('すべて見る')),
            ],
          ),
          CardList(
            cards: recent,
            vault: vault,
            onTap: onOpenCard,
            onDelete: onDelete,
            onShare: onShare,
            today: today,
            showStatus: false,
            shrinkWrap: true,
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value, unit;
  const _Stat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.gutter),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: appShadow(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: scheme.primary)),
          const SizedBox(height: AppSpace.unit / 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: text.headlineMedium
                      ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
              if (unit.isNotEmpty)
                Text(' $unit', style: text.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
            ],
          ),
        ],
      ),
    );
  }
}
