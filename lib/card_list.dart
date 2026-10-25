import 'dart:io';

import 'package:flutter/material.dart';

import 'ocr/history.dart';
import 'theme.dart';

enum CardSort { date, company, name }

/// Pure ordering used by the list screen.
List<CardSummary> sortCards(List<CardSummary> cards, CardSort sort) {
  final out = List.of(cards);
  switch (sort) {
    case CardSort.date:
      out.sort((a, b) => (b.scanned ?? '').compareTo(a.scanned ?? ''));
    case CardSort.company:
      out.sort((a, b) {
        final c = (a.company ?? '￿').compareTo(b.company ?? '￿');
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    case CardSort.name:
      out.sort((a, b) => a.name.compareTo(b.name));
  }
  return out;
}

/// The list of saved cards: thumbnail, name, company / title / memo, date.
class CardList extends StatelessWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final ValueChanged<CardSummary> onTap;
  final String emptyText;
  const CardList({
    super.key,
    required this.cards,
    required this.vault,
    required this.onTap,
    this.emptyText = 'まだ名刺がありません。撮影して保存すると、ここに並びます',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.gutter * 2),
          child: Text(emptyText, style: text.bodyLarge, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: cards.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = cards[i];
        final img = c.imageFront == null ? null : File('${vault.path}/${c.imageFront}');
        return ListTile(
          leading: SizedBox(
            width: AppSize.thumb * 0.75,
            child: img != null && img.existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: Image.file(img, fit: BoxFit.cover, semanticLabel: '${c.name}の名刺'),
                  )
                : Icon(Icons.badge_outlined, color: scheme.onSurfaceVariant, semanticLabel: '写真なし'),
          ),
          title: Text(c.name),
          subtitle: Text([
            if (c.company != null) c.company!,
            if (c.title != null) c.title!,
            if (c.memo != null) c.memo!,
          ].join('　')),
          trailing: Text(c.scanned ?? '', style: text.labelSmall),
          onTap: () => onTap(c),
        );
      },
    );
  }
}

/// 検索: a search box over name / company / title / memo.
class SearchScreen extends StatefulWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final ValueChanged<CardSummary> onTap;
  const SearchScreen({super.key, required this.cards, required this.vault, required this.onTap});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hits = sortCards(widget.cards.where((c) => c.matches(_query)).toList(), CardSort.date);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: '氏名・ふりがな・会社・電話・メールで探す',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: CardList(
            cards: hits,
            vault: widget.vault,
            onTap: widget.onTap,
            emptyText: widget.cards.isEmpty
                ? 'まだ名刺がありません。撮影して保存すると検索できます'
                : '「$_query」に合う名刺はありません',
          ),
        ),
      ],
    );
  }
}

/// 一覧: every card, ordered by date / company / name.
class ListScreen extends StatefulWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final ValueChanged<CardSummary> onTap;
  const ListScreen({super.key, required this.cards, required this.vault, required this.onTap});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  CardSort _sort = CardSort.date;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.unit),
          child: SegmentedButton<CardSort>(
            segments: const [
              ButtonSegment(value: CardSort.date, label: Text('新しい順')),
              ButtonSegment(value: CardSort.company, label: Text('会社順')),
              ButtonSegment(value: CardSort.name, label: Text('氏名順')),
            ],
            selected: {_sort},
            onSelectionChanged: (s) => setState(() => _sort = s.first),
          ),
        ),
        Expanded(
          child: CardList(cards: sortCards(widget.cards, _sort), vault: widget.vault, onTap: widget.onTap),
        ),
      ],
    );
  }
}
