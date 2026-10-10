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

// Full product UI, actual isolated HTTPS C/V, native encrypted storage. The
// host advances ONLY build-overlay Gate/evidence clocks; no SQL deadline edit.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const driver = MethodChannel('hnuhole/owned_device_driver');
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRun = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  testWidgets(
    'formal closure and same exact email fresh-account isolation',
    (tester) async {
      expect(
        Platform.isAndroid && runId == 'hnuhole-android-live-matrix-20261006',
        isTrue,
      );
      expect(accountRun, 'hnuhole-android-live-closure-20261007');
      final phase = (await driver.invokeMethod<String>('phase'))!;
      expect(
        {
          'closure-draft-request',
          'closure-draft-released',
          'closure-draft-register',
          'closure-profile-request',
          'closure-profile-released',
          'closure-profile-register',
          'closure-new-read',
        }.contains(phase),
        isTrue,
      );
      final c = Uri.parse(
        const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'),
      );
      final v = Uri.parse(
        const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'),
      );
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
        namespace: 'native.security.test.$accountRun.closure',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        client: createAppHttpClient(community: c, verifier: v),
      );
      final flags = <String, Object>{};
      final password =
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(accountRun))}#9';
      final stem =
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode(accountRun)).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      var accepted = false;
      try {
        final original = await store.read();
        if (phase == 'closure-draft-request') {
          expect(
            fixture.isEmpty &&
                original.session == null &&
                original.registration?['commit'] == null,
            isTrue,
          );
          fixture['email'] =
              (original.registration?['request'] as Map?)?['email'] ??
              'closure-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
          fixture['generation'] = 0;
        } else {
          expect(fixture['pid'] != pid, isTrue);
        }
        app.main();
        await tester.pump();
        if (phase == 'closure-draft-request') {
          await _tap(tester, find.text('登录或注册'));
          await _tap(tester, find.text('新注册'));
          fixture['recovery'] = await _register(
            tester,
            fixture['email'] as String,
            '${stem}_0',
            password,
            evidence: flags,
          );
          final state = await store.read();
          fixture['accountId'] = state.session!.accountId;
          await _identity(tester);
          await _tap(tester, find.byKey(const ValueKey('identity-add')));
          await _input(tester, 'identity-nickname', '注销前草稿');
          await _wait(
            tester,
            () async =>
                (await store.read()).identityDrafts[state
                    .session!
                    .accountId]?['nickname'] ==
                '注销前草稿',
            'native draft',
          );
          await _tap(tester, find.text('取消'));
          await _tap(tester, find.byType(BackButton).first);
          flags['actualRegistrationAndNativeDraftBeforeClosure'] = true;
        }
        if (phase.endsWith('-request')) {
          final state = await store.read();
          expect(state.session!.accountId, fixture['accountId']);
          final token = state.session!.token;
          if (phase == 'closure-profile-request') {
            await _wait(
              tester,
              () => find.byType(ChannelTree).evaluate().isNotEmpty,
              'restored fresh account',
            );
            await _identity(tester);
            for (var i = 1; i <= 3; i++) {
              await _tap(tester, find.byKey(const ValueKey('identity-add')));
              await _input(tester, 'identity-nickname', '关闭身份$i');
              await _tap(tester, find.byKey(const ValueKey('identity-save')));
              await _wait(
                tester,
                () => find
                    .widgetWithText(ListTile, '关闭身份$i')
                    .evaluate()
                    .isNotEmpty,
                'identity creation',
              );
            }
            final directory = await api.identities(token);
            expect(
              directory.createdCount == 3 && directory.identities.length == 3,
              isTrue,
            );
            fixture['identityIds'] = directory.identities
                .map((e) => e.id)
                .toList();
            await _tap(tester, find.byType(BackButton).first);
            flags['threeActualProductIdentitiesCreated'] = true;
          }
          fixture['oldToken'] = token;
          final directory = await api.identities(token);
          fixture['priorIdentityCount'] = directory.identities.length;
          await _tap(tester, find.widgetWithText(ListTile, '账号与注销'));
          await _input(tester, 'closure-password', password);
          await _tap(tester, find.text('查看并确认注销申请'));
          await _tap(tester, find.text('申请注销'));
          await _wait(
            tester,
            () => find.text('注销缓冲期').evaluate().isNotEmpty,
            'seven-day pending',
          );
          final pending = await store.read();
          expect(
            pending.session == null &&
                pending.pendingClosure?['state'] == 'PENDING',
            isTrue,
          );
          final status = await _status(api, pending.pendingClosure!);
          expect(status.state, ClosureState.pending);
          // DueAt is verified relative to the signed Gate TrustedAt by host SQL;
          // phone time deliberately remains real even on the second cycle.
          fixture['dueAt'] = status.dueAt!.toUtc().toIso8601String();
          fixture['closure'] = pending.pendingClosure;
          if (phase == 'closure-draft-request') {
            expect(
              pending.identityDrafts[fixture['accountId']]?['nickname'],
              '注销前草稿',
            );
          }
          await _unauthorized(api.currentSession(token));
          flags['sevenDayRequestClearedBearerAndRetainedAccountScopedData'] =
              true;
        } else if (phase.endsWith('-released')) {
          expect(original.session, isNull);
          expect(
            original.pendingClosure?['closureId'],
            (fixture['closure'] as Map)['closureId'],
          );
          await _wait(
            tester,
            () => find.text('核对注销状态').evaluate().isNotEmpty,
            'restored closure status',
          );
          await _tap(tester, find.text('核对注销状态'));
          await _wait(
            tester,
            () async =>
                (await store.read()).pendingClosure?['state'] == 'RELEASED',
            'actual closure and V ACK',
          );
          await _wait(
            tester,
            () => find.text('账号已关闭，资格已释放').evaluate().isNotEmpty,
            'released product page rendered after native state commit',
          );
          expect(find.text('账号已关闭，资格已释放'), findsOneWidget);
          final after = await store.read();
          expect(after.session, isNull);
          await _unauthorized(
            api.currentSession(fixture['oldToken'] as String),
          );
          await _unauthorized(
            api.login(
              username: '${stem}_${fixture['generation']}',
              password: password,
              installationId: after.cInstallationId!,
              idempotencyKey: AuthCrypto.randomEncoded(32),
            ),
          );
          await _unauthorized(
            api.createCodeResetIntent(fixture['recovery'] as String),
          );
          final again = await _status(api, fixture['closure'] as Map);
          expect(again.state, ClosureState.released);
          flags['actualWorkerClosureAndVerifierReleaseReconciled'] = true;
          flags['oldBearerPasswordAndRecoveryCodeRejected'] = true;
          flags['repeatedOriginalStatusLookupDidNotRestoreSession'] = true;
          fixture['closedAccountId'] = fixture['accountId'];
        } else if (phase.endsWith('-register')) {
          if (original.pendingClosure != null) {
            expect(original.pendingClosure?['state'], 'RELEASED');
            await _tap(tester, find.text('创建全新账号'));
          } else {
            // A failed fixture may already have selected fresh registration.
            // Resume only that same durable, uncommitted email request.
            expect(
              fixture['lastPhase'],
              phase.replaceFirst('-register', '-released'),
            );
            expect(original.session, isNull);
            expect(original.registration?['commit'], isNull);
            expect(
              (original.registration?['request'] as Map?)?['email'],
              fixture['email'],
            );
            await _tap(tester, find.text('登录或注册'));
            await _tap(tester, find.text('新注册'));
          }
          final generation = (fixture['generation'] as int) + 1;
          fixture['recovery'] = await _register(
            tester,
            fixture['email'] as String,
            '${stem}_$generation',
            password,
            evidence: flags,
          );
          final fresh = await store.read();
          final account = fresh.session!.accountId;
          expect(account != fixture['closedAccountId'], isTrue);
          expect(
            fresh.pendingClosure == null &&
                fresh.pendingReset == null &&
                fresh.registration == null,
            isTrue,
          );
          expect(
            fresh.identityChanges[account] == null &&
                fresh.identityDrafts[account] == null,
            isTrue,
          );
          final directory = await api.identities(fresh.session!.token);
          expect(
            directory.createdCount == 0 &&
                directory.identities.isEmpty &&
                directory.nextCreateAt == null,
            isTrue,
          );
          expect(
            (await api.recoveryCredentials(fresh.session!.token))
                .passkeys
                .isEmpty,
            isTrue,
          );
          await _identity(tester);
          await _tap(tester, find.byKey(const ValueKey('identity-add')));
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('identity-nickname')),
                )
                .controller!
                .text,
            '',
          );
          await _tap(tester, find.text('取消'));
          flags['sameExactEmailRequiredFreshOtpAndActualRegistration'] = true;
          flags['newAccountNoOldIdentityCounterCooldownDraftOrLocalOperation'] =
              true;
          flags['newAccountNoInheritedPasskey'] = true;
          fixture['generation'] = generation;
          fixture['accountId'] = account;
          fixture['newTokenDigest'] = AuthCrypto.domainDigest(
            'CLOSURE-SESSION',
            utf8.encode(fresh.session!.token),
          );
        } else {
          expect(original.session!.accountId, fixture['accountId']);
          expect(
            AuthCrypto.domainDigest(
              'CLOSURE-SESSION',
              utf8.encode(original.session!.token),
            ),
            fixture['newTokenDigest'],
          );
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'new session restart',
          );
          final directory = await api.identities(original.session!.token);
          expect(
            directory.createdCount == 0 && directory.identities.isEmpty,
            isTrue,
          );
          await _identity(tester);
          await _tap(tester, find.byKey(const ValueKey('identity-add')));
          await _input(tester, 'identity-nickname', '关闭身份1');
          await _tap(tester, find.byKey(const ValueKey('identity-save')));
          await _wait(
            tester,
            () => find.widgetWithText(ListTile, '关闭身份1').evaluate().isNotEmpty,
            'new independent identity',
          );
          final fresh = await api.identities(original.session!.token);
          expect(
            fresh.createdCount == 1 &&
                fresh.identities.single.isOriginal &&
                !(fixture['identityIds'] as List).contains(
                  fresh.identities.single.id,
                ),
            isTrue,
          );
          flags['newSessionRestoredInIndependentProcess'] = true;
          flags['sameNicknameCreatedWithFreshIdAndIndependentHistory'] = true;
        }
        fixture['pid'] = pid;
        fixture['lastPhase'] = phase;
        await marker.write(jsonEncode(fixture));
        binding.reportData = {
          'phase': phase,
          'pid': pid,
          'actualApp': true,
          'actualCV': true,
          'nativeVault': true,
          'systemPasskey': false,
          'simulatedGateTime': true,
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
    timeout: const Timeout(Duration(minutes: 6)),
    skip: runId.isEmpty,
  );
}

