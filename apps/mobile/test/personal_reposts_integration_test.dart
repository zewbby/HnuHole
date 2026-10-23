import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'package:hnuhole_mobile/src/posts/post_interactions_api.dart';

import 'feed_interactions_test.dart' as interaction_test;
import 'feed_ui_test.dart' as feed;
import 'identity_test_support.dart';
import 'login_home_test_support.dart';

const secondIdentity = '22222222-2222-4222-8222-222222222222';
const unavailableId = '44444444-4444-4444-8444-444444444444';

// Exercise the shipped app routes and one real PostController. Only transport
// and storage are substituted; source SQL/concurrency evidence is separate.
class PersonalRepostsApi extends HomeTestPostsApi
    implements PostRepostsApi, PostInteractionsApi {
  final interactionApi = interaction_test.InteractionTestApi();
  final rows = <String, RepostedPost>{};
  final mutations = <String>[];
  final pages = <String?>[];
  int generation = 0;
  String get version => '"${generation.toRadixString(16).padLeft(64, '0')}"';
  PostResponse<T> response<T>(T value) => PostResponse(
    value: value,
    serverTime: feed.at,
    sessionExpiresAt: identityTestRenewed,
    requestId: AuthCrypto.encode(List.filled(16, 9)),
    statusCode: 200,
    interactionVersion: version,
  );

  @override
  Future<PostResponse<PostRepostSnapshot>> postReposts({
    required String sessionToken,
    required String postId,
  }) async => response(
    PostRepostSnapshot(postId, [
      if (sessionToken == identityTestToken)
        for (final row in rows.values.where((r) => r.postId == postId))
          PostRepostMark(row.identityId, row.repostedAt),
    ]),
  );

  @override
  Future<PostResponse<PostRepostSnapshot>> setPostRepost({
    required String sessionToken,
    required String postId,
    required String identityId,
    required bool reposted,
    required String version,
  }) async {
    expect(sessionToken, identityTestToken);
    expect(version, this.version);
    mutations.add('$identityId/$postId:$reposted');
    final key = '$identityId/$postId';
    if (reposted) {
      final original = (await detail(
        sessionToken: sessionToken,
        postId: postId,
      )).value;
      rows.putIfAbsent(
        key,
        () => RepostedPost(
          postId: postId,
          identityId: identityId,
          repostedAt: feed.at.add(Duration(minutes: generation)),
          post: original,
        ),
      );
    } else {
      rows.remove(key);
    }
    generation++;
    return postReposts(sessionToken: sessionToken, postId: postId);
  }

  @override
  Future<PostResponse<PostsPage<RepostedPost>>> ownReposts({
    required String sessionToken,
    String? cursor,
    int limit = 20,
  }) async {
    pages.add(cursor);
    final sorted = sessionToken == identityTestToken
        ? rows.values.toList()
        : <RepostedPost>[];
    sorted.sort((a, b) => b.repostedAt.compareTo(a.repostedAt));
    final start = cursor == null ? 0 : int.parse(cursor);
    // A small server page exercises the UI's cursor path with two identities.
    return response(
      PostsPage(
        items: sorted.skip(start).take(1).toList(),
        nextCursor: start + 1 < sorted.length ? '${start + 1}' : null,
      ),
    );
  }

  @override
  Future<PostResponse<List<PostInteractions>>> interactions({
    required String sessionToken,
    required List<String> postIds,
  }) =>
      interactionApi.interactions(sessionToken: sessionToken, postIds: postIds);
  @override
  Future<PostResponse<PostInteractions>> postInteractions({
    required String sessionToken,
    required String postId,
  }) => interactionApi.postInteractions(
    sessionToken: sessionToken,
    postId: postId,
  );
  @override
  Future<PostResponse<PostInteractions>> setPostLike({
    required String sessionToken,
    required String postId,
    required bool liked,
    required String version,
  }) => interactionApi.setPostLike(
    sessionToken: sessionToken,
    postId: postId,
    liked: liked,
    version: version,
  );
  @override
  Future<PostResponse<PostInteractions>> setPostFavorite({
    required String sessionToken,
    required String postId,
    required bool favorited,
    required String version,
  }) => interactionApi.setPostFavorite(
    sessionToken: sessionToken,
    postId: postId,
    favorited: favorited,
    version: version,
  );
}

Finder row(String identity, [String post = feed.postId]) =>
    find.byKey(ValueKey('personal-repost:$identity/$post'));
