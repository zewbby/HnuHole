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

/// Real App/V/SMTP phases. Host waits for normal immutable flow cleanup;
/// it must not shorten SQL deadlines or replace API/session authority.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runId = String.fromEnvironment('AUTH_DEVICE_RUN_ID');
  const accountRunId = String.fromEnvironment('AUTH_MATRIX_ACCOUNT_RUN_ID');
  const driver = MethodChannel('hnuhole/owned_device_driver');
  testWidgets(
    'actual Android OTP continuation after normal flow cleanup',
    (tester) async {
      expect(
        Platform.isAndroid &&
            runId == 'hnuhole-android-live-matrix-20261006' &&
            accountRunId == 'hnuhole-android-live-boundary-20261006',
        isTrue,
      );
      final phase = await driver.invokeMethod<String>('phase');
      expect(
        const {
          'otp-continuation-request',
          'otp-continuation-frozen',
          'otp-continuation-cleaned',
          'otp-continuation-resume',
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
      final digest = AuthCrypto.domainDigest(
        'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
        utf8.encode(scope),
      );
      final store = AuthStore(
        FlutterAuthVault(namespace: 'hnuhole.auth.v1.$digest'),
        scope: scope,
      );
      final marker = FlutterAuthVault(
        namespace: 'native.security.test.$runId.otp-continuation',
      );
      final fixture =
          jsonDecode(await marker.read() ?? '{}') as Map<String, dynamic>;
      final flags = <String, Object>{};
      var accepted = false;
      try {
        final original = await store.read();
        expect(
          original.session == null &&
              original.pendingReset == null &&
              original.pendingClosure == null,
          isTrue,
        );
        if (phase == 'otp-continuation-request') {
          expect(original.registration == null, isTrue);
        } else {
          expect(
            original.registration != null &&
                original.registration!['ticket'] == null &&
                original.registration!['commit'] == null,
            isTrue,
          );
          expect(fixture['pid'] != pid, isTrue);
          _sameBootstrap(original.registration!, fixture);
        }
        app.main();
        await tester.pump();
        await _wait(
          tester,
          () => find.text('登录或注册').evaluate().isNotEmpty,
          'guest App',
        );
        await _tap(tester, find.text('登录或注册'));
        await _tap(tester, find.text('新注册'));
        final flows = tester.widget<AuthScreen>(find.byType(AuthScreen)).flows;
        if (phase == 'otp-continuation-request') {
          final email =
              'continuation-${DateTime.now().microsecondsSinceEpoch}@hainanu.edu.cn';
          await _input(tester, 'registration-email', email);
          await _tap(tester, find.text('获取验证码'));
          await _wait(
            tester,
            () => !flows.busy && flows.status == AuthFlowStatus.otpRequested,
            'V request',
          );
          expect(flows.error == null, isTrue);
          final registration = (await store.read()).registration!;
          fixture['email'] = email;
          fixture['otp'] = await _smtpOtp(
            Uri.parse(const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL')),
            email,
          );
          for (final field in ['seed', 'publicKey', 'slotId']) {
            fixture[field] = registration[field];
          }
          fixture['requestKey'] = registration['request']['key'];
          flags['actualVRequestAndSMTPDelivered'] = true;
          flags['requestedAtUTC'] = DateTime.now().toUtc().toIso8601String();
        } else if (phase == 'otp-continuation-frozen' ||
            phase == 'otp-continuation-cleaned') {
          await _input(
            tester,
            'registration-email',
            fixture['email'] as String,
          );
          await _input(tester, 'registration-otp', fixture['otp'] as String);
          await _tap(
            tester,
            find.text(
              phase == 'otp-continuation-frozen' ? '确认验证码' : '使用原验证码继续确认',
            ),
          );
          await _wait(
            tester,
            () => !flows.busy && flows.error != null,
            'definitive V response',
          );
          final after = (await store.read()).registration!;
          _sameBootstrap(after, fixture);
          expect(after['ticket'] == null && after['commit'] == null, isTrue);
          if (phase == 'otp-continuation-frozen') {
            expect(
              flows.error!.statusCode == 503 &&
                  !flows.canRestartOtpVerification,
              isTrue,
            );
            fixture['confirmationKey'] = after['confirmation']['key'];
            flags['actualFrozenVRejectedWithoutNewVerification'] = true;
          } else {
            expect(
              flows.error!.statusCode == 422 &&
                  flows.error!.code == 'OTP_FLOW_INVALID',
              isTrue,
            );
            expect(
              after['confirmation']['key'] == fixture['confirmationKey'] &&
                  after['confirmation']['expired'] == true,
              isTrue,
            );
            expect(flows.canRestartOtpVerification, isTrue);
            flags['actualCleanedFlowPostRejectedWithOriginalKey'] = true;
            // A missing anchor still means unknown. Querying it must not destroy
            // the explicit continuation permission from the definitive POST.
            await _tap(tester, find.text('核对校邮确认结果'));
            await _wait(tester, () => !flows.busy, 'original unknown result');
            expect(
              flows.error == null &&
                  flows.status == AuthFlowStatus.otpConfirmationPending &&
                  flows.canRestartOtpVerification,
              isTrue,
            );
            expect(
              (await store.read()).registration!['confirmation']['key'] ==
                  fixture['confirmationKey'],
              isTrue,
            );
            flags['unknownGetPreservesOriginalKeyAndExplicitPermission'] = true;
          }
        } else {
          expect(
            flows.error == null && flows.canRestartOtpVerification,
            isTrue,
          );
          expect(find.text('使用原验证码继续确认'), findsNothing);
          expect(
            original.registration!['confirmation']['key'] ==
                fixture['confirmationKey'],
            isTrue,
          );
          flags['nativeRestartRestoresActionWithoutTransientError'] = true;
          await _tap(tester, find.text('结束过期操作，重新收码'));
          await _wait(
            tester,
            () => !flows.busy && flows.status == AuthFlowStatus.idle,
            'explicit abandon',
          );
          final cleared = (await store.read()).registration!;
          _sameBootstrap(cleared, fixture);
          expect(
            cleared['request'] == null &&
                cleared['confirmation'] == null &&
                cleared['ticket'] == null,
            isTrue,
          );
          flags['explicitExitPreservesBootstrapWithoutAutomaticSend'] = true;
          await _input(
            tester,
            'registration-email',
            fixture['email'] as String,
          );
          await _tap(tester, find.text('获取验证码'));
          await _wait(
            tester,
            () => !flows.busy && flows.status == AuthFlowStatus.otpRequested,
            'explicit new V request',
          );
          final requested = (await store.read()).registration!;
          _sameBootstrap(requested, fixture);
          expect(requested['request']['key'] != fixture['requestKey'], isTrue);
          final otp = await _smtpOtp(
            Uri.parse(const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL')),
            fixture['email'] as String,
            previousOtp: fixture['otp'] as String,
          );
          await _input(tester, 'registration-otp', otp);
          await _tap(tester, find.text('确认验证码'));
          await _wait(
            tester,
            () =>
                !flows.busy && flows.status == AuthFlowStatus.eligibilityReady,
            'same bootstrap ticket',
          );
          expect(flows.error == null, isTrue);
          final after = await store.read();
          _sameBootstrap(after.registration!, fixture);
          final ticket = AuthCrypto.parseRegistrationTicket(
            after.registration!['ticket'] as String,
          );
          expect(
            ticket.bootstrapPublicKey == fixture['publicKey'] &&
                ticket.slotId == fixture['slotId'],
            isTrue,
          );
          expect(
            after.session == null && after.registration!['commit'] == null,
            isTrue,
          );
          fixture.remove('otp');
          flags['actualNewOtpTicketBoundToOriginalBootstrap'] = true;
          flags['noCRegistrationCommitOrAutomaticLogin'] = true;
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
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: runId.isEmpty,
  );
}

void _sameBootstrap(
  Map<String, dynamic> registration,
  Map<String, dynamic> fixture,
) {
  for (final field in ['seed', 'publicKey', 'slotId']) {
    expect(registration[field] == fixture[field], isTrue);
  }
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

Future<String> _smtpOtp(Uri origin, String email, {String? previousOtp}) async {
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
      if (response.statusCode == 200 &&
          raw.contains(email) &&
          match != null &&
          match[1] != previousOtp) {
        return match[1]!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('Owned SMTP delivery absent');
  } finally {
    client.close(force: true);
  }
}
