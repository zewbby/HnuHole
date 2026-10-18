import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../posts/post_models.dart';

String governanceId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

const reportReasons = <String, String>{
  'ADVERTISING': '广告引流',
  'HARASSMENT': '辱骂骚扰',
  'PRIVACY': '泄露隐私',
  'FRAUD': '诈骗',
  'ILLEGAL': '色情或违法内容',
  'OTHER': '其他',
};

class EvidenceImage {
  EvidenceImage(this.mime, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes) {
    if (!{
          'image/jpeg',
          'image/png',
          'image/gif',
          'image/webp',
        }.contains(mime) ||
        bytes.isEmpty ||
        bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Invalid evidence image');
    }
  }
  final String mime;
  final Uint8List bytes;
  Map<String, dynamic> toJson() => {
    'mime': mime,
    'base64': base64Encode(bytes),
  };
  static EvidenceImage parse(Object? raw) {
    final m = PostJson.record(raw, {'mime', 'base64'});
    final encoded = PostJson.text(m, 'base64', maxLength: 3 * 1024 * 1024);
    final bytes = base64Decode(encoded);
    if (base64Encode(bytes) != encoded) {
      throw const FormatException('Noncanonical image');
    }
    return EvidenceImage(PostJson.text(m, 'mime'), bytes);
  }
}

void validateMaterials(
  String description,
  List<EvidenceImage> images, {
  required int textLimit,
  required int imageLimit,
}) {
  if (description.runes.length > textLimit ||
      images.length > imageLimit ||
      images.fold<int>(0, (total, i) => total + i.bytes.length) >
          8 * 1024 * 1024) {
    throw const FormatException('Material budget exceeded');
  }
}

class NotificationRoute {
  const NotificationRoute(this.name, this.resourceId);
  final String name, resourceId;
  static NotificationRoute parse(Object? raw) {
    final m = PostJson.record(raw, {'name', 'resourceId'});
    final name = PostJson.text(m, 'name');
    if (!{'REPORT', 'SANCTION', 'APPEAL', 'COMMENT_FAILURE'}.contains(name)) {
      throw const FormatException('Unknown notification route');
    }
    return NotificationRoute(name, PostJson.id(m, 'resourceId'));
  }
}

class SystemNotice {
  const SystemNotice({
    required this.id,
    required this.eventId,
    required this.source,
    required this.scope,
    required this.kind,
    required this.state,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.route,
    this.identityId,
    this.readAt,
  });
  final String id, eventId, source, scope, kind, state, title, body;
  final String? identityId;
  final DateTime createdAt;
  final DateTime? readAt;
  final NotificationRoute route;
  bool get unread => readAt == null;
  static SystemNotice parse(Object? raw) {
    final m = PostJson.record(
      raw,
      {
        'id',
        'eventId',
        'source',
        'scope',
        'kind',
        'state',
        'title',
        'body',
        'createdAt',
        'route',
      },
      optional: {'identityId', 'readAt'},
    );
    final scope = PostJson.text(m, 'scope');
    final identity = m['identityId'] == null
        ? null
        : PostJson.id(m, 'identityId');
    if (m['source'] != 'SERVER' ||
        !{'ACCOUNT', 'IDENTITY'}.contains(scope) ||
        (scope == 'IDENTITY') != (identity != null)) {
      throw const FormatException('Invalid notice scope');
    }
    return SystemNotice(
      id: PostJson.id(m, 'id'),
      eventId: PostJson.text(m, 'eventId', maxLength: 256),
      source: 'SERVER',
      scope: scope,
      identityId: identity,
      kind: PostJson.text(m, 'kind', maxLength: 64),
      state: PostJson.text(m, 'state', maxLength: 64),
      title: PostJson.text(m, 'title', maxLength: 512),
      body: PostJson.text(m, 'body', maxLength: 2048),
      createdAt: PostJson.date(m, 'createdAt'),
      readAt: m['readAt'] == null ? null : PostJson.date(m, 'readAt'),
      route: NotificationRoute.parse(m['route']),
    );
  }
}

/// Comment task ownership stays with comments-replies. A local entry must be
/// explicitly local; merely rendering or reading it never resolves its task.
abstract interface class CommentFailureProvider {
  List<LocalCommentFailure> entries(String accountId, String identityId);
  Future<void> retry(String accountId, String identityId, String taskId);
  Future<void> discard(String accountId, String identityId, String taskId);
}

class LocalCommentFailure {
  const LocalCommentFailure({
    required this.taskId,
    required this.identityId,
    required this.createdAt,
    required this.content,
    required this.targetLabel,
  });
  final String taskId, identityId, content, targetLabel;
  final DateTime createdAt;
  String get source => 'LOCAL_COMMENT_TASK';
}
