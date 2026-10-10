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

/// Human-assisted actual Keyguard transitions. Reboot additionally requires
/// independent host boot-count evidence; a changed App PID alone is insufficient.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const cOrigin = String.fromEnvironment('AUTH_COMMUNITY_BASE_URL');
  const vOrigin = String.fromEnvironment('AUTH_VERIFIER_BASE_URL');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual physical lock and reboot restoration',
    (tester) async {
      expect(
        Platform.isAndroid && runId == 'hnuhole-android-live-matrix-20261006',
        isTrue,
      );
      expect(accountRunId, 'hnuhole-android-live-boundary-20261006');
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'phone-prime',
          'phone-lock-cycle',
          'phone-reboot-read',
        }.contains(phase),
        isTrue,
      );
      final c = Uri.parse(cOrigin), v = Uri.parse(vOrigin);
      validateDevelopmentOrigins(c, v);
      final scope = 'hnuhole.isolated.auth.v1|$c|$v';
      final store = AuthStore(
        FlutterAuthVault(
          namespace:
              'hnuhole.auth.v1.${AuthCrypto.domainDigest('HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1', utf8.encode(scope))}',
        ),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$runId.lifecycle',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
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
      const draft = '锁屏重启草稿';
      final flags = <String, Object>{};
      var accepted = false;
      final observer = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(observer);
      try {
        final original = await store.read();
        var loginNeeded = original.session == null;
        if (phase == 'phone-prime' && original.session != null) {
          try {
            expect(
              (await api.currentSession(original.session!.token)).username,
              username,
            );
          } on AuthFailure catch (error) {
            expect(error.unauthorized, isTrue);
            loginNeeded = true;
          }
        } else if (phase != 'phone-prime') {
          expect(original.session!.accountId, fixture['accountId']);
          expect(
            AuthCrypto.domainDigest(
              'LIFECYCLE-SESSION',
              utf8.encode(original.session!.token),
            ),
            fixture['sessionDigest'],
          );
          expect(
            (await api.currentSession(original.session!.token)).username,
            username,
          );
          expect(fixture['pid'] != pid, isTrue);
        }
        app.main();
        await tester.pump();
        if (phase == 'phone-prime' && loginNeeded) {
          await _wait(
            tester,
            () => find.text('登录或注册').evaluate().isNotEmpty,
            'explicit login required',
          );
          await _tap(tester, find.text('登录或注册'));
          await _input(tester, 'login-username', username);
          await _input(tester, 'login-password', password);
          await _tap(tester, find.text('登录并进入'));
        }
        await _wait(
          tester,
          () async =>
              (await store.read()).session != null &&
              find.byType(AuthScreen).evaluate().isEmpty &&
              find.text('登录或注册').evaluate().isEmpty,
          'authoritative App',
        );
        if (phase == 'phone-lock-cycle') {
          final initial = await driver.invokeMapMethod<String, dynamic>(
            'deviceState',
          );
          expect(
            initial?['deviceSecure'] == true &&
                initial?['deviceLocked'] == false,
            isTrue,
          );
          observer.reset();
          await driver.invokeMethod<void>('stage', 'await-real-lock');
          await _wait(
            tester,
            () async =>
                (await driver.invokeMapMethod<String, dynamic>(
                  'deviceState',
                ))?['deviceLocked'] ==
                true,
            'actual Keyguard locked',
          );
          await driver.invokeMethod<void>('stage', 'actual-lock-observed');
          await _wait(
            tester,
            () async =>
                observer.backgrounded &&
                observer.resumed &&
                (await driver.invokeMapMethod<String, dynamic>(
                      'deviceState',
                    ))?['deviceLocked'] ==
                    false,
            'actual unlock and resume',
          );
          flags['actualSecureKeyguardLockUnlockObserved'] = true;
          flags['actualAndroidBackgroundAndResume'] = true;
        }
        final state = await store.read();
        expect(
          (await api.currentSession(state.session!.token)).username,
          username,
        );
        final directory = await api.identities(state.session!.token);
        expect(directory.identities, isEmpty);
        expect(directory.createdCount, 0);
        await _tap(tester, find.byTooltip('My content'));
        await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
        await _tap(tester, find.byKey(const ValueKey('identity-add')));
        if (phase == 'phone-prime') {
          await _input(tester, 'identity-nickname', draft);
          await _wait(
            tester,
            () async =>
                ((await store.read()).identityDrafts[state.session!.accountId]
                    as Map?)?['nickname'] ==
                draft,
            'durable physical draft',
          );
          fixture['accountId'] = state.session!.accountId;
          fixture['sessionDigest'] = AuthCrypto.domainDigest(
            'LIFECYCLE-SESSION',
            utf8.encode(state.session!.token),
          );
          flags['actualLoginAndNativeDraftPrepared'] = true;
        } else {
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('identity-nickname')),
                )
                .controller!
                .text,
            draft,
          );
          expect(state.session!.token, original.session!.token);
          flags['sameSessionAndDraftPreserved'] = true;
          if (phase == 'phone-reboot-read') {
            flags['requiresIndependentHostBootCountEvidence'] = true;
          }
        }
        await marker.write(
          jsonEncode({...fixture, 'pid': pid, 'lastPhase': phase}),
        );
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'systemPasskey': false,
          ...flags,
        };
        accepted = true;
      } finally {
        WidgetsBinding.instance.removeObserver(observer);
        if (accepted) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        api.close();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
    skip: runId.isEmpty,
  );
}

class _LifecycleProbe with WidgetsBindingObserver {
  bool backgrounded = false, resumed = false;
  void reset() {
    backgrounded = false;
    resumed = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      backgrounded = true;
    }
    if (state == AppLifecycleState.resumed && backgrounded) resumed = true;
  }
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage,
) async {
  final end = DateTime.now().add(const Duration(seconds: 180));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Physical lifecycle phase timed out: $stage');
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
