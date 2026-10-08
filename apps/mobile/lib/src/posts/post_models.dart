import 'post_protocol.dart';

enum PostAuthorState { active, deleted, accountClosed }

enum PostTaskState { accepted, published, failed, cancelled }

enum PostCommandState {
  unknownNotObserved,
  accepted,
  committed,
  rejected,
  notAccepted,
  resultExpired,
}

enum ComposerSelectionState {
  initialSetupRequired,
  defaultAvailable,
  selectionRequired,
}

class PostAuthor {
  const PostAuthor({
    required this.state,
    required this.avatar,
    this.nickname,
    this.shortCode,
  });
  final PostAuthorState state;
  final String avatar;
  final String? nickname, shortCode;
  String get displayName =>
      state == PostAuthorState.active ? nickname! : '注销身份 · $shortCode';
  String? get inactiveMessage => switch (state) {
    PostAuthorState.active => null,
    PostAuthorState.deleted => '身份已删除',
    PostAuthorState.accountClosed => '账户已注销',
  };
  static PostAuthor fromJson(Object? raw) {
    final m = PostJson.record(
      raw,
      {'state', 'avatar'},
      optional: {'nickname', 'shortCode'},
    );
    final state = PostJson.text(m, 'state');
    if (state == 'ACTIVE') {
      PostJson.record(raw, {'state', 'nickname', 'avatar'});
      if (m['avatar'] != 'default-v1') {
        throw const FormatException('Invalid active author avatar');
      }
      return PostAuthor(
        state: PostAuthorState.active,
        avatar: 'default-v1',
        nickname: PostJson.text(m, 'nickname', maxLength: 512),
      );
    }
    PostJson.record(raw, {'state', 'shortCode', 'avatar'});
    final shortCode = PostJson.text(m, 'shortCode');
    if ((state != 'DELETED' && state != 'ACCOUNT_CLOSED') ||
        m['avatar'] != 'inactive-v1' ||
        !RegExp(r'^[A-Z2-7]{12}$').hasMatch(shortCode)) {
      throw const FormatException('Invalid inactive author');
    }
    return PostAuthor(
      state: state == 'DELETED'
          ? PostAuthorState.deleted
          : PostAuthorState.accountClosed,
      avatar: 'inactive-v1',
      shortCode: shortCode,
    );
  }
}

class PostCard {
  const PostCard({
    required this.postId,
    required this.channelId,
    required this.title,
    required this.author,
    required this.publishedAt,
  });
  final String postId, channelId, title;
  final PostAuthor author;
  final DateTime publishedAt;
  static PostCard fromJson(Object? raw) {
    final m = PostJson.record(raw, {
      'postId',
      'channelId',
      'title',
      'author',
      'publishedAt',
    });
    final title = PostJson.text(m, 'title', maxLength: 4096);
    PostContentRules.validateTitle(title);
    return PostCard(
      postId: PostJson.id(m, 'postId'),
      channelId: PostJson.id(m, 'channelId'),
      title: title,
      author: PostAuthor.fromJson(m['author']),
      publishedAt: PostJson.date(m, 'publishedAt'),
    );
  }
}

class PostDetail extends PostCard {
  const PostDetail({
    required super.postId,
    required super.channelId,
    required super.title,
    required super.author,
    required super.publishedAt,
    required this.body,
  });
  final String body;
  static PostDetail fromJson(Object? raw) {
    final m = PostJson.record(raw, {
      'postId',
      'channelId',
      'title',
      'body',
      'author',
      'publishedAt',
    });
    final title = PostJson.text(m, 'title', maxLength: 4096);
    final body = PostJson.text(m, 'body', maxLength: 65536);
    PostContentRules.validate(title, body);
    return PostDetail(
      postId: PostJson.id(m, 'postId'),
      channelId: PostJson.id(m, 'channelId'),
      title: title,
      body: body,
      author: PostAuthor.fromJson(m['author']),
      publishedAt: PostJson.date(m, 'publishedAt'),
    );
  }
}

class OwnPostCard {
  const OwnPostCard({required this.post, required this.serverSortAt});
  final PostCard post;
  final DateTime serverSortAt;
  static OwnPostCard fromJson(Object? raw) {
    final m = PostJson.record(raw, {'post', 'serverSortAt'});
    final post = PostCard.fromJson(m['post']);
    final time = PostJson.date(m, 'serverSortAt');
    if (time != post.publishedAt) {
      throw const FormatException('Invalid own post sort time');
    }
    return OwnPostCard(post: post, serverSortAt: time);
  }
}

