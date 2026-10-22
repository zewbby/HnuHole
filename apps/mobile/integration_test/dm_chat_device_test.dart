import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';

import '../test/support/dm_chat_scenario.dart';

class DeviceChatRuntime implements DmRuntime {
  DeviceChatRuntime(this.controller, this.identities);
  @override
  final DmController controller;
  @override
  List<DmIdentity> identities;
  @override
  final void Function(BuildContext, String)? openPost = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'P2 native encrypted images/ACK, controls and chat management over real TLS',
    (tester) async {
      const config = <String, String>{
        'DM_ORIGIN': String.fromEnvironment('DM_ORIGIN'),
        'DM_CA': String.fromEnvironment('DM_CA'),
        'DM_TOKEN_A': String.fromEnvironment('DM_TOKEN_A'),
        'DM_TOKEN_B': String.fromEnvironment('DM_TOKEN_B'),
        'DM_TOKEN_C': String.fromEnvironment('DM_TOKEN_C'),
        'DM_ACCOUNT_A': String.fromEnvironment('DM_ACCOUNT_A'),
        'DM_ACCOUNT_B': String.fromEnvironment('DM_ACCOUNT_B'),
        'DM_IDENTITY_A': String.fromEnvironment('DM_IDENTITY_A'),
        'DM_IDENTITY_B': String.fromEnvironment('DM_IDENTITY_B'),
        'DM_CONVERSATION': String.fromEnvironment('DM_CONVERSATION'),
        'DM_IMAGE': String.fromEnvironment('DM_IMAGE'),
        'DM_IMAGE_WIDTH': String.fromEnvironment('DM_IMAGE_WIDTH'),
        'DM_IMAGE_HEIGHT': String.fromEnvironment('DM_IMAGE_HEIGHT'),
      };
      expect(config.values.every((v) => v.isNotEmpty), isTrue);
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(config['DM_CA']!));
      final api = HttpPostApi(
        communityBaseUri: Uri.parse(config['DM_ORIGIN']!),
        client: HttpClient(context: trust),
      );
      late DmController c;
      await tester.runAsync(() async {
        c = await exerciseDmChat(
          config,
          api,
          (account) =>
              DmStore.openNative('dm-p2:${config['DM_ACCOUNT_A']}', account),
        );
        // One fresh outgoing native photo also exercises the real chat/viewer
        // UI after the destructive scenario has cleared its older local group.
        final bytes = base64Decode(config['DM_IMAGE']!), id = dmId();
        await c.savePhoto(config['DM_IDENTITY_B']!, config['DM_IDENTITY_A']!, {
          'mediaId': id,
          'sha256': hashes.sha256.convert(bytes).toString(),
          'byteLength': bytes.length,
          'mimeType': 'image/png',
          'width': 7,
          'height': 5,
        }, bytes);
        expect(
          await c.sendPhotos(
            {
              'identityId': config['DM_IDENTITY_B']!,
              'peerId': config['DM_IDENTITY_A']!,
              'conversationId': config['DM_CONVERSATION']!,
              'sourcePostId': '',
              'sourceCommentId': '',
              'text': '',
              'attempt': 1,
            },
            [id],
          ),
          isTrue,
        );
        await c.sync();
      });
      final own = DmIdentity(id: config['DM_IDENTITY_B']!, name: '私信乙'),
          peer = DmIdentity(id: config['DM_IDENTITY_A']!, name: '私信甲');
      await tester.pumpWidget(
        MaterialApp(
          home: DmChatRoute(
            runtime: DeviceChatRuntime(c, [own]),
            own: own,
            peer: peer,
            sourcePost: '',
            conversation: config['DM_CONVERSATION']!,
          ),
        ),
      );
      for (
        var i = 0;
        i < 40 && find.byType(HhDirectMessageScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HhDirectMessageScreen), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('删除边界之后的新消息'), findsOneWidget);
      expect(find.bySemanticsLabel('第1张图片'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('第1张图片'));
      await tester.pumpAndSettle();
      expect(find.byType(HnuImageViewer), findsOneWidget);
      Navigator.of(tester.element(find.byType(HnuImageViewer))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await c.detach();
        c.dispose();
        api.close();
      });
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