Future<ClosureStatus> _status(HttpAuthApi api, Map closure) =>
    api.closureStatus(
      closureId: closure['closureId'] as String,
      statusSecret: closure['statusSecret'] as String,
    );
Future<void> _unauthorized(Future<Object?> future) => expectLater(
  future,
  throwsA(
    isA<AuthFailure>().having(
      (e) => e.statusCode,
      'old authority rejected',
      401,
    ),
  ),
);
Future<void> _identity(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('My content'));
  await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
  await _wait(
    tester,
    () => find.byKey(const ValueKey('identity-add')).evaluate().isNotEmpty,
    'identity route',
  );
}

Future<String> _register(
  WidgetTester tester,
  String email,
  String username,
  String password, {
  Map<String, Object>? evidence,
}) async {
  await _wait(
    tester,
    () =>
        find
            .byKey(const ValueKey('registration-email'))
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const ValueKey('registration-username'))
            .evaluate()
            .isNotEmpty,
    'registration stage',
  );
  // A failed environment startup may leave a genuine V ticket. Reuse its
  // original qualification; never fabricate or discard an unknown C commit.
  if (find
      .byKey(const ValueKey('registration-username'))
      .evaluate()
      .isNotEmpty) {
    // Read only the original result first. A long manual-install delay can
    // exhaust V's confirmation window; only its terminal response permits a
    // new OTP through the normal product action, retaining the original slot.
    final flows = tester.widget<AuthScreen>(find.byType(AuthScreen)).flows;
    await flows.reconcileOtpConfirmation();
    await tester.pump(const Duration(milliseconds: 200));
    if (flows.canRestartOtpVerification) {
      await _tap(tester, find.text('结束过期操作，重新收码'));
    }
  }
  for (
    var attempt = 0;
    attempt < 3 &&
        find.byKey(const ValueKey('registration-email')).evaluate().isNotEmpty;
    attempt++
  ) {
    final flows = tester.widget<AuthScreen>(find.byType(AuthScreen)).flows;
    if (flows.status == AuthFlowStatus.otpConfirmationPending) {
      await _tap(tester, find.text('核对校邮确认结果'));
      await _wait(
        tester,
        () => !flows.busy,
        'original confirmation result returned',
      );
      if (flows.status == AuthFlowStatus.eligibilityReady) break;
    }
    if (flows.canRestartOtpVerification) {
      await _tap(tester, find.text('结束过期操作，重新收码'));
      await _wait(
        tester,
        () => !flows.busy && flows.status == AuthFlowStatus.idle,
        'explicit expired continuation',
      );
      evidence?['expiredOriginalOtpReconciledAndExplicitlyContinued'] = true;
    }
    await _input(tester, 'registration-email', email);
    final originalConfirmation = find.text('使用原验证码继续确认').evaluate().isNotEmpty;
    final mail = Uri.parse(
      const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL'),
    );
    String? previousMessage;
    if (!originalConfirmation && flows.status != AuthFlowStatus.otpRequested) {
      previousMessage = await _smtpFingerprint(mail);
      await _tap(tester, find.text('获取验证码'));
    }
    final otp = await _smtpOtp(mail, email, excludingMessage: previousMessage);
    await _input(tester, 'registration-otp', otp);
    await _tap(
      tester,
      find.text(originalConfirmation ? '使用原验证码继续确认' : '确认验证码'),
    );
    await _wait(
      tester,
      () =>
          !flows.busy &&
          (flows.status == AuthFlowStatus.eligibilityReady ||
              flows.canRestartOtpVerification),
      'original confirmation reached ticket or known terminal expiry',
    );
  }
  await _input(tester, 'registration-username', username);
  await _input(tester, 'registration-password', password);
  await _tap(tester, find.text('生成并保存恢复码'));
  await _wait(
    tester,
    () => find
        .byKey(const ValueKey('displayed-recovery-code'))
        .evaluate()
        .isNotEmpty,
    'real recovery code',
  );
  final recovery = tester
      .widget<Text>(find.byKey(const ValueKey('displayed-recovery-code')))
      .data!;
  await _tap(tester, find.text('我已保存，隐藏原码并确认'));
  await _input(tester, 'recovery-confirmation', recovery);
  await _tap(tester, find.text('确认恢复码并创建账号'));
  await _wait(
    tester,
    () =>
        find.byType(ChannelTree).evaluate().isNotEmpty &&
        find.byType(AuthScreen).evaluate().isEmpty,
    'actual fresh account',
  );
  return recovery;
}

