import 'post_models.dart';
import 'post_protocol.dart';

enum PostFailureKind {
  unauthorized,
  unavailable,
  transport,
  invalidResponse,
  rejected,
}

/// 只保留固定分类与允许的错误码，避免网络异常带出文字、URL 或凭据。
class PostFailure implements Exception {
  const PostFailure({
    required this.kind,
    this.code,
    this.statusCode,
    this.retryAfterSeconds,
    this.requestId,
  });
  final PostFailureKind kind;
  final String? code, requestId;
  final int? statusCode, retryAfterSeconds;
  @override
  String toString() => 'PostFailure(${kind.name}, $code, $statusCode)';
}

class PostResponse<T> {
  const PostResponse({
    required this.value,
    required this.serverTime,
    required this.sessionExpiresAt,
    required this.requestId,
    required this.statusCode,
  });
  final T value;
  final DateTime serverTime, sessionExpiresAt;
  final String requestId;
  final int statusCode;
}

abstract interface class PostApi {
  Future<PostResponse<PostCommandResult>> create({
    required String sessionToken,
    required String commandId,
    required String channelId,
    required String identityId,
    required String title,
    required String body,
  });
  Future<PostResponse<PostCommandResult>> commandResult({
    required String sessionToken,
    required String commandId,
  });
  Future<PostResponse<PostCommandResult>> seal({
    required String sessionToken,
    required String commandId,
    required PostOperation operation,
    required String requestDigest,
  });
  Future<PostResponse<PostsPage<PostTask>>> tasks({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<PostTask>> task({
    required String sessionToken,
    required String taskId,
  });
  Future<PostResponse<PostCommandResult>> cancel({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  });
  Future<PostResponse<PostCommandResult>> retry({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
  });
  Future<PostResponse<PostCommandResult>> hide({
    required String sessionToken,
    required String commandId,
    required String taskId,
    required int expectedAttemptVersion,
  });
  Future<PostResponse<PostsPage<PostCard>>> feed({
    required String sessionToken,
    required String channelId,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<PostDetail>> detail({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<PostsPage<OwnPostCard>>> ownPosts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  });
  Future<PostResponse<PostCapabilities>> capabilities({
    required String sessionToken,
    required String postId,
  });
  Future<PostResponse<PostCommandResult>> delete({
    required String sessionToken,
    required String commandId,
    required String postId,
  });
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  });
}
