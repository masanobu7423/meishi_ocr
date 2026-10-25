import 'dart:io';

/// Stems for a burst of [count] captures taken at [now]:
/// `shot_20261025-181207042_1`, `_2`, ... (millisecond stamp so two bursts
/// never share a stem; no characters a file name rejects).
List<String> shotStems(DateTime now, int count) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '${now.millisecond.toString().padLeft(3, '0')}';
  return [for (var i = 1; i <= count; i++) 'shot_${t}_$i'];
}

/// One card waiting in the inbox folder: its stem and image file(s).
typedef InboxCard = ({String stem, File front, File? back});

/// Inbox files grouped into cards, sorted by stem: `<stem>_front.*` and
/// `<stem>_back.*` belong together (burst captures); any other file is a
/// front on its own, as is a back without a front.
List<InboxCard> pairInboxFiles(List<File> files) {
  String base(File f) => f.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), '');
  final fronts = <String, File>{}, backs = <String, File>{};
  for (final f in files) {
    final b = base(f);
    if (b.endsWith('_back')) {
      backs[b.substring(0, b.length - 5)] = f;
    } else {
      fronts[b.endsWith('_front') ? b.substring(0, b.length - 6) : b] = f;
    }
  }
  for (final e in backs.entries) {
    fronts.putIfAbsent(e.key, () => e.value); // a lone back is still a card
  }
  final stems = fronts.keys.toList()..sort();
  return [
    for (final s in stems)
      (stem: s, front: fronts[s]!, back: fronts[s] == backs[s] ? null : backs[s]),
  ];
}

/// Cursor over a batch of imported cards for the review screen.
class ReviewQueue<T> {
  final List<T> items;
  int _i = 0;
  ReviewQueue([List<T>? items]) : items = items ?? [];

  T? get current => items.isEmpty ? null : items[_i];
  String get label => items.isEmpty ? '' : '${_i + 1}/${items.length}';

  bool next() {
    if (_i + 1 >= items.length) return false;
    _i++;
    return true;
  }

  bool prev() {
    if (_i == 0) return false;
    _i--;
    return true;
  }

  /// Drops everything and goes back to the start; `items.clear()` alone would
  /// leave the cursor pointing past the end of a smaller next batch.
  void clear() {
    items.clear();
    _i = 0;
  }

  void removeCurrent() {
    if (items.isEmpty) return;
    items.removeAt(_i);
    if (_i >= items.length && _i > 0) _i = items.length - 1;
  }
}
