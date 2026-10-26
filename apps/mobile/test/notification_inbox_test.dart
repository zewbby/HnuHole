import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/system_notifications/inbox_screen.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_inbox.dart';
import 'package:hnuhole_mobile/src/messaging/direct_message_models.dart';
import 'package:hnuhole_mobile/src/system_notifications/notification_thumbnail.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import 'identity_test_support.dart';

const post = '11111111-1111-4111-8111-111111111111';
const notice = 'i_22222222-2222-4222-8222-222222222222';
Map<String, dynamic> row(
  String identity,
  String body, {
  String kind = 'comment',
}) => {
  'id': notice,
  'kind': kind,
  'identityId': identity,
  'isReply': kind == 'comment',
  'unread': true,
  'version': 2,
  'createdAt': '2030-01-01T00:00:00Z',
  'title': '回复了你',
  'body': body,
  'sourceTitle': '原帖子',
  'actor': kind == 'comment'
      ? {
          'ref': 'ABCDEFGHIJKL',
          'nickname': '发言者',
          'avatar': 'default-v1',
          'state': 'ACTIVE',
        }
      : null,
  'postId': post,
  'commentId': null,
  'targetAvailable': true,
  'hasPostImage': false,
  'newLikeCount': kind == 'like' ? 1 : 0,
  'system': null,
};

class Api implements GovernanceApi {
  bool hasPostImage = false;
  final calls =
      <
        ({
          String method,
          String path,
          Map<String, dynamic>? body,
          Map<String, String>? query,
        })
      >[];
  Future<Map<String, dynamic>> Function(String, Map<String, String>?)? delayed;
  @override
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    calls.add((method: method, path: path, body: body, query: query));
    final identity = query?['identityId'] ?? identityTestId;
    if (path.endsWith('/read')) {
      return GovernanceResponse({
        'id': notice,
        'readVersion': body!['seenVersion'],
      }, identityTestRenewed);
    }
    if (path.endsWith('unread-counts')) {
      return GovernanceResponse({
        'all': 1,
        'reply': 1,
        'like': 0,
        'system': 0,
        'identityUnread': {identityTestId: 1, identityTestSecondId: 1},
      }, identityTestRenewed);
    }
    if (delayed != null) {
      return GovernanceResponse(
        await delayed!(path, query),
        identityTestRenewed,
      );
    }
    return GovernanceResponse({
      'items': [
        {
          ...row(
            identity,
            '${identity == identityTestId ? '甲' : '乙'}${query?['category']}正文',
            kind: query?['category'] == 'like' ? 'like' : 'comment',
          ),
          'hasPostImage': hasPostImage,
        },
      ],
      'nextCursor': null,
    }, identityTestRenewed);
  }
}

Future<(IdentityTestFixture, GovernanceController, Api)> fixture() async {
  final auth = await IdentityTestFixture.create();
  auth.api.items = [
    identityTestItem(name: '面具一'),
    identityTestItem(id: identityTestSecondId, name: '面具二', original: false),
  ];
  final api = Api();
  final controller = GovernanceController(
    api: api,
    sessions: auth.sessions,
    authStore: auth.store,
    identitiesApi: auth.api,
    pendingStore: GovernancePendingStore(IdentityTestVault()),
  );
  return (auth, controller, api);
}

void main() {
  testWidgets(
    '320dp dark theme and large type retain equal tabs and source cover',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (auth, c, api) = await fixture();
      api.hasPostImage = true;
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: NotificationInboxScreen(
            controller: c,
            loadImages: (_) async => throw StateError('explicit media fixture'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationThumbnail), findsWidgets);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('notification-tab:reply')))
            .width,
        80,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'notification cover releases its media lease and rejects revoked late bytes',
    (tester) async {
      final access = ValueNotifier(true), bytes = Completer<ImageProvider>();
      var releases = 0;
      const placeholder = AssetImage('unused.png');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationThumbnail(
              postId: post,
              load: (id) async => PostImages(
                postId: id,
                accessGranted: access,
                onRelease: () => releases++,
                images: [
                  PostImage.deferred(
                    loadThumbnail: () => bytes.future,
                    item: ViewerItem.provider(
                      id: 'preview',
                      provider: placeholder,
                      pixelSize: const Size(1, 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      access.value = false;
      bytes.complete(placeholder);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(releases, 1);
      access.dispose();
    },
  );
  testWidgets(
    'four equal tabs, click/swipe and original DM identity geometry',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (auth, c, api) = await fixture();
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          home: HhDmInboxScreen(
            scopeKey: 'test',
            identity: const DmIdentity(id: identityTestId, name: '面具一'),
            identities: const [
              DmInboxIdentity(DmIdentity(id: identityTestId, name: '面具一')),
            ],
            entries: const [],
            onOpen: (_) {},
            onIdentitySelected: (_) {},
          ),
        ),
      );
      final oldSize = tester.getSize(
        find.byKey(const ValueKey('dm-inbox-identity')),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: HhTelegramTheme.create(Brightness.light),
          home: NotificationInboxScreen(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('notification-identity'))),
        oldSize,
      );
      for (final category in ['all', 'reply', 'like', 'system']) {
        expect(
          tester
              .getSize(find.byKey(ValueKey('notification-tab:$category')))
              .width,
          80,
        );
      }
      expect(find.text('5 条未读'), findsNothing);
      expect(find.byTooltip('全部标为已读'), findsNothing);
      expect(find.byTooltip('通知设置'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notification-tab:reply')));
      await tester.pumpAndSettle();
      expect(
        api.calls
            .lastWhere((call) => call.path == '/api/v1/notifications')
            .query!['category'],
        'reply',
      );
      await tester.drag(find.byType(PageView), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(
        api.calls
            .lastWhere((call) => call.path == '/api/v1/notifications')
            .query!['category'],
        'like',
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('notification-tabs')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      expect(
        api.calls
            .lastWhere((call) => call.path == '/api/v1/notifications')
            .query!['category'],
        'system',
      );
    },
  );
  testWidgets(
    'identity switching fences a delayed previous identity response',
    (tester) async {
      final (auth, c, api) = await fixture();
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(home: NotificationInboxScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      final pending = Completer<Map<String, dynamic>>();
      api.delayed = (path, query) async {
        final id = query?['identityId'] ?? identityTestId;
        if (id == identityTestId && query?['category'] == 'reply') {
          return pending.future;
        }
        return {
          'items': [row(id, '乙身份回复')],
          'nextCursor': null,
        };
      };
      await tester.tap(find.byKey(const ValueKey('notification-tab:reply')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('notification-identity')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.byKey(
          const ValueKey('notification-identity:$identityTestSecondId'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete({
        'items': [row(identityTestId, '迟到甲身份回复')],
        'nextCursor': null,
      });
      await tester.pumpAndSettle();
      expect(c.selectedIdentityId, identityTestSecondId);
      expect(find.text('迟到甲身份回复'), findsNothing);
      expect(find.text('乙身份回复').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('opening uses the exact observed version and original target', (
    tester,
  ) async {
    final (auth, c, api) = await fixture();
    addTearDown(() {
      c.dispose();
      auth.dispose();
    });
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationInboxScreen(
          controller: c,
          onOpenPost: (id) async {
            opened.add(id);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('甲all正文').hitTestable());
    await tester.pumpAndSettle();
    expect(opened, [post]);
    final call = api.calls.singleWhere((c) => c.method == 'POST');
    expect(call.body, {'seenVersion': 2});
    expect(call.query, {'identityId': identityTestId});
  });
}
