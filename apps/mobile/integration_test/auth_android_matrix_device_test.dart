import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// Attach to the installed owned debug APK. Every mutation uses actual product
/// routes, native storage and C/V. Test-only synthetic recovery material stays
/// in a separate encrypted vault namespace and never enters reportData.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const cOrigin = String.fromEnvironment('AUTH_COMMUNITY_BASE_URL');
  const vOrigin = String.fromEnvironment('AUTH_VERIFIER_BASE_URL');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual Android App account and credential matrix',
    (tester) async {
      expect(
        Platform.isAndroid &&
            RegExp(r'^hnuhole-android-live-[A-Za-z0-9_-]+$').hasMatch(runId),
        isTrue,
      );
      expect(accountRunId == 'hnuhole-android-live-faults-20261005-r2', isTrue);
      final phase = await driver.invokeMethod<String>('phase');
      const phases = {
        'account-closure-cancel',
        'rotation',
        'code-reset',
        'lifecycle',
        'passkey-bind',
        'passkey-reconcile',
        'passkey-cancel',
        'passkey-remove',
        'passkey-recover',
        'lock-state',
      };
      expect(phases.contains(phase), isTrue);
      final c = Uri.parse(cOrigin), v = Uri.parse(vOrigin);
      validateDevelopmentOrigins(c, v);
      final scope = 'hnuhole.isolated.auth.v1|$c|$v';
      final digest = AuthCrypto.domainDigest(
        'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
        utf8.encode(scope),
      );
      final store = AuthStore(
        FlutterAuthVault(namespace: 'hnuhole.auth.v1.$digest'),
        scope: scope,
      );
      final marker = FlutterAuthVault(namespace: 'native.security.test.$runId');
      final raw = await marker.read();
      final fixture = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final username =
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode(accountRunId)).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      var password =
          fixture['password'] as String? ??
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(accountRunId))}#9';
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        passkeyRpId: developmentPasskeyRp(community: c, verifier: v),
        client: createAppHttpClient(community: c, verifier: v),
      );
      final flags = <String, Object?>{};
      var accepted = false;
      try {
        final original = await store.read();
        expect(
          original.session != null,
          isTrue,
          reason: 'The accepted owned synthetic account must be logged in',
        );
        final legacy = await FlutterAuthVault(
          namespace: 'native.security.test.$accountRunId',
        ).read();
        expect(
          legacy != null,
          isTrue,
          reason: 'Prior accepted run ownership required',
        );
        final legacyAccount =
            (jsonDecode(legacy!) as Map<String, dynamic>)['accountId'];
        expect(original.session!.accountId == legacyAccount, isTrue);
        final authoritative = await api.currentSession(original.session!.token);
        expect(authoritative.username == username, isTrue);
        final beforeDirectory = await api.identities(original.session!.token);
        final beforeCredentials = await api.recoveryCredentials(
          original.session!.token,
        );
        final priorPid = fixture['pid'];
        if (priorPid != null) {
          expect(
            priorPid != pid,
            isTrue,
            reason: 'Each matrix phase needs a distinct App process',
          );
        }
        app.main();
        await tester.pump();
        await _wait(
          tester,
          () =>
              find.byType(ChannelTree).evaluate().isNotEmpty &&
              find.text('登录或注册').evaluate().isEmpty,
          'actual session restored',
        );
        flags['authoritativeSessionRestored'] = true;

        if (phase == 'account-closure-cancel') {
          await _account(tester);
          expect(
            find.byKey(const ValueKey('closure-password')),
            findsOneWidget,
          );
          flags['accountClosureReachableFromSettings'] = true;
          await _input(tester, 'closure-password', password);
          await _tap(tester, find.text('查看并确认注销申请'));
          expect(find.text('申请七天后注销'), findsOneWidget);
          await _tap(tester, find.text('申请注销'));
          await _wait(
            tester,
            () => find.text('注销缓冲期').evaluate().isNotEmpty,
            'actual closure pending',
          );
          final pending = await store.read();
          expect(
            pending.session == null &&
                pending.pendingClosure?['state'] == 'PENDING',
            isTrue,
          );
          final closure = pending.pendingClosure!;
          final status = await api.closureStatus(
            closureId: closure['closureId'] as String,
            statusSecret: closure['statusSecret'] as String,
          );
          final days = status.dueAt!.difference(DateTime.now()).inHours;
          expect(
            status.state == ClosureState.pending && days >= 166 && days <= 168,
            isTrue,
          );
          await _oldSessionRejected(api, original.session!.token);
          flags['realSevenDayRequestAccepted'] = true;
          flags['requestClearedLocalSessionAndRevokedOldBearer'] = true;
          await _tap(tester, find.text('登录并撤销注销'));
          await _login(tester, username, password);
          final cancelled = await api.closureStatus(
            closureId: closure['closureId'] as String,
            statusSecret: closure['statusSecret'] as String,
          );
          expect(cancelled.state == ClosureState.cancelled, isTrue);
          final after = await store.read();
          final directory = await api.identities(after.session!.token);
          expect(
            directory.identities.length == beforeDirectory.identities.length &&
                directory.createdCount == beforeDirectory.createdCount &&
                directory.identities.every(
                  (identity) => beforeDirectory.identities.any(
                    (old) =>
                        old.id == identity.id &&
                        old.nickname == identity.nickname,
                  ),
                ),
            isTrue,
          );
          flags['explicitLoginCancelledClosure'] = true;
          flags['gracePeriodPreservedAllIdentities'] = true;
          await _tap(tester, find.widgetWithText(ListTile, '账号与注销'));
          await _tap(tester, find.text('核对上次注销申请'));
          await _tap(tester, find.text('已确认取消，清除上次状态'));
          expect((await store.read()).pendingClosure == null, isTrue);
        } else if (phase == 'rotation') {
          await _security(tester);
          await _input(tester, 'management-password', password);
          await _tap(tester, find.text('轮换恢复码'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('rotation-displayed-code'))
                .evaluate()
                .isNotEmpty,
            'new rotation code',
          );
          final code = tester
              .widget<Text>(
                find.byKey(const ValueKey('rotation-displayed-code')),
              )
              .data!;
          await _tap(tester, find.text('我已保存，隐藏原码并确认'));
          expect(
            find.byKey(const ValueKey('rotation-displayed-code')),
            findsNothing,
          );
          await _input(tester, 'rotation-confirmation', code);
          await _tap(tester, find.text('确认并激活新恢复码'));
          await _credentialCommitted(tester);
          final after = await store.read();
          expect(
            after.session!.token == original.session!.token &&
                after.pendingCredentialChange == null &&
                !jsonEncode(after.toJson(scope)).contains(code),
            isTrue,
          );
          fixture['recoveryCode'] = code;
          flags['realRecoveryCodeRotationConfirmed'] = true;
          flags['sameSessionPreserved'] = true;
          flags['originalCodeAbsentFromProductPersistence'] = true;
        } else if (phase == 'code-reset' || phase == 'passkey-recover') {
          await _account(tester);
          await _tap(tester, find.text('退出本机'));
          await _tap(tester, find.text('恢复账号'));
          if (phase == 'code-reset') {
            final code = fixture['recoveryCode'] as String?;
            expect(
              code != null,
              isTrue,
              reason: 'First accept actual code rotation',
            );
            await _input(tester, 'recovery-code', code!);
            await _tap(tester, find.text('验证恢复码'));
          } else {
            expect(beforeCredentials.passkeys.isNotEmpty, isTrue);
            await driver.invokeMethod<void>('stage', 'passkey-recovery-sheet');
            await _tap(tester, find.text('使用 Passkey 恢复'));
          }
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('displayed-recovery-code'))
                .evaluate()
                .isNotEmpty,
            'actual recovery intent accepted',
            seconds: 85,
          );
          final code = tester
              .widget<Text>(
                find.byKey(const ValueKey('displayed-recovery-code')),
              )
              .data!;
          final nextPassword =
              'Matrix-${AuthCrypto.domainDigest('DEVICE-RESET-PASSWORD', utf8.encode('$runId-$phase'))}#8';
          await _tap(tester, find.text('我已保存，隐藏原码并确认'));
          await _input(tester, 'reset-new-password', nextPassword);
          await _input(tester, 'recovery-confirmation', code);
          await _tap(tester, find.text('设置新密码并激活新恢复码'));
          await _wait(
            tester,
            () => find.text('密码已重设').evaluate().isNotEmpty,
            'reset committed',
          );
          expect((await store.read()).session == null, isTrue);
          flags['passwordResetDidNotAutoLogin'] = true;
          await _oldSessionRejected(api, original.session!.token);
          await _tap(tester, find.text('前往登录'));
          await _login(tester, username, nextPassword);
          password = nextPassword;
          final after = await store.read();
          expect(
            after.session!.accountId == legacyAccount &&
                after.pendingReset == null,
            isTrue,
          );
          final credentials = await api.recoveryCredentials(
            after.session!.token,
          );
          expect(credentials.passkeys.isEmpty, isTrue);
          final directory = await api.identities(after.session!.token);
          expect(
            directory.identities.length == beforeDirectory.identities.length &&
                directory.createdCount == beforeDirectory.createdCount,
            isTrue,
          );
          fixture['recoveryCode'] = code;
          flags['actualPasswordLoginAfterReset'] = true;
          flags['sameAccountIdentitiesPreserved'] = true;
          flags['oldSessionsAndPasskeysInvalidated'] = true;
          flags[phase == 'passkey-recover'
                  ? 'systemDiscoverablePasskeyRecovery'
                  : 'actualRecoveryCodeReset'] =
              true;
        } else if (phase == 'passkey-reconcile') {
          final pending = original.pendingCredentialChange;
          expect(
            pending?['kind'] == 'PASSKEY_BINDING' &&
                pending?['state'] == 'UNKNOWN',
            isTrue,
          );
          await _tap(tester, find.byTooltip('My content'));
          await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
          await _wait(
            tester,
            () =>
                find.text('变更已确认提交。').evaluate().isNotEmpty ||
                find.text('本次变更未提交，可重新输入密码开始。').evaluate().isNotEmpty,
            'original binding result query without a new native proof',
          );
          final committed = find.text('变更已确认提交。').evaluate().isNotEmpty;
          final reconciled = await store.read();
          expect(
            reconciled.pendingCredentialChange?['key'] == pending!['key'] &&
                reconciled.pendingCredentialChange?['intentId'] ==
                    pending['intentId'],
            isTrue,
          );
          await _tap(tester, find.text('返回当前凭据'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('management-password'))
                .evaluate()
                .isNotEmpty,
            'original binding result acknowledged',
          );
          expect((await store.read()).pendingCredentialChange == null, isTrue);
          flags['originalBindingResultReconciled'] = true;
          flags['originalBindingWasCommitted'] = committed;
          flags['noNewNativeProofOrBindingSubmitted'] = true;
        } else if (phase == 'passkey-bind' || phase == 'passkey-cancel') {
          await _security(tester);
          await _input(tester, 'management-password', password);
          await driver.invokeMethod<void>(
            'stage',
            phase == 'passkey-bind'
                ? 'passkey-creation-sheet'
                : 'passkey-cancellation-sheet',
          );
          await _tap(tester, find.text('绑定新的 Passkey'));
          if (phase == 'passkey-bind') {
            await _credentialCommitted(tester, seconds: 85);
            final after = await store.read();
            final credentials = await api.recoveryCredentials(
              after.session!.token,
            );
            expect(
              credentials.passkeys.length ==
                      beforeCredentials.passkeys.length + 1 &&
                  after.pendingCredentialChange == null,
              isTrue,
            );
            flags['systemCredentialManagerBinding'] = true;
            flags['actualServerAcceptedNativeProof'] = true;
          } else {
            await _wait(
              tester,
              () => find.textContaining('已取消').evaluate().isNotEmpty,
              'actual OS cancellation observed',
              seconds: 85,
            );
            final after = await store.read();
            expect(after.pendingCredentialChange == null, isTrue);
            final credentials = await api.recoveryCredentials(
              after.session!.token,
            );
            expect(
              credentials.passkeys.length == beforeCredentials.passkeys.length,
              isTrue,
            );
            flags['systemSheetCancellationPreservedCredentials'] = true;
            flags['noPendingProofAfterCancellation'] = true;
          }
        } else if (phase == 'passkey-remove') {
          expect(beforeCredentials.passkeys.length == 1, isTrue);
          await _security(tester);
          await _input(tester, 'management-password', password);
          await _tap(tester, find.text('移除此 Passkey'));
          await _tap(tester, find.text('确认移除'));
          await _credentialCommitted(tester);
          final after = await store.read();
          expect(
            (await api.recoveryCredentials(after.session!.token))
                    .passkeys
                    .isEmpty &&
                after.pendingCredentialChange == null &&
                after.session!.token == original.session!.token,
            isTrue,
          );
          flags['actualPasskeyRemovalConfirmed'] = true;
          flags['currentSessionPreserved'] = true;
        } else if (phase == 'lifecycle') {
          final observer = _LifecycleProbe();
          WidgetsBinding.instance.addObserver(observer);
          try {
            await driver.invokeMethod<void>('stage', 'await-real-background');
            await _wait(
              tester,
              () => observer.backgrounded && observer.resumed,
              'real Home and foreground activity transition',
              seconds: 85,
            );
            final after = await store.read();
            expect(after.session!.token == original.session!.token, isTrue);
            await api.currentSession(after.session!.token);
            flags['actualAndroidBackgroundAndResume'] = true;
            flags['sessionRecheckedAfterResume'] = true;
          } finally {
            WidgetsBinding.instance.removeObserver(observer);
          }
        } else if (phase == 'lock-state') {
          final state = await driver.invokeMapMethod<String, dynamic>(
            'deviceState',
          );
          expect(
            state?['deviceSecure'] == true && state?['deviceLocked'] == false,
            isTrue,
          );
          flags['actualKeyguardSecureAndUnlocked'] = true;
          // This phase records the prerequisite only; it does not claim a lock /
          // unlock transition, reboot or Keystore authentication binding.
        }
        final after = await store.read();
        expect(
          after.session != null && after.session!.accountId == legacyAccount,
          isTrue,
        );
        await marker.write(
          jsonEncode({
            ...fixture,
            'pid': pid,
            'password': password,
            'lastPhase': phase,
          }),
        );
        await driver.invokeMethod<void>('stage', 'phase-accepted');
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          if (priorPid != null) 'priorPid': priorPid,
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'systemPasskey': {
            'passkey-bind',
            'passkey-cancel',
            'passkey-recover',
          }.contains(phase),
          ...flags,
        };
        accepted = true;
      } finally {
        // Preserve the product error/result page on a failed physical-device
        // phase, so the person confirming the system sheet sees its outcome.
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

class _LifecycleProbe extends WidgetsBindingObserver {
  bool backgrounded = false, resumed = false;
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
  bool Function() ready,
  String stage, {
  int seconds = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (ready()) return;
  }
  throw StateError('Owned App matrix stage timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () {
    if (finder.evaluate().length != 1) return false;
    var enabled = true;
    finder.evaluate().single.visitAncestorElements((element) {
      if (element.widget is ButtonStyleButton) {
        enabled = (element.widget as ButtonStyleButton).enabled;
        return false;
      }
      return true;
    });
    return enabled;
  }, 'single enabled action');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(tester, () => finder.evaluate().isNotEmpty, 'input ready');
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _account(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '账号与注销'));
  await _wait(
    tester,
    () => find.text('账号已登录').evaluate().isNotEmpty,
    'account route',
  );
}

