part of 'http_post_api.dart';

extension _PostRepostsHttp on HttpPostApi {
  Future<PostResponse<PostRepostSnapshot>> _repostRequest(
    String token,
    String id, {
    String? identity,
    bool? enabled,
    String? version,
  }) => _input(() {
    if (identity != null) {
      PostProtocol.resourceId(identity);
      if (version == null || !_validInteractionVersion(version)) {
        throw const FormatException('Repost write requires version');
      }
    }
    return _send(
      token,
      identity == null ? 'GET' : 'PUT',
      '/api/v1/posts/${PostProtocol.resourceId(id)}/repost',
      body: identity == null
          ? null
          : {'identityId': identity, 'reposted': enabled!},
      headers: {if (version != null) 'If-Interaction-Version': version},
      readInteractionVersion: true,
      decode: (raw) {
        final value = PostRepostSnapshot.fromJson(raw);
        if (value.postId != id ||
            identity != null && value.contains(identity) != enabled) {
          throw const FormatException('Mismatched repost response');
        }
        return value;
      },
    );
  });
}