class PostContent {
  const PostContent({required this.title, required this.body});
  final String title, body;
  static PostContent fromJson(Object? raw) {
    final m = PostJson.record(raw, {'title', 'body'});
    final title = PostJson.text(m, 'title', maxLength: 4096);
    final body = PostJson.text(m, 'body', maxLength: 65536);
    PostContentRules.validate(title, body);
    return PostContent(title: title, body: body);
  }
}

class PostTask {
  const PostTask({
    required this.taskId,
    required this.postId,
    required this.channelId,
    required this.identityId,
    required this.attemptVersion,
    required this.state,
    required this.acceptedAt,
    required this.serverSortAt,
    required this.visible,
    required this.contentAvailable,
    required this.canRetry,
    required this.canCancel,
    required this.canHide,
    this.failureCode,
    this.terminalAt,
    this.content,
  });
  final String taskId, postId, channelId, identityId;
  final int attemptVersion;
  final PostTaskState state;
  final DateTime acceptedAt, serverSortAt;
  final DateTime? terminalAt;
  final String? failureCode;
  final bool visible, contentAvailable, canRetry, canCancel, canHide;
  final PostContent? content;
  static PostTask fromJson(Object? raw) {
    final detail = PostJson.record(raw, {'task', 'content'});
    final m = PostJson.record(detail['task'], {
      'taskId',
      'postId',
      'channelId',
      'identityId',
      'attemptVersion',
      'state',
      'acceptedAt',
      'failureCode',
      'visible',
      'contentAvailable',
      'canRetry',
      'serverSortAt',
      'terminalAt',
      'canCancel',
      'canHide',
    });
    final state = PostJson.taskState(m['state']);
    final accepted = PostJson.date(m, 'acceptedAt');
    final sort = PostJson.date(m, 'serverSortAt');
    final terminal = m['terminalAt'] == null
        ? null
        : PostJson.date(m, 'terminalAt');
    final failure = m['failureCode'];
    if (failure != null &&
        !{
          'PUBLICATION_FAILED',
          'PUBLISHING_STOPPED',
          'IDENTITY_INACTIVE',
        }.contains(failure)) {
      throw const FormatException('Invalid publication failure');
    }
    final visible = PostJson.boolean(m, 'visible');
    final available = PostJson.boolean(m, 'contentAvailable');
    final retry = PostJson.boolean(m, 'canRetry');
    final cancel = PostJson.boolean(m, 'canCancel');
    final hide = PostJson.boolean(m, 'canHide');
    final content = detail['content'] == null
        ? null
        : PostContent.fromJson(detail['content']);
    if (accepted != sort ||
        (state == PostTaskState.accepted) != (terminal == null) ||
        terminal != null && terminal.isBefore(accepted) ||
        (state == PostTaskState.failed) != (failure != null) ||
        available != (content != null) ||
        visible &&
            state != PostTaskState.accepted &&
            state != PostTaskState.failed ||
        cancel != (visible && state == PostTaskState.accepted) ||
        hide != (visible && state == PostTaskState.failed) ||
        retry && (!hide || !available) ||
        state == PostTaskState.cancelled && available) {
      throw const FormatException('Inconsistent publication task');
    }
    return PostTask(
      taskId: PostJson.id(m, 'taskId'),
      postId: PostJson.id(m, 'postId'),
      channelId: PostJson.id(m, 'channelId'),
      identityId: PostJson.id(m, 'identityId'),
      attemptVersion: PostJson.integer(m, 'attemptVersion', 1, 2147483647),
      state: state,
      acceptedAt: accepted,
      serverSortAt: sort,
      terminalAt: terminal,
      failureCode: failure as String?,
      visible: visible,
      contentAvailable: available,
      canRetry: retry,
      canCancel: cancel,
      canHide: hide,
      content: content,
    );
  }
}