Future<void> _security(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
  await _wait(
    tester,
    () =>
        find.byKey(const ValueKey('management-password')).evaluate().isNotEmpty,
    'actual credential directory',
  );
}

Future<void> _login(
  WidgetTester tester,
  String username,
  String password,
) async {
  await _input(tester, 'login-username', username);
  await _input(tester, 'login-password', password);
  await _tap(tester, find.text('登录并进入'));
  await _wait(
    tester,
    () => find.byType(AuthScreen).evaluate().isEmpty,
    'explicit password login',
  );
}

Future<void> _credentialCommitted(
  WidgetTester tester, {
  int seconds = 45,
}) async {
  await _wait(
    tester,
    () {
      final screens = find.byType(SecurityManagementScreen).evaluate();
      if (screens.length == 1) {
        final controller =
            (screens.single.widget as SecurityManagementScreen).controller;
        if (!controller.busy && controller.error != null) {
          final error = controller.error!;
          throw StateError(
            'Credential operation refused: kind=${error.kind.name}, code=${error.code}, status=${error.statusCode}',
          );
        }
      }
      return find.text('变更已确认提交。').evaluate().isNotEmpty;
    },
    'credential commit',
    seconds: seconds,
  );
  await _tap(tester, find.text('返回当前凭据'));
  await _wait(
    tester,
    () =>
        find.byKey(const ValueKey('management-password')).evaluate().isNotEmpty,
    'credential result acknowledged',
  );
}

Future<void> _oldSessionRejected(HttpAuthApi api, String token) async {
  await expectLater(
    api.currentSession(token),
    throwsA(
      isA<AuthFailure>().having(
        (failure) => failure.statusCode == 401,
        'old session rejected',
        true,
      ),
    ),
  );
}
