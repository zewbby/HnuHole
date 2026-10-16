import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

// Actual product widgets and owned SMTP only. Never export synthetic secrets.
Future<String> registerOwned(
  WidgetTester tester,
  String email,
  String username,
  String password, {
  Map<String, Object>? evidence,
  Future<void> Function(String)? onRecoveryPrepared,
}) async {
  expect(
    RegExp(r'^[a-z][a-z0-9_]{5,23}$').hasMatch(username),
    true,
    reason: 'Owned registration fixture must satisfy the product username contract before UI actions',
  );
  await waitOwned(
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
      await tapOwned(tester, find.text('结束过期操作，重新收码'));
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
      await tapOwned(tester, find.text('核对校邮确认结果'));
      await waitOwned(
        tester,
        () => !flows.busy,
        'original confirmation result returned',
      );
      if (flows.status == AuthFlowStatus.eligibilityReady) break;
    }
    if (flows.canRestartOtpVerification) {
      await tapOwned(tester, find.text('结束过期操作，重新收码'));
      await waitOwned(
        tester,
        () => !flows.busy && flows.status == AuthFlowStatus.idle,
        'explicit expired continuation',
      );
      evidence?['expiredOriginalOtpReconciledAndExplicitlyContinued'] = true;
    }
    await inputOwned(tester, 'registration-email', email);
    final originalConfirmation = find.text('使用原验证码继续确认').evaluate().isNotEmpty;
    final mail = Uri.parse(
      const String.fromEnvironment('AUTH_DEVICE_MAILPIT_URL'),
    );
    String? previousMessage;
    if (!originalConfirmation && flows.status != AuthFlowStatus.otpRequested) {
      previousMessage = await smtpFingerprint(mail);
      await tapOwned(tester, find.text('获取验证码'));
    }
    final otp = await smtpOtp(mail, email, excludingMessage: previousMessage);
    await inputOwned(tester, 'registration-otp', otp);
    await tapOwned(
      tester,
      find.text(originalConfirmation ? '使用原验证码继续确认' : '确认验证码'),
    );
    await waitOwned(
      tester,
      () =>
          !flows.busy &&
          (flows.status == AuthFlowStatus.eligibilityReady ||
              flows.canRestartOtpVerification),
      'original confirmation reached ticket or known terminal expiry',
    );
  }
  await inputOwned(tester, 'registration-username', username);
  await inputOwned(tester, 'registration-password', password);
  await tapOwned(tester, find.text('生成并保存恢复码'));
  await waitOwned(
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
  await onRecoveryPrepared?.call(recovery);
  await tapOwned(tester, find.text('我已保存，隐藏原码并确认'));
  await inputOwned(tester, 'recovery-confirmation', recovery);
  final auth = tester.widget<AuthScreen>(find.byType(AuthScreen));
  await tapOwned(tester, find.text('确认恢复码并创建账号'));
  try {
    await waitOwned(
      tester,
      () =>
          auth.sessions.isAuthenticated &&
          find.byType(ChannelTree, skipOffstage: false).evaluate().isNotEmpty &&
          find.byType(AuthScreen).evaluate().isEmpty,
      'actual fresh account',
    );
    evidence?['actualFreshRegistrationAuthenticatedAndAuthRouteClosed'] = true;
  } catch (_) {
    // Public enums/counts only. An authenticated return may leave Settings above
    // ChannelTree; that underlying route is intentionally offstage.
    throw StateError(
      'Owned fresh registration: session=${auth.sessions.status.name}, '
      'flow=${auth.flows.status.name}, busy=${auth.flows.busy}, '
      'authRoutes=${find.byType(AuthScreen).evaluate().length}, '
      'visibleTrees=${find.byType(ChannelTree).evaluate().length}',
    );
  }
  return recovery;
}

Future<void> waitOwned(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String stage,
) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await ready()) return;
  }
  throw StateError('Owned B3/B4 phase timed out: $stage');
}

Future<void> tapOwned(WidgetTester tester, Finder finder) async {
  await waitOwned(tester, () => finder.evaluate().length == 1, 'single action');
  await waitOwned(tester, () {
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

Future<void> inputOwned(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await waitOwned(
    tester,
    () =>
        finder.evaluate().isNotEmpty &&
        tester.widget<TextFormField>(finder).enabled,
    'enabled input',
  );
  await tester.ensureVisible(finder);
  // Synthetic secret preparation only; physical IME acceptance is separate.
  tester.widget<TextFormField>(finder).controller!.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  expect(
    tester.widget<TextFormField>(finder).controller!.text == value,
    isTrue,
    reason: 'Enabled product input must receive the intended value',
  );
}

Future<String?> smtpFingerprint(Uri origin) async {
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

Future<String> smtpOtp(
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
