import 'dart:io';

import 'package:flutter/material.dart';

import 'ocr/card_status.dart';
import 'ocr/history.dart';
import 'theme.dart';

enum CardSort { date, company, name }

/// What the list shows: everything, only burst captures nobody has looked
/// at yet, or everything not yet in the address book.
enum StatusFilter { all, unreviewed, unregistered }

List<CardSummary> filterCards(List<CardSummary> cards, StatusFilter f) => switch (f) {
      StatusFilter.all => cards,
      StatusFilter.unreviewed => cards.where((c) => c.status == CardStatus.unreviewed).toList(),
      StatusFilter.unregistered => cards.where((c) => c.status != CardStatus.registered).toList(),
    };

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
/// With [onDelete], a long-press starts selection: checkboxes, a bar with
/// すべて選択 / 修正 (one card) / 削除 / 選択解除.
class CardList extends StatefulWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final ValueChanged<CardSummary> onTap;
  final Future<void> Function(List<CardSummary> cards)? onDelete;
  final String emptyText;
  /// Show 未確認 / 未登録 under the date for cards that still need work.
  final bool showStatus;
  /// Size to the rows instead of filling the parent (for a list embedded in
  /// another scroll view, e.g. the home screen); the selection bar then adds
  /// height instead of squeezing the rows.
  final bool shrinkWrap;
  const CardList({
    super.key,
    required this.cards,
    required this.vault,
    required this.onTap,
    this.onDelete,
    this.emptyText = 'まだ名刺がありません。撮影して保存すると、ここに並びます',
    this.showStatus = true,
    this.shrinkWrap = false,
  });

  @override
  State<CardList> createState() => _CardListState();
}

class _CardListState extends State<CardList> {
  final _selected = <String>{}; // stems

  bool get _selecting => _selected.isNotEmpty;
  List<CardSummary> get _chosen =>
      widget.cards.where((c) => _selected.contains(c.stem)).toList();

  void _toggle(CardSummary c) => setState(() {
        if (!_selected.remove(c.stem)) _selected.add(c.stem);
      });

  Future<void> _delete() async {
    final chosen = _chosen;
    setState(_selected.clear);
    await widget.onDelete!(chosen);
  }

  Widget _bar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final one = _selected.length == 1 ? _chosen.single : null;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.unit),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpace.unit / 2,
          children: [
            IconButton(
              tooltip: '選択解除',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
            Text('${_selected.length} 件を選択中'),
            TextButton(
              onPressed: () => setState(() => _selected.addAll(widget.cards.map((c) => c.stem))),
              child: const Text('すべて選択'),
            ),
            if (one != null)
              TextButton.icon(
                onPressed: () {
                  setState(_selected.clear);
                  widget.onTap(one);
                },
                icon: const Icon(Icons.edit_outlined, size: AppSize.iconSmall),
                label: const Text('修正'),
              ),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_outline, size: AppSize.iconSmall),
              label: const Text('削除'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final cards = widget.cards;
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.gutter * 2),
          child: Text(widget.emptyText, style: text.bodyLarge, textAlign: TextAlign.center),
        ),
      );
    }
    final list = ListView.separated(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter, vertical: AppSpace.unit),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.unit + 2),
      itemBuilder: (context, i) {
        final c = cards[i];
        final img = c.imageFront == null ? null : File('${widget.vault.path}/${c.imageFront}');
        final selected = _selected.contains(c.stem);
        // Rows as raised white cards on the white page (案 A, 立体).
        return Card(
          color: selected ? scheme.primaryContainer : scheme.surface,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
          selected: selected,
          leading: _selecting
              ? Checkbox(value: _selected.contains(c.stem), onChanged: (_) => _toggle(c))
              : SizedBox(
                  width: AppSize.thumb * 0.75,
                  child: img != null && img.existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: Image.file(img, fit: BoxFit.cover, semanticLabel: '${c.name}の名刺'),
                        )
                      : Icon(Icons.badge_outlined,
                          color: scheme.onSurfaceVariant, semanticLabel: '写真なし'),
                ),
          title: Text(c.name),
          subtitle: Text([
            if (c.category != null) '［${c.category}］',
            if (c.company != null) c.company!,
            if (c.title != null) c.title!,
            if (c.memo != null) c.memo!,
          ].join('　')),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(c.scanned ?? '', style: text.labelSmall),
              if (widget.showStatus && c.status != CardStatus.registered)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.unit, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.status == CardStatus.unreviewed
                        ? scheme.errorContainer
                        : scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    c.status == CardStatus.unreviewed ? '未確認' : '未登録',
                    style: text.labelSmall?.copyWith(
                        color: c.status == CardStatus.unreviewed
                            ? scheme.onErrorContainer
                            : scheme.onTertiaryContainer),
                  ),
                ),
            ],
          ),
          onTap: () => _selecting ? _toggle(c) : widget.onTap(c),
          onLongPress: widget.onDelete == null ? null : () => _toggle(c),
          ),
        );
      },
    );
    if (!_selecting) return list;
    return widget.shrinkWrap
        ? Column(mainAxisSize: MainAxisSize.min, children: [_bar(context), list])
        : Column(children: [_bar(context), Expanded(child: list)]);
  }
}

/// 検索: a search box over name / company / title / memo.
class SearchScreen extends StatefulWidget {
  final List<CardSummary> cards;
  final Directory vault;
  final ValueChanged<CardSummary> onTap;
  final Future<void> Function(List<CardSummary>)? onDelete;
  const SearchScreen(
      {super.key, required this.cards, required this.vault, required this.onTap, this.onDelete});

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
            onDelete: widget.onDelete,
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
  /// Status filter; the shell owns it so the home screen can preset it.
  final StatusFilter filter;
  final ValueChanged<StatusFilter>? onFilter;
  final Future<void> Function(List<CardSummary>)? onDelete;
  const ListScreen({
    super.key,
    required this.cards,
    required this.vault,
    required this.onTap,
    this.filter = StatusFilter.all,
    this.onFilter,
    this.onDelete,
  });

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  CardSort _sort = CardSort.date;
  late StatusFilter _filter = widget.filter;

  @override
  void didUpdateWidget(ListScreen old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) _filter = widget.filter;
  }

  @override
  Widget build(BuildContext context) {
    final shown = filterCards(widget.cards, _filter);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.unit, AppSpace.unit, AppSpace.unit, 0),
          child: SegmentedButton<StatusFilter>(
            segments: const [
              ButtonSegment(value: StatusFilter.all, label: Text('すべて')),
              ButtonSegment(value: StatusFilter.unreviewed, label: Text('未確認')),
              ButtonSegment(value: StatusFilter.unregistered, label: Text('未登録')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) {
              setState(() => _filter = s.first);
              widget.onFilter?.call(s.first);
            },
          ),
        ),
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
          child: CardList(
            cards: sortCards(shown, _sort),
            vault: widget.vault,
            onTap: widget.onTap,
            onDelete: widget.onDelete,
            emptyText: widget.cards.isEmpty
                ? 'まだ名刺がありません。撮影して保存すると、ここに並びます'
                : _filter == StatusFilter.unreviewed
                    ? '未確認の名刺はありません'
                    : '未登録の名刺はありません',
          ),
        ),
      ],
    );
  }
}