Future<void> _wait(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage,
) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Closure phase timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().length == 1, 'single action');
  await _wait(tester, () {
    final target = tester.widget<Widget>(finder);
    if (target is ButtonStyleButton) return target.onPressed != null;
    final buttons = find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    return buttons.evaluate().isEmpty ||
        tester.widget<ButtonStyleButton>(buttons.first).onPressed != null;
  }, 'enabled action');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(
    tester,
    () =>
        finder.evaluate().isNotEmpty &&
        tester.widget<TextFormField>(finder).enabled,
    'enabled input',
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  expect(
    tester.widget<TextFormField>(finder).controller!.text == value,
    isTrue,
    reason: 'Enabled product input must receive the intended value',
  );
}

Future<String?> _smtpFingerprint(Uri origin) async {
  expect(
    origin.scheme == 'http' && origin.host == '127.0.0.1' && origin.hasPort,
    isTrue,
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(
      origin.resolve('/api/v1/message/latest/raw'),
    );
    request.followRedirects = false;
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (a, b) => a..addAll(b),
    );
    expect(bytes.length <= 16384, isTrue);
    return response.statusCode == 200
        ? AuthCrypto.domainDigest('CLOSURE-SMTP-MESSAGE', bytes)
        : null;
  } finally {
    client.close(force: true);
  }
}

Future<String> _smtpOtp(
  Uri origin,
  String email, {
  String? excludingMessage,
}) async {
  expect(
    origin.scheme == 'http' && origin.host == '127.0.0.1' && origin.hasPort,
    isTrue,
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    for (var i = 0; i < 100; i++) {
      final request = await client.getUrl(
        origin.resolve('/api/v1/message/latest/raw'),
      );
      request.followRedirects = false;
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      expect(bytes.length <= 16384, isTrue);
      final raw = utf8.decode(bytes);
      final match = RegExp(
        r'Your Hnuhole campus verification code is ([0-9]{6})\.',
      ).firstMatch(raw);
      if (response.statusCode == 200 &&
          raw.contains(email) &&
          match != null &&
          AuthCrypto.domainDigest('CLOSURE-SMTP-MESSAGE', bytes) !=
              excludingMessage) {
        return match[1]!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Owned SMTP delivery absent');
  } finally {
    client.close(force: true);
  }
}
