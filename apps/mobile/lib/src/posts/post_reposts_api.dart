import 'post_api.dart';
import 'post_models.dart';

class PostRepostMark {
  const PostRepostMark(this.identityId, this.repostedAt);
  final String identityId;
  final DateTime repostedAt;
  static PostRepostMark fromJson(Object? raw) {
    final m = PostJson.record(raw, {'identityId', 'repostedAt'});
    return PostRepostMark(
      PostJson.id(m, 'identityId'),
      PostJson.date(m, 'repostedAt'),
    );
  }
}

class PostRepostSnapshot {
  const PostRepostSnapshot(this.postId, this.items);
  final String postId;
  final List<PostRepostMark> items;
  bool contains(String identityId) =>
      items.any((i) => i.identityId == identityId);
  static PostRepostSnapshot fromJson(Object? raw) {
    final m = PostJson.record(raw, {'postId', 'items'});
    if (m['items'] is! List) {
      throw const FormatException('Invalid repost state');
    }
    final items = (m['items'] as List).map(PostRepostMark.fromJson).toList();
    if (items.length > 3 ||
        items.map((i) => i.identityId).toSet().length != items.length) {
      throw const FormatException('Duplicate repost identity');
    }
    return PostRepostSnapshot(
      PostJson.id(m, 'postId'),
      List.unmodifiable(items),
    );
  }
}

class RepostedPost {
  const RepostedPost({
    required this.postId,
    required this.identityId,
    required this.repostedAt,
    required this.post,
  });
  final String postId, identityId;
  final DateTime repostedAt;
  final PostDetail? post;
  String get key => '$identityId/$postId';
  static RepostedPost fromJson(Object? raw) {
    final m = PostJson.record(raw, {
      'postId',
      'identityId',
      'repostedAt',
      'post',
    });
    final id = PostJson.id(m, 'postId');
    final post = m['post'] == null ? null : PostDetail.fromJson(m['post']);
    if (post != null && post.postId != id) {
      throw const FormatException('Mismatched repost');
    }
    return RepostedPost(
      postId: id,
      identityId: PostJson.id(m, 'identityId'),
      repostedAt: PostJson.date(m, 'repostedAt'),
      post: post,
    );
  }
}

abstract interface class PostRepostsApi {
  Future<PostResponse<PostRepostSnapshot>> postReposts({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<PostRepostSnapshot>> setPostRepost({
    required String sessionToken,
    required String postId,
    required String identityId,
    required bool reposted,
    required String version,
  });
  Future<PostResponse<PostsPage<RepostedPost>>> ownReposts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  });
}
