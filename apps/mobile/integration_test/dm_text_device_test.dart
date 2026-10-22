import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('DM P1 real Android storage and real HTTPS text recovery', (
    tester,
  ) async {
    const origin = String.fromEnvironment('DM_ORIGIN');
    const ca = String.fromEnvironment('DM_CA');
    const a = String.fromEnvironment('DM_TOKEN_A'),
        b = String.fromEnvironment('DM_TOKEN_B');
    const aa = String.fromEnvironment('DM_ACCOUNT_A'),
        ba = String.fromEnvironment('DM_ACCOUNT_B');
    const ia = String.fromEnvironment('DM_IDENTITY_A'),
        ib = String.fromEnvironment('DM_IDENTITY_B');
    const post = String.fromEnvironment('DM_POST');
    expect(origin, isNotEmpty);
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(base64Decode(ca));
    final api = HttpPostApi(
      communityBaseUri: Uri.parse(origin),
      client: HttpClient(context: trust),
    );
    // Separate noBackup files and native Keystore namespaces for synthetic accounts.
    Future<DmStore> open(String account) =>
        DmStore.openNative('dm-p1-device:$origin', account);
    var controller = DmController(api: api, openStore: open);
    await tester.runAsync(() async {
      await controller.bind(
        account: aa,
        token: a,
        identities: [ia],
        isCurrent: () => true,
      );
      final contact = await controller.contact(post, '');
      expect(contact['peerId'], ib);
      await controller.saveDraft(ia, ib, '你好，真机可靠文字');
      expect(
        await controller.send({
          'identityId': ia,
          'peerId': ib,
          'conversationId': '',
          'sourcePostId': post,
          'sourceCommentId': '',
          'text': '你好，真机可靠文字',
          'attempt': 1,
        }),
        isTrue,
      );
      await controller.sync();
      expect((await controller.history(ia, ib)).single['_state'], 'unknown');
      await controller.detach();
      controller.dispose();
      controller = DmController(api: api, openStore: open);
      await controller.bind(
        account: aa,
        token: a,
        identities: [ia],
        isCurrent: () => true,
      );
      final sent = (await controller.history(ia, ib)).single;
      expect(sent['_state'], 'sent');
      expect(await controller.draft(ia, ib), '');
      final conv = (sent['receipt'] as Map)['conversationId'] as String;
      await controller.detach();
      controller.dispose();
      final receiver = DmController(api: api, openStore: open);
      await receiver.bind(
        account: ba,
        token: b,
        identities: [ib],
        isCurrent: () => true,
      );
      final incoming = (await receiver.history(ib, ia)).single;
      expect(incoming['text'], '你好，真机可靠文字');
      expect(incoming['_state'], 'inbox');
      expect(
        (await api.dmRequest(b, 'GET', 'pending')).value['items'],
        isEmpty,
      );
      final unread = (await api.dmRequest(
        b,
        'GET',
        'conversations',
        query: {'identityId': ib},
      )).value;
      expect((unread['items'] as List).single['unread'], 1);
      await receiver.visible([incoming['_id']]);
      await receiver.sync();
      expect(
        await receiver.send({
          'identityId': ib,
          'peerId': ia,
          'conversationId': conv,
          'sourcePostId': '',
          'sourceCommentId': '',
          'text': '收到，离线回复',
          'attempt': 1,
        }),
        isTrue,
      );
      await receiver.sync();
      await receiver.detach();
      receiver.dispose();
      controller = DmController(api: api, openStore: open);
      await controller.bind(
        account: aa,
        token: a,
        identities: [ia],
        isCurrent: () => true,
      );
      final history = await controller.history(ia, ib);
      expect(history.length, 2);
      expect(history.last['text'], '收到，离线回复');
      await controller.saveDraft(ia, ib, '重开后保留的草稿');
      await controller.detach();
      controller.dispose();
      final reopened = await open(aa);
      expect(await reopened.draft(ia, ib), '重开后保留的草稿');
      expect((await reopened.history(ia, ib)).length, 2);
      await reopened.close();
      api.close();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('可靠文字收发 · 真机验收通过'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('可靠文字收发 · 真机验收通过'), findsOneWidget);
  });
}
