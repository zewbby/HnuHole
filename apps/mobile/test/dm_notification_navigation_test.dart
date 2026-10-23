import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_notifications.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_screen.dart';

import 'identity_test_support.dart';
import 'login_home_test_support.dart';
import 'dm_chat_test.dart' as p2;
import 'dm_reliability_test.dart' as p1;

class _NavigationDm extends ChangeNotifier implements DmController {
  @override
  bool available = true;
  @override
  String scope = 'stable-window';
  @override
  String? accountId = identityTestAccount;
  @override
  bool chatEnabled = false;
  @override
  String? error;
  @override
  List<Map<String, dynamic>> conversations = [];
  int reads = 0;
  void loaded() {
    conversations = [p2.directory()];
    notifyListeners();
  }

  @override
  Future<List<Map<String, dynamic>>> history(
    String own,
    String peer, {
    int? before,
  }) async => [];
  @override
  Future<String> draft(String own, String peer) async => '';
  @override
  Future<void> visible(List<String> ids) async {
    reads += ids.length;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Runtime extends p2.ChatRuntime {
  _Runtime(super.controller);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

void main() {
  for (final matching in [true, false]) {
    testWidgets(
      'cold notification waits for authenticated directory; matching owner=$matching',
      (tester) async {
        const channel = MethodChannel('test/dm-root');
        final f = HomeTestFixture(), c = _NavigationDm();
        final original = await f.create();
        final n = DmNotifications(
          environment: 'root-test',
          preferences: IdentityTestVault(),
          channel: channel,
        );
        final r = _Runtime(c);
        r.identities = [const DmIdentity(id: p1.own, name: '目标本人身份')];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'takeTap') {
                return {
                  'scope': n.scopeFor(
                    matching ? identityTestAccount : 'another-account',
                  ),
                  'identityId': p1.own,
                  'conversationId': p1.conversation,
                };
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        await tester.pumpWidget(
          app.HnuholeApp(
            directory: original.directory,
            repository: original.repository,
            api: original.api,
            sessions: original.sessions,
            flows: original.flows,
            management: original.management,
            identities: original.identities,
            store: original.store,
            posts: original.posts,
            postApi: original.postApi,
            dm: r,
            dmNotifications: n,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HhDirectMessageScreen), findsNothing);
        c.loaded();
        await tester.pumpAndSettle();
        expect(
          find.byType(HhDirectMessageScreen),
          matching ? findsOneWidget : findsNothing,
        );
        expect(c.reads, 0);
        if (matching) {
          // A second click must replace the current conversation immediately,
          // without waiting for the user to leave the first chat route.
          const secondConversation = '88888888-8888-4888-8888-888888888888';
          c.conversations.add({
            ...p2.directory(),
            'id': secondConversation,
            'peerId': p1.post,
            'peerName': '第二个会话',
          });
          n.pending = DmNotificationTarget(
            n.scopeFor(identityTestAccount),
            p1.own,
            secondConversation,
          );
          n.onTap!();
          await tester.pumpAndSettle();
          expect(
            tester.widget<DmChatRoute>(find.byType(DmChatRoute)).conversation,
            secondConversation,
          );
          expect(c.reads, 0);
          Navigator.of(tester.element(find.byType(DmChatRoute))).pop();
          await tester.pumpAndSettle();
          expect(find.byType(DmInboxRoute), findsOneWidget);
          expect(
            tester
                .widget<DmInboxRoute>(find.byType(DmInboxRoute))
                .initialIdentity,
            p1.own,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
