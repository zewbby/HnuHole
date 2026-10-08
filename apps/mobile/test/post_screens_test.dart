import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/identity/identity_api.dart';
import 'package:hnuhole_mobile/src/posts/post_controller.dart';
import 'package:hnuhole_mobile/src/posts/post_models.dart';
import 'package:hnuhole_mobile/src/posts/post_screens.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';

const _channelId = '11111111-1111-4111-8111-111111111111';
const _postId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _channel = Channel(
  id: _channelId,
  code: 'buddy',
  name: '搭子',
  initiallyVisible: true,
  displayOrder: 4,
);
final _time = DateTime.utc(2026, 10, 8, 12);
const _active = PostAuthor(
  state: PostAuthorState.active,
  avatar: 'default-v1',
  nickname: '北岸',
);

/// 本替身只验证 widget 与导航/权限遮蔽，不能证明 HTTP 或持久存储。
class _WidgetPosts extends ChangeNotifier implements PostController {
  bool access = true, loading = false;
  int version = 1;
  String? failure, channel;
  List<PostCard> cards = [];
  PostDetail? detail;
  Completer<PostDetail?>? detailWait;
  bool deleteAllowed = false, deleted = false;
  int reads = 0, deletions = 0;
  int saves = 0, publications = 0;
  int personalReads = 0, recoveries = 0, abandonments = 0;
  bool saveSucceeds = true;
  List<ManagedIdentity> identities = [];
  List<PersonalPostItem> personal = [];
  PostDraftEditor? restored;
  @override
  bool get available => access;
  @override
  int get authorityVersion => version;
  @override
  String? get accountId => _accountId;
  @override
  bool get busy => false;
  @override
  String? get errorMessage => failure;
  @override
  List<PostCard> get feedItems => cards;
  @override
  bool get feedLoading => loading;
  @override
  String? get feedCursor => null;
  @override
  String? get feedError => failure;
  @override
  String? get currentChannelId => channel;
  @override
  List<PersonalPostItem> get personalItems => personal;
  @override
  bool get personalLoading => false;
  @override
  bool get personalHasMore => false;
  @override
  String? get personalError => failure;
  @override
  ManagedIdentity? get personalIdentity => identities.firstOrNull;
  @override
  Future<void> loadPersonal({bool more = false}) async {
    personalReads++;
    notifyListeners();
  }

  @override
  Future<void> loadFeed(String channelId, {bool more = false}) async {
    channel = channelId;
    reads++;
    notifyListeners();
  }

  @override
  Future<PostDetail?> loadDetail(String postId) async =>
      detailWait == null ? detail : detailWait!.future;
  @override
  Future<bool> canDelete(String postId) async => deleteAllowed;
  @override
  Future<bool> deletePost(String postId) async {
    deletions++;
    return deleted;
  }

  @override
  bool editorCurrent(PostDraftEditor e) =>
      available && e.accountId == accountId && e.authorityVersion == version;
  @override
  Future<bool> saveDraft(PostDraftEditor e) async {
    saves++;
    e.saved = saveSucceeds;
    e.error = saveSucceeds ? null : '保存失败，当前内容仍保留。';
    notifyListeners();
    return saveSucceeds;
  }

  @override
  Future<bool> discardDraft(PostDraftEditor e) async => true;
  @override
  Future<PostDraftEditor?> restoreDraft(String id) async => restored;
  @override
  Future<PostDraftEditor?> editFailedTask(String taskId) async => restored;
  @override
  Future<PostDraftEditor?> recoverUnaccepted(String id) async {
    recoveries++;
    return restored;
  }

  @override
  Future<void> discardUnaccepted(String id) async {
    abandonments++;
  }

  @override
  Future<void> reconcile(String id) async {}
  @override
  Future<void> seal(String id) async {}
  @override
  Future<bool> publish(PostDraftEditor e) async {
    publications++;
    return true;
  }

  @override
  Future<List<ManagedIdentity>> prepareComposer(PostDraftEditor e) async {
    if (identities.length == 1) e.identityId = identities.single.id;
    return identities;
  }

