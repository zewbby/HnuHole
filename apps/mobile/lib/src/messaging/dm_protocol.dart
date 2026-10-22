import 'dart:convert';
import 'dart:math';

import 'package:characters/characters.dart';

import '../posts/post_api.dart';
import '../posts/post_models.dart';
import '../posts/post_protocol.dart';

String dmId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

bool dmValidText(String text) =>
    text.trim().isNotEmpty &&
    text.characters.length <= 4000 &&
    utf8.encode(text).length <= 16384;

abstract interface class DmApi {
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  });
}

/// Allowlist at the transport boundary; private account keys cannot become UI
/// fields through an untyped server response.
Map<String, dynamic> decodeDm(Object? raw, String resource) {
  if (resource == 'contact') {
    final m = PostJson.record(raw, {
      'peerId',
      'peerName',
      'boundIdentityId',
      'self',
    });
    PostProtocol.resourceId(m['peerId'] as String);
    if (m['boundIdentityId'] != '') {
      PostProtocol.resourceId(m['boundIdentityId'] as String);
    }
    if (m['self'] is! bool || m['peerName'] is! String) {
      throw const FormatException('Invalid contact');
    }
    return m;
  }
  if (resource.startsWith('commands/')) {
    final m = PostJson.record(
      raw,
      {'state', 'attempt'},
      optional: {
        'errorCode',
        'messageId',
        'conversationId',
        'sequence',
        'acceptedAt',
      },
    );
    final state = m['state'];
    if (!{'ABSENT', 'FAILED', 'SENT'}.contains(state) || m['attempt'] is! int) {
      throw const FormatException('Invalid DM receipt');
    }
    if (state == 'ABSENT') {
      if (m['attempt'] != 0 || m.length != 2) {
        throw const FormatException('Invalid absent receipt');
      }
    } else if ((m['attempt'] as int) < 1) {
      throw const FormatException('Invalid DM attempt');
    }
    if (state == 'SENT') {
      for (final k in ['messageId', 'conversationId']) {
        PostProtocol.resourceId(m[k] as String);
      }
      if (m['sequence'] is! int ||
          (m['sequence'] as int) < 1 ||
          DateTime.tryParse(m['acceptedAt'] as String) == null) {
        throw const FormatException('Invalid sent receipt');
      }
    }
    if (state == 'FAILED' &&
        !{
          'POSTING_RESTRICTED',
          'IDENTITY_UNAVAILABLE',
          'CONTACT_UNAVAILABLE',
          'POST_IDENTITY_BOUND',
          'WAITING_FOR_REPLY',
          'PENDING_LIMIT',
        }.contains(m['errorCode'])) {
      throw const FormatException('Invalid failure receipt');
    }
    return m;
  }
  if (resource == 'ack' || resource == 'read') {
    final m = PostJson.record(raw, {'state'});
    if (m['state'] != 'APPLIED') throw const FormatException('Invalid ACK');
    return m;
  }
  final m = PostJson.record(raw, {'items'});
  if (m['items'] is! List || (m['items'] as List).length > 100) {
    throw const FormatException('Invalid DM page');
  }
  final seen = <String>{};
  for (final rawItem in m['items'] as List) {
    final pending = resource == 'pending';
    final item = PostJson.record(
      rawItem,
      pending
          ? {
              'messageId',
              'conversationId',
              'identityId',
              'senderId',
              'sequence',
              'text',
              'acceptedAt',
            }
          : {
              'id',
              'identityId',
              'peerId',
              'peerName',
              'sourcePostId',
              'sequence',
              'unread',
              'waiting',
              'canSend',
            },
    );
    for (final k
        in pending
            ? ['messageId', 'conversationId', 'identityId', 'senderId']
            : ['id', 'identityId', 'peerId', 'sourcePostId']) {
      PostProtocol.resourceId(item[k] as String);
    }
    if (!seen.add(item[pending ? 'messageId' : 'id'] as String) ||
        item['sequence'] is! int ||
        (item['sequence'] as int) < 0) {
      throw const FormatException('Invalid DM sequence');
    }
    if (pending) {
      if (!dmValidText(item['text'] as String) ||
          DateTime.tryParse(item['acceptedAt'] as String) == null) {
        throw const FormatException('Invalid DM delivery');
      }
    } else if (item['unread'] is! int ||
        (item['unread'] as int) < 0 ||
        item['waiting'] is! bool ||
        item['canSend'] is! bool ||
        item['peerName'] is! String) {
      throw const FormatException('Invalid DM directory');
    }
  }
  return m;
}