Finder cancel(String identity, [String post = feed.postId]) =>
    find.byKey(ValueKey('cancel-repost:$identity/$post'));
Finder menu(String identity, [String post = feed.postId]) => find.descendant(
  of: row(identity, post),
  matching: find.byTooltip('帖子更多操作'),
);
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'feed/detail -> aggregate personal sliver -> original -> exact cancel; refresh, unavailable and account change',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PersonalRepostsApi();
      final f = HomeTestFixture(api: api);
      final app = await f.create();
      final reportApi = HttpGovernanceApi(
        baseUri: Uri.parse('https://unused.invalid'),
      );
      final governance = GovernanceController(
        api: reportApi,
        sessions: f.sessions,
        authStore: f.store,
        identitiesApi: f.identitiesApi,
        pendingStore: GovernancePendingStore(IdentityTestVault()),
      );
      addTearDown(governance.dispose);
      addTearDown(reportApi.close);
      await tester.pumpWidget(
        GovernanceScope(controller: governance, child: app),
      );
      await tester.pumpAndSettle();
      f.identitiesApi.items.add(
        identityTestItem(id: secondIdentity, name: '第二身份', original: false),
      );

      // Feed and detail must operate on the same controller and original post.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('repost:${feed.postId}')),
      );
      await tester.tap(find.text('账号A的身份'));
      await tester.pumpAndSettle();
      expect(
        f.posts.repostState(feed.postId).value!.contains(identityTestId),
        isTrue,
      );
      await tapVisible(tester, find.text('关闭'));
      await tapVisible(tester, find.text('今天的校园'));
      expect(
        tester
            .widget<PostDetailScreen>(find.byType(PostDetailScreen))
            .controller,
        same(f.posts),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('repost:${feed.postId}')),
      );
      expect(find.text('已转帖，点击取消'), findsNothing);
      await tester.tap(find.text('第二身份'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('关闭'));
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('feed-account')));
      await tapVisible(tester, find.text('转帖'));
      expect(
        tester
            .widget<PersonalPostsScreen>(find.byType(PersonalPostsScreen))
            .controller,
        same(f.posts),
      );
      expect(find.byType(PersonalRepostsList), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(row(secondIdentity), findsOneWidget);
      expect(find.text('以“第二身份”转帖'), findsNothing);
      expect(find.text(feed.author.nickname!), findsOneWidget);
      expect(f.posts.repostItems.single.post!.body, feed.post().body);
      await tapVisible(tester, find.byKey(const ValueKey('reposts-load-more')));
      expect(api.pages, [null, '1']);
      expect(f.posts.repostItems.map((i) => i.key).toSet(), {
        '$identityTestId/${feed.postId}',
        '$secondIdentity/${feed.postId}',
      });
      expect(row(identityTestId), findsOneWidget);

      // Icon centers stay equally spaced even when count labels differ.
      final iconFinders = [
        for (final action in ['comment'])
          find.byKey(ValueKey('action-glyph:$action:${feed.postId}')),
        find.byType(PostRepostIcon),
        find.byKey(const ValueKey('action-glyph:like:${feed.postId}')),
        find.byKey(const ValueKey('views-glyph:${feed.postId}')),
        find.byKey(const ValueKey('action-glyph:bookmark:${feed.postId}')),
        find.byKey(const ValueKey('action-glyph:share:${feed.postId}')),
      ];
      final centers = iconFinders
          .map(
            (finder) => tester.getCenter(
              find.descendant(of: row(secondIdentity), matching: finder),
            ),
          )
          .toList();
      final spacing = centers[1].dx - centers[0].dx;
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i].dx - centers[i - 1].dx, closeTo(spacing, .5));
        expect(centers[i].dy, closeTo(centers[0].dy, .5));
      }

      // Blue inline action requires confirmation; cancelling preserves records.
      final undo = find.byKey(
        const ValueKey('repost-undo:$secondIdentity/${feed.postId}'),
      );
      expect(tester.widget<IconButton>(undo).color, const Color(0xFF229ED9));
      await tapVisible(tester, undo);
      expect(find.text('确认移除？'), findsOneWidget);
      await tapVisible(tester, find.text('取消'));
      expect(f.posts.repostItems, hasLength(2));

      // Three actions open the real original/report routes, not an archive key.
      await tapVisible(tester, menu(identityTestId));
      expect(find.text('查看帖子'), findsOneWidget);
      expect(find.text('举报帖子'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);
      await tapVisible(tester, find.text('举报帖子'));
      expect(
        tester.widget<ReportScreen>(find.byType(ReportScreen)).postId,
        feed.postId,
      );
      expect(find.text('举报原因'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tapVisible(tester, menu(identityTestId));
      await tapVisible(tester, find.text('查看帖子'));
      expect(
        tester.widget<PostDetailScreen>(find.byType(PostDetailScreen)).postId,
        feed.postId,
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('喜欢'));
      await tapVisible(tester, find.text('转帖'));
      expect(f.posts.repostItems, hasLength(2));
      expect(api.pages, [null, '1']);

      // Changing the profile identity does not filter the aggregate repost tab.
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('切换身份'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('profile-identity-$secondIdentity')),
      );
      expect(f.posts.repostItems, hasLength(2));
      expect(find.text('以“账号A的身份”转帖'), findsNothing);

      // Pull-to-refresh resets pagination, and uses updated original projection.
      final old = api.rows['$secondIdentity/${feed.postId}']!;
      final p = old.post!;
      api.rows[old.key] = RepostedPost(
        postId: old.postId,
        identityId: old.identityId,
        repostedAt: old.repostedAt,
        post: PostDetail(
          postId: p.postId,
          channelId: p.channelId,
          title: p.title,
          body: '刷新后的原帖正文',
          author: p.author,
          publishedAt: p.publishedAt,
          imageCount: 0,
        ),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(api.pages.last, isNull);
      expect(f.posts.repostItems, hasLength(1));
      expect(find.text('刷新后的原帖正文'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('reposts-load-more')));
      expect(find.text('取消此转帖'), findsNothing);
      await tapVisible(tester, menu(identityTestId));
      expect(find.byType(PostDetailScreen), findsNothing);
      await tapVisible(tester, cancel(identityTestId));
      expect(find.text('确认移除？'), findsOneWidget);
      expect(api.rows, hasLength(2));
      await tapVisible(tester, find.text('确认'));
      expect(api.rows.containsKey('$identityTestId/${feed.postId}'), isFalse);
      expect(api.rows.containsKey('$secondIdentity/${feed.postId}'), isTrue);
      expect(f.posts.repostItems.single.identityId, secondIdentity);

      // Hidden/deleted original exposes no cached body and cannot be opened,
      // while its exact-identity cancellation remains available.
      api.rows.clear();
      api.rows['$secondIdentity/$unavailableId'] = RepostedPost(
        postId: unavailableId,
        identityId: secondIdentity,
        repostedAt: feed.at,
        post: null,
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.text('原帖已不可用'), findsOneWidget);
      expect(find.text('刷新后的原帖正文'), findsNothing);
      expect(find.text('今天的校园'), findsNothing);
      await tapVisible(tester, find.text('原帖已不可用'));
      expect(find.byType(PostDetailScreen), findsNothing);
      await tapVisible(tester, menu(secondIdentity, unavailableId));
      final oldCancel = tester
          .widget<ListTile>(cancel(secondIdentity, unavailableId))
          .onTap!;
      expect(
        tester
            .widget<ListTile>(
              find.byKey(
                const ValueKey('view-repost:$secondIdentity/$unavailableId'),
              ),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(
                const ValueKey('report-repost:$secondIdentity/$unavailableId'),
              ),
            )
            .enabled,
        isFalse,
      );
      await tapVisible(tester, cancel(secondIdentity, unavailableId));
      final oldConfirm = tester
          .widget<TextButton>(
            find.byKey(
              const ValueKey(
                'confirm-undo-repost:$secondIdentity/$unavailableId',
              ),
            ),
          )
          .onPressed!;
      await tapVisible(tester, find.text('确认'));
      expect(api.mutations.last, '$secondIdentity/$unavailableId:false');
      expect(find.text('暂无转帖'), findsOneWidget);

      // Seed a retained record so logout must clear a nonempty real controller.
      api.rows['$secondIdentity/$unavailableId'] = RepostedPost(
        postId: unavailableId,
        identityId: secondIdentity,
        repostedAt: feed.at,
        post: null,
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(f.posts.repostItems, hasLength(1));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await f.loginB(tester);
      expect(f.posts.repostItems, isEmpty);
      final writes = api.mutations.length;
      oldCancel();
      oldConfirm();
      await tester.pumpAndSettle();
      expect(api.mutations, hasLength(writes));
      await tapVisible(tester, find.text('转帖'));
      expect(find.text('暂无转帖'), findsOneWidget);
      expect(find.text('原帖已不可用'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
