import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/identity/active_identity_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';

import 'identity_test_support.dart';
import 'login_home_test_support.dart';
import 'notification_inbox_test.dart' as inbox;
import 'dm_chat_test.dart' as dm;

class _Dm extends ChangeNotifier implements DmController {
  @override
  bool available = true;
  @override
  bool chatEnabled = false;
  @override
  String scope = 'identity-test';
  @override
  String? accountId = identityTestAccount;
  @override
  String? error;
  @override
  List<Map<String, dynamic>> conversations = [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Runtime extends dm.ChatRuntime {
  _Runtime(super.controller, this.store);
  final AuthStore store;
  @override
  AuthStore get authStore => store;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

void main() {
  test('selection survives management view cancellation and resets on deletion or authority loss', () async {
    final f = await IdentityTestFixture.create();
    f.api.items = [
      identityTestItem(),
      identityTestItem(id: identityTestSecondId, original: false),
    ];
    final active = ActiveIdentityController(f.controller);
    addTearDown(() {
      active.dispose();
      f.dispose();
    });
    await f.controller.load();
    expect(active.selectedId, identityTestId);
    expect(active.select(identityTestSecondId), isTrue);
    f.controller.cancelView();
    expect(active.selectedId, identityTestSecondId);
    expect(
      active.selectConfirmed(identityTestId, [
        identityTestId,
      ], account: 'another-account'),
      isFalse,
    );
    f.api.items = [identityTestItem()];
    await f.controller.load();
    expect(active.selectedId, identityTestId);
    expect(active.select(identityTestSecondId), isFalse);
    f.sessions.sessionUnavailable(identityTestToken);
    expect(active.selectedId, isNull);
    expect(active.accountId, isNull);
  });
  testWidgets(
    'one identity selection updates notification, DM and personal tabs and every tab keeps compose',
    (tester) async {
      final f = HomeTestFixture();
      final original = await f.create();
      f.identitiesApi.items = [
        identityTestItem(name: '身份一'),
        identityTestItem(
          id: identityTestSecondId,
          name: '身份二',
          original: false,
        ),
      ];
      final api = inbox.Api();
      final governance = GovernanceController(
        api: api,
        sessions: f.sessions,
        authStore: f.store,
        identitiesApi: f.identitiesApi,
        pendingStore: GovernancePendingStore(IdentityTestVault()),
      );
      final runtime = _Runtime(_Dm(), f.store)
        ..identities = const [
          DmIdentity(id: identityTestId, name: '身份一'),
          DmIdentity(id: identityTestSecondId, name: '身份二'),
        ];
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
          governance: governance,
          dm: runtime,
        ),
      );
      await tester.pumpAndSettle();
      for (final destination in [
        'messages',
        'directMessages',
        'personal',
        'home',
      ]) {
        await tester.tap(find.byKey(ValueKey('destination:$destination')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('feed-compose')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('personal-profile')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('profile-identity-$identityTestSecondId')),
      );
      await tester.pumpAndSettle();
      expect(governance.selectedIdentityId, identityTestSecondId);
      await tester.tap(find.byKey(const ValueKey('destination:messages')));
      await tester.pumpAndSettle();
      expect(
        api.calls
            .lastWhere((call) => call.path == '/api/v1/notifications')
            .query!['identityId'],
        identityTestSecondId,
      );
      await tester.tap(find.byKey(const ValueKey('notification-identity')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('notification-identity:$identityTestId')),
      );
      await tester.pumpAndSettle();
      expect(f.posts.personalIdentity?.id, identityTestId);
      await tester.tap(
        find.byKey(const ValueKey('destination:directMessages')),
      );
      await tester.pumpAndSettle();
      expect(find.text('身份一'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dm-inbox-identity')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inbox-identity:$identityTestSecondId')),
      );
      await tester.pumpAndSettle();
      expect(governance.selectedIdentityId, identityTestSecondId);
      expect(f.posts.personalIdentity?.id, identityTestSecondId);
      expect(
        f.posts.newDraft(f.directory.channels.first.id).identityId,
        identityTestSecondId,
      );
      await f.posts.loadTimeline(channelId: f.directory.channels.first.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-compose')));
      await tester.pumpAndSettle();
      expect(find.byType(PostComposerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
