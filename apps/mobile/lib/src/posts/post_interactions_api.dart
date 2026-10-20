import 'post_api.dart';
import 'post_models.dart';

class PostInteractions {
  const PostInteractions({
    required this.postId,
    required this.likeCount,
    required this.favoriteCount,
    required this.commentCount,
    required this.likedByMe,
    required this.favoritedByMe,
  });
  final String postId;
  final int likeCount, favoriteCount, commentCount;
  final bool likedByMe, favoritedByMe;

  static PostInteractions fromJson(Object? raw) {
    final m = PostJson.record(raw, {
      'postId',
      'likeCount',
      'favoriteCount',
      'commentCount',
      'likedByMe',
      'favoritedByMe',
    });
    if (m['likedByMe'] is! bool || m['favoritedByMe'] is! bool) {
      throw const FormatException('Invalid interaction flags');
    }
    final result = PostInteractions(
      postId: PostJson.id(m, 'postId'),
      likeCount: PostJson.integer(m, 'likeCount', 0, 9223372036854775807),
      favoriteCount: PostJson.integer(
        m,
        'favoriteCount',
        0,
        9223372036854775807,
      ),
      commentCount: PostJson.integer(m, 'commentCount', 0, 9223372036854775807),
      likedByMe: m['likedByMe'] as bool,
      favoritedByMe: m['favoritedByMe'] as bool,
    );
    if (result.likedByMe && result.likeCount == 0 ||
        result.favoritedByMe && result.favoriteCount == 0) {
      throw const FormatException('Invalid interaction counts');
    }
    return result;
  }
}

abstract interface class PostInteractionsApi {
  Future<PostResponse<List<PostInteractions>>> interactions({
    required String sessionToken,
    required List<String> postIds,
  });
  Future<PostResponse<PostInteractions>> postInteractions({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
    required String version,
  });
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
    required String version,
  });
}
