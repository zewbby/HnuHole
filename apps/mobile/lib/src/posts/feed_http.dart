part of 'http_post_api.dart';

extension _FeedHttp on HttpPostApi {
  Future<PostResponse<PostsPage<FeedPost>>> _timeline({
    required String sessionToken,
    String? channelId,
    String? cursor,
    int limit = 20,
  }) => _input(
    () => _send(
      sessionToken,
      'GET',
      '/api/v1/feed',
      headers: const {'X-Post-Preview': 'thumbnail-v1'},
      query: {
        ...HttpPostApi._pageQuery(cursor, limit),
        if (channelId != null) 'channelId': PostProtocol.resourceId(channelId),
      },
      maxResponseBytes: 24 * 1024 * 1024,
      decode: (raw) {
        final page = PostsPage.fromJson(raw, FeedPost.fromJson);
        if (page.items.length > limit ||
            channelId != null &&
                page.items.any((p) => p.channelId != channelId)) {
          throw const FormatException('Invalid feed page');
        }
        return page;
      },
    ),
  );
}
