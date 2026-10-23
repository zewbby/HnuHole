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
  if (resource.startsWith('chat/')) return decodeDmChat(raw, resource);
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
          'INVALID_IMAGE',
          'COMMAND_CONFLICT',
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

Map<String, dynamic> decodeDmChat(Object? raw, String resource) {
  if (resource.startsWith('chat/operations/')) {
    final m = PostJson.record(raw, {
      'state',
      'errorCode',
      'conversationId',
      'version',
      'settingsVersion',
      'deletedThrough',
      'messageId',
    });
    if (!{'ABSENT', 'APPLIED', 'REJECTED'}.contains(m['state']) ||
        m['errorCode'] is! String ||
        m['conversationId'] is! String ||
        m['messageId'] is! String) {
      throw const FormatException('Invalid DM operation');
    }
    for (final k in ['version', 'settingsVersion', 'deletedThrough']) {
      if (m[k] is! int || (m[k] as int) < 0) {
        throw const FormatException('Invalid DM version');
      }
    }
    for (final k in ['conversationId', 'messageId']) {
      if (m[k] != '') PostProtocol.resourceId(m[k] as String);
    }
    return m;
  }
  if (resource == 'chat/conversations') {
    final m = PostJson.record(raw, {'items'});
    if (m['items'] is! List || (m['items'] as List).length > 100) {
      throw const FormatException('Invalid DM directory');
    }
    final originals = <Map<String, dynamic>>[];
    for (final rawItem in m['items'] as List) {
      final item = PostJson.record(rawItem, {
        'id',
        'identityId',
        'peerId',
        'peerName',
        'sourcePostId',
        'sequence',
        'unread',
        'waiting',
        'canSend',
        'version',
        'settingsVersion',
        'pinned',
        'muted',
        'hidden',
        'deleted',
        'deletedThrough',
        'note',
        'unavailableUnread',
        'sourceTitle',
      });
      for (final k in [
        'version',
        'settingsVersion',
        'deletedThrough',
        'unavailableUnread',
      ]) {
        if (item[k] is! int || (item[k] as int) < 0) {
          throw const FormatException('Invalid DM directory version');
        }
      }
      for (final k in ['pinned', 'muted', 'hidden', 'deleted']) {
        if (item[k] is! bool) {
          throw const FormatException('Invalid DM settings');
        }
      }
      if (item['note'] is! String ||
          (item['note'] as String).characters.length > 100 ||
          utf8.encode(item['note'] as String).length > 400) {
        throw const FormatException('Invalid DM note');
      }
      originals.add(
        Map.of(item)..removeWhere(
          (k, _) => {
            'version',
            'settingsVersion',
            'pinned',
            'muted',
            'hidden',
            'deleted',
            'deletedThrough',
            'note',
            'unavailableUnread',
            'sourceTitle',
          }.contains(k),
        ),
      );
    }
    decodeDm({'items': originals}, 'conversations');
    return m;
  }
  if (resource == 'chat/controls') {
    final m = PostJson.record(raw, {'items', 'next'});
    if (m['items'] is! List ||
        (m['items'] as List).length > 100 ||
        m['next'] is! int ||
        (m['next'] as int) < 0) {
      throw const FormatException('Invalid DM controls');
    }
    var last = 0;
    for (final rawItem in m['items'] as List) {
      final item = PostJson.record(rawItem, {
        'eventId',
        'sequence',
        'identityId',
        'conversationId',
        'messageId',
        'messageSequence',
        'type',
        'createdAt',
      });
      for (final k in [
        'eventId',
        'identityId',
        'conversationId',
        'messageId',
      ]) {
        PostProtocol.resourceId(item[k] as String);
      }
      if (item['type'] != 'RETRACTED' ||
          item['sequence'] is! int ||
          (item['sequence'] as int) <= last ||
          item['messageSequence'] is! int ||
          (item['messageSequence'] as int) < 1 ||
          DateTime.tryParse(item['createdAt'] as String) == null) {
        throw const FormatException('Invalid DM control');
      }
      last = item['sequence'] as int;
    }
    if (last > (m['next'] as int)) {
      throw const FormatException('Invalid DM control cursor');
    }
    return m;
  }
  if (resource.startsWith('chat/images/')) {
    return decodeDm(
      raw,
      'commands/${resource.substring('chat/images/'.length)}',
    );
  }
  if (resource.startsWith('chat/media/')) {
    final m = PostJson.record(raw, {
      'messageId',
      'mediaId',
      'sha256',
      'byteLength',
      'mimeType',
      'width',
      'height',
      'data',
    });
    PostProtocol.resourceId(m['messageId'] as String);
    dmMediaDescriptor(m, withData: true);
    return m;
  }
  if (resource == 'chat/pending') {
    final m = PostJson.record(raw, {'items'});
    if (m['items'] is! List || (m['items'] as List).length > 100) {
      throw const FormatException('Invalid DM chat page');
    }
    final seen = <String>{};
    for (final raw in m['items'] as List) {
      final item = PostJson.record(raw, {
        'messageId',
        'conversationId',
        'identityId',
        'senderId',
        'sequence',
        'text',
        'acceptedAt',
        'kind',
        'groupId',
        'position',
        'groupSize',
        'media',
      });
      for (final k in [
        'messageId',
        'conversationId',
        'identityId',
        'senderId',
      ]) {
        PostProtocol.resourceId(item[k] as String);
      }
      if (!seen.add(item['messageId'] as String) ||
          item['sequence'] is! int ||
          (item['sequence'] as int) < 1 ||
          DateTime.tryParse(item['acceptedAt'] as String) == null) {
        throw const FormatException('Invalid DM chat item');
      }
      if (item['kind'] == 'TEXT') {
        if (!dmValidText(item['text'] as String) || item['media'] != null) {
          throw const FormatException('Invalid DM text');
        }
      } else if (item['kind'] == 'IMAGE') {
        PostProtocol.resourceId(item['groupId'] as String);
        if (item['groupSize'] is! int ||
            (item['groupSize'] as int) < 1 ||
            (item['groupSize'] as int) > 9 ||
            item['position'] is! int ||
            (item['position'] as int) < 0 ||
            (item['position'] as int) >= (item['groupSize'] as int)) {
          throw const FormatException('Invalid DM image group');
        }
        dmMediaDescriptor(
          PostJson.record(item['media'], {
            'mediaId',
            'sha256',
            'byteLength',
            'mimeType',
            'width',
            'height',
          }),
        );
      } else {
        throw const FormatException('Invalid DM kind');
      }
    }
    return m;
  }
  throw const FormatException('Unsupported DM chat response');
}

void dmMediaDescriptor(Map<String, dynamic> m, {bool withData = false}) {
  PostProtocol.resourceId(m['mediaId'] as String);
  PostProtocol.digestValue(m['sha256'] as String);
  if (m['byteLength'] is! int ||
      m['byteLength'] < 1 ||
      m['byteLength'] > 10 * 1024 * 1024 ||
      m['width'] is! int ||
      m['height'] is! int ||
      m['width'] < 1 ||
      m['height'] < 1 ||
      m['width'] > 16384 ||
      m['height'] > 16384 ||
      m['width'] * m['height'] > 12 * 1024 * 1024 ||
      !{
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
      }.contains(m['mimeType']) ||
      withData && m['data'] is! String) {
    throw const FormatException('Invalid DM image');
  }
}
