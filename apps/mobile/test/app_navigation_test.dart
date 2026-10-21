import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';
import 'package:hnuhole_mobile/src/messaging/direct_messages_unavailable.dart';

import 'identity_test_support.dart';
import 'login_home_test_support.dart';

class _Notices implements GovernanceApi {
  final calls = <String>[];
  @override
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add('$method $path');
    return GovernanceResponse({
      'items': <Object>[],
      'nextBefore': null,
    }, identityTestRenewed);
  }
}

void main() {
  testWidgets(
    'root switches separate notification and DM tabs, retaining the feed channel',
    (tester) async {
      final fixture = HomeTestFixture();
      final root = await fixture.create();
      final notices = _Notices();
      final governance = GovernanceController(
        api: notices,
        sessions: fixture.sessions,
        authStore: fixture.store,
        identitiesApi: fixture.identitiesApi,
        pendingStore: GovernancePendingStore(IdentityTestVault()),
      );
      await tester.pumpWidget(
        app.HnuholeApp(
          directory: root.directory,
          repository: root.repository,
          api: root.api,
          sessions: root.sessions,
          flows: root.flows,
          management: root.management,
          identities: root.identities,
          store: root.store,
          posts: root.posts,
          postApi: root.postApi,
          governance: governance,
        ),
      );
      await tester.pumpAndSettle();
      final originalHome = tester.state(find.byType(FeedScreen));
      final channel = fixture.directory.channels.last.id;
      await fixture.posts.loadTimeline(channelId: channel);
      await tester.pumpAndSettle();
      for (var round = 0; round < 2; round++) {
        await tester.tap(find.byKey(const ValueKey('destination:messages')));
        await tester.pumpAndSettle();
        expect(find.byType(SystemNotificationsScreen), findsOneWidget);
        expect(
          tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
          AppDestination.messages,
        );
        final calls = List.of(notices.calls);
        await tester.tap(
          find.byKey(const ValueKey('destination:directMessages')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DirectMessagesUnavailableScreen), findsOneWidget);
        expect(find.text('私信暂未开放'), findsOneWidget);
        expect(find.byType(SystemNotificationsScreen), findsNothing);
        expect(notices.calls, calls);
        await tester.tap(find.byKey(const ValueKey('destination:personal')));
        await tester.pumpAndSettle();
        expect(find.byType(PersonalPostsScreen), findsOneWidget);
        expect(
          tester.widget<HhAppNavigation>(find.byType(HhAppNavigation)).selected,
          AppDestination.personal,
        );
        await tester.tap(find.byKey(const ValueKey('destination:home')));
        await tester.pumpAndSettle();
        expect(
          identical(originalHome, tester.state(find.byType(FeedScreen))),
          isTrue,
        );
        expect(fixture.posts.timelineChannelId, channel);
        expect(
          Navigator.of(tester.element(find.byType(FeedScreen))).canPop(),
          isFalse,
        );
      }
      expect(
        notices.calls.every(
          (call) => call == 'GET /api/v1/system-notifications',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
