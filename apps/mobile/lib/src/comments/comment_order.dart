import '../posts/post_protocol.dart';

class CommentRank {
  CommentRank({
    required this.id,
    required this.publishedAt,
    required this.likes,
  }) {
    PostProtocol.resourceId(id);
    if (!publishedAt.isUtc || likes < 0) {
      throw const FormatException('Invalid comment ordering data');
    }
  }
  final String id;
  final DateTime publishedAt;
  final int likes;
  CommentRank withLikes(int next) =>
      CommentRank(id: id, publishedAt: publishedAt, likes: next);
}

/// Capture only when entering/reopening the whole comments region. Changing a
/// number never recomputes the leading set or inserts other people's new rows.
class CommentOrderSnapshot {
  CommentOrderSnapshot._(this._leadingIds, this._items, this._order);
  factory CommentOrderSnapshot.capture(
    Iterable<CommentRank> items, {
    bool replies = false,
  }) {
    final values = items.toList();
    final byId = {for (final item in values) item.id: item};
    if (byId.length != values.length) {
      throw const FormatException('Duplicate comment ID');
    }
    final limit = replies ? 5 : 10;
    values.sort((a, b) {
      final likes = b.likes.compareTo(a.likes);
      return likes == 0 ? _time(a, b) : likes;
    });
    final leading = values.take(limit).toList();
    final rest = values.skip(limit).toList()..sort(_time);
    return CommentOrderSnapshot._(
      {for (final item in leading) item.id},
      byId,
      [
        for (final item in [...leading, ...rest]) item.id,
      ],
    );
  }
  final Set<String> _leadingIds;
  int get leadingCount => _leadingIds.length;
  final Map<String, CommentRank> _items;
  final List<String> _order;
  List<CommentRank> get all =>
      List.unmodifiable(_order.map((id) => _items[id]!));
  List<CommentRank> replies({required bool expanded}) =>
      expanded ? all : List.unmodifiable(all.take(leadingCount));
  int get hiddenCount => (_order.length - leadingCount).clamp(0, _order.length);
  void updateLikes(String id, int value) {
    final item = _items[id];
    if (item != null) _items[id] = item.withLikes(value);
  }

  void remove(Iterable<String> ids) {
    for (final id in ids) {
      _items.remove(id);
      _order.remove(id);
      _leadingIds.remove(id);
    }
  }

  static int _time(CommentRank a, CommentRank b) {
    final at = a.publishedAt.compareTo(b.publishedAt);
    return at == 0 ? a.id.compareTo(b.id) : at;
  }
}
