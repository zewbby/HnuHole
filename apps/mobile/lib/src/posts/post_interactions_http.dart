part of 'http_post_api.dart';

extension _PostInteractionsHttp on HttpPostApi {
  Future<PostResponse<PostInteractions>> _interactionRequest(
    String token,
    String id, {
    String? action,
    bool? desired,
    String? version,
  }) => _input(() {
    if (action != null &&
        (version == null || !_validInteractionVersion(version))) {
      throw const FormatException('Interaction write requires a version');
    }
    return _send(
      token,
      action == null ? 'GET' : 'PUT',
      '/api/v1/posts/${PostProtocol.resourceId(id)}/${action ?? 'interactions'}',
      body: action == null
          ? null
          : {action == 'like' ? 'liked' : 'favorited': desired!},
      headers: {if (version != null) 'If-Interaction-Version': version},
      readInteractionVersion: true,
      decode: (raw) {
        final value = PostInteractions.fromJson(raw);
        if (value.postId != id ||
            action == 'like' && value.likedByMe != desired ||
            action == 'favorite' && value.favoritedByMe != desired) {
          throw const FormatException('Mismatched interaction result');
        }
        return value;
      },
    );
  });
}

bool _validInteractionVersion(String version) =>
    RegExp(r'^"[0-9a-f]{64}"$').hasMatch(version);
