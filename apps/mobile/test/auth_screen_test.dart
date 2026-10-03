import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

const _account = '00000000-0000-4000-8000-000000000001';
const _savedCode = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _newCode = 'BBBBBBBBBBBBBBBBBBBBBBBBBB';
final _expiry = DateTime.utc(2026, 10, 30);

class _Vault implements AuthVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class _Channels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) async => ChannelDirectoryResult(expiresAt: _expiry, channels: [
    for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
      Channel(
        id: 'channel-$i',
        code: ChannelDirectory.requiredCodes[i],
        name: ChannelDirectory.requiredCodes[i],
        initiallyVisible: i < 5,
        displayOrder: i,
      ),
  ]);
}

class _Api implements AuthApi {
  int logins = 0;
  int otpRequests = 0;
  int registrations = 0;
  int resets = 0;
  int revocations = 0;
  bool rejectRevocation = false;
  String? submittedUsername;
  String? submittedConfirmation;
  final token = AuthCrypto.randomEncoded(32);

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async {
    logins++;
    submittedUsername = username;
    return AuthSession(
      accountId: _account,
      sessionToken: token,
      expiresAt: _expiry,
    );
  }

  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: _account,
    username: 'private_name',
    expiresAt: _expiry,
  );

  @override
  Future<void> revokeSession(String secret) async {
    revocations++;
    if (rejectRevocation) {
      throw const AuthFailure(kind: AuthFailureKind.timeout);
    }
  }

  @override
  Future<OtpRequestAccepted> requestOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  }) async {
    otpRequests++;
    return OtpRequestAccepted(
      flowId: AuthCrypto.randomEncoded(32),
      retryAfterSeconds: 60,
    );
  }

  @override
  Future<RegistrationIntent> createRegistrationIntent({
    required String registrationTicket,
    required String username,
    required String password,
    required String installationId,
  }) async => RegistrationIntent(
    intentId: AuthCrypto.randomEncoded(32),
    challenge: AuthCrypto.randomEncoded(32),
    expiresAt: _expiry,
    recoveryCode: _savedCode,
  );

  @override
  Future<AuthSession> commitRegistration({
    required String intentId,
    required String bootstrapSignature,
    required String recoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    registrations++;
    submittedConfirmation = recoveryCodeConfirmation;
    return AuthSession(
      accountId: _account,
      sessionToken: token,
      expiresAt: _expiry,
    );
  }

  @override
  Future<PasswordResetIntent> createCodeResetIntent(String code) async =>
      PasswordResetIntent(
        resetIntentId: AuthCrypto.randomEncoded(32),
        expiresAt: _expiry,
        username: 'private_name',
        newRecoveryCode: _newCode,
      );

  @override
  Future<void> commitPasswordReset({
    required String resetIntentId,
    required String newPassword,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    resets++;
  }

  @override
  Future<ClosureAccepted> requestClosure({
    required String sessionToken,
    required String password,
    required String closureId,
    required String statusDigest,
  }) async => ClosureAccepted(closureId: closureId, dueAt: _expiry);

  @override
  Future<ClosureStatus> closureStatus({
    required String closureId,
    required String statusSecret,
  }) async => ClosureStatus(state: ClosureState.pending, dueAt: _expiry);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness() {
    sessions = AuthSessionController(
      api: api,
      store: store,
      directory: directory,
    );
    flows = AuthFlows(
      api: api,
      store: store,
      acceptRegistrationSession: sessions.acceptSession,
      clearCommunityAccess: sessions.clearCommunityAccess,
    );
  }
  final api = _Api();
  final vault = _Vault();
  late final store = AuthStore(vault);
  final directory = ChannelDirectoryController(repository: _Channels());
  late final AuthSessionController sessions;
  late final AuthFlows flows;

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    bool dark = false,
  }) async {
    const qaFont = String.fromEnvironment('AUTH_UI_QA_FONT');
    if (qaFont.isNotEmpty) {
      await tester.runAsync(() async {
        final bytes = await File(qaFont).readAsBytes();
        await (FontLoader(
          'AuthQaChinese',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
    }
    await sessions.start();
    await flows.restorePending();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('qa-auth-surface'),
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: qaFont.isEmpty ? null : 'AuthQaChinese',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF76AFC8),
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            useMaterial3: true,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: AuthScreen(sessions: sessions, flows: flows),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    flows.dispose();
    sessions.dispose();
    directory.dispose();
    store.dispose();
  }
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('AUTH_UI_QA_DIR');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qa-auth-surface')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _seedEligibility(_Harness h) async {
  final key = await AuthCrypto.newBootstrapKey();
  final ticket = Uint8List(156);
  ticket.setRange(0, 20, [...ascii.encode('HNUHOLE/REGISTER/V2'), 0]);
  ByteData.sublistView(ticket).setUint32(20, 1);
  ticket.setRange(28, 60, AuthCrypto.decode(key.slotId, bytes: 32));
  ticket.setRange(60, 92, AuthCrypto.decode(key.publicKey, bytes: 32));
  await h.store.update(
    (state) => state.copyWith(
      cInstallationId: AuthCrypto.randomEncoded(16),
      vInstallationId: AuthCrypto.randomEncoded(16),
      registration: {
        'v': 1,
        'seed': key.seed,
        'publicKey': key.publicKey,
        'slotId': key.slotId,
        'ticket': AuthCrypto.encode(ticket),
      },
    ),
  );
}

void main() {
  testWidgets('restoring a covered auth route cannot pop the management route above it', (tester) async {
    final h = _Harness();
    await h.sessions.start();
    final navigator = GlobalKey<NavigatorState>();
    var callbacks = 0;
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator,
      home: AuthScreen(sessions: h.sessions, flows: h.flows,
        onAuthenticated: () { callbacks++; navigator.currentState!.pop(); })));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) =>
      const Scaffold(body: Text('management remains open')))));
    await tester.pumpAndSettle();
    await h.sessions.acceptSession(AuthSession(accountId: _account,
      sessionToken: h.api.token, expiresAt: _expiry));
    await tester.pumpAndSettle();
    h.sessions.sessionUnavailable(h.api.token);
    await tester.pumpAndSettle();
    await h.sessions.retry();
    await tester.pumpAndSettle();
    expect(h.sessions.isAuthenticated, isTrue);
    expect(find.text('management remains open'), findsOneWidget);
    expect(callbacks, 0);
    await h.finish(tester);
  });
  testWidgets('existing account uses password login without V', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    expect(find.byKey(const ValueKey('registration-email')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'private_name',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'independent password',
    );
    await _tap(tester, '登录并进入');
    expect(h.api.logins, 1);
    expect(h.api.otpRequests, 0);
    expect(h.sessions.isAuthenticated, isTrue);
    expect(h.directory.status, ChannelDirectoryStatus.ready);
    await h.finish(tester);
  });

  testWidgets(
    'new registration has OTP field before sending and does not require it to request',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await _tap(tester, '新注册');
      expect(find.byKey(const ValueKey('registration-otp')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'exact@hainanu.edu.cn',
      );
      await _tap(tester, '获取验证码');
      expect(h.api.otpRequests, 1);
      expect(h.api.logins, 0);
      expect(h.flows.status, AuthFlowStatus.otpRequested);
      await h.finish(tester);
    },
  );

  testWidgets(
    'registration hides original code before re-entry and does not persist raw code',
    (tester) async {
      final h = _Harness();
      await _seedEligibility(h);
      await h.mount(tester);
      await _tap(tester, '新注册');
      await tester.enterText(
        find.byKey(const ValueKey('registration-username')),
        'new_private',
      );
      await tester.enterText(
        find.byKey(const ValueKey('registration-password')),
        'an independent password',
      );
      await _tap(tester, '生成并保存恢复码');
      expect(find.text(_savedCode), findsOneWidget);
      expect(find.byKey(const ValueKey('recovery-confirmation')), findsNothing);
      expect(h.vault.value, isNot(contains(_savedCode)));
      await _tap(tester, '我已保存，隐藏原码并确认');
      expect(find.text(_savedCode), findsNothing);
      expect(h.flows.recoveryCode, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('recovery-confirmation')),
        _savedCode,
      );
      await _tap(tester, '确认恢复码并创建账号');
      expect(h.api.registrations, 1);
      expect(h.api.submittedConfirmation, _savedCode);
      expect(h.sessions.isAuthenticated, isTrue);
      expect(h.vault.value, isNot(contains(_savedCode)));
      await h.finish(tester);
    },
  );

  testWidgets(
    'reset completes without login and explains closure preservation',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await _tap(tester, '恢复账号');
      await tester.enterText(
        find.byKey(const ValueKey('recovery-code')),
        _savedCode,
      );
      await _tap(tester, '验证恢复码');
      expect(find.text(_newCode), findsOneWidget);
      await _tap(tester, '我已保存，隐藏原码并确认');
      expect(find.text(_newCode), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('reset-new-password')),
        'a new independent password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recovery-confirmation')),
        _newCode,
      );
      await _tap(tester, '设置新密码并激活新恢复码');
      expect(h.api.resets, 1);
      expect(h.api.logins, 0);
      expect(h.sessions.isAuthenticated, isFalse);
      expect(find.text('密码已重设'), findsOneWidget);
      expect(find.textContaining('不会自动登录，也不会撤销注销申请'), findsOneWidget);
      await h.finish(tester);
    },
  );

  testWidgets('pending closure offers recovery without implicit cancellation', (
    tester,
  ) async {
    final h = _Harness();
    final secret = AuthCrypto.randomEncoded(32);
    await h.store.update(
      (state) => state.copyWith(
        pendingClosure: {
          'v': 1,
          'closureId': AuthCrypto.randomEncoded(32),
          'statusSecret': secret,
          'statusDigest': AuthCrypto.closureStatusDigest(secret),
          'state': 'PENDING',
          'dueAt': _expiry.toIso8601String(),
        },
      ),
    );
    await h.mount(tester);
    expect(find.text('注销缓冲期'), findsOneWidget);
    await _tap(tester, '重设密码，继续保留注销');
    expect(find.byKey(const ValueKey('recovery-code')), findsOneWidget);
    expect(h.api.logins, 0);
    expect((await h.store.read()).pendingClosure, isNotNull);
    await h.finish(tester);
  });

  testWidgets('closure cancellation requires an explicit password login', (
    tester,
  ) async {
    final h = _Harness();
    final secret = AuthCrypto.randomEncoded(32);
    await h.store.update(
      (state) => state.copyWith(
        pendingClosure: {
          'v': 1,
          'closureId': AuthCrypto.randomEncoded(32),
          'statusSecret': secret,
          'statusDigest': AuthCrypto.closureStatusDigest(secret),
          'state': 'PENDING',
          'dueAt': _expiry.toIso8601String(),
        },
      ),
    );
    await h.mount(tester);
    expect(h.api.logins, 0);
    await _tap(tester, '登录并撤销注销');
    expect(h.api.logins, 0);
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'private_name',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'independent password',
    );
    await _tap(tester, '登录并进入');
    expect(h.api.logins, 1);
    expect(h.sessions.isAuthenticated, isTrue);
    expect(find.text('账号已登录'), findsOneWidget);
    await h.finish(tester);
  });

  testWidgets('failed server revocation shows durable local logout pending', (
    tester,
  ) async {
    final h = _Harness();
    await h.store.update(
      (state) => state.copyWith(
        session: SessionRecord(
          token: h.api.token,
          accountId: _account,
          expiresAt: _expiry,
        ),
      ),
    );
    await h.mount(tester);
    h.api.rejectRevocation = true;
    await _tap(tester, '退出本机');
    expect(h.sessions.isAuthenticated, isFalse);
    expect((await h.store.read()).session, isNull);
    expect(find.textContaining('本机已退出，服务端撤销仍待完成'), findsOneWidget);
    expect((await h.store.read()).logouts.single.revocationSecret, isNotNull);
    await h.finish(tester);
  });

  testWidgets(
    'small viewport and larger text retain labeled controls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.mount(tester, scale: 1.6);
      await _tap(tester, '新注册');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('获取验证码'));
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 1200),
      );
      await tester.pumpAndSettle();
      await _snapshot(tester, 'auth-registration-375px-160pct');
      await h.finish(tester);
    },
  );

  testWidgets('dark recovery code is readable and keeps native controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    await h.mount(tester, dark: true);
    await _tap(tester, '恢复账号');
    await tester.enterText(
      find.byKey(const ValueKey('recovery-code')),
      _savedCode,
    );
    await _tap(tester, '验证恢复码');
    expect(
      find.byKey(const ValueKey('displayed-recovery-code')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final colors = Theme.of(tester.element(find.byType(AuthScreen)))
        .colorScheme;
    double contrast(Color first, Color second) {
      final a = first.computeLuminance(), b = second.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    for (final pair in [
      (colors.primary, colors.onPrimary),
      (colors.surface, colors.onSurface),
      (colors.secondaryContainer, colors.onSecondaryContainer),
    ]) {
      expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
    await _snapshot(tester, 'auth-recovery-code-dark-375px');
    await h.finish(tester);
  });
}
