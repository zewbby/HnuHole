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

/// Actual App phases on the owned phone/emulator. Never fabricates a session,
/// registration ticket or API result. Synthetic OTPs stay in a test-only vault.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const cOrigin = String.fromEnvironment('AUTH_COMMUNITY_BASE_URL');
  const vOrigin = String.fromEnvironment('AUTH_VERIFIER_BASE_URL');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual Android authorization boundary phases',
    (tester) async {
      expect(
        Platform.isAndroid && runId == 'hnuhole-android-live-matrix-20261006',
        isTrue,
      );
      expect(accountRunId == 'hnuhole-android-live-boundary-20261006', isTrue);
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'takeover-register',
          'takeover-source',
          'takeover-other',
          'takeover-observe',
          'v-gate-request',
          'v-gate-frozen-confirm',
          'v-gate-old-confirm',
        }.contains(phase),
        isTrue,
      );
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
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$runId.boundary',
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
      // Disposable boundary account, created only through the actual App.
      // Its password is used through the login form and never reported.
      final password =
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(accountRunId))}#9';
      final flags = <String, Object>{};
      var accepted = false;
      try {
        final original = await store.read();
        if (phase == 'takeover-register') {
          expect(
            original.session == null && original.registration == null,
            isTrue,
          );
        } else if (phase == 'takeover-source') {
          expect(original.session != null, isTrue);
          final legacy = jsonDecode(
            (await FlutterAuthVault(
              namespace: 'native.security.test.$accountRunId',
            ).read())!,
          );
          expect(legacy['accountId'] == original.session!.accountId, isTrue);
          final current = await api.currentSession(original.session!.token);
          expect(current.username == username, isTrue);
          final directory = await api.identities(original.session!.token);
          fixture['sourceAccountId'] = current.accountId;
          fixture['sourceIdentityCount'] = directory.identities.length;
          fixture['sourceCreatedCount'] = directory.createdCount;
        } else if (phase == 'takeover-other') {
          expect(
            original.session == null &&
                original.registration == null &&
                original.pendingReset == null,
            isTrue,
            reason: 'Companion must start with an owned fresh scoped vault',
          );
        } else if (phase == 'takeover-observe') {
          expect(
            original.session?.accountId == fixture['sourceAccountId'],
            isTrue,
          );
          await _rejectedSession(api, original.session!.token);
          flags['actualOldBearerRejectedBeforeStartup'] = true;
        }
        app.main();
        await tester.pump();
        if (phase == 'takeover-register') {
          await _wait(
            tester,
            () => find.text('登录或注册').evaluate().isNotEmpty,
            'fresh App',
          );
          await _tap(tester, find.text('登录或注册'));
          await _tap(tester, find.text('新注册'));
          final email =
              'boundary-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
          await _input(tester, 'registration-email', email);
          await _tap(tester, find.text('获取验证码'));
          await _wait(
            tester,
            () => find.text('确认验证码').evaluate().isNotEmpty,
            'V request',
          );
          final otp = await _smtpOtp(
            Uri.parse(const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL')),
            email,
          );
          await _input(tester, 'registration-otp', otp);
          await _tap(tester, find.text('确认验证码'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('registration-username'))
                .evaluate()
                .isNotEmpty,
            'V eligibility',
          );
          await _input(tester, 'registration-username', username);
          await _input(tester, 'registration-password', password);
          await _tap(tester, find.text('生成并保存恢复码'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('displayed-recovery-code'))
                .evaluate()
                .isNotEmpty,
            'C registration intent',
          );
          final code = tester
              .widget<Text>(
                find.byKey(const ValueKey('displayed-recovery-code')),
              )
              .data!;
          await _tap(tester, find.text('我已保存，隐藏原码并确认'));
          await _input(tester, 'recovery-confirmation', code);
          await _tap(tester, find.text('确认恢复码并创建账号'));
          await _wait(
            tester,
            () => find.byType(AuthScreen).evaluate().isEmpty,
            'actual C account',
          );
          final after = await store.read();
          expect(after.session != null && after.registration == null, isTrue);
          final directory = await api.identities(after.session!.token);
          expect(
            directory.identities.isEmpty && directory.createdCount == 0,
            isTrue,
          );
          await FlutterAuthVault(
            namespace: 'native.security.test.$accountRunId',
          ).write(jsonEncode({'accountId': after.session!.accountId}));
          fixture['sourceAccountId'] = after.session!.accountId;
          fixture['sourceIdentityCount'] = 0;
          fixture['sourceCreatedCount'] = 0;
          flags['actualVSMTPAndFullRecoveryConfirmationCreatedAccount'] = true;
        } else if (phase == 'takeover-source') {
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'source App restored',
          );
          flags['sourceAuthoritativeSessionAndIdentitiesCaptured'] = true;
        } else if (phase == 'takeover-other' || phase == 'takeover-observe') {
          await _wait(
            tester,
            () async =>
                find.text('登录或注册').evaluate().isNotEmpty &&
                (await store.read()).session == null,
            'guest after absent or stale session',
          );
          flags['noAutomaticLoginBeforeExplicitAction'] = true;
          await _tap(tester, find.text('登录或注册'));
          await _input(tester, 'login-username', username);
          await _input(tester, 'login-password', password);
          await _tap(tester, find.text('登录并进入'));
          await _wait(
            tester,
            () async =>
                find.byType(AuthScreen).evaluate().isEmpty &&
                (await store.read()).session != null,
            'actual explicit password login',
          );
          final after = await store.read();
          expect(
            (await api.currentSession(after.session!.token)).username ==
                username,
            isTrue,
          );
          if (phase == 'takeover-observe') {
            final directory = await api.identities(after.session!.token);
            expect(
              after.session!.accountId == fixture['sourceAccountId'] &&
                  directory.identities.length ==
                      fixture['sourceIdentityCount'] &&
                  directory.createdCount == fixture['sourceCreatedCount'],
              isTrue,
            );
            await _rejectedSession(api, original.session!.token);
            flags['sameAccountAndIdentitiesAfterExplicitRetake'] = true;
          }
          flags['actualProductPasswordLogin'] = true;
        } else {
          if (phase == 'v-gate-request') {
            if (original.session != null) {
              // Phone has retaken the single mobile session. Startup must clear
              // the emulator's stale bearer before starting a fresh registration.
              await _rejectedSession(api, original.session!.token);
            }
            await _wait(
              tester,
              () async =>
                  find.text('登录或注册').evaluate().isNotEmpty &&
                  (await store.read()).session == null,
              'signed out companion',
            );
            await _tap(tester, find.text('登录或注册'));
          } else {
            expect(
              original.session == null && original.registration != null,
              isTrue,
            );
            await _wait(
              tester,
              () => find.text('登录或注册').evaluate().isNotEmpty,
              'guest registration restore',
            );
            await _tap(tester, find.text('登录或注册'));
          }
          await _tap(tester, find.text('新注册'));
          if (phase == 'v-gate-request') {
            expect(
              original.registration?['request'] == null &&
                  original.registration?['confirmation'] == null &&
                  original.registration?['ticket'] == null,
              isTrue,
            );
            final email =
                'boundary-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
            await _input(tester, 'registration-email', email);
            await _tap(tester, find.text('获取验证码'));
            await _wait(
              tester,
              () => find.text('确认验证码').evaluate().isNotEmpty,
              'actual V OTP request',
            );
            fixture['email'] = email;
            fixture['otp'] = await _smtpOtp(
              Uri.parse(
                const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL'),
              ),
              email,
            );
            flags['actualVRequestAndTestSMTPDelivered'] = true;
          } else {
            await _input(
              tester,
              'registration-email',
              fixture['email'] as String,
            );
            await _input(tester, 'registration-otp', fixture['otp'] as String);
            if (phase == 'v-gate-frozen-confirm') {
              expect(original.registration!['confirmation'] == null, isTrue);
              await _tap(tester, find.text('确认验证码'));
              await _wait(
                tester,
                () => !_flows(tester).busy && _flows(tester).error != null,
                'V frozen rejection',
              );
              expect(_flows(tester).error!.statusCode == 503, isTrue);
              final persisted = await store.read();
              expect(
                persisted.registration?['ticket'] == null &&
                    persisted.session == null &&
                    persisted.registration?['confirmation'] != null,
                isTrue,
              );
              fixture['confirmationKey'] =
                  (persisted.registration!['confirmation'] as Map)['key'];
              flags['actualFrozenVRejectedConfirmation'] = true;
              flags['noTicketOrSessionGranted'] = true;
            } else {
              expect(
                (original.registration!['confirmation'] as Map)['key'] ==
                    fixture['confirmationKey'],
                isTrue,
              );
              await _tap(tester, find.text('使用原验证码继续确认'));
              await _wait(
                tester,
                () => !_flows(tester).busy && _flows(tester).error != null,
                'old generation rejected',
              );
              final error = _flows(tester).error!;
              // This flow had no accepted confirmation before the freeze.
              // V's immutable flow-generation check returns OTP_EXPIRED;
              // REVERIFY_REQUIRED belongs to prior confirmation anchors.
              expect(error.code, 'OTP_EXPIRED');
              expect(error.statusCode, 422);
              expect(
                (await store.read()).registration?['ticket'] == null,
                isTrue,
              );
              flags['actualOldOtpRejectedAfterVRecovery'] = true;
              await _tap(tester, find.text('核对校邮确认结果'));
              await _wait(
                tester,
                () async =>
                    !_flows(tester).busy &&
                    (await store.read()).registration?['confirmation'] == null,
                'original confirmation terminalized',
              );
              final after = await store.read();
              expect(
                after.session == null &&
                    after.registration?['ticket'] == null &&
                    after.registration?['request'] == null,
                isTrue,
              );
              fixture.remove('otp');
              flags['originalResultReconciledWithoutNewOtpOrAccount'] = true;
            }
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

AuthFlows _flows(WidgetTester tester) =>
    tester.widget<AuthScreen>(find.byType(AuthScreen)).flows;
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
  throw StateError('Boundary phase timed out: $stage');
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

Future<void> _rejectedSession(HttpAuthApi api, String token) => expectLater(
  api.currentSession(token),
  throwsA(
    isA<AuthFailure>().having(
      (e) => e.statusCode,
      'stale bearer rejected',
      401,
    ),
  ),
);
Future<String> _smtpOtp(Uri origin, String email) async {
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
        (buffer, part) => buffer..addAll(part),
      );
      expect(bytes.length <= 16384, isTrue);
      final raw = utf8.decode(bytes);
      final match = RegExp(
        r'Your Hnuhole campus verification code is ([0-9]{6})\.',
      ).firstMatch(raw);
      if (response.statusCode == 200 && raw.contains(email) && match != null) {
        return match[1]!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Owned SMTP delivery absent');
  } finally {
    client.close(force: true);
  }
}