  void loseAuthority() {
    access = false;
    version++;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected widget test operation');
}

Widget _app(Widget child, {double scale = 1, String? fontFamily}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: fontFamily == null ? null : ThemeData(fontFamily: fontFamily),
      home: child,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    );

void main() {
  PostDraftEditor editor() => PostDraftEditor(
    id: 'draft-widget-1',
    channelId: _channelId,
    accountId: _accountId,
    authorityVersion: 1,
  );
  PostComposerScreen composer(
    _WidgetPosts c,
    PostDraftEditor e, {
    Future<void> Function()? manage,
  }) => PostComposerScreen(
    controller: c,
    editor: e,
    channelName: '搭子',
    onManageIdentities: manage ?? () async {},
    onAuthenticationRequired: () {},
  );
  PersonalPostItem localItem(String state, {String id = 'local-1'}) =>
      PersonalPostItem(
        id: id,
        title: '原操作标题',
        sortAt: _time,
        local: StoredPostEntry(
          id: id,
          revision: 4,
          state: state,
          data: {'channelId': _channelId, 'title': '原操作标题', 'body': '仅本机的原文字'},
          intents: state == 'draft'
              ? []
              : [
                  StoredPostIntent(
                    commandId: _postId,
                    operation: 'CREATE',
                    digest: 'widget-only',
                    payload: {},
                  ),
                ],
        ),
      );
  PersonalPostsScreen personalPage(
    _WidgetPosts c, {
    ValueChanged<String>? onPublished,
  }) => PersonalPostsScreen(
    controller: c,
    channelNames: const {_channelId: '搭子'},
    onManageIdentities: () async {},
    onAuthenticationRequired: () {},
    onPublishedToChannel: onPublished,
  );

  testWidgets('正文可先填写，确认返回保留原文字，编辑只自动保存不发送', (tester) async {
    final c = _WidgetPosts(), e = editor();
    await tester.pumpWidget(_app(composer(c, e)));
    await tester.enterText(
      find.byKey(const ValueKey('post-body-input')),
      '先写的正文',
    );
    await tester.enterText(
      find.byKey(const ValueKey('post-title-input')),
      '后写标题',
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(c.saves, greaterThan(0));
    expect(c.publications, 0);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('确认发布'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('先写的正文'), findsOneWidget);
    expect(find.text('后写标题'), findsOneWidget);
    expect(c.publications, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('保存失败留在编辑页，提供重试复制和明确放弃', (tester) async {
    final c = _WidgetPosts()..saveSucceeds = false, e = editor();
    await tester.pumpWidget(_app(composer(c, e)));
    await tester.enterText(
      find.byKey(const ValueKey('post-body-input')),
      '未保存正文',
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('未保存正文'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.text('复制文字'), findsOneWidget);
    expect(find.text('放弃退出'), findsOneWidget);
    expect(c.publications, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('零身份进入设置后返回原确认且不自动发布', (tester) async {
    final c = _WidgetPosts(),
        e = editor()
          ..title = '标题'
          ..body = '原正文';
    var managements = 0;
    await tester.pumpWidget(
      _app(
        composer(
          c,
          e,
          manage: () async {
            managements++;
            c.identities = [
              ManagedIdentity(
                id: _postId,
                nickname: '新身份',
                avatar: 'default-v1',
                isOriginal: true,
                createdAt: _time,
              ),
            ];
          },
        ),
      ),
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('设置身份'), findsOneWidget);
    await tester.tap(find.text('设置身份'));
    await tester.pumpAndSettle();
    expect(managements, 1);
    expect(find.text('新身份'), findsOneWidget);
    expect(e.body, '原正文');
    expect(c.publications, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('文字列表只显示标题和作者，未实现入口隐藏', (tester) async {
    final c = _WidgetPosts()
      ..cards = [
        PostCard(
          postId: _postId,
          channelId: _channelId,
          title: '一起练英语',
          author: _active,
          publishedAt: _time,
        ),
      ];
    await tester.pumpWidget(
      _app(
        ChannelPostsScreen(
          controller: c,
          channel: _channel,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
          onOpenPersonal: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('一起练英语'), findsOneWidget);
    expect(find.text('北岸'), findsOneWidget);
    expect(find.text('搭子'), findsOneWidget);
    expect(find.text('搜索'), findsNothing);
    expect(find.text('筛选'), findsNothing);
    expect(find.text('消息'), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
    c.loseAuthority();
    await tester.pump();
    expect(find.text('一起练英语'), findsNothing);
    expect(find.text('北岸'), findsNothing);
    expect(find.text('请重新核对登录状态'), findsOneWidget);
    c.dispose();
  });

  testWidgets('滚离顶部后插入新帖子保持原可见锚点', (tester) async {
    final c = _WidgetPosts()
      ..cards = [
        for (var i = 1; i <= 16; i++)
          PostCard(
            postId:
                '22222222-2222-4222-8222-${i.toRadixString(16).padLeft(12, '0')}',
            channelId: _channelId,
            title: '帖子 $i',
            author: _active,
            publishedAt: _time,
          ),
      ];
    await tester.pumpWidget(
      _app(
        ChannelPostsScreen(
          controller: c,
          channel: _channel,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('帖子 9')).dy;
    c.cards = [
      for (var i = 17; i <= 18; i++)
        PostCard(
          postId:
              '22222222-2222-4222-8222-${i.toRadixString(16).padLeft(12, '0')}',
          channelId: _channelId,
          title: '新帖 $i',
          author: _active,
          publishedAt: _time,
        ),
      ...c.cards,
    ];
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      (tester.getTopLeft(find.text('帖子 9')).dy - before).abs(),
      lessThan(2),
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('迟到详情响应不能重新展示旧会话正文', (tester) async {
    final c = _WidgetPosts()..detailWait = Completer<PostDetail?>();
    await tester.pumpWidget(
      _app(PostDetailScreen(controller: c, postId: _postId)),
    );
    await tester.pump();
    c.loseAuthority();
    await tester.pump();
    c.detailWait!.complete(
      PostDetail(
        postId: _postId,
        channelId: _channelId,
        title: '迟到标题',
        body: '迟到正文',
        author: _active,
        publishedAt: _time,
      ),
    );
    await tester.pump();
    expect(find.text('迟到标题'), findsNothing);
    expect(find.text('迟到正文'), findsNothing);
    expect(find.text('请重新核对登录状态'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('空列表与首次失败提供不同状态和真实重试', (tester) async {
    final c = _WidgetPosts();
    await tester.pumpWidget(
      _app(
        ChannelPostsScreen(
          controller: c,
          channel: _channel,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这里还没有帖子'), findsOneWidget);
    c.failure = '暂时不可用';
    c.notifyListeners();
    await tester.pump();
    expect(find.text('暂时无法加载帖子'), findsOneWidget);
    final previous = c.reads;
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(c.reads, previous + 1);
    c.dispose();
  });

  testWidgets('小屏大字的纯文字卡片不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _WidgetPosts()
      ..cards = [
        PostCard(
          postId: _postId,
          channelId: _channelId,
          title: '想找一个晨跑搭子',
          author: _active,
          publishedAt: _time,
        ),
      ];
    await tester.pumpWidget(
      _app(
        ChannelPostsScreen(
          controller: c,
          channel: _channel,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
        ),
        scale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('想找一个晨跑搭子'), findsOneWidget);
    c.dispose();
  });

  testWidgets('注销身份提示不跳转，authority变化后正文立即遮蔽', (tester) async {
    final c = _WidgetPosts()
      ..detail = PostDetail(
        postId: _postId,
        channelId: _channelId,
        title: '原帖标题',
        body: '需要会话保护的正文',
        author: const PostAuthor(
          state: PostAuthorState.accountClosed,
          avatar: 'inactive-v1',
          shortCode: 'ABCDEFGHIJKL',
        ),
        publishedAt: _time,
      );
    await tester.pumpWidget(
      _app(PostDetailScreen(controller: c, postId: _postId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('需要会话保护的正文'), findsOneWidget);
    expect(find.text('注销身份 · ABCDEFGHIJKL'), findsOneWidget);
    await tester.tap(find.text('注销身份 · ABCDEFGHIJKL'));
    await tester.pump();
    expect(find.text('账户已注销'), findsOneWidget);
    c.loseAuthority();
    await tester.pump();
    expect(find.text('需要会话保护的正文'), findsNothing);
    expect(find.text('原帖标题'), findsNothing);
    c.dispose();
  });

  testWidgets('作者删除需要确认，明确成功后不保留旧正文', (tester) async {
    final c = _WidgetPosts()
      ..deleteAllowed = true
      ..deleted = true
      ..detail = PostDetail(
        postId: _postId,
        channelId: _channelId,
        title: '删除目标',
        body: '即将删除的正文',
        author: _active,
        publishedAt: _time,
      );
    await tester.pumpWidget(
      _app(PostDetailScreen(controller: c, postId: _postId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除帖子'));
    await tester.pumpAndSettle();
    expect(c.deletions, 0);
    await tester.tap(find.widgetWithText(FilledButton, '删除帖子'));
    await tester.pumpAndSettle();
    expect(c.deletions, 1);
    expect(find.text('帖子已删除'), findsOneWidget);
    expect(find.text('即将删除的正文'), findsNothing);
    c.dispose();
  });

  testWidgets('删除确认框在会话变化后不能继续执行', (tester) async {
    final c = _WidgetPosts()
      ..deleteAllowed = true
      ..detail = PostDetail(
        postId: _postId,
        channelId: _channelId,
        title: '删除目标',
        body: '原正文',
        author: _active,
        publishedAt: _time,
      );
    await tester.pumpWidget(
      _app(PostDetailScreen(controller: c, postId: _postId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除帖子'));
    await tester.pumpAndSettle();
    c.loseAuthority();
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '删除帖子'), findsNothing);
    expect(find.text('会话已变化，请重新登录。'), findsOneWidget);
    expect(c.deletions, 0);
    c.dispose();
  });

  testWidgets('文字修改不自行推进数据库 revision', (tester) async {
    final c = _WidgetPosts(), e = editor()..revision = 7;
    await tester.pumpWidget(_app(composer(c, e)));
    await tester.enterText(
      find.byKey(const ValueKey('post-title-input')),
      '修改',
    );
    await tester.enterText(find.byKey(const ValueKey('post-body-input')), '正文');
    expect(e.revision, 7);
    expect(e.saved, isFalse);
    await tester.pump(const Duration(milliseconds: 800));
    expect(c.saves, 1);
    expect(e.revision, 7);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('从我的恢复草稿发布成功后交还原通道，返回不重置分页', (tester) async {
    final c = _WidgetPosts()
      ..personal = [localItem('draft')]
      ..restored = (editor()
        ..title = '原操作标题'
        ..body = '原正文')
      ..identities = [
        ManagedIdentity(
          id: _postId,
          nickname: '北岸',
          avatar: 'default-v1',
          isOriginal: true,
          createdAt: _time,
        ),
      ];
    String? publishedChannel;
    await tester.pumpWidget(
      _app(personalPage(c, onPublished: (value) => publishedChannel = value)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('原操作标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认发布'));
    await tester.pumpAndSettle();
    expect(publishedChannel, _channelId);
    expect(c.publications, 1);
    expect(c.personalReads, 1);
    expect(find.text('自己的帖子'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('明确未受理 CREATE 可恢复新草稿，UNKNOWN 仅核对与封印', (tester) async {
    final c = _WidgetPosts()
      ..personal = [localItem('REJECTED')]
      ..restored = (editor()
        ..title = '原操作标题'
        ..body = '原正文');
    await tester.pumpWidget(_app(personalPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原操作标题'));
    await tester.pumpAndSettle();
    expect(find.text('恢复为新草稿'), findsOneWidget);
    expect(find.text('放弃未受理文字'), findsOneWidget);
    await tester.tap(find.text('恢复为新草稿'));
    await tester.pumpAndSettle();
    expect(c.recoveries, 1);
    expect(find.text('原正文'), findsOneWidget);
    expect(c.publications, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();

    final unknown = _WidgetPosts()..personal = [localItem('UNKNOWN')];
    await tester.pumpWidget(_app(personalPage(unknown)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原操作标题'));
    await tester.pumpAndSettle();
    expect(find.text('核对原操作'), findsOneWidget);
    expect(find.text('停止尚未受理的原操作'), findsOneWidget);
    expect(find.text('恢复为新草稿'), findsNothing);
    expect(find.text('放弃未受理文字'), findsNothing);
    expect(find.text('修改文字重试'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unknown.dispose();
  });

  testWidgets('UNKNOWN 仍有旧失败 task 时不展示旧重试或隐藏能力', (tester) async {
    final local = localItem('UNKNOWN');
    final c = _WidgetPosts()
      ..personal = [
        PersonalPostItem(
          id: local.id,
          title: local.title,
          sortAt: local.sortAt,
          local: local.local,
          task: PostTask(
            taskId: _postId,
            postId: _postId,
            channelId: _channelId,
            identityId: _postId,
            attemptVersion: 1,
            state: PostTaskState.failed,
            acceptedAt: _time,
            serverSortAt: _time,
            terminalAt: _time.add(const Duration(seconds: 1)),
            failureCode: 'PUBLICATION_FAILED',
            visible: true,
            contentAvailable: true,
            canRetry: true,
            canCancel: false,
            canHide: true,
            content: const PostContent(title: '原操作标题', body: '原失败正文'),
          ),
        ),
      ];
    await tester.pumpWidget(_app(personalPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原操作标题'));
    await tester.pumpAndSettle();
    expect(find.text('核对原操作'), findsOneWidget);
    expect(find.text('停止尚未受理的原操作'), findsOneWidget);
    expect(find.text('修改文字重试'), findsNothing);
    expect(find.text('删除失败入口'), findsNothing);
    expect(find.text('取消本次发布'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('放弃未受理文字的确认在权限变化后停止执行', (tester) async {
    final c = _WidgetPosts()..personal = [localItem('NOT_ACCEPTED')];
    await tester.pumpWidget(_app(personalPage(c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原操作标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃未受理文字'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '放弃文字'), findsOneWidget);
    c.loseAuthority();
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '放弃文字'), findsNothing);
    expect(find.text('仅本机的原文字'), findsNothing);
    expect(c.abandonments, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  final renderDirectory = Platform.environment['HNUHOLE_UI_RENDER_DIR'];
  if (renderDirectory != null) {
    testWidgets('输出本次实际 Flutter 页面渲染供布局核对', (tester) async {
      final fontPath = Platform.environment['HNUHOLE_UI_RENDER_FONT'];
      final iconFontPath = Platform.environment['HNUHOLE_UI_RENDER_ICON_FONT'];
      String? fontFamily;
      if (fontPath != null) {
        // 只用于布局截图，读取机器已有字体，不添加 app 资产或替代平台验收。
        await tester.runAsync(() async {
          final font = FontLoader('HnuHoleSnapshot');
          font.addFont(
            File(fontPath)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
          await font.load();
          if (iconFontPath != null) {
            final icons = FontLoader('MaterialIcons');
            icons.addFont(
              File(iconFontPath)
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
            await icons.load();
          }
        });
        fontFamily = 'HnuHoleSnapshot';
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _WidgetPosts()
        ..cards = [
          for (final title in [
            '想找一个晨跑搭子',
            '一起练英语',
            '周末徒步有人吗',
            '约个自习搭子',
            '今晚去操场',
            '想一起吃食堂',
          ])
            PostCard(
              postId: 'render-${title.hashCode}',
              channelId: _channelId,
              title: title,
              author: _active,
              publishedAt: _time,
            ),
        ]
        ..identities = [
          ManagedIdentity(
            id: _postId,
            nickname: '北岸',
            avatar: 'default-v1',
            isOriginal: true,
            createdAt: _time,
          ),
        ]
        ..personal = [
          localItem('draft', id: 'draft-render'),
          localItem('REJECTED', id: 'rejected-render'),
          PersonalPostItem(
            id: _postId,
            title: '想找一个晨跑搭子',
            sortAt: _time,
            post: PostCard(
              postId: _postId,
              channelId: _channelId,
              title: '想找一个晨跑搭子',
              author: _active,
              publishedAt: _time,
            ),
          ),
        ];
      Future<void> capture(String name, Widget page) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: _app(page, fontFamily: fontFamily),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final rendered = await boundary.toImage(pixelRatio: 2);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = await Directory(renderDirectory)
              .create(recursive: true);
          await File('${directory.path}/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }

      await capture(
        'channel-list',
        ChannelPostsScreen(
          controller: c,
          channel: _channel,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
          onOpenPersonal: () {},
        ),
      );
      await capture(
        'text-editor',
        composer(
          c,
          editor()
            ..title = '想找一个晨跑搭子'
            ..body =
                '最近想把早起跑步坚持下来，想找一位同学一起。\n\n周二和周四早上七点，在操场跑三公里。速度不快，跑完可以一起吃早饭。',
        ),
      );
      await capture('personal-posts', personalPage(c));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
