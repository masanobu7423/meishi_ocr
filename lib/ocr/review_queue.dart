/// Stems for a burst of [count] captures taken at [now]:
/// `shot_20261025-181207042_1`, `_2`, ... (millisecond stamp so two bursts
/// never share a stem; no characters a file name rejects).
List<String> shotStems(DateTime now, int count) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '${now.millisecond.toString().padLeft(3, '0')}';
  return [for (var i = 1; i <= count; i++) 'shot_${t}_$i'];
}

/// Pages from one burst grouped into cards: alternating front / back when
/// [paired], else every page is a front. An odd trailing page has no back.
List<({T front, T? back})> pairPages<T>(List<T> pages, {required bool paired}) => [
      if (paired)
        for (var i = 0; i < pages.length; i += 2)
          (front: pages[i], back: i + 1 < pages.length ? pages[i + 1] : null)
      else
        for (final p in pages) (front: p, back: null),
    ];

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
