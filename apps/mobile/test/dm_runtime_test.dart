import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_runtime.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';

import 'dm_reliability_test.dart' as dm;
import 'identity_test_support.dart';
import 'login_home_test_support.dart';

// Real runtime, auth/identity controllers and encrypted SQLite; HTTP and the
// OS vault are substitutes. This covers their assembly, not native storage.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'runtime transition did not complete');
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(done(), isTrue, reason: 'widget runtime transition did not complete');
}

Future<DmRuntime> runtimeFor(
  IdentityTestFixture f, {
  bool failStore = false,
}) async {
  final root = await Directory.systemTemp.createTemp('hnuhole-dm-runtime-');
  final vaults = <String, dm.Vault>{};
  final controller = DmController(
    api: dm.FakeDmApi()..offline = true,
    openStore: (account) {
      if (failStore) throw StateError('fixture store unavailable');
      return DmStore.open(
        File('${root.path}/$account.sqlite'),
        'test',
        account,
        vaults.putIfAbsent(account, dm.Vault.new),
      );
    },
    onUnauthorized: f.sessions.sessionUnauthorized,
    onUnavailable: f.sessions.sessionUnavailable,
    onMetadata: (token, expiry, current) async {
      await f.sessions.persistSessionMetadata(token, expiry, current);
    },
  );
  final runtime = DmRuntime(
    controller: controller,
    sessions: f.sessions,
    authStore: f.store,
    identityApi: f.api,
    identityChanges: f.controller,
  );
  addTearDown(() async {
    await controller.detach();
    runtime.dispose();
    f.dispose();
    await root.delete(recursive: true);
  });
  return runtime;
}

