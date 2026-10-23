import 'dart:convert';

import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

/// Shared assertions for the real Dart HTTPS host and native Android runs.
/// The external fixture owns real synthetic sessions/PostgreSQL and injects an
/// invalid original for image positions 7/8 on attempt1 only.
Future<DmController> exerciseDmChat(
  Map<String, String> config,
  HttpPostApi api,
  DmStoreFactory open,
) async {
  final a = config['DM_TOKEN_A']!,
      b = config['DM_TOKEN_B']!,
      ia = config['DM_IDENTITY_A']!,
      ib = config['DM_IDENTITY_B']!,
      conv = config['DM_CONVERSATION']!;
  final bytes = base64Decode(config['DM_IMAGE']!);
  final sender = DmController(api: api, chatEnabled: true, openStore: open);
  final receiver = DmController(api: api, chatEnabled: true, openStore: open);
  var senderClosed = false;
  try {
    await sender.bind(
      account: config['DM_ACCOUNT_A']!,
      token: a,
      identities: [ia],
      isCurrent: () => true,
    );
    final selected = List.generate(9, (_) => dmId());
    for (final id in selected) {
      await sender.savePhoto(ia, ib, {
        'mediaId': id,
        'sha256': hashes.sha256.convert(bytes).toString(),
        'byteLength': bytes.length,
        'mimeType': 'image/png',
        'width': int.parse(config['DM_IMAGE_WIDTH']!),
        'height': int.parse(config['DM_IMAGE_HEIGHT']!),
      }, bytes);
    }
    expect(
      await sender.sendPhotos({
        'identityId': ia,
        'peerId': ib,
        'conversationId': conv,
        'sourcePostId': '',
        'sourceCommentId': '',
        'text': '',
        'attempt': 1,
      }, selected),
      isTrue,
    );
    await sender.sync();
    var images = (await sender.history(ia, ib))
        .where(
          (r) =>
              r['messageType'] == 'IMAGE' &&
              selected.contains((r['intent'] as Map)['mediaId']),
        )
        .toList();
    expect(images.length, 9);
    expect(images.where((r) => r['_state'] == 'sent').length, 7);
    final failed = images.where((r) => r['_state'] == 'failed').toList();
    expect(failed.length, 2);
    for (final row in failed) {
      await sender.retry(row['_id']);
      await sender.sync();
    }
    images = (await sender.history(ia, ib))
        .where(
          (r) =>
              r['messageType'] == 'IMAGE' &&
              selected.contains((r['intent'] as Map)['mediaId']),
        )
        .toList();
    expect(images.every((r) => r['_state'] == 'sent'), isTrue);
    expect(
      images.map((r) => (r['intent'] as Map)['position']).toSet().length,
      9,
    );
    for (final row in failed) {
      final updated = images.singleWhere((r) => r['_id'] == row['_id']);
      expect((updated['intent'] as Map)['attempt'], 2);
    }
    final sample = (images.first['receipt'] as Map)['messageId'] as String;
    await expectLater(
      api.dmRequest(config['DM_TOKEN_C']!, 'GET', 'chat/media/$sample'),
      throwsA(
        isA<PostFailure>().having(
          (e) => e.kind,
          'kind',
          PostFailureKind.rejected,
        ),
      ),
    );
    await receiver.bind(
      account: config['DM_ACCOUNT_B']!,
      token: b,
      identities: [ib],
      isCurrent: () => true,
    );
    final inbox = await receiver.history(ib, ia);
    final incoming = inbox
        .where(
          (r) =>
              r['messageType'] == 'IMAGE' &&
              selected.contains((r['media'] as Map)['mediaId']),
        )
        .toList();
    expect(incoming.length, 9);
    for (final row in incoming) {
      expect(row['_state'], 'inbox');
      expect(
        await receiver.photo(
          (row['media'] as Map)['mediaId'],
          senderId: row['senderId'],
        ),
        orderedEquals(bytes),
      );
    }
    await expectLater(
      api.dmRequest(b, 'GET', 'chat/media/$sample'),
      throwsA(isA<PostFailure>()),
    );
    final directory = receiver.conversations.singleWhere(
      (d) => d['id'] == conv,
    );
    final unread = directory['unread'] as int;
    expect(unread, greaterThanOrEqualTo(9));
    await receiver.manage(
      directory,
      'SETTINGS',
      note: '本机搜索备注',
      pinned: true,
      muted: true,
    );
    await receiver.sync();
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['note'],
      '本机搜索备注',
    );
    final senderDirectory = (await api.dmRequest(
      a,
      'GET',
      'chat/conversations',
      query: {'identityId': ia},
    )).value;
    expect(
      ((senderDirectory['items'] as List).single as Map)['note'],
      isNot('本机搜索备注'),
    );
    await receiver.manage(
      receiver.conversations.singleWhere((d) => d['id'] == conv),
      'HIDE',
    );
    await receiver.sync();
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['hidden'],
      isTrue,
    );
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['unread'],
      unread,
    );
    Future<void> sendText(String text) async {
      expect(
        await sender.send({
          'identityId': ia,
          'peerId': ib,
          'conversationId': conv,
          'sourcePostId': '',
          'sourceCommentId': '',
          'text': text,
          'attempt': 1,
        }),
        isTrue,
      );
      await sender.sync();
    }

    await sendText('隐藏后到达的新文字');
    await receiver.sync();
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['hidden'],
      isFalse,
    );
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['unread'],
      unread + 1,
    );
    // Receiver has ACKed the original: a fresh local store gets directory/read
    // metadata, not historical pixels. It must not silently clear old unread.
    await receiver.detach();
    final fresh = DmController(
      api: api,
      chatEnabled: true,
      openStore: (account) => open('fresh:$account'),
    );
    await fresh.bind(
      account: config['DM_ACCOUNT_B']!,
      token: b,
      identities: [ib],
      isCurrent: () => true,
    );
    expect(await fresh.history(ib, ia), isEmpty);
    expect(
      fresh.conversations.singleWhere((d) => d['id'] == conv)['note'],
      '本机搜索备注',
    );
    expect(
      fresh.conversations.singleWhere((d) => d['id'] == conv)['unread'],
      unread + 1,
    );
    await fresh.detach();
    fresh.dispose();
    await receiver.bind(
      account: config['DM_ACCOUNT_B']!,
      token: b,
      identities: [ib],
      isCurrent: () => true,
    );
    // Offline control replay must erase an already ACKed original as well.
    await receiver.detach();
    await sender.manage(
      sender.conversations.singleWhere((d) => d['id'] == conv),
      'RETRACT',
      messageId: sample,
    );
    await sender.sync();
    await receiver.bind(
      account: config['DM_ACCOUNT_B']!,
      token: b,
      identities: [ib],
      isCurrent: () => true,
    );
    expect(
      (await receiver.history(
        ib,
        ia,
      )).singleWhere((r) => r['_id'] == sample)['recalled'],
      isTrue,
    );
    await receiver.saveDraft(ib, ia, '将删除的本机草稿');
    await receiver.manage(
      receiver.conversations.singleWhere((d) => d['id'] == conv),
      'DELETE',
    );
    await receiver.sync();
    expect(await receiver.history(ib, ia), isEmpty);
    expect(await receiver.draft(ib, ia), '');
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['note'],
      '本机搜索备注',
    );
    await sendText('删除边界之后的新消息');
    await receiver.sync();
    expect((await receiver.history(ib, ia)).single['text'], '删除边界之后的新消息');
    expect(
      receiver.conversations.singleWhere((d) => d['id'] == conv)['deleted'],
      isFalse,
    );
    await sender.detach();
    sender.dispose();
    senderClosed = true;
    return receiver;
  } catch (_) {
    await receiver.detach();
    receiver.dispose();
    rethrow;
  } finally {
    if (!senderClosed) {
      await sender.detach();
      sender.dispose();
    }
  }
}
