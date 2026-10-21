import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;

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
class HomeTestFixture {
  final store = AuthStore(IdentityTestVault());
  final sessionApi = _Sessions();
  final channels = _Channels();
  late final directory = ChannelDirectoryController(repository: channels);
  final identitiesApi = IdentityTestApi();
  final postApi = _Posts();
  late AuthSessionController sessions;
  late PostController posts;

  Future<app.HnuholeApp> create({bool signedIn = true}) async {
    if (signedIn) {
      await store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: identityTestToken,
            accountId: identityTestAccount,
            expiresAt: identityTestExpiry,
          ),
        ),
      );
    }
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
    bool openPersonal = true,
    bool directoryPending = false,
    String? expectedChannelId,
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
    if (directoryPending) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
    expect(sessions.isAuthenticated, isTrue);
    expect(store.current!.session!.accountId, account);
    expect(find.byType(AuthScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(PersonalPostsScreen), findsNothing);
    if (directoryPending) return;
    expect(find.byType(FeedScreen), findsOneWidget);
    expect(posts.timelineChannelId, expectedChannelId);
    if (openPersonal) {
      await tester.tap(find.byKey(const ValueKey('feed-account')));
      await tester.pumpAndSettle();
    }
  }
}
