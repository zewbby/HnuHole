import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// Actual App and native product record; only the owned emulator is reinstalled.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const cOrigin = String.fromEnvironment('AUTH_COMMUNITY_BASE_URL');
  const vOrigin = String.fromEnvironment('AUTH_VERIFIER_BASE_URL');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual App storage recovery boundaries',
    (tester) async {
      expect(
        Platform.isAndroid && runId == 'hnuhole-android-live-matrix-20261006',
        isTrue,
      );
      expect(accountRunId, 'hnuhole-android-live-boundary-20261006');
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'storage-source',
          'storage-restart',
          'storage-fresh',
          'storage-restored-no-key',
        }.contains(phase),
        isTrue,
      );
      final c = Uri.parse(cOrigin), v = Uri.parse(vOrigin);
      validateDevelopmentOrigins(c, v);
      final scope = 'hnuhole.isolated.auth.v1|$c|$v';
      final namespace =
          'hnuhole.auth.v1.${AuthCrypto.domainDigest('HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1', utf8.encode(scope))}';
      final store = AuthStore(
        FlutterAuthVault(namespace: namespace),
        scope: scope,
      );
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        passkeyRpId: developmentPasskeyRp(community: c, verifier: v),
        client: createAppHttpClient(community: c, verifier: v),
      );
      final username =
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode(accountRunId)).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      final password =
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(accountRunId))}#9';
      const draft = '迁移前草稿';
      final flags = <String, Object>{};
      var accepted = false;
      try {
        if (phase == 'storage-restored-no-key') {
          await expectLater(store.read(), throwsA(isA<AuthStorageFailure>()));
          await expectLater(
            store.update((_) => const AuthState()),
            throwsA(isA<AuthStorageFailure>()),
          );
          app.main();
          await tester.pump();
          await _wait(
            tester,
            () => find.text('安全存储暂不可用').evaluate().isNotEmpty,
            'fail closed storage page',
          );
          final screen = tester.widget<AuthScreen>(find.byType(AuthScreen));
          expect(screen.sessions.status, AuthStatus.storageFailure);
          expect(screen.sessions.isAuthenticated, isFalse);
          expect(find.byKey(const ValueKey('login-password')), findsNothing);
          await _tap(tester, find.text('重试安全存储'));
          await _wait(
            tester,
            () => screen.sessions.status == AuthStatus.storageFailure,
            'retry stays unavailable',
          );
          flags['productReadAndOverwriteRejected'] = true;
          flags['actualAppStorageFailurePageAndNoCommunityAccess'] = true;
        } else {
          final original = await store.read();
          if (phase == 'storage-source' || phase == 'storage-fresh') {
            expect(original.session, isNull);
            if (phase == 'storage-fresh') {
              expect(original.identityDrafts, isEmpty);
              expect(original.registration, isNull);
              expect(original.pendingReset, isNull);
              expect(original.pendingClosure, isNull);
            }
          } else {
            expect(original.session, isNotNull);
            expect(
              (original.identityDrafts[original.session!.accountId]
                  as Map)['nickname'],
              draft,
            );
            expect(
              (await api.currentSession(original.session!.token)).username,
              username,
            );
          }
          app.main();
          await tester.pump();
          if (phase == 'storage-fresh') {
            await _wait(
              tester,
              () => find.text('登录或注册').evaluate().isNotEmpty,
              'fresh guest App',
            );
            expect((await store.read()).session, isNull);
            flags['noSessionDraftOrPendingStateAfterReinstall'] = true;
            flags['actualGuestAppWithoutAutomaticLogin'] = true;
          } else {
            if (phase == 'storage-source') {
              await _wait(
                tester,
                () => find.text('登录或注册').evaluate().isNotEmpty,
                'guest',
              );
              await _tap(tester, find.text('登录或注册'));
              await _input(tester, 'login-username', username);
              await _input(tester, 'login-password', password);
              await _tap(tester, find.text('登录并进入'));
              await _wait(
                tester,
                () async =>
                    find.byType(AuthScreen).evaluate().isEmpty &&
                    (await store.read()).session != null,
                'explicit login',
              );
            } else {
              await _wait(
                tester,
                () =>
                    find.byType(ChannelTree).evaluate().isNotEmpty &&
                    find.text('登录或注册').evaluate().isEmpty,
                'authority restored',
              );
            }
            final state = await store.read();
            final session = state.session!;
            expect(
              (await api.currentSession(session.token)).username,
              username,
            );
            final directory = await api.identities(session.token);
            expect(directory.identities, isEmpty);
            expect(directory.createdCount, 0);
            await _tap(tester, find.byTooltip('My content'));
            await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
            await _tap(tester, find.byKey(const ValueKey('identity-add')));
            if (phase == 'storage-source') {
              await _input(tester, 'identity-nickname', draft);
              await _wait(
                tester,
                () async =>
                    ((await store.read()).identityDrafts[session.accountId]
                        as Map?)?['nickname'] ==
                    draft,
                'native draft durable',
              );
            } else {
              final input = tester.widget<TextFormField>(
                find.byKey(const ValueKey('identity-nickname')),
              );
              expect(input.controller!.text, draft);
              expect(
                (await store.read()).session!.token,
                original.session!.token,
              );
              flags['sameAuthoritativeSessionAndDraftAfterProcessRestart'] =
                  true;
            }
            flags['actualProductLoginAndNativeDraft'] = true;
            flags['noIdentityCreatedByDraft'] = true;
          }
        }
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'actualApp': true,
          'actualCV': phase == 'storage-source' || phase == 'storage-restart',
          'nativeVault': true,
          'systemPasskey': false,
          ...flags,
        };
        accepted = true;
      } finally {
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runId.isEmpty,
  );
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage,
) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Storage phase timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().length == 1, 'single action');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(tester, () => finder.evaluate().isNotEmpty, 'input');
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
}
