import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import '../integration_test/owned_auth_device_helpers.dart';

class _FileVault implements AuthVault {
  _FileVault(this.file);
  final File file;
  @override
  Future<String?> read() async =>
      file.existsSync() ? file.readAsString() : null;
  @override
  Future<void> write(String value) async {
    await file.writeAsString(value, flush: true);
  }
}

class _FileKey implements BusinessKeyVault {
  _FileKey(this.file);
  final File file;
  @override
  Future<String?> read() async =>
      file.existsSync() ? file.readAsString() : null;
  @override
  Future<void> write(String value) async {
    await file.writeAsString(value, flush: true);
  }
}

/// Same product root/controllers and real HTTPS/SQL scenario on host and phone.
/// Host vault ports are explicitly substituted; only native mode calls main().
Future<Map<String, Object>> runCommunityStage1(
  WidgetTester tester,
  Map<String, dynamic> config, {
  required bool native,
}) async {
  final c = Uri.parse(config['AUTH_COMMUNITY_BASE_URL'] as String);
  final v = Uri.parse(config['AUTH_VERIFIER_BASE_URL'] as String);
  final environment = MobileEnvironment(
    communityBaseUri: c,
    verifierBaseUri: v,
  );
  final run = config['COMMUNITY_STAGE1_RUN_ID'] as String;
  expect(RegExp(r'^community-stage1-[a-f0-9]{10}$').hasMatch(run), isTrue);
  HttpClient client() => HttpClient(
    context: SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        base64Decode(config['AUTH_DEV_CA_BASE64'] as String),
      ),
  );
  Future<Map<String, dynamic>> control(String action) async {
    final http = client();
    try {
      final request = await http.postUrl(c.resolve('/__stage1/control'));
      request.followRedirects = false;
      request.headers.set(
        'Authorization',
        'LabControl ${config['COMMUNITY_STAGE1_CONTROL_TOKEN']}',
      );
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({'action': action}));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      expect(response.statusCode, 200, reason: 'owned stage1 control');
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
    } finally {
      http.close(force: true);
    }
  }

  String Function() diagnostic = () => 'boot';
  Future<void> wait(bool Function() ready, String label) async {
    final timer = Stopwatch()..start();
    while (!ready() && timer.elapsed < const Duration(seconds: 100)) {
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(ready(), isTrue, reason: '$label; ${diagnostic()}');
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tap(Finder finder) async {
    await wait(() => finder.evaluate().length == 1, 'one product action');
    await wait(() {
      if (finder.evaluate().length != 1) return false;
      final widget = tester.widget<Widget>(finder);
      if (widget is ButtonStyleButton) {
        return widget.onPressed != null;
      }
      final parent = find.ancestor(
        of: finder,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      return parent.evaluate().isEmpty ||
          tester.widget<ButtonStyleButton>(parent.first).onPressed != null;
    }, 'enabled product action');
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> input(String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await wait(() => field.evaluate().length == 1, 'one product text field');
    await wait(() {
      if (field.evaluate().length != 1) return false;
      final fieldWidget = tester.widget<Widget>(field);
      if (fieldWidget is TextField) {
        return fieldWidget.enabled != false && !fieldWidget.readOnly;
      }
      if (fieldWidget is TextFormField) {
        return fieldWidget.enabled != false;
      }
      return false;
    }, 'enabled product text field');
    await tester.ensureVisible(field);
    final widget = tester.widget<Widget>(field);
    expect(
      widget is TextField || widget is TextFormField,
      isTrue,
      reason: 'editable product field',
    );
    await tester.enterText(field, value);
    final controller = widget is TextField
        ? widget.controller
        : (widget as TextFormField).controller;
    expect(
      controller?.text == value,
      isTrue,
      reason: 'product field retains typed input',
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> back() async {
    final button = find.byType(BackButton).hitTestable();
    // A product auto-return can remove a back control between async waits.
    // Navigation is read/tapped in one turn; home() still requires the root.
    if (button.evaluate().isNotEmpty) {
      expect(button, findsOneWidget);
      await tester.tap(button);
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  final repository = HttpChannelRepository(baseUri: c, client: client());
  final directory = ChannelDirectoryController(repository: repository);
  app.HnuholeApp? hostRoot;
  Future<PostStore> openHost(String account) async {
    final path = config['hostRunDir'] as String;
    return PostStore.openFile(
      File('$path/$account.sqlite'),
      environment: environment.storageScope,
      accountId: account,
      vault: _FileKey(File('$path/$account.key')),
    );
  }

  if (native) {
    expect(Platform.isAndroid, isTrue);
    app.main();
    await tester.pump();
  } else {
    final path = Directory(config['hostRunDir'] as String);
    await path.create(recursive: true);
    final store = AuthStore(
      _FileVault(File('${path.path}/auth.private.json')),
      scope: environment.storageScope,
    );
    final api = HttpAuthApi(
      communityBaseUri: c,
      verifierBaseUri: v,
      client: client(),
    );
    final sessions = AuthSessionController(
      api: api,
      store: store,
      directory: directory,
    );
    final postApi = HttpPostApi(communityBaseUri: c, client: client());
    final posts = PostController(
      api: postApi,
      sessions: sessions,
      authStore: store,
      identities: api,
      openStore: openHost,
      // File-port equivalent of main's idempotent native purge dependency.
      purgeStore: (id) async {
        PostStore? opened;
        try {
          opened = await openHost(id);
          await opened.purgeClosedAccount();
        } on PostStorageClosed {
          // An existing durable CLOSED tombstone is the required result.
        } finally {
          await opened?.close();
        }
      },
    );
    final passkey = NativePasskeyClient();
    final flows = AuthFlows(
      api: api,
      store: store,
      acceptRegistrationSession: sessions.acceptSession,
      clearCommunityAccess: sessions.clearCommunityAccess,
      passkeyApi: api,
      passkey: passkey,
      sessionAuthorityVersion: () => sessions.authorityVersion,
      sessionAuthority: sessions,
      onAccountClosed: posts.purgeClosedAccount,
    );
    hostRoot = app.HnuholeApp(
      directory: directory,
      repository: repository,
      api: api,
      sessions: sessions,
      flows: flows,
      store: store,
      posts: posts,
      postApi: postApi,
      identities: IdentityManagementController(
        api: api,
        store: store,
        sessions: sessions,
      ),
      management: SecurityManagementController(
        api: api,
        store: store,
        passkey: passkey,
        sessions: sessions,
      ),
    );
    await tester.pumpWidget(hostRoot);
  }
  await wait(
    () => find.byType(app.HnuholeApp).evaluate().isNotEmpty,
    'production root mounted',
  );
  final root = tester.widget<app.HnuholeApp>(find.byType(app.HnuholeApp));
  final sessions = root.sessions, posts = root.posts;
  diagnostic = () =>
      'session=${sessions.status.name}; postAvailable=${posts.available}; authError=${sessions.error}; flow=${root.flows.status.name}; authRoutes=${find.byType(AuthScreen).evaluate().length}';
  final checks = <String, bool>{};
  final suffix = run.substring(run.length - 10);
  final userA = 's1a_$suffix', userB = 's1b_$suffix';
  // Synthetic credentials generated only for this new disposable lab.
  final password =
      'Stage1-${AuthCrypto.domainDigest('STAGE1-PASSWORD', utf8.encode(run))}!9';
  Future<void> accountScreen() async {
    if (find.byType(AuthScreen).evaluate().isNotEmpty) return;
    await openOwnedManagement(tester);
    if (find.byType(SettingsScreen).evaluate().isNotEmpty) {
      await tap(find.text('账号与安全'));
    }
    await wait(
      () => find.byType(AuthScreen).evaluate().isNotEmpty,
      'actual account screen',
    );
  }

  Future<void> home() async {
    final timer = Stopwatch()..start();
    while (find.byType(ChannelTree).evaluate().isEmpty &&
        timer.elapsed < const Duration(seconds: 20)) {
      // Read and tap visible navigation in one turn. Route animations may
      // temporarily expose neither control; keep pumping instead of stopping.
      final homeAction = find.text('首页').hitTestable();
      final backAction = find.byType(BackButton).hitTestable();
      if (homeAction.evaluate().length == 1) {
        await tester.tap(homeAction);
      } else if (backAction.evaluate().length == 1) {
        await tester.tap(backAction);
      }
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await wait(
      () => find.byType(ChannelTree).evaluate().isNotEmpty,
      'home navigation',
    );
  }

  Future<void> login(String user) async {
    await accountScreen();
    await wait(
      () => !sessions.busy && !root.flows.busy,
      'account actions settled',
    );
    if (find.text('创建全新账号').evaluate().isNotEmpty) {
      await tap(find.text('创建全新账号'));
      await tap(find.widgetWithText(OutlinedButton, '登录'));
    }
    if (find.text('登录并撤销注销').evaluate().isNotEmpty) {
      await tap(find.text('登录并撤销注销'));
    }
    if (find.text('前往登录').evaluate().isNotEmpty) await tap(find.text('前往登录'));
    await input('login-username', user);
    await input('login-password', password);
    await tap(find.text('登录并进入'));
    await wait(
      () =>
          sessions.isAuthenticated ||
          (!sessions.busy && sessions.error != null),
      'original login completed',
    );
    expect(sessions.isAuthenticated, isTrue, reason: diagnostic());
    await wait(
      () =>
          sessions.isAuthenticated &&
          posts.available &&
          find.byType(AuthScreen).evaluate().isEmpty,
      'actual login accepted',
    );
  }

  Future<void> logout() async {
    await accountScreen();
    await tap(find.text('退出本机'));
    await wait(() => sessions.status == AuthStatus.signedOut, 'actual logout');
  }

  Future<void> requestClosure() async {
    await accountScreen();
    await input('closure-password', password);
    await tap(find.text('查看并确认注销申请'));
    await tap(find.widgetWithText(FilledButton, '申请注销'));
    await wait(
      () => root.flows.status == AuthFlowStatus.closurePending,
      'formal pending closure',
    );
  }

  Future<void> registerStage1(String email, String user) async {
    final mail = Uri.parse(config['AUTH_DEVICE_MAILPIT_URL'] as String);
    if (root.flows.status == AuthFlowStatus.otpConfirmationPending) {
      await root.flows.reconcileOtpConfirmation();
      if (root.flows.canRestartOtpVerification) {
        await tap(find.text('结束过期操作，重新收码'));
      }
    }
    if (root.flows.status != AuthFlowStatus.eligibilityReady) {
      await input('registration-email', email);
      final previous = await smtpFingerprint(mail);
      await tap(find.text('获取验证码'));
      final otp = await smtpOtp(mail, email, excludingMessage: previous);
      await input('registration-otp', otp);
      await tap(find.text('确认验证码'));
      final timer = Stopwatch()..start();
      while (root.flows.status != AuthFlowStatus.eligibilityReady &&
          timer.elapsed < const Duration(seconds: 90)) {
        if (!root.flows.busy &&
            root.flows.status == AuthFlowStatus.otpConfirmationPending) {
          await tap(find.text('核对校邮确认结果'));
        } else if (!root.flows.busy && root.flows.error != null) {
          throw StateError(
            'stage1 OTP status=${root.flows.status.name}; kind=${root.flows.error!.kind.name}; code=${root.flows.error!.code}',
          );
        }
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(
        root.flows.status == AuthFlowStatus.eligibilityReady,
        isTrue,
        reason:
            'original OTP result status=${root.flows.status.name}; busy=${root.flows.busy}; kind=${root.flows.error?.kind.name}; code=${root.flows.error?.code}',
      );
    }
    await input('registration-username', user);
    await input('registration-password', password);
    await tap(find.text('生成并保存恢复码'));
    await wait(
      () => find
          .byKey(const ValueKey('displayed-recovery-code'))
          .evaluate()
          .isNotEmpty,
      'real generated recovery code',
    );
    final recovery = tester
        .widget<Text>(find.byKey(const ValueKey('displayed-recovery-code')))
        .data!;
    await tap(find.text('我已保存，隐藏原码并确认'));
    await input('recovery-confirmation', recovery);
    await tap(find.text('确认恢复码并创建账号'));
    await wait(
      () =>
          sessions.isAuthenticated &&
          posts.available &&
          find.byType(AuthScreen).evaluate().isEmpty,
      'fresh account through product UI',
    );
  }

  PersonalPostItem item(String id) =>
      posts.personalItems.singleWhere((e) => e.id == id);
  try {
    final before = await control('stats');
    expect((before['sql'] as Map)['accounts'], 0);
    await wait(
      () => sessions.status == AuthStatus.signedOut,
      'fresh isolated native/host scope',
    );
    await tap(find.text('登录或注册'));
    // Establish both accounts through the normal registration UI before faults.
    // Keep the cancelled closure receipt intact when later switching accounts.
    await tap(find.text('新注册'));
    await registerStage1('stage1b_$suffix@hainanu.edu.cn', userB);
    await wait(() => posts.available, 'pre-registered second isolated account');
    final accountB = posts.accountId!;
    await logout();
    await tap(find.text('新注册'));
    await registerStage1('stage1a_$suffix@hainanu.edu.cn', userA);
    await wait(
      () =>
          posts.available &&
          root.directory.status == ChannelDirectoryStatus.ready,
      'actual native/host bootstrap',
    );
    checks['CA-A01'] = true;
    checks['CA-A02'] = true;
    await openOwnedManagement(tester);
    await tap(find.text('身份管理'));
    await tap(find.byKey(const ValueKey('identity-add')));
    await input('identity-nickname', '单机验收身份');
    await tap(find.byKey(const ValueKey('identity-save')));
    await wait(
      () =>
          root.identities.directory?.identities.any(
            (e) => e.nickname == '单机验收身份',
          ) ==
          true,
      'real identity stored',
    );
    final identity = root.identities.directory!.identities
        .firstWhere((e) => e.nickname == '单机验收身份')
        .id;
    await home();
    final channel = root.directory.channels.firstWhere((e) => e.code == 'vent');
    final accountA = posts.accountId!;
    final draftA = posts.newDraft(channel.id)
      ..title = 'A保留草稿'
      ..body = '另一账号注销不应影响此草稿';
    expect(await posts.saveDraft(draftA), isTrue);
    await tap(find.text(channel.displayName));
    await control('pause-posts');
    await tap(find.byIcon(Icons.add));
    await input('post-title-input', '单机文字验收');
    await input('post-body-input', '中文与换行\n原身份、原通道 👩‍💻');
    await tap(find.text('下一步'));
    await wait(
      () => find.byIcon(Icons.expand_more).evaluate().isNotEmpty,
      'identity chooser',
    );
    await tap(find.byIcon(Icons.expand_more));
    await tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('单机验收身份'),
      ),
    );
    await control('drop-create');
    final confirm = find.text('确认发布');
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    await wait(
      () => find.byType(PostComposerScreen).evaluate().isEmpty,
      'double submission returns to channel',
    );
    await posts.loadPersonal();
    final pending = posts.personalItems.singleWhere(
      (e) => e.local?.intents.lastOrNull?.operation == 'CREATE',
    );
    final pendingId = pending.id;
    final command = pending.local!.intents.last.commandId;
    final digest = pending.local!.intents.last.digest;
    expect({'SUBMITTED', 'UNKNOWN'}.contains(pending.state), isTrue);
    expect(pending.local!.data['commandState'], 'UNKNOWN');
    for (var n = 0; n < 60; n++) {
      final witnessed = await control('stats');
      if ((witnessed['counters'] as Map)['droppedReplies'] == 1) break;
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final unknown = await control('stats');
    expect((unknown['counters'] as Map)['creates'], 1);
    expect((unknown['counters'] as Map)['droppedReplies'], 1);
    await control('release-queries');
    // The product's normal five-second poller performs the original result read.
    await wait(
      () => item(pendingId).state == 'ACCEPTED',
      'production automatic poll result',
    );
    expect(item(pendingId).local!.intents.last.commandId == command, isTrue);
    expect(item(pendingId).local!.intents.last.digest == digest, isTrue);
    checks['CA-A04'] = true;
    // Formal closure stops the accepted publication via the existing stop hook.
    // Active password login normally cancels that closure; no SQL state is forged.
    await home();
    await requestClosure();
    await login(userA);
    await logout();
    await tap(find.text('核对注销状态'));
    await wait(
      () => root.flows.status == AuthFlowStatus.closureCancelled,
      'authoritative cancelled receipt',
    );
    await tap(find.text('结束已取消的注销操作'));
    await wait(
      () =>
          find.byKey(const ValueKey('login-username')).evaluate().length == 1 &&
          !sessions.busy &&
          !root.flows.busy,
      'cancelled operation ended without login',
    );
    await login(userA);
    await posts.loadPersonal();
    expect(item(pendingId).state, 'FAILED');
    await home();
    await tap(find.byTooltip('我的'));
    await wait(
      () => find.text('单机文字验收').evaluate().isNotEmpty,
      'failed task in personal list',
    );
    await tap(find.text('单机文字验收'));
    // The personal failed card opens the existing retry composer directly.
    // The separate task-detail retry action is not on this navigation path.
    await wait(
      () => find.text('身份和通道保持不变').evaluate().isNotEmpty,
      'immutable retry identity and channel',
    );
    await control('drop-retry');
    await tap(find.text('确认重试'));
    await wait(
      () => find.byType(PostComposerScreen).evaluate().isEmpty,
      'retry submitted',
    );
    await posts.loadPersonal();
    final retried = item(pendingId);
    final retryCommand = retried.local!.intents.last.commandId;
    expect(retried.local!.data['identityId'] == identity, isTrue);
    expect(retried.local!.data['channelId'] == channel.id, isTrue);
    await control('release-queries');
    await wait(
      () => item(pendingId).state == 'ACCEPTED',
      'original retry result automatically reconciled',
    );
    expect(
      item(pendingId).local!.intents.last.commandId == retryCommand,
      isTrue,
    );
    expect(item(pendingId).task!.identityId == identity, isTrue);
    expect(item(pendingId).task!.channelId == channel.id, isTrue);
    final postId = item(pendingId).task!.postId;
    await control('resume-posts');
    await wait(
      () => posts.personalItems.any((e) => e.post?.postId == postId),
      'unchanged actual publication worker',
    );
    await home();
    await tap(find.text(channel.displayName));
    await posts.loadFeed(channel.id);
    await wait(() => find.text('单机文字验收').evaluate().isNotEmpty, 'real feed');
    await tap(find.text('单机文字验收'));
    await wait(
      () => find.byTooltip('删除帖子').evaluate().isNotEmpty,
      'actual detail',
    );
    expect(find.text('中文与换行\n原身份、原通道 👩‍💻'), findsOneWidget);
    await back();
    await tap(find.text('我的'));
    await wait(
      () => find.text('单机文字验收').evaluate().isNotEmpty,
      'personal published list',
    );
    await tap(find.text('单机文字验收'));
    await wait(
      () => find.byTooltip('删除帖子').evaluate().isNotEmpty,
      'personal detail',
    );
    checks['CA-A03'] = true;
    checks['CA-A05'] = true;
    await control('drop-delete');
    await tap(find.byTooltip('删除帖子'));
    await tap(find.byKey(const ValueKey('scoped-confirm-action')));
    for (var n = 0; n < 60; n++) {
      final witnessed = await control('stats');
      if ((witnessed['sql'] as Map)['deleted'] == 1) break;
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect(((await control('stats'))['sql'] as Map)['deleted'], 1);
    await control('release-queries');
    await wait(
      () => posts.isPostDeleted(postId),
      'original deletion automatically reconciled',
    );
    await wait(
      () => find.byType(PostDetailScreen).evaluate().isEmpty,
      'deleted detail returns automatically',
    );
    await posts.loadFeed(channel.id);
    expect(posts.feedItems.isEmpty, isTrue);
    checks['CA-A06'] = true;
    await home();
    await logout();
    await login(userB);
    await wait(() => posts.available, 'second isolated account');
    expect(posts.accountId == accountB, isTrue);
    expect(accountB != accountA, isTrue);
    expect(await posts.restoreDraft(draftA.id), isNull);
    final draftB = posts.newDraft(channel.id)
      ..title = 'B待清理草稿'
      ..body = '闭号只清原账号';
    expect(await posts.saveDraft(draftB), isTrue);
    await openOwnedManagement(tester);
    await tap(find.text('身份管理'));
    await tap(find.byKey(const ValueKey('identity-add')));
    await input('identity-nickname', 'B待关闭身份');
    await tap(find.byKey(const ValueKey('identity-save')));
    await wait(
      () =>
          root.identities.directory?.identities.any(
            (e) => e.nickname == 'B待关闭身份',
          ) ==
          true,
      'second owned identity',
    );
    final identityB = root.identities.directory!.identities
        .firstWhere((e) => e.nickname == 'B待关闭身份')
        .id;
    await control('pause-posts');
    final unpublishedB = posts.newDraft(channel.id)
      ..title = 'B待关闭未公开载荷'
      ..body = '正式闭号后不得保留'
      ..identityId = identityB;
    expect(await posts.publish(unpublishedB), isTrue);
    await wait(
      () => posts.personalItems.any(
        (e) => e.id == unpublishedB.id && e.state == 'ACCEPTED',
      ),
      'second account payload actually accepted',
    );
    final beforeB = await control('stats');
    expect((beforeB['sql'] as Map)['posts'], 2);
    await home();
    await logout();
    await login(userA);
    expect((await posts.restoreDraft(draftA.id))?.title == 'A保留草稿', isTrue);
    expect(await posts.restoreDraft(draftB.id), isNull);
    await home();
    await logout();
    await login(userB);
    checks['CA-A07'] = true;
    await requestClosure();
    await control('advance-closure');
    await wait(() => !root.flows.busy, 'pending closure available');
    for (var n = 0; n < 60; n++) {
      await root.flows.reconcileClosure();
      if ({
        AuthFlowStatus.closureClosedReleasePending,
        AuthFlowStatus.closureReleased,
      }.contains(root.flows.status)) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(
      {
        AuthFlowStatus.closureClosedReleasePending,
        AuthFlowStatus.closureReleased,
      }.contains(root.flows.status),
      isTrue,
    );
    var tombstone = false;
    try {
      final store = native
          ? await PostStore.openNative(
              environment: environment.storageScope,
              accountId: accountB,
            )
          : await openHost(accountB);
      await store.close();
    } on PostStorageClosed {
      tombstone = true;
    }
    expect(
      tombstone,
      isTrue,
      reason: 'original closed business scope cannot reopen',
    );
    final facts = await control('stats');
    final db = facts['sql'] as Map;
    expect(db['closed'], 1);
    expect(db['closedPayloadsRemaining'], 0);
    expect(db['closedPrivateReceiptsRemaining'], 0);
    expect(db['closedCredentialsRemaining'], 0);
    final releaseTimer = Stopwatch()..start();
    while (root.flows.status != AuthFlowStatus.closureReleased &&
        releaseTimer.elapsed < const Duration(seconds: 90)) {
      await tap(find.text('核对注销状态'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(
      root.flows.status,
      AuthFlowStatus.closureReleased,
      reason: 'normal worker and original closure status UI',
    );
    await login(userA);
    expect(
      (await posts.restoreDraft(draftA.id))?.body == '另一账号注销不应影响此草稿',
      isTrue,
    );
    expect(await posts.restoreDraft(draftB.id), isNull);
    checks['CA-A10'] = true;
    final counts = facts['counters'] as Map;
    expect(counts['creates'], 2);
    expect(counts['retries'], 1);
    expect(counts['deletes'], 1);
    expect(counts['uniqueCreates'], 2);
    expect(counts['uniqueRetries'], 1);
    expect(counts['uniqueDeletes'], 1);
    expect(counts['droppedReplies'], 3);
    expect(counts['rawTokensOrProofsStored'], false);
    return {
      'scope': native
          ? 'ACTUAL_ANDROID_DEVICE_RUN'
          : 'HOST_REHEARSAL_NATIVE_PORTS_SUBSTITUTED',
      'checkpoints': native
          ? checks
          : {
              for (final entry in checks.entries)
                'HOST-${entry.key}': entry.value,
            },
      'counters': Map<String, Object>.from(counts),
      'sql': Map<String, Object>.from(db),
      'manualChineseImeVerified': false,
      'phoneUsed': native,
      'actualMainCalled': native,
      'hostVaultSubstitutes': !native,
    };
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
