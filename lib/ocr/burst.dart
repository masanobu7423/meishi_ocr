import 'review_queue.dart' show shotStems;

enum CardSide { front, back }

/// State of one 続けて撮影 session: which side is next, how many cards and
/// backs were saved, and the inbox file name for each capture. Pure, so the
/// capture screen stays thin.
class BurstSession {
  final bool paired;
  int cards = 0, backs = 0;
  String? _stem; // the card whose back is expected next
  BurstSession({required this.paired});

  CardSide get side => _stem == null ? CardSide.front : CardSide.back;

  /// Ending is only offered between cards, never with a back outstanding.
  bool get canFinish => _stem == null;

  String get title =>
      side == CardSide.front ? '表面を撮影（${cards + 1} 枚目）' : '裏面を撮影（$cards 枚目）';

  /// Inbox name (without extension) for the page captured now, and advances.
  String nextName(DateTime now) {
    final stem = shotStems(now, 1).first;
    if (!paired) {
      cards++;
      return stem;
    }
    if (_stem == null) {
      _stem = stem;
      cards++;
      return '${stem}_front';
    }
    final s = _stem!;
    _stem = null;
    backs++;
    return '${s}_back';
  }

  /// The card that gets a blank back instead of a photo, or null when no
  /// back is outstanding.
  String? blankStem() {
    final s = _stem;
    if (s == null) return null;
    _stem = null;
    backs++;
    return s;
  }

  String? get summary => cards == 0
      ? null
      : '$cards 枚を取込フォルダに保存しました${paired ? '（表 $cards 枚、裏 $backs 枚）' : ''}。'
          '「まとめて取込」で読み取って、1 枚ずつ確認できます';
}
