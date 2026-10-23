import 'post_api.dart';
import 'post_models.dart';
import 'post_protocol.dart';

/// New public feed projection; legacy PostCard/Detail remain strict and unchanged.
class FeedPost extends PostCard {
  const FeedPost({
    required super.postId,
    required super.channelId,
    required super.title,
    required super.author,
    required super.publishedAt,
    required this.body,
    required this.viewCount,
    this.imageCount = 0,
    this.imageSizes,
  });
  final String body;
  final int viewCount, imageCount;
  final List<({int width, int height})>? imageSizes;
  static FeedPost fromJson(Object? raw) {
    final m = PostJson.record(
      raw,
      {
        'postId',
        'channelId',
        'title',
        'body',
        'author',
        'publishedAt',
        'viewCount',
      },
      optional: {'imageCount', 'imageSizes'},
    );
    final title = PostJson.text(m, 'title', maxLength: 4096);
    final imageCount = PostJson.imageCount(m);
    List<({int width, int height})>? sizes;
    if (m.containsKey('imageSizes')) {
      final rawSizes = m['imageSizes'];
      if (rawSizes is! List || rawSizes.length != imageCount) {
        throw const FormatException('Mismatched feed image geometry');
      }
      sizes = List.unmodifiable(
        rawSizes.map((raw) {
          final size = PostJson.record(raw, {'width', 'height'});
          final width = PostJson.integer(size, 'width', 1, 16384);
          final height = PostJson.integer(size, 'height', 1, 16384);
          if (width * height > 12 * 1024 * 1024) {
            throw const FormatException('Invalid feed image geometry');
          }
          return (width: width, height: height);
        }),
      );
    }
    final body = PostJson.text(
      m,
      'body',
      maxLength: 65536,
      allowEmpty: imageCount > 0,
    );
    PostContentRules.validateTitle(title);
    if (body.isNotEmpty || imageCount == 0) {
      PostContentRules.validateBody(body);
    }
    return FeedPost(
      postId: PostJson.id(m, 'postId'),
      channelId: PostJson.id(m, 'channelId'),
      title: title,
      body: body,
      author: PostAuthor.fromJson(m['author']),
      publishedAt: PostJson.date(m, 'publishedAt'),
      viewCount: PostJson.integer(m, 'viewCount', 0, 9223372036854775807),
      imageCount: imageCount,
      imageSizes: sizes,
    );
  }
}

class FeedPreferences {
  FeedPreferences(Iterable<String> ids)
    : blockedChannelIds = Set.unmodifiable(ids) {
    if (blockedChannelIds.length > 7) {
      throw const FormatException('Too many channels');
    }
    for (final id in blockedChannelIds) {
      PostProtocol.resourceId(id);
    }
  }
  final Set<String> blockedChannelIds;
  static FeedPreferences fromJson(Object? raw) {
    final m = PostJson.record(raw, {'blockedChannelIds'});
    final ids = m['blockedChannelIds'];
    if (ids is! List ||
        ids.any((id) => id is! String) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid feed preferences');
    }
    return FeedPreferences(ids.cast<String>());
  }
}

class PostViews {
  const PostViews(this.postId, this.viewCount);
  final String postId;
  final int viewCount;
  static PostViews fromJson(Object? raw) {
    final m = PostJson.record(raw, {'postId', 'viewCount'});
    return PostViews(
      PostJson.id(m, 'postId'),
      PostJson.integer(m, 'viewCount', 0, 9223372036854775807),
    );
  }
}

abstract interface class FeedApi {
  Future<PostResponse<PostsPage<FeedPost>>> timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<FeedPreferences>> feedPreferences({
    required String sessionToken,
  });
  Future<PostResponse<FeedPreferences>> saveFeedPreferences({
    required String sessionToken,
    required Set<String> blockedChannelIds,
  });
  Future<PostResponse<PostViews>> registerPostView({
    required String sessionToken,
    required String postId,
  });
}
