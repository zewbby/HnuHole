import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// Actual App/routes, native vault, actual cmd C/V and disposable SQL.
/// Mailpit is a test-only SMTP sink. No AuthApi/IdentityApi is replaced.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const mailOrigin = String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL');
  const cOrigin = String.fromEnvironment('AUTH_COMMUNITY_BASE_URL');
  const vOrigin = String.fromEnvironment('AUTH_VERIFIER_BASE_URL');
  testWidgets(
    'actual App and C/V with native persistence across processes',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(
        RegExp(r'^hnuhole-android-live-[A-Za-z0-9_-]+$').hasMatch(runId),
        isTrue,
      );
      final c = Uri.parse(cOrigin);
      final v = Uri.parse(vOrigin);
      validateDevelopmentOrigins(c, v);
      final mail = Uri.parse(mailOrigin);
      expect(
        mail.scheme == 'http' && mail.host == '127.0.0.1' && mail.hasPort,
        isTrue,
      );
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
      final prior = await marker.read();
      final username =
          'dev_${AuthCrypto.domainDigest('DEVICE-USERNAME', utf8.encode(runId)).substring(0, 16)}'
              .replaceAll('-', '_')
              .toLowerCase();
      // Synthetic, disposable credentials only; never persisted in a test report.
      final password =
          'Dev-${AuthCrypto.domainDigest('DEVICE-PASSWORD', utf8.encode(runId))}#9';
      final api = HttpAuthApi(
        communityBaseUri: c,
        verifierBaseUri: v,
        client: createAppHttpClient(community: c, verifier: v),
      );
      try {
        if (prior == null) {
          // Only this private cluster's endpoint-scoped test state is reset.
          // A failed previous UI run can have created a session before writing
          // the cross-process marker. Revoke it through the actual API first.
          final leftover = await store.read();
          if (leftover.session != null) {
            await api.revokeSession(
              AuthCrypto.revocationSecret(leftover.session!.token),
            );
          }
          await store.update((_) => const AuthState());
        }
        final ordinaryTrust = HttpClient()
          ..connectionTimeout = const Duration(seconds: 10);
        try {
          await expectLater(
            () async {
              final request = await ordinaryTrust.getUrl(
                c.resolve('/health/ready'),
              );
              await request.close();
            },
            throwsA(isA<HandshakeException>()),
            reason: 'A private development CA must not be accepted without explicit trust',
          );
        } finally {
          ordinaryTrust.close(force: true);
        }
        app.main();
        await tester.pump();
        if (prior == null) {
          await _wait(
            tester,
            () => find.text('登录或注册').evaluate().isNotEmpty,
            'signed-out App entry',
          );
          await _tap(tester, find.text('登录或注册'));
          await _tap(tester, find.text('新注册'));
          final email =
              'device-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
          await _input(tester, 'registration-email', email);
          await _tap(tester, find.text('获取验证码'));
          final otp = await _smtpOtp(mail, email);
          await _wait(
            tester,
            () => find.text('确认验证码').evaluate().isNotEmpty,
            'OTP request accepted',
          );
          await _input(tester, 'registration-otp', otp);
          await _tap(tester, find.text('确认验证码'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('registration-username'))
                .evaluate()
                .isNotEmpty,
            'eligibility confirmed',
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
            'registration intent',
          );
          final recovery = tester
              .widget<Text>(
                find.byKey(const ValueKey('displayed-recovery-code')),
              )
              .data!;
          await _tap(tester, find.text('我已保存，隐藏原码并确认'));
          await _input(tester, 'recovery-confirmation', recovery);
          await _tap(tester, find.text('确认恢复码并创建账号'));
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'actual registration and directory',
          );
          await _tap(tester, find.byTooltip('My content'));
          await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('identity-add'))
                .evaluate()
                .isNotEmpty,
            'real identity directory',
          );
          await _tap(tester, find.byKey(const ValueKey('identity-add')));
          await _input(tester, 'identity-nickname', '真机身份');
          await _tap(tester, find.byKey(const ValueKey('identity-save')));
          await _wait(
            tester,
            () => find.widgetWithText(ListTile, '真机身份').evaluate().isNotEmpty,
            'identity persisted',
          );
          await _tap(tester, find.widgetWithText(ListTile, '真机身份'));
          await _input(tester, 'identity-nickname', '真机改名');
          await _tap(tester, find.byKey(const ValueKey('identity-save')));
          await _wait(
            tester,
            () => find.widgetWithText(ListTile, '真机改名').evaluate().isNotEmpty,
            'identity rename persisted',
          );
          final state = await store.read();
          expect(state.session != null && state.logouts.isEmpty, isTrue);
          final directory = await api.identities(state.session!.token);
          expect(
            directory.identities.length == 1 &&
                directory.identities.single.nickname == '真机改名',
            isTrue,
          );
          await marker.write(
            jsonEncode({'pid': pid, 'accountId': state.session!.accountId}),
          );
          binding.reportData = {
            'phase': 'write',
            'pid': pid,
            'actualApp': true,
            'actualCV': true,
            'nativeVault': true,
            'identityCount': 1,
          };
        } else {
          final priorState = jsonDecode(prior) as Map<String, dynamic>;
          expect(
            priorState['pid'] != pid,
            isTrue,
            reason: 'Requires an external process restart',
          );
          final restored = await store.read();
          expect(
            restored.session != null &&
                restored.session!.accountId == priorState['accountId'],
            isTrue,
          );
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'native session restored by App',
          );
          await _tap(tester, find.byTooltip('My content'));
          await _tap(tester, find.widgetWithText(ListTile, '身份管理'));
          await _wait(
            tester,
            () => find.text('真机改名').evaluate().isNotEmpty,
            'SQL identity restored after restart',
          );
          await _tap(tester, find.byType(BackButton).first);
          await _tap(tester, find.widgetWithText(ListTile, '设备与恢复凭据'));
          await _wait(
            tester,
            () => find.text('退出本机').evaluate().isNotEmpty,
            'actual security management',
          );
          await _tap(tester, find.text('退出本机'));
          await _wait(
            tester,
            () => find
                .widgetWithText(OutlinedButton, '前往登录')
                .evaluate()
                .isNotEmpty,
            'logout shows signed-out management',
          );
          // This button remains disabled until the actual logout drain ends.
          // Follow the existing UI action before checking the old token.
          await _tap(tester, find.text('前往登录'));
          final loggedOut = await store.read();
          expect(
            loggedOut.session == null && loggedOut.logouts.isEmpty,
            isTrue,
          );
          await expectLater(
            api.currentSession(restored.session!.token),
            throwsA(
              isA<AuthFailure>().having(
                (e) => e.unauthorized,
                'revoked old session',
                true,
              ),
            ),
          );
          await _input(tester, 'login-username', username);
          await _input(tester, 'login-password', password);
          await _tap(tester, find.text('登录并进入'));
          await _wait(
            tester,
            () => find.widgetWithText(ListTile, '身份管理').evaluate().isNotEmpty,
            'password login after logout',
          );
          final reauthenticated = await store.read();
          expect(
            reauthenticated.session != null &&
                reauthenticated.session!.token != restored.session!.token,
            isTrue,
          );
          final directory = await api.identities(
            reauthenticated.session!.token,
          );
          expect(
            directory.identities.length == 1 &&
                directory.identities.single.nickname == '真机改名',
            isTrue,
          );
          await _tap(tester, find.byType(BackButton).first);
          await _wait(
            tester,
            () => find.byType(ChannelTree).evaluate().isNotEmpty,
            'directory ready after explicit login',
          );
          binding.reportData = {
            'phase': 'read',
            'pid': pid,
            'priorPid': priorState['pid'],
            'actualApp': true,
            'actualCV': true,
            'nativeVault': true,
            'logoutRevokedOldSession': true,
            'passwordLogin': true,
            'identityCount': 1,
          };
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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
  bool Function() ready,
  String stage,
) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (ready()) return;
  }
  throw StateError('App stage timed out: $stage');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () {
    if (finder.evaluate().isEmpty) return false;
    var enabled = true;
    finder.evaluate().single.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton) {
        enabled = widget.enabled;
        return false;
      }
      return true;
    });
    return enabled;
  }, 'tap target ready and enabled');
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _input(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _wait(tester, () => finder.evaluate().isNotEmpty, 'input target ready');
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  // Close the physical IME through the current route's normal focus handling.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<String> _smtpOtp(Uri origin, String email) async {
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
      if (bytes.length > 16384) {
        throw StateError('Test SMTP response is oversized');
      }
      final raw = utf8.decode(bytes);
      final code = RegExp(
        r'Your Hnuhole campus verification code is ([0-9]{6})\.',
      ).firstMatch(raw);
      if (response.statusCode == 200 && raw.contains(email) && code != null) {
        return code.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Owned test SMTP did not deliver an OTP');
  } finally {
    client.close(force: true);
  }
}