class PostsPage<T> {
  PostsPage({required List<T> items, required this.nextCursor})
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;
  static PostsPage<T> fromJson<T>(Object? raw, T Function(Object?) decode) {
    final m = PostJson.record(raw, {'items', 'nextCursor'});
    final items = m['items'];
    if (items is! List ||
        items.length > 50 ||
        m['nextCursor'] != null && m['nextCursor'] is! String) {
      throw const FormatException('Invalid post page');
    }
    return PostsPage<T>(
      items: items.map(decode).toList(growable: false),
      nextCursor: PostProtocol.cursor(m['nextCursor'] as String?),
    );
  }
}

class PostCapabilities {
  const PostCapabilities({
    required this.postId,
    required this.canDelete,
    required this.canEdit,
  });
  final String postId;
  final bool canDelete, canEdit;
  static PostCapabilities fromJson(Object? raw) {
    final m = PostJson.record(raw, {'postId', 'canDelete', 'canEdit'});
    if (m['canDelete'] != true || m['canEdit'] != false) {
      throw const FormatException('Invalid post capabilities');
    }
    return PostCapabilities(
      postId: PostJson.id(m, 'postId'),
      canDelete: true,
      canEdit: false,
    );
  }
}

class ComposerContext {
  const ComposerContext({
    required this.selectionState,
    required this.defaultIdentityId,
  });
  final ComposerSelectionState selectionState;
  final String? defaultIdentityId;
  static ComposerContext fromJson(Object? raw) {
    final m = PostJson.record(raw, {'selectionState', 'defaultIdentityId'});
    final state = switch (m['selectionState']) {
      'INITIAL_SETUP_REQUIRED' => ComposerSelectionState.initialSetupRequired,
      'DEFAULT_AVAILABLE' => ComposerSelectionState.defaultAvailable,
      'SELECTION_REQUIRED' => ComposerSelectionState.selectionRequired,
      _ => throw const FormatException('Invalid composer selection state'),
    };
    final identity = m['defaultIdentityId'] == null
        ? null
        : PostJson.id(m, 'defaultIdentityId');
    if ((state == ComposerSelectionState.defaultAvailable) !=
        (identity != null)) {
      throw const FormatException('Invalid default identity');
    }
    return ComposerContext(selectionState: state, defaultIdentityId: identity);
  }
}

/// 命令回执是不可变历史事实，不能把 ACCEPTED 当作公开成功。
class PostCommandResult {
  const PostCommandResult({
    required this.state,
    this.operation,
    this.taskId,
    this.postId,
    this.attemptVersion,
    this.taskState,
    this.errorCode,
    this.reason,
  });
  final PostCommandState state;
  final PostOperation? operation;
  final String? taskId, postId, errorCode, reason;
  final int? attemptVersion;
  final PostTaskState? taskState;
  bool get accepted => state == PostCommandState.accepted;
  static PostCommandResult fromJson(Object? raw) {
    final initial = PostJson.record(
      raw,
      {'state'},
      optional: {
        'operation',
        'taskId',
        'postId',
        'attemptVersion',
        'taskState',
        'errorCode',
        'reason',
      },
    );
    switch (initial['state']) {
      case 'UNKNOWN_NOT_OBSERVED':
        PostJson.record(raw, {'state'});
        return const PostCommandResult(
          state: PostCommandState.unknownNotObserved,
        );
      case 'RESULT_EXPIRED':
        PostJson.record(raw, {'state'});
        return const PostCommandResult(state: PostCommandState.resultExpired);
      case 'ACCEPTED':
        final m = PostJson.record(raw, {
          'state',
          'operation',
          'taskId',
          'postId',
          'attemptVersion',
        });
        final op = PostJson.operation(m['operation']);
        if (op != PostOperation.create && op != PostOperation.retry) {
          throw const FormatException('Invalid accepted operation');
        }
        return PostCommandResult(
          state: PostCommandState.accepted,
          operation: op,
          taskId: PostJson.id(m, 'taskId'),
          postId: PostJson.id(m, 'postId'),
          attemptVersion: PostJson.integer(m, 'attemptVersion', 1, 2147483647),
        );
      case 'COMMITTED':
        final op = PostJson.operation(initial['operation']);
        if (op == PostOperation.deletePost) {
          final m = PostJson.record(raw, {'state', 'operation', 'postId'});
          return PostCommandResult(
            state: PostCommandState.committed,
            operation: op,
            postId: PostJson.id(m, 'postId'),
          );
        }
        if (op != PostOperation.cancel && op != PostOperation.hideTask) {
          throw const FormatException('Invalid committed operation');
        }
        final m = PostJson.record(raw, {
          'state',
          'operation',
          'taskId',
          'attemptVersion',
          if (op == PostOperation.cancel) 'taskState',
        });
        final state = op == PostOperation.cancel
            ? PostJson.taskState(m['taskState'])
            : null;
        if (state == PostTaskState.accepted) {
          throw const FormatException('Invalid cancel outcome');
        }
        return PostCommandResult(
          state: PostCommandState.committed,
          operation: op,
          taskId: PostJson.id(m, 'taskId'),
          taskState: state,
          attemptVersion: PostJson.integer(m, 'attemptVersion', 1, 2147483647),
        );
      case 'REJECTED':
        final m = PostJson.record(raw, {'state', 'operation', 'errorCode'});
        final error = PostJson.text(m, 'errorCode');
        if (!PostJson.businessRejections.contains(error)) {
          throw const FormatException('Invalid rejection');
        }
        return PostCommandResult(
          state: PostCommandState.rejected,
          operation: PostJson.operation(m['operation']),
          errorCode: error,
        );
      case 'NOT_ACCEPTED':
        final m = PostJson.record(raw, {'state', 'operation', 'reason'});
        if (m['reason'] != 'COMMAND_SEALED') {
          throw const FormatException('Invalid command seal');
        }
        return PostCommandResult(
          state: PostCommandState.notAccepted,
          operation: PostJson.operation(m['operation']),
          reason: 'COMMAND_SEALED',
        );
      default:
        throw const FormatException('Invalid post command state');
    }
  }
}

