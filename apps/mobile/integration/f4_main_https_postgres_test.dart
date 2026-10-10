import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' show HnuholeApp;

// One-time host ports. These are never production secure-storage evidence.
class _AuthFile implements AuthVault {
  _AuthFile(this.file);
  final File file;
  @override
  Future<String?> read() async =>
      await file.exists() ? file.readAsString() : null;
  @override
  Future<void> write(String value) async {
    await file.writeAsString(value, flush: true);
  }
}

class _KeyFile implements BusinessKeyVault {
  _KeyFile(this.file);
  final File file;
  @override
  Future<String?> read() async =>
      await file.exists() ? file.readAsString() : null;
  @override
  Future<void> write(String value) async {
    await file.writeAsString(value, flush: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configPath = Platform.environment['F4_MAIN_CONFIG'];
  if (configPath == null) {
    test(
      'F4 root requires isolated C/V/PG',
      () {},
      skip: 'Use tools/run-community-flutter-f4-linux.sh integration',
    );
    return;
  }
  // Test binding normally supplies an HTTP rejection mock; this opt-in process
  // uses actual sockets and a dedicated CA with normal hostname verification.
  HttpOverrides.global = null;
  testWidgets(
    'F4 production main root, actual transport and durable original command',
    (tester) async {
      tester.view.physicalSize = const Size(480, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final config = jsonDecode(
          File(configPath).readAsStringSync(),
        ) as Map<String, dynamic>;
        final phase = Platform.environment['F4_MAIN_PHASE'];
        final root = config['runDir'] as String;
        final c = Uri.parse(config['communityOrigin'] as String),
            v = Uri.parse(config['verifierOrigin'] as String);
        final environment = MobileEnvironment(
          communityBaseUri: c,
          verifierBaseUri: v,
        );
        final trust = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(config['caPath'] as String);
        final api = HttpAuthApi(
          communityBaseUri: c,
          verifierBaseUri: v,
          client: HttpClient(context: trust),
        );
        final postApi = HttpPostApi(
          communityBaseUri: c,
          client: HttpClient(context: trust),
        );
        final repository = HttpChannelRepository(
          baseUri: c,
          client: HttpClient(context: trust),
        );
        final directory = ChannelDirectoryController(repository: repository);
        final store = AuthStore(
          _AuthFile(File('$root/auth.json')),
          scope: environment.storageScope,
        );
        final sessions = AuthSessionController(
          api: api,
          store: store,
          directory: directory,
        );
        final openedStores = <String, PostStore>{};
        final posts = PostController(
          api: postApi,
          sessions: sessions,
          authStore: store,
          identities: api,
          pollInterval: Duration.zero,
          openStore: (id) async {
            final opened = await PostStore.openFile(
              File('$root/$id.sqlite'),
              environment: environment.storageScope,
              accountId: id,
              vault: _KeyFile(File('$root/$id.key')),
            );
            openedStores[id] = opened;
            return opened;
          },
        );
        final passkey = NativePasskeyClient();
        final management = SecurityManagementController(
          api: api,
          store: store,
          passkey: passkey,
          sessions: sessions,
        );
        final identities = IdentityManagementController(
          api: api,
          store: store,
          sessions: sessions,
        );
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
        final control = HttpClient(context: trust);
        Future<Map<String, dynamic>> fixture(
          String action, [
          Map<String, String> data = const {},
        ]) async {
          final request = await control.postUrl(
            Uri.parse(config['controlOrigin'] as String).resolve('/$action'),
          );
          request.followRedirects = false;
          request.headers.set(
            'Authorization',
            'LabControl ${config['controlToken']}',
          );
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(data));
          final response = await request.close();
          expect(response.statusCode, 200, reason: 'owned F4 control $action');
          return jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
        }

        Future<void> wait(bool Function() predicate, String label) async {
          final elapsed = Stopwatch()..start();
          while (!predicate() &&
              elapsed.elapsed < const Duration(seconds: 20)) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
          expect(predicate(), isTrue, reason: label);
          await tester.pump(const Duration(milliseconds: 350));
        }

        Future<void> tap(Finder finder) async {
          expect(finder, findsOneWidget);
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        }

        Future<void> back() async {
          final button = find.byType(BackButton).hitTestable();
          expect(button, findsOneWidget);
          final route = ModalRoute.of(tester.element(button))!;
          var removed = false;
          route.completed.then((_) => removed = true);
          await tap(button);
          await wait(() => removed, 'top route removed after back animation');
        }

        Future<void> register(String email, String username) async {
          await flows.requestOtp(email);
          expect(flows.status, AuthFlowStatus.otpRequested);
          final mail = await fixture('otp', {'email': email});
          await flows.confirmOtp(mail['code'] as String);
          await flows.createRegistration(
            username,
            'F4 synthetic long password 2026!',
          );
          final recovery = flows.recoveryCode!;
          flows.hideRecoveryCode();
          await flows.commitRegistration(recovery);
          expect(sessions.isAuthenticated, isTrue);
        }

        final stateFile = File('$root/scenario.json');
        final checks = <String, bool>{};
        var state = <String, dynamic>{};
        if (phase == 'write') {
          await sessions.start();
          await register('f4a@hainanu.edu.cn', 'f4_user_a');
          final changed = await api.changeIdentity(
            sessionToken: store.current!.session!.token,
            idempotencyKey: AuthCrypto.randomEncoded(16),
            operation: IdentityOperation.create,
            nickname: 'F4原身份',
          );
          expect(changed.committed, isTrue);
          state['accountId'] = posts.accountId;
          state['identityId'] = changed.identityId;
          await sessions.logout();
          expect(sessions.status, AuthStatus.signedOut);
        } else {
          expect(phase, 'read');
          state = jsonDecode(
            await stateFile.readAsString(),
          ) as Map<String, dynamic>;
        }
        await tester.pumpWidget(
          HnuholeApp(
            directory: directory,
            repository: repository,
            api: api,
            sessions: sessions,
            flows: flows,
            management: management,
            identities: identities,
            store: store,
            posts: posts,
            postApi: postApi,
          ),
        );
        if (phase == 'write') {
          await wait(
            () => sessions.status == AuthStatus.signedOut,
            'root signed out',
          );
          await tap(find.text('登录或注册'));
          await wait(
            () => find
                .byKey(const ValueKey('login-username'))
                .evaluate()
                .isNotEmpty,
            'real login form visible',
          );
          await tester.enterText(
            find.byKey(const ValueKey('login-username')),
            'f4_user_a',
          );
          await tester.enterText(
            find.byKey(const ValueKey('login-password')),
            'F4 synthetic long password 2026!',
          );
          await tap(find.text('登录并进入'));
        }
        await wait(
          () =>
              sessions.isAuthenticated &&
              posts.available &&
              directory.status == ChannelDirectoryStatus.ready,
          'main restores or accepts real session',
        );
        await wait(
          () => find.byType(AuthScreen).evaluate().isEmpty,
          'auth route dismissed',
        );
        if (phase == 'write') checks['F4-H01'] = true;
        final channel = directory.channels.firstWhere((e) => e.code == 'vent');
        state['channelId'] = channel.id;
        if (phase == 'write') {
          await tap(find.byTooltip('My content'));
          await wait(
            () => find.byType(PersonalPostsScreen).evaluate().isNotEmpty,
            'root profile route',
          );
          await tap(find.byTooltip('设置'));
          await tap(find.text('账号与安全'));
          await wait(
            () => find.text('账号已登录').evaluate().isNotEmpty,
            'settings preserves account actions',
          );
          await back();
          await tap(find.text('身份管理'));
          await wait(
            () =>
                find.byType(IdentityManagementScreen).evaluate().isNotEmpty &&
                find.text('F4原身份').evaluate().isNotEmpty,
            'settings identity directory',
          );
          await back();
          await back();
          await tap(find.text('首页'));
          await wait(
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'My home returns root',
          );
          checks['F4-H02'] = true;
          debugPrint('F4-H02 PASS');
        }
        await tap(find.text(channel.displayName));
        await wait(
          () =>
              find.byType(ChannelPostsScreen).evaluate().isNotEmpty &&
              !posts.feedLoading,
          'tree opens actual channel',
        );
        if (phase == 'write') {
          final draft = posts.newDraft(channel.id)
            ..title = 'F4保留草稿'
            ..body = '主机文件SQLite恢复正文';
          expect(await posts.saveDraft(draft), isTrue);
          state['draftId'] = draft.id;
          await tap(find.byIcon(Icons.add));
          await wait(
            () => find
                .byKey(const ValueKey('post-title-input'))
                .evaluate()
                .isNotEmpty,
            'main composer',
          );
          await tester.enterText(
            find.byKey(const ValueKey('post-title-input')),
            'F4真实发布',
          );
          await tester.enterText(
            find.byKey(const ValueKey('post-body-input')),
            '原文👩‍💻e\u0301\r\n下一行  ',
          );
          await tap(find.text('下一步'));
          await wait(
            () => find.text('确认发布').evaluate().isNotEmpty,
            'publish confirmation',
          );
          await wait(
            () => find.byIcon(Icons.expand_more).evaluate().isNotEmpty,
            'actual identity directory loaded',
          );
          await tap(find.byIcon(Icons.expand_more));
          final identityChoice = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('F4原身份'),
          );
          await wait(
            () => identityChoice.evaluate().isNotEmpty,
            'actual identity sheet choice',
          );
          await tap(identityChoice);
          final before = await fixture('stats');
          expect(before['creates'], 0);
          await fixture('drop-create');
          await tap(find.text('确认发布'));
          await wait(
            () =>
                find.byType(ChannelPostsScreen).evaluate().isNotEmpty &&
                find.byType(PostComposerScreen).evaluate().isEmpty,
            'confirmation returns original channel',
          );
          await posts.loadPersonal();
          final pending = posts.personalItems.singleWhere(
            (e) => e.local != null && e.title == 'F4真实发布',
          );
          expect(pending.local, isNotNull);
          expect(
            pending.local!.state == 'UNKNOWN' ||
                pending.local!.state == 'submitted',
            isTrue,
          );
          state['pendingId'] = pending.id;
          state['commandId'] = pending.local!.intents.last.commandId;
          state['digest'] = pending.local!.intents.last.digest;
          expect(posts.latestPublicationNotice, isNull);
          await posts.reconcile(pending.id);
          expect((await fixture('stats'))['queryDrops'], greaterThan(0));
          checks['F4-H03'] = true;
          debugPrint('F4-H03 PASS');
          await stateFile.writeAsString(jsonEncode(state), flush: true);
        } else {
          expect(
            posts.accountId == state['accountId'],
            isTrue,
            reason: 'same restored account',
          );
          final restored = await posts.restoreDraft(state['draftId'] as String);
          expect(restored?.title, 'F4保留草稿');
          await posts.loadPersonal();
          final pending = posts.personalItems.singleWhere(
            (e) => e.id == state['pendingId'],
          );
          expect(
            pending.local!.intents.last.commandId == state['commandId'],
            isTrue,
          );
          expect(pending.local!.intents.last.digest == state['digest'], isTrue);
          await posts.reconcile(pending.id);
          await posts.loadPersonal();
          final accepted = posts.personalItems.singleWhere(
            (e) => e.id == state['pendingId'],
          );
          expect(accepted.task?.identityId == state['identityId'], isTrue);
          checks['F4-H04'] = true;
          debugPrint('F4-H04 PASS');
          await fixture('publish');
          await fixture('publish');
          await posts.reconcile(pending.id);
          await posts.loadFeed(channel.id);
          expect(posts.feedItems, hasLength(1));
          final card = posts.feedItems.single;
          expect(card.author.nickname, 'F4原身份');
          state['postId'] = card.postId;
          await wait(
            () => find.text('F4真实发布').evaluate().isNotEmpty,
            'published list',
          );
          await tap(find.text('F4真实发布'));
          await wait(
            () => find.byTooltip('删除帖子').evaluate().isNotEmpty,
            'detail private delete capability',
          );
          expect(find.text('原文👩‍💻e\u0301\r\n下一行  '), findsOneWidget);
          await back();
          await tap(find.text('我的'));
          await wait(
            () => find.text('自己的帖子').evaluate().isNotEmpty,
            'channel My route',
          );
          await tap(find.text('F4真实发布'));
          await wait(
            () => find.byTooltip('删除帖子').evaluate().isNotEmpty,
            'My detail',
          );
          await fixture('drop-delete');
          await tap(find.byTooltip('删除帖子'));
          await tap(find.byKey(const ValueKey('scoped-confirm-action')));
          await wait(
            () =>
                posts.isPostDeleted(card.postId) &&
                find.byType(PostDetailScreen).evaluate().isEmpty,
            'lost delete response reconciles original command and returns to My',
          );
          final deletion = (await openedStores[state['accountId']]!.list())
              .singleWhere(
                (e) =>
                    e.intents.isNotEmpty &&
                    e.intents.last.operation == 'DELETE_POST',
              );
          expect(deletion.state, 'DELETED');
          expect(
            deletion.intents.last.commandId == state['commandId'],
            isFalse,
          );
          await posts.reconcile(deletion.id);
          expect(find.text('原文👩‍💻e\u0301\r\n下一行  '), findsNothing);
          await posts.loadPersonal();
          expect(
            posts.personalItems.any((e) => e.post?.postId == card.postId),
            isFalse,
          );
          expect(posts.isPostDeleted(card.postId), isTrue);
          checks['F4-H05'] = true;
          debugPrint('F4-H05 PASS');
          await tap(find.text('首页'));
          await wait(
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'main home restored',
          );
          await tap(find.text(channel.displayName));
          await wait(() => !posts.feedLoading, 'empty deleted feed');
          expect(posts.feedItems, isEmpty);
          final oldToken = store.current!.session!.token;
          await fixture('freeze');
          await posts.loadFeed(channel.id);
          expect(posts.available, isFalse);
          expect(sessions.status, AuthStatus.unavailable);
          expect(store.current!.session!.token == oldToken, isTrue);
          await fixture('recover');
          await sessions.retry();
          expect(sessions.status, AuthStatus.signedOut);
          expect(store.current!.session, isNull);
          expect(posts.available, isFalse);
          await sessions.login('f4_user_a', 'F4 synthetic long password 2026!');
          await wait(
            () => posts.available,
            'fresh session after Gate generation change',
          );
          expect(store.current!.session!.token == oldToken, isFalse);
          final takeover = await api.login(
            username: 'f4_user_a',
            password: 'F4 synthetic long password 2026!',
            installationId: AuthCrypto.randomEncoded(16),
            idempotencyKey: AuthCrypto.randomEncoded(32),
          );
          await sessions.retry();
          expect(sessions.isAuthenticated, isFalse);
          expect(posts.available, isFalse);
          await api.revokeSession(
            AuthCrypto.revocationSecret(takeover.sessionToken),
          );
          await sessions.login('f4_user_a', 'F4 synthetic long password 2026!');
          await wait(() => posts.available, 'explicit fresh A session');
          expect(
            (await posts.restoreDraft(state['draftId'] as String))?.title,
            'F4保留草稿',
          );
          checks['F4-H06'] = true;
          debugPrint('F4-H06 PASS');
          await sessions.logout();
          await register('f4b@hainanu.edu.cn', 'f4_user_b');
          await wait(() => posts.available, 'independent B authority');
          await posts.loadPersonal();
          expect(posts.accountId == state['accountId'], isFalse);
          expect(
            posts.personalItems.any(
              (e) => e.id == state['draftId'] || e.id == state['pendingId'],
            ),
            isFalse,
          );
          expect(posts.isPostDeleted(card.postId), isFalse);
          expect((await fixture('stats'))['creates'], 1);
          expect((await fixture('stats'))['deletes'], 1);
          checks['F4-H07'] = true;
          debugPrint('F4-H07 PASS');
          final closingAccount = posts.accountId!;
          final closedDraft = posts.newDraft(channel.id)
            ..title = 'B关闭前草稿'
            ..body = '只清理B';
          expect(await posts.saveDraft(closedDraft), isTrue);
          await back();
          await wait(
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'B returns to root',
          );
          await tap(find.byTooltip('My content'));
          await wait(
            () => find.byTooltip('设置').evaluate().isNotEmpty,
            'B My route',
          );
          await tap(find.byTooltip('设置'));
          await tap(find.text('账号与安全'));
          await wait(
            () => find
                .byKey(const ValueKey('closure-password'))
                .evaluate()
                .isNotEmpty,
            'actual account closure form',
          );
          await tester.enterText(
            find.byKey(const ValueKey('closure-password')),
            'F4 synthetic long password 2026!',
          );
          await tap(find.text('查看并确认注销申请'));
          await tap(find.text('申请注销'));
          await wait(
            () => flows.status == AuthFlowStatus.closurePending,
            'real closure accepted',
          );
          expect(
            store.current!.pendingClosure!['originalAccountId'] ==
                closingAccount,
            isTrue,
          );
          await fixture('finalize');
          await flows.reconcileClosure();
          expect(flows.status, AuthFlowStatus.closureClosedReleasePending);
          expect(posts.available, isFalse);
          try {
            final closed = await PostStore.openFile(
              File('$root/$closingAccount.sqlite'),
              environment: environment.storageScope,
              accountId: closingAccount,
              vault: _KeyFile(File('$root/$closingAccount.key')),
            );
            await closed.close();
            fail('Closed B business scope reopened');
          } on PostStorageClosed {
            /* actual encrypted SQLite tombstone */
          }
          final preservedA = await PostStore.openFile(
            File('${root}/${state['accountId']}.sqlite'),
            environment: environment.storageScope,
            accountId: state['accountId'] as String,
            vault: _KeyFile(File('${root}/${state['accountId']}.key')),
          );
          expect(await preservedA.get(state['draftId'] as String), isNotNull);
          await preservedA.close();
          checks['F4-H08'] = true;
          debugPrint('F4-H08 PASS');
        }
        await File('$root/checks-$phase.json')
            .writeAsString(jsonEncode(checks), flush: true);
        control.close(force: true);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
