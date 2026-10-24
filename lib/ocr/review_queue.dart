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

  void removeCurrent() {
    if (items.isEmpty) return;
    items.removeAt(_i);
    if (_i >= items.length && _i > 0) _i = items.length - 1;
  }
}
