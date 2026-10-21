import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/posts/feed_screen.dart';

import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';

const _b = '00000000-0000-0000-0000-000000000002';
const _channel = '00000000-0000-0000-0000-000000000001';

class _Sessions extends IdentityTestSessionApi {
  int logins = 0;
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async {
    logins++;
    return AuthSession(
      accountId: account,
      sessionToken: identityTestOtherToken,
      expiresAt: identityTestExpiry,
    );
  }
}

class _Channels extends IdentityTestChannels {
  Completer<ChannelDirectoryResult>? wait;
  @override
  Future<ChannelDirectoryResult> loadChannels({
    required String sessionToken,
  }) async => wait?.future ?? super.loadChannels(sessionToken: sessionToken);
}

class _Store implements PostStore {
  _Store(this.accountId);
  @override
  final String accountId;
  @override
  Future<List<StoredPostEntry>> list() async => [];
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Posts extends feed.FeedTestApi {
  _Posts() {
    items = [feed.post(channel: _channel)];
  }
  final personalTokens = <String>[];
  Completer<PostResponse<PostsPage<OwnPostCard>>>? oldPersonal;
  @override
  Future<PostResponse<PostsPage<OwnPostCard>>> ownPosts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async {
    personalTokens.add(sessionToken);
    if (sessionToken == identityTestToken && oldPersonal != null) {
      return oldPersonal!.future;
    }
    return feed.reply(PostsPage(items: [], nextCursor: null));
  }

  @override
  Future<PostResponse<PostsPage<PostTask>>> tasks({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async => feed.reply(PostsPage(items: [], nextCursor: null));
  @override
  Future<PostResponse<ComposerContext>> composerContext({
    required String sessionToken,
  }) async => feed.reply(
    const ComposerContext(
      defaultIdentityId: identityTestId,
      selectionState: ComposerSelectionState.defaultAvailable,
    ),
  );
}

// The shipped root, auth/session controller, post controller and personal/feed
// routes are real. HTTP, secure storage and post storage are host substitutes;
// invoking the publication callback below verifies navigation, not publishing.
class _Fixture {
  final store = AuthStore(IdentityTestVault());
  final sessionApi = _Sessions();
  final channels = _Channels();
  late final directory = ChannelDirectoryController(repository: channels);
  final identitiesApi = IdentityTestApi();
  final postApi = _Posts();
  late AuthSessionController sessions;
  late PostController posts;

  Future<app.HnuholeApp> create() async {
    await store.update(
      (s) => s.copyWith(
        session: SessionRecord(
          token: identityTestToken,
          accountId: identityTestAccount,
          expiresAt: identityTestExpiry,
        ),
      ),
    );
    sessions = AuthSessionController(
      api: sessionApi,
      store: store,
      directory: directory,
    );
    identitiesApi.items = [identityTestItem(name: '账号A的身份')];
    posts = PostController(
      api: postApi,
      sessions: sessions,
      authStore: store,
      identities: identitiesApi,
      openStore: (id) async => _Store(id),
      pollInterval: Duration.zero,
    );
    final unusedHttp = HttpAuthApi(
      communityBaseUri: Uri.parse('https://unused.invalid'),
      verifierBaseUri: Uri.parse('https://verifier.invalid'),
    );
    return app.HnuholeApp(
      directory: directory,
      repository: HttpChannelRepository(
        baseUri: Uri.parse('https://unused.invalid'),
      ),
      api: unusedHttp,
      sessions: sessions,
      store: store,
      posts: posts,
      postApi: HttpPostApi(
        communityBaseUri: Uri.parse('https://unused.invalid'),
      ),
      flows: AuthFlows(
        api: unusedHttp,
        store: store,
        acceptRegistrationSession: sessions.acceptSession,
        clearCommunityAccess: sessions.clearCommunityAccess,
      ),
      identities: IdentityManagementController(
        api: identitiesApi,
        store: store,
        sessions: sessions,
      ),
      management: SecurityManagementController(
        api: unusedHttp,
        store: store,
        passkey: NativePasskeyClient(),
        sessions: sessions,
      ),
    );
  }

  Future<void> loginB(
    WidgetTester tester, {
    String account = _b,
    String name = '账号B的身份',
  }) async {
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号与安全'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出本机'));
    await tester.pumpAndSettle();
    // Logout must leave the auth route on its login form, not pop it as if a
    // fresh login had happened. B is not entered until this assertion passes.
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('账号已登录'), findsNothing);
    expect(sessions.isAuthenticated, isFalse);
    sessionApi.account = account;
    identitiesApi.items = [identityTestItem(name: name)];
    await tester.enterText(find.byType(TextFormField).at(0), 'device_b');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'valid-password-123',
    );
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();
    expect(sessions.isAuthenticated, isTrue);
    expect(store.current!.session!.accountId, account);
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final fromFeed in [false, true]) {
    testWidgets(
      'root My route switches A to B and fences old publication; feed=$fromFeed',
      (tester) async {
        final f = _Fixture();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        State? oldFeed;
        if (fromFeed) {
          tester
              .widget<EntryScreen>(find.byType(EntryScreen))
              .onChannelSelected(f.directory.channels.first);
          await tester.pumpAndSettle();
          oldFeed = tester.state(find.byType(FeedScreen));
          tester.widget<FeedScreen>(find.byType(FeedScreen)).onOpenPersonal!();
        } else {
          await tester.tap(find.byTooltip('我的'));
        }
        await tester.pumpAndSettle();
        expect(find.text('账号A的身份'), findsOneWidget);
        final oldPersonal = tester.widget<PersonalPostsScreen>(
          find.byType(PersonalPostsScreen),
        );
        final oldState = tester.state(find.byType(PersonalPostsScreen));
        await f.sessions.persistSessionMetadata(
          identityTestToken,
          identityTestRenewed,
          () => true,
        );
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(PersonalPostsScreen)), oldState),
          isTrue,
        );
        await f.loginB(tester);
        expect(find.text('账号B的身份'), findsOneWidget);
        expect(find.text('账号A的身份'), findsNothing);
        expect(find.text('请重新核对登录状态'), findsNothing);
        expect(f.postApi.personalTokens, contains(identityTestOtherToken));
        oldPersonal.onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(find.byType(PersonalPostsScreen), findsOneWidget);
        final current = tester.widget<PersonalPostsScreen>(
          find.byType(PersonalPostsScreen),
        );
        current.onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(find.byType(FeedScreen), findsOneWidget);
        expect(find.text('请重新核对登录状态'), findsNothing);
        if (fromFeed) {
          expect(
            identical(tester.state(find.byType(FeedScreen)), oldFeed),
            isFalse,
          );
        }
        final currentFeed = tester.state(find.byType(FeedScreen));
        tester.widget<FeedScreen>(find.byType(FeedScreen)).onOpenPersonal!();
        await tester.pumpAndSettle();
        tester
            .widget<PersonalPostsScreen>(find.byType(PersonalPostsScreen))
            .onPublishedToChannel!(_channel);
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(FeedScreen)), currentFeed),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final status in [null, 401, 503]) {
    testWidgets(
      'late personal read from A cannot change B route/session: $status',
      (tester) async {
        final f = _Fixture();
        f.postApi.oldPersonal = Completer();
        await tester.pumpWidget(await f.create());
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('我的'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await f.loginB(tester);
        expect(find.text('账号B的身份'), findsOneWidget);
        final token = f.store.current!.session!.token;
        final expiry = f.store.current!.session!.expiresAt;
        if (status == null) {
          f.postApi.oldPersonal!.complete(
            feed.reply(PostsPage(items: [], nextCursor: null)),
          );
        } else {
          f.postApi.oldPersonal!.completeError(
            PostFailure(
              kind: status == 401
                  ? PostFailureKind.unauthorized
                  : PostFailureKind.unavailable,
              statusCode: status,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('账号B的身份'), findsOneWidget);
        expect(find.text('请重新核对登录状态'), findsNothing);
        expect(f.sessions.isAuthenticated, isTrue);
        expect(f.store.current!.session!.token, token);
        expect(f.store.current!.session!.expiresAt, expiry);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('same-account explicit new login recreates My window', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.pumpWidget(await f.create());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('我的'));
    await tester.pumpAndSettle();
    final old = tester.state(find.byType(PersonalPostsScreen));
    await f.loginB(tester, account: identityTestAccount, name: '同账号的新窗口');
    expect(find.text('同账号的新窗口'), findsOneWidget);
    expect(
      identical(tester.state(find.byType(PersonalPostsScreen)), old),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'delayed B directory refreshes route props without resetting its window',
    (tester) async {
      final f = _Fixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      tester
          .widget<EntryScreen>(find.byType(EntryScreen))
          .onChannelSelected(f.directory.channels.first);
      await tester.pumpAndSettle();
      tester.widget<FeedScreen>(find.byType(FeedScreen)).onOpenPersonal!();
      await tester.pumpAndSettle();
      f.channels.wait = Completer();
      await f.loginB(tester);
      final feedFinder = find.byType(FeedScreen, skipOffstage: false);
      final state = tester.state(feedFinder);
      expect(tester.widget<FeedScreen>(feedFinder).channels, isEmpty);
      f.channels.wait!.complete(
        await IdentityTestChannels().loadChannels(
          sessionToken: identityTestOtherToken,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FeedScreen>(feedFinder).channels, hasLength(7));
      expect(
        tester
            .widget<PersonalPostsScreen>(find.byType(PersonalPostsScreen))
            .channelNames,
        hasLength(7),
      );
      expect(identical(tester.state(feedFinder), state), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final status in [503, 401]) {
    testWidgets('root feed recovers $status with the correct session policy', (
      tester,
    ) async {
      final f = _Fixture();
      await tester.pumpWidget(await f.create());
      await tester.pumpAndSettle();
      tester
          .widget<EntryScreen>(find.byType(EntryScreen))
          .onChannelSelected(f.directory.channels.first);
      await tester.pumpAndSettle();
      final oldToken = f.store.current!.session!.token;
      f.postApi.timelineFailure = PostFailure(
        kind: status == 401
            ? PostFailureKind.unauthorized
            : PostFailureKind.unavailable,
        code: status == 401 ? 'SESSION_INVALID' : 'AUTHORIZATION_UNAVAILABLE',
        statusCode: status,
      );
      await f.posts.loadTimeline();
      await tester.pumpAndSettle();
      expect(f.sessions.isAuthenticated, isFalse);
      expect(f.store.current!.session?.token, status == 503 ? oldToken : null);
      await tester.tap(find.textContaining(RegExp(r'^(请重新登录|登录或核对会话)$')));
      await tester.pumpAndSettle();
      if (status == 503) {
        await tester.tap(find.text('重新核对会话'));
      } else {
        await tester.enterText(find.byType(TextFormField).at(0), 'device_a');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'valid-password-123',
        );
        await tester.tap(find.byKey(const ValueKey('login-submit')));
      }
      await tester.pumpAndSettle();
      expect(f.sessions.isAuthenticated, isTrue);
      expect(f.sessionApi.logins, status == 503 ? 0 : 1);
      expect(
        f.store.current!.session!.token,
        status == 503 ? oldToken : identityTestOtherToken,
      );
      expect(find.byType(AuthScreen), findsNothing);
      expect(find.text('登录或核对会话'), findsNothing);
      expect(find.text('请重新登录'), findsNothing);
      expect(find.text('今天的校园'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