void main() {
  testWidgets(
    'empty identity directory exits loading and exposes setup action',
    (tester) async {
      late IdentityTestFixture f;
      late DmRuntime r;
      await tester.runAsync(() async {
        f = await IdentityTestFixture.create();
        r = await runtimeFor(f);
        await until(() => r.identityStatus == DmIdentityStatus.empty);
      });
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: DmInboxRoute(
            runtime: r,
            onManageIdentities: () => opened = true,
          ),
        ),
      );
      expect(find.textContaining('核对'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('您目前还没有身份'), findsOneWidget);
      await tester.tap(find.text('添加身份'));
      expect(opened, isTrue);
      expect(f.api.submissions, isEmpty);
      expect(f.api.reads, 1);
      expect(f.store.current!.session!.expiresAt, identityTestRenewed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pending read becomes visible failure and explicit retry recovers',
    (tester) async {
      final pending = Completer<IdentityDirectory>();
      late IdentityTestFixture f;
      late DmRuntime r;
      await tester.runAsync(() async {
        f = await IdentityTestFixture.create(
          api: IdentityTestApi()..readWait = pending,
        );
        r = await runtimeFor(f);
        await f.api.readStarted.future;
      });
      await tester.pumpWidget(MaterialApp(home: DmInboxRoute(runtime: r)));
      expect(find.textContaining('核对'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        '正在加载',
      );
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(22, 22),
      );
      pending.completeError(const AuthFailure(kind: AuthFailureKind.timeout));
      await tester.pump();
      expect(find.text('加载失败，请重试'), findsOneWidget);
      expect(find.textContaining('核对'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(f.sessions.isAuthenticated, isTrue);
      f.api.readWait = null;
      f.api.items = [identityTestItem()];
      f.api.createdCount = 1;
      await tester.tap(find.text('重试'));
      await pumpUntil(tester, () => r.identityStatus == DmIdentityStatus.ready);
      await tester.pump();
      expect(find.text('加载失败，请重试'), findsNothing);
      expect(f.api.reads, 2);
      expect(r.controller.available, isTrue);
      f.sessions.sessionUnavailable(identityTestToken);
      await tester.pump();
      expect(find.text('暂时无法加载私信'), findsOneWidget);
      expect(find.textContaining('核对'), findsNothing);
      expect(find.text('重试'), findsOneWidget);
      var detached = false;
      final detach = r.controller.detach().then((_) => detached = true);
      await pumpUntil(tester, () => detached);
      await detach;
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('directory metadata does not cause reload loop and creation binds new identity', () async {
    final f = await IdentityTestFixture.create();
    final r = await runtimeFor(f);
    await until(() => r.identityStatus == DmIdentityStatus.empty);
    await f.sessions.persistSessionMetadata(
      identityTestToken,
      identityTestRenewed.add(const Duration(days: 1)),
      () => true,
    );
    expect(f.api.reads, 1);
    await f.controller.load();
    await f.controller.create('新面具');
    await until(() => r.identityStatus == DmIdentityStatus.ready);
    expect(r.identities.single.name, '新面具');
    expect(r.controller.accountId, identityTestAccount);
  });

  for (final kind in [
    AuthFailureKind.unauthorized,
    AuthFailureKind.unavailable,
  ]) {
    test(
      'identity $kind closes shared authorization and does not retry it',
      () async {
        final f = await IdentityTestFixture.create(
          api: IdentityTestApi()
            ..readFailure = AuthFailure(kind: kind, code: 'session_replaced'),
        );
        final r = await runtimeFor(f);
        await until(() => !f.sessions.isAuthenticated);
        expect(r.identityStatus, DmIdentityStatus.unavailable);
        expect(r.controller.available, isFalse);
        expect(r.identities, isEmpty);
        expect(
          f.sessions.status,
          kind == AuthFailureKind.unauthorized
              ? AuthStatus.signedOut
              : AuthStatus.unavailable,
        );
        await until(
          () =>
              kind != AuthFailureKind.unauthorized ||
              f.store.current?.session == null,
        );
        expect(f.api.reads, 1);
      },
    );
  }

  test('late old directory never binds a replacement account', () async {
    final pending = Completer<IdentityDirectory>();
    final f = await IdentityTestFixture.create(
      api: IdentityTestApi()..readWait = pending,
    );
    final r = await runtimeFor(f);
    await f.api.readStarted.future;
    final old = f.api.directory();
    await f.sessions.logout();
    f.api.readWait = null;
    f.api.items = [identityTestItem(id: identityTestSecondId, name: '新账号')];
    f.api.createdCount = 1;
    f.sessionApi.account = '00000000-0000-0000-0000-000000000002';
    await f.sessions.login('other_user', 'valid password');
    await until(() => r.identityStatus == DmIdentityStatus.ready);
    pending.complete(old);
    await Future<void>.delayed(Duration.zero);
    expect(r.controller.accountId, f.sessionApi.account);
    expect(r.identities.single.id, identityTestSecondId);
    expect(r.identityStatus, DmIdentityStatus.ready);
  });

  test('local store failure has a terminal retryable state', () async {
    final f = await IdentityTestFixture.create();
    final r = await runtimeFor(f, failStore: true);
    await until(() => r.identityStatus == DmIdentityStatus.failed);
    expect(r.controller.available, isFalse);
    expect(r.controller.error, '私信本地保存不可用，输入不会被清除');
  });

  testWidgets('production root opens real identity setup from empty DM inbox', (
    tester,
  ) async {
    final f = HomeTestFixture();
    final base = await f.create();
    f.identitiesApi.items = [];
    final dir = Directory.systemTemp.createTempSync('hnuhole-dm-root-');
    final vault = dm.Vault();
    final r = DmRuntime(
      controller: DmController(
        api: dm.FakeDmApi()..offline = true,
        openStore: (account) => DmStore.open(
          File('${dir.path}/dm.sqlite'),
          'root-test',
          account,
          vault,
        ),
      ),
      sessions: f.sessions,
      authStore: f.store,
      identityApi: f.identitiesApi,
      identityChanges: base.identities,
    );
    await tester.pumpWidget(
      app.HnuholeApp(
        directory: base.directory,
        repository: base.repository,
        api: base.api,
        sessions: base.sessions,
        flows: base.flows,
        management: base.management,
        identities: base.identities,
        store: base.store,
        posts: base.posts,
        postApi: base.postApi,
        dm: r,
      ),
    );
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => r.identityStatus == DmIdentityStatus.empty);
    await tester.tap(find.byKey(const ValueKey('destination:directMessages')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加身份'));
    await tester.pumpAndSettle();
    expect(find.byType(IdentityManagementScreen), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(f.identitiesApi.submissions, isEmpty);
    Navigator.of(tester.element(find.byType(TextFormField))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(IdentityManagementScreen))).pop();
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => r.identityStatus == DmIdentityStatus.empty);
    await tester.tap(find.byKey(const ValueKey('destination:home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('destination:directMessages')));
    await tester.pumpAndSettle();
    expect(find.text('添加身份'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('destination:directMessages'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(f.identitiesApi.submissions, isEmpty);
    var detached = false;
    final detach = r.controller.detach().then((_) => detached = true);
    await pumpUntil(tester, () => detached);
    await detach;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await r.controller.detach();
      await dir.delete(recursive: true);
    });
  });
}
