import 'dart:io';

import 'package:flutter/material.dart';

import 'ocr/history.dart';
import 'theme.dart';

/// Saved cards, newest first, with a search box. Pops with the chosen
/// card's summary. Pure UI: the caller supplies the summaries and the
/// vault root used to show thumbnails.
class HistoryScreen extends StatefulWidget {
  final List<CardSummary> cards;
  final Directory vault;
  const HistoryScreen({super.key, required this.cards, required this.vault});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hits = widget.cards.where((c) => c.matches(_query)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('保存した名刺（${widget.cards.length}）')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.unit, AppSpace.gutter, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: '氏名・会社・役職・メモで探す',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: widget.cards.isEmpty
                ? Center(
                    child: Text('まだ名刺がありません。撮影して保存すると、ここに並びます',
                        style: text.bodyLarge, textAlign: TextAlign.center))
                : hits.isEmpty
                    ? Center(child: Text('「$_query」に合う名刺はありません', style: text.bodyLarge))
                    : ListView.separated(
                        itemCount: hits.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = hits[i];
                          final img = c.imageFront == null
                              ? null
                              : File('${widget.vault.path}/${c.imageFront}');
                          return ListTile(
                            leading: SizedBox(
                              width: AppSize.thumb * 0.75,
                              child: img != null && img.existsSync()
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(AppRadius.small),
                                      child: Image.file(img, fit: BoxFit.cover,
                                          semanticLabel: '${c.name}の名刺'),
                                    )
                                  : Icon(Icons.badge_outlined, color: scheme.onSurfaceVariant,
                                      semanticLabel: '写真なし'),
                            ),
                            title: Text(c.name),
                            subtitle: Text([
                              if (c.company != null) c.company!,
                              if (c.title != null) c.title!,
                              if (c.memo != null) c.memo!,
                            ].join('　')),
                            trailing: Text(c.scanned ?? '', style: text.labelSmall),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
