import 'dart:io';

import 'package:flutter/material.dart';

import 'card_list.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final month = '${today.year}-${today.month.toString().padLeft(2, '0')}';
    final thisMonth = cards.where((c) => (c.scanned ?? '').startsWith(month)).length;
    final recent = sortCards(cards, CardSort.date).take(5).toList();

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
          SizedBox(
            height: recent.length * 72.0 + 8,
            child: CardList(cards: recent, vault: vault, onTap: onOpenCard),
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
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.unit / 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: text.headlineSmall),
              if (unit.isNotEmpty) Text(' $unit', style: text.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