/// DTO 只接受契约字段；公共作者永远不能透传账号或身份内部标识。
class PostJson {
  static const businessRejections = {
    'POST_CONTENT_INVALID',
    'POST_IDENTITY_UNAVAILABLE',
    'POST_CHANNEL_UNAVAILABLE',
    'POSTING_RESTRICTED',
    'ACCOUNT_CLOSING',
    'TASK_NOT_FOUND',
    'TASK_NOT_RETRYABLE',
    'TASK_NOT_HIDEABLE',
    'TASK_VERSION_CONFLICT',
    'POST_NOT_FOUND',
  };
  static Map<String, Object?> record(
    Object? raw,
    Set<String> required, {
    Set<String> optional = const {},
  }) {
    if (raw is! Map<String, Object?> ||
        required.any((key) => !raw.containsKey(key)) ||
        raw.keys.any(
          (key) => !required.contains(key) && !optional.contains(key),
        )) {
      throw const FormatException('Invalid post object fields');
    }
    return raw;
  }

  static String text(
    Map<String, Object?> m,
    String key, {
    int maxLength = 1024,
  }) {
    final value = m[key];
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw const FormatException('Invalid post string');
    }
    PostContentRules.scalarText(value);
    return value;
  }

  static String id(Map<String, Object?> m, String key) =>
      PostProtocol.resourceId(text(m, key));
  static bool boolean(Map<String, Object?> m, String key) {
    if (m[key] is! bool) throw const FormatException('Invalid post boolean');
    return m[key] as bool;
  }

  static int integer(Map<String, Object?> m, String key, int min, int max) {
    final value = m[key];
    if (value is! int || value < min || value > max) {
      throw const FormatException('Invalid post integer');
    }
    return value;
  }

  static DateTime date(Map<String, Object?> m, String key) => utc(text(m, key));
  static DateTime utc(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$')
        .hasMatch(value)) {
      throw const FormatException('Invalid UTC post time');
    }
    final time = DateTime.parse(value);
    if (!time.isUtc ||
        time.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      throw const FormatException('Invalid post calendar time');
    }
    return time;
  }

  static PostOperation operation(Object? value) => switch (value) {
    'CREATE' => PostOperation.create,
    'RETRY' => PostOperation.retry,
    'CANCEL' => PostOperation.cancel,
    'DELETE_POST' => PostOperation.deletePost,
    'HIDE_TASK' => PostOperation.hideTask,
    _ => throw const FormatException('Invalid post operation'),
  };
  static PostTaskState taskState(Object? value) => switch (value) {
    'ACCEPTED' => PostTaskState.accepted,
    'PUBLISHED' => PostTaskState.published,
    'FAILED' => PostTaskState.failed,
    'CANCELLED' => PostTaskState.cancelled,
    _ => throw const FormatException('Invalid post task state'),
  };
}
