import '../posts/post_models.dart';
import '../posts/post_protocol.dart';
import '../messaging/direct_message_models.dart';
import 'notification_models.dart';

class InboxNotice {
  const InboxNotice({
    required this.id,
    required this.kind,
    required this.unread,
    required this.version,
    required this.createdAt,
    required this.title,
    required this.body,
    required this.sourceTitle,
    required this.available,
    required this.isReply,
    required this.newLikes,
    required this.hasPostImage,
    this.identityId,
    this.postId,
    this.commentId,
    this.actor,
    this.system,
  });
  final String id, kind, title, body, sourceTitle;
  final String? identityId, postId, commentId;
  final bool unread, available, isReply;
  final int version, newLikes;
  final bool hasPostImage;
  final DateTime createdAt;
  final DmIdentity? actor;
  final SystemNotice? system;
  static InboxNotice parse(Object? raw, String? selected) {
    final m = PostJson.record(raw, {
      'id',
      'kind',
      'identityId',
      'isReply',
      'unread',
      'version',
      'createdAt',
      'title',
      'body',
      'sourceTitle',
      'actor',
      'postId',
      'commentId',
      'targetAvailable',
      'hasPostImage',
      'newLikeCount',
      'system',
    });
    final id = PostJson.text(m, 'id'), kind = PostJson.text(m, 'kind');
    if (!RegExp(r'^[is]_[a-f0-9-]{36}$').hasMatch(id) ||
        !{'comment', 'like', 'system'}.contains(kind)) {
      throw const FormatException('Invalid inbox notice');
    }
    PostProtocol.resourceId(id.substring(2));
    final identity = m['identityId'] == null
        ? null
        : PostJson.id(m, 'identityId');
    if (kind != 'system' && identity != selected) {
      throw const FormatException('Cross-identity notice');
    }
    DmIdentity? actor;
    if (m['actor'] != null) {
      final a = PostJson.record(m['actor'], {
            'ref',
            'nickname',
            'avatar',
            'state',
          }),
          ref = PostJson.text(a, 'ref');
      if (kind != 'comment' ||
          !RegExp(r'^[A-Z2-7]{12}$').hasMatch(ref) ||
          !{
            'ACTIVE',
            'ACCOUNT_CLOSED',
            'IDENTITY_DELETED',
          }.contains(a['state'])) {
        throw const FormatException('Invalid public actor');
      }
      actor = DmIdentity(
        id: ref,
        name: PostJson.text(a, 'nickname'),
        avatar: PostJson.text(a, 'avatar'),
      );
    }
    final system = m['system'] == null ? null : SystemNotice.parse(m['system']);
    if ((kind == 'system') != (system != null) ||
        (kind == 'system') != id.startsWith('s_')) {
      throw const FormatException('Invalid notice source');
    }
    return InboxNotice(
      id: id,
      kind: kind,
      identityId: identity,
      isReply: PostJson.boolean(m, 'isReply'),
      unread: PostJson.boolean(m, 'unread'),
      version: PostJson.integer(m, 'version', 1, 9007199254740991),
      createdAt: PostJson.date(m, 'createdAt'),
      title: PostJson.text(m, 'title', maxLength: 512, allowEmpty: true),
      body: PostJson.text(m, 'body', maxLength: 2048, allowEmpty: true),
      sourceTitle: PostJson.text(
        m,
        'sourceTitle',
        maxLength: 2048,
        allowEmpty: true,
      ),
      actor: actor,
      postId: m['postId'] == null ? null : PostJson.id(m, 'postId'),
      commentId: m['commentId'] == null ? null : PostJson.id(m, 'commentId'),
      available: PostJson.boolean(m, 'targetAvailable'),
      hasPostImage: PostJson.boolean(m, 'hasPostImage'),
      newLikes: PostJson.integer(m, 'newLikeCount', 0, 9007199254740991),
      system: system,
    );
  }
}
