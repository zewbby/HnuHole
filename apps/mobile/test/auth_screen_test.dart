import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/auth/welcome_at_mark.dart';

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
  Future<ChannelDirectoryResult> loadChannels({
    required String sessionToken,
  }) async => ChannelDirectoryResult(
    expiresAt: _expiry,
    channels: [
      for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
        Channel(
          id: 'channel-$i',
          code: ChannelDirectory.requiredCodes[i],
          name: ChannelDirectory.requiredCodes[i],
          initiallyVisible: i < 5,
          displayOrder: i,
        ),
    ],
  );
}

class _Api implements AuthApi {
  int logins = 0;
  int otpRequests = 0;
  int otpRetrySeconds = 60;
  int registrations = 0;
  int resets = 0;
  int revocations = 0;
  ClosureState closureState = ClosureState.pending;
  bool rejectRevocation = false;
  bool rejectLogin = false;
  AuthFailure? loginFailure;
  AuthFailure? currentFailure;
  int currentReads = 0;
  Completer<void>? loginPending;
  String? submittedUsername;
  String? submittedEmail;
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
    await loginPending?.future;
    if (loginFailure != null) throw loginFailure!;
    if (rejectLogin) {
      throw const AuthFailure(kind: AuthFailureKind.unauthorized);
    }
    return AuthSession(
      accountId: _account,
      sessionToken: token,
      expiresAt: _expiry,
    );
  }

  @override
  Future<CurrentSession> currentSession(String token) async {
    currentReads++;
    if (currentFailure case final failure?) throw failure;
    return CurrentSession(
      accountId: _account,
      username: 'private_name',
      expiresAt: _expiry,
    );
  }

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
    submittedEmail = email;
    return OtpRequestAccepted(
      flowId: AuthCrypto.randomEncoded(32),
      retryAfterSeconds: otpRetrySeconds,
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
  }) async => ClosureStatus(
    state: closureState,
    dueAt: closureState == ClosureState.pending ? _expiry : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmailApi extends _Api implements EmailLoginApi {
  Completer<void>? sendPending;
  AuthFailure? sendFailure;
  final sendKeys = <String>[];
  final sentEmails = <String>[];

  @override
  Future<OtpRequestAccepted> requestEmailLoginOtp({
    required String email,
    required String installationId,
    required String idempotencyKey,
  }) async {
    otpRequests++;
    sendKeys.add(idempotencyKey);
    sentEmails.add(email);
    await sendPending?.future;
    if (sendFailure != null) throw sendFailure!;
    return OtpRequestAccepted(
      flowId: AuthCrypto.randomEncoded(32),
      retryAfterSeconds: 60,
    );
  }
}

class _Harness {
  _Harness({_Api? api}) : api = api ?? _Api() {
    sessions = AuthSessionController(
      api: this.api,
      store: store,
      directory: directory,
    );
    flows = AuthFlows(
      api: this.api,
      store: store,
      acceptRegistrationSession: sessions.acceptSession,
      clearCommunityAccess: sessions.clearCommunityAccess,
    );
  }
  final _Api api;
  final vault = _Vault();
  late final store = AuthStore(vault);
  final directory = ChannelDirectoryController(repository: _Channels());
  late final AuthSessionController sessions;
  late final AuthFlows flows;

  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    bool dark = false,
    AuthPresentationController? presentation,
    Widget? home,
    VoidCallback? onAuthenticated,
    VoidCallback? onManageSecurity,
  }) async {
    const qaFont = String.fromEnvironment('AUTH_UI_QA_FONT');
    if (qaFont.isNotEmpty) {
      await tester.runAsync(() async {
        final bytes = await File(qaFont).readAsBytes();
        await (FontLoader(
          'AuthQaChinese',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        for (final (family, filename) in [
          (
            'MaterialIcons',
            const String.fromEnvironment('AUTH_UI_QA_ICON_FONT'),
          ),
          ('serif', const String.fromEnvironment('AUTH_UI_QA_SERIF_FONT')),
          ('monospace', const String.fromEnvironment('AUTH_UI_QA_MONO_FONT')),
        ]) {
          if (filename.isEmpty) continue;
          final font = await File(filename).readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        }
      });
    }
    await sessions.start();
    await flows.restorePending();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('qa-auth-surface'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
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
            child: presentation == null
                ? child!
                : AuthPresentationScope(
                    controller: presentation,
                    child: child!,
                  ),
          ),
          home:
              home ??
              AuthScreen(
                sessions: sessions,
                flows: flows,
                onAuthenticated: onAuthenticated,
                onManageSecurity: onManageSecurity,
              ),
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
  final finder = text == '返回登录'
      ? find.byTooltip('返回登录')
      : text == '生成并保存恢复码' || text == '确认验证码'
      ? find.byKey(const ValueKey('registration-next'))
      : text == '登录并进入'
      ? find.byKey(const ValueKey('login-submit'))
      : find.text(text);
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
  testWidgets(
    'known OTP cooldown permits correcting email and confirming only its current request',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      h.api.otpRetrySeconds = 0;
      await h.mount(tester);
      await _tap(tester, '创建账号');
      await _snapshot(tester, 'registration-email');
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'mistyped',
      );
      await _tap(tester, '发送验证码');
      expect(h.flows.status, AuthFlowStatus.otpRequested);
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'corrected',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('registration-next')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, '发送验证码');
      expect(h.api.otpRequests, 2);
      expect(h.api.submittedEmail, 'corrected@hainanu.edu.cn');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('registration-email')),
            )
            .controller!
            .text,
        'corrected',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('registration-next')),
            )
            .onPressed,
        isNotNull,
      );
      await _tap(tester, '返回登录');
      await _tap(tester, '创建账号');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('registration-email')),
            )
            .controller!
            .text,
        'corrected',
      );
      await h.finish(tester);
    },
  );

  for (final (width, dark, scale) in [
    (375.0, false, 1.0),
    (320.0, true, 1.6),
  ]) {
    testWidgets(
      'registration security, copy and explicit finish at $width / $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = _Harness();
        await _seedEligibility(h);
        var completed = 0, securityOpened = 0;
        final copies = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copies.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await h.mount(
          tester,
          dark: dark,
          scale: scale,
          onAuthenticated: () => completed++,
          onManageSecurity: () => securityOpened++,
        );
        await _tap(tester, '创建账号');
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .minHeight,
          10,
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(2 / 3, .001),
        );
        await tester.enterText(
          find.byKey(const ValueKey('registration-username')),
          'campus_echo',
        );
        await tester.enterText(
          find.byKey(const ValueKey('registration-password')),
          'IndependentPassword123',
        );
        tester.testTextInput.hide();
        await _snapshot(tester, 'registration-account-${width.toInt()}');
        await _tap(tester, '生成并保存恢复码');
        expect(tester.takeException(), isNull);
        expect(copies, isEmpty);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          1,
        );
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('registration-passkey')),
              )
              .onPressed,
          isNull,
        );
        final box = tester.getRect(
          find
              .ancestor(
                of: find.byKey(const ValueKey('displayed-recovery-code')),
                matching: find.byType(Stack),
              )
              .first,
        );
        final copy = find.byKey(
          const ValueKey('copy-registration-recovery-code'),
        );
        expect(box.contains(tester.getCenter(copy)), isTrue);
        expect(tester.getSize(copy).width, greaterThanOrEqualTo(48));
        await _snapshot(tester, 'registration-recovery-${width.toInt()}');
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(copies, [_savedCode]);
        expect(find.textContaining('恢复码已复制'), findsOneWidget);
        expect(h.vault.value, isNot(contains(_savedCode)));
        await _tap(tester, '我已保存，继续确认');
        expect(
          find.byKey(const ValueKey('displayed-recovery-code')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('copy-registration-recovery-code')),
          findsNothing,
        );
        expect(h.flows.recoveryCode, isNull);
        await _tap(tester, '确认恢复码并创建账号');
        expect(h.api.registrations, 0);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirmation')),
          _savedCode,
        );
        await _tap(tester, '确认恢复码并创建账号');
        expect(h.sessions.isAuthenticated, isTrue);
        expect(
          completed,
          0,
          reason: 'Registration keeps the optional security stage open.',
        );
        expect(find.text('暂不设置'), findsNothing);
        expect(find.text('恢复码已保存并确认'), findsOneWidget);
        expect(h.vault.value, isNot(contains(_savedCode)));
        final setup = find.byKey(const ValueKey('registration-passkey'));
        await tester.ensureVisible(setup);
        await tester.tap(setup);
        await tester.pumpAndSettle();
        expect(securityOpened, 1);
        expect(completed, 0);
        await _snapshot(tester, 'registration-complete-${width.toInt()}');
        final finish = find.byKey(const ValueKey('registration-finish'));
        await tester.ensureVisible(finish);
        await tester.tap(finish);
        await tester.pumpAndSettle();
        expect(completed, 1);
        expect(tester.takeException(), isNull);
        await h.finish(tester);
      },
    );
  }

  testWidgets(
    'copy failure gives feedback and returning to account hides the code',
    (tester) async {
      final h = _Harness();
      await _seedEligibility(h);
      await h.mount(tester);
      await _tap(tester, '创建账号');
      await tester.enterText(
        find.byKey(const ValueKey('registration-username')),
        'campus_echo',
      );
      await tester.enterText(
        find.byKey(const ValueKey('registration-password')),
        'IndependentPassword123',
      );
      await _tap(tester, '生成并保存恢复码');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'copy-denied');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('copy-registration-recovery-code')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('复制未成功'), findsOneWidget);
      await tester.tap(find.byTooltip('返回登录'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('registration-username')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('displayed-recovery-code')),
        findsNothing,
      );
      expect(h.flows.recoveryCode, isNull);
      expect(h.api.registrations, 0);
      await h.finish(tester);
    },
  );

  testWidgets(
    'login method swaps in place and pending email cannot invoke C or V',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      final presentation = AuthPresentationController();
      await h.mount(tester, presentation: presentation);
      final beforeUser = tester.getRect(
        find.byKey(const ValueKey('login-username')),
      );
      final beforePassword = tester.getRect(
        find.byKey(const ValueKey('login-password')),
      );
      final beforeArrow = tester.getRect(
        find.byKey(const ValueKey('login-submit')),
      );
      expect(find.text('私有用户名'), findsNothing);
      expect(find.textContaining('使用你的私有用户名和密码'), findsNothing);
      expect(find.text('新注册'), findsNothing);
      await _snapshot(tester, 'auth-login-final-375px');
      await tester.enterText(
        find.byKey(const ValueKey('login-username')),
        'private_name',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'private password here',
      );
      await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('欢迎回来'), findsOneWidget);
      expect(find.text('您的校园邮箱'), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('email-login-address'))),
        beforeUser,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('email-login-code'))),
        beforePassword,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('login-submit'))),
        beforeArrow,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('email-login-address')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('email-login-request')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
            .onPressed,
        isNull,
      );
      expect(find.text('待接入'), findsOneWidget);
      expect(h.api.logins, 0);
      expect(h.api.otpRequests, 0);
      await _snapshot(tester, 'auth-email-pending-final-375px');
      await tester.tap(find.byKey(const ValueKey('auth-theme-toggle')));
      await tester.pumpAndSettle();
      final footer = find.text('第一次来？');
      final footerTheme = Theme.of(tester.element(footer));
      expect(footerTheme.brightness, Brightness.dark);
      expect(
        tester.widget<Text>(footer).style!.color,
        footerTheme.colorScheme.onSurfaceVariant,
      );
      await _snapshot(tester, 'auth-email-pending-dark-final-375px');
      await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('login-password')),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-username')))
            .controller!
            .text,
        'private_name',
      );
      expect(tester.takeException(), isNull);
      await h.finish(tester);
      presentation.dispose();
    },
  );

  testWidgets(
    'campus registration accepts prefix and exact pasted suffix without rewriting another domain',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await _tap(tester, '创建账号');
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'Exact@other.example',
      );
      await _tap(tester, '发送验证码');
      expect(h.api.otpRequests, 0);
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'Exact@hainanu.edu.cn',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('registration-email')),
            )
            .controller!
            .text,
        'Exact',
      );
      await _tap(tester, '发送验证码');
      expect(h.api.otpRequests, 1);
      expect(h.api.submittedEmail, 'Exact@hainanu.edu.cn');
      await h.finish(tester);
    },
  );

  testWidgets('welcome switches theme and language without authenticating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    final presentation = AuthPresentationController();
    final controlsVisible = ValueNotifier(false);
    addTearDown(controlsVisible.dispose);
    var started = false;
    await h.mount(
      tester,
      presentation: presentation,
      home: ValueListenableBuilder<bool>(
        valueListenable: controlsVisible,
        builder: (context, visible, _) => AuthWelcomeScreen(
          onStarted: () => started = true,
          showControls: visible,
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/branding/welcome-shush-mark.png'),
        tester.element(find.byKey(const ValueKey('auth-welcome'))),
      );
    });
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeAtMark), findsOneWidget);
    expect(find.bySemanticsLabel('开始使用'), findsNothing);
    expect(find.bySemanticsLabel('Continue in English'), findsNothing);
    await _snapshot(tester, 'auth-welcome-loading-375px');
    controlsVisible.value = true;
    await tester.pumpAndSettle();
    expect(find.text('开始使用'), findsOneWidget);
    expect(find.bySemanticsLabel('@SpeechFUL'), findsOneWidget);
    await _snapshot(tester, 'auth-welcome-final-375px');
    await tester.tap(find.byKey(const ValueKey('auth-theme-toggle')));
    await tester.pumpAndSettle();
    expect(presentation.themeMode, ThemeMode.dark);
    await _snapshot(tester, 'auth-welcome-wordmark-dark-375px');
    await tester.tap(find.byKey(const ValueKey('auth-language-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-start')));
    expect(started, isTrue);
    expect(h.api.logins, 0);
    expect(h.api.otpRequests, 0);
    expect(tester.takeException(), isNull);
    await h.finish(tester);
    presentation.dispose();
  });

  testWidgets('English choice applies to login and registration controls', (
    tester,
  ) async {
    final h = _Harness();
    final presentation = AuthPresentationController()..english = true;
    await h.mount(tester, presentation: presentation);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    await _tap(tester, 'Create an account');
    expect(find.text('Your campus email'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    expect(find.byTooltip('Back to sign in'), findsOneWidget);
    await h.finish(tester);
    presentation.dispose();
  });

  testWidgets(
    'persisted invalid OTP flow offers explicit continuation without an error or resend',
    (tester) async {
      final h = _Harness();
      await h.flows.requestOtp('Exact@hainanu.edu.cn');
      final original = (await h.store.read()).registration!;
      await h.store.update(
        (state) => state.copyWith(
          registration: {
            ...original,
            'confirmation': {
              'key': AuthCrypto.randomEncoded(32),
              'flowId': original['request']['flowId'],
              'expired': true,
            },
          },
        ),
      );
      await h.mount(tester);
      await _tap(tester, '创建账号');
      expect(h.flows.error, isNull);
      expect(find.text('结束过期操作，重新收码'), findsOneWidget);
      expect(find.text('使用原验证码继续确认'), findsNothing);
      expect(h.api.otpRequests, 1);
      await _tap(tester, '结束过期操作，重新收码');
      final resumed = (await h.store.read()).registration!;
      for (final field in ['seed', 'publicKey', 'slotId']) {
        expect(resumed[field], original[field]);
      }
      expect(resumed['request'], isNull);
      expect(resumed['confirmation'], isNull);
      expect(h.api.otpRequests, 1);
      expect(h.api.registrations, 0);
      expect(h.sessions.isAuthenticated, isFalse);
      await h.finish(tester);
    },
  );
  testWidgets(
    'restoring a covered auth route cannot pop the management route above it',
    (tester) async {
      final h = _Harness();
      await h.sessions.start();
      final navigator = GlobalKey<NavigatorState>();
      var callbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AuthScreen(
            sessions: h.sessions,
            flows: h.flows,
            onAuthenticated: () {
              callbacks++;
              navigator.currentState!.pop();
            },
          ),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('management remains open')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await h.sessions.acceptSession(
        AuthSession(
          accountId: _account,
          sessionToken: h.api.token,
          expiresAt: _expiry,
        ),
      );
      await tester.pumpAndSettle();
      h.sessions.sessionUnavailable(h.api.token);
      await tester.pumpAndSettle();
      await h.sessions.retry();
      await tester.pumpAndSettle();
      expect(h.sessions.isAuthenticated, isTrue);
      expect(find.text('management remains open'), findsOneWidget);
      expect(callbacks, 0);
      await h.finish(tester);
    },
  );
  testWidgets(
    'unavailable auth retry can fail repeatedly without losing its dialog',
    (tester) async {
      final h = _Harness();
      await h.store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            accountId: _account,
            token: h.api.token,
            expiresAt: _expiry,
          ),
        ),
      );
      h.api.currentFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      await h.mount(tester);
      for (var i = 0; i < 2; i++) {
        expect(find.text('暂时无法进入'), findsOneWidget);
        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).content,
          isNull,
        );
        await _tap(tester, '重试');
        expect(find.text('暂时无法进入'), findsOneWidget);
      }
      expect(h.api.currentReads, 3);
      await _tap(tester, '取消');
      expect(find.byType(AlertDialog), findsNothing);
      expect(h.store.current!.session!.token, h.api.token);
      await h.finish(tester);
    },
  );
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

  testWidgets('password errors use a dismissible dialog and retain inputs', (
    tester,
  ) async {
    final h = _Harness();
    h.api.rejectLogin = true;
    await h.mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'private_name',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'incorrect password',
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt == 1) {
        h.api.loginFailure = const AuthFailure(
          kind: AuthFailureKind.rejected,
          code: 'CLIENT_INPUT_INVALID',
        );
      }
      h.api.loginPending = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
            .onPressed,
        isNull,
      );
      h.api.loginPending!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final scaling = find.byKey(const ValueKey('auth-error-dialog-scale'));
      final scale = tester.widget<ScaleTransition>(scaling).scale.value;
      expect(scale, greaterThan(0.88));
      expect(scale, lessThan(1));
      expect(
        find.ancestor(
          of: find.byType(AlertDialog),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ScaleTransition>(scaling).scale.value, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
      expect(find.text('取消'), findsNothing);
      expect(find.text('用户名或密码不正确。'), findsOneWidget);
      await _snapshot(tester, 'auth-password-error-dialog');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('用户名或密码不正确。'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-username')))
            .controller!
            .text,
        'private_name',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        'incorrect password',
      );
    }
    expect(h.api.logins, 2);
    await h.finish(tester);
  });

  testWidgets(
    'accepted email code has neutral notice between code and toggle',
    (tester) async {
      final api = _EmailApi()..sendPending = Completer<void>();
      final h = _Harness(api: api);
      await h.mount(tester);
      await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
      await tester.pumpAndSettle();
      final notice = find.byKey(const ValueKey('email-login-sent-notice'));
      expect(notice, findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('email-login-address')),
        'owned',
      );
      await tester.tap(find.byKey(const ValueKey('email-login-request')));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(notice, findsNothing);
      api.sendPending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('若邮箱存在，将会收到验证码。'), findsOneWidget);
      expect(
        tester.getTopLeft(notice).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('email-login-code')))
              .dy,
        ),
      );
      expect(
        tester.getBottomLeft(notice).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('login-method-toggle')))
              .dy,
        ),
      );
      final text = tester.widget<Text>(notice);
      final colors = Theme.of(tester.element(notice)).colorScheme;
      expect(text.style!.color, colors.onSurfaceVariant);
      await _snapshot(tester, 'auth-email-sent-notice');
      await h.finish(tester);
    },
  );

  testWidgets(
    'uncertain email request uses one friendly dialog and reuses request',
    (tester) async {
      final api = _EmailApi()
        ..sendFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      final h = _Harness(api: api);
      await h.mount(tester);
      await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email-login-address')),
        'owned',
      );
      final fieldTop = tester
          .getTopLeft(find.byKey(const ValueKey('email-login-address')))
          .dy;
      await tester.tap(find.byKey(const ValueKey('email-login-request')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('结果未知，请保留原请求并核对。'), findsNothing);
      expect(find.text('验证码发送或验证结果暂时无法确认，请检查网络后重试。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('email-login-sent-notice')),
        findsNothing,
      );
      final original = Map<String, dynamic>.from(h.flows.emailLogin!);
      expect(original['sendState'], 'UNKNOWN');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await h.sessions.retryPendingLogout();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('email-login-address'))).dy,
        fieldTop,
      );
      await h.store.update(
        (state) => state.copyWith(
          emailLogin: {
            ...original,
            'waitUntil': DateTime.now()
                .subtract(const Duration(seconds: 1))
                .toUtc()
                .toIso8601String(),
          },
        ),
      );
      api.sendFailure = null;
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('email-login-request')));
      await tester.pumpAndSettle();
      expect(api.sendKeys, [original['sendKey'], original['sendKey']]);
      expect(
        find.byKey(const ValueKey('email-login-sent-notice')),
        findsOneWidget,
      );
      await h.finish(tester);
    },
  );

  for (final uncertain in [false, true]) {
    testWidgets(
      'saved email remains editable during cooldown, uncertain=$uncertain',
      (tester) async {
        final api = _EmailApi();
        if (uncertain) {
          api.sendFailure = const AuthFailure(kind: AuthFailureKind.timeout);
        }
        final h = _Harness(api: api);
        await h.flows.requestEmailLogin('old@hainanu.edu.cn');
        await h.mount(tester);
        final address = find.byKey(const ValueKey('email-login-address'));
        final code = find.byKey(const ValueKey('email-login-code'));
        expect(tester.widget<TextFormField>(address).enabled, isTrue);
        expect(tester.widget<TextFormField>(address).controller!.text, 'old');
        await tester.enterText(code, '123456');
        await tester.enterText(address, 'correct');
        await tester.pump();
        expect(tester.widget<TextFormField>(code).controller!.text, isEmpty);
        expect(
          find.byKey(const ValueKey('email-login-sent-notice')),
          findsNothing,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('login-method-toggle')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextFormField>(address).controller!.text,
          'correct',
        );
        final original = Map<String, dynamic>.from(h.flows.emailLogin!);
        await h.store.update(
          (state) => state.copyWith(
            emailLogin: {
              ...original,
              'waitUntil': DateTime.now()
                  .subtract(const Duration(seconds: 1))
                  .toUtc()
                  .toIso8601String(),
            },
          ),
        );
        api.sendFailure = null;
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const ValueKey('email-login-request')));
        await tester.pumpAndSettle();
        expect(api.sentEmails, [
          'old@hainanu.edu.cn',
          'correct@hainanu.edu.cn',
        ]);
        expect(api.sendKeys.last, isNot(api.sendKeys.first));
        expect(h.flows.emailLogin!['email'], 'correct@hainanu.edu.cn');
        expect(
          find.byKey(const ValueKey('email-login-sent-notice')),
          findsOneWidget,
        );
        expect(tester.widget<TextFormField>(address).enabled, isTrue);
        await h.finish(tester);
      },
    );
  }

  testWidgets(
    'editing an unresolved sign-in offers continuation of its original email',
    (tester) async {
      final h = _Harness(api: _EmailApi());
      await h.flows.requestEmailLogin('original@hainanu.edu.cn');
      await h.store.update(
        (state) => state.copyWith(
          emailLogin: {
            ...state.emailLogin!,
            'confirmKey': AuthCrypto.randomEncoded(32),
            'otp': '123456',
            'proof': AuthCrypto.encode(List<int>.filled(227, 5)),
          },
        ),
      );
      await h.mount(tester);
      final address = find.byKey(const ValueKey('email-login-address'));
      await tester.enterText(address, 'correct');
      await tester.pump();
      expect(find.text('继续上次登录'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('继续上次登录'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(address).controller!.text,
        'original',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
            .onPressed,
        isNotNull,
      );
      expect(h.flows.emailLogin!['proof'], isNotNull);
      await h.finish(tester);
    },
  );

  testWidgets(
    'new registration has OTP field before sending and does not require it to request',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await _tap(tester, '创建账号');
      expect(find.byKey(const ValueKey('registration-otp')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('registration-email')),
        'exact@hainanu.edu.cn',
      );
      await _tap(tester, '发送验证码');
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
      await _tap(tester, '创建账号');
      await tester.enterText(
        find.byKey(const ValueKey('registration-username')),
        'new_private',
      );
      await tester.enterText(
        find.byKey(const ValueKey('registration-password')),
        'IndependentPassword123',
      );
      await _tap(tester, '生成并保存恢复码');
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('displayed-recovery-code')))
            .data!
            .replaceAll('\n', ''),
        _savedCode,
      );
      expect(find.byKey(const ValueKey('recovery-confirmation')), findsNothing);
      expect(h.vault.value, isNot(contains(_savedCode)));
      await _tap(tester, '我已保存，继续确认');
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
      await _tap(tester, '找回账号');
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
        'NewIndependentPassword123',
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

  testWidgets(
    'only confirmed cancelled closure can return to normal account actions',
    (tester) async {
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
      expect(find.text('结束已取消的注销操作'), findsNothing);
      expect((await h.store.read()).pendingClosure, isNotNull);
      h.api.closureState = ClosureState.cancelled;
      await _tap(tester, '核对注销状态');
      expect((await h.store.read()).pendingClosure!['state'], 'CANCELLED');
      await _tap(tester, '结束已取消的注销操作');
      expect((await h.store.read()).pendingClosure, isNull);
      expect(h.api.logins, 0);
      expect(h.sessions.isAuthenticated, isFalse);
      expect(find.text('创建账号'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-username')), findsOneWidget);
      await h.finish(tester);
    },
  );

  testWidgets(
    'failed server revocation retries without exposing internal status',
    (tester) async {
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
      expect(find.textContaining('本机已退出，服务端撤销仍待完成'), findsNothing);
      expect(find.text('本地已退出，服务器撤销待确认。'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect((await h.store.read()).logouts.single.revocationSecret, isNotNull);
      h.api.rejectRevocation = false;
      await h.sessions.retryPendingLogout();
      await tester.pumpAndSettle();
      expect((await h.store.read()).logouts, isEmpty);
      expect(h.sessions.isAuthenticated, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      await h.finish(tester);
    },
  );

  testWidgets(
    'small viewport and larger text retain labeled controls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = _Harness();
      await h.mount(tester, scale: 1.6);
      await _tap(tester, '创建账号');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('发送验证码'));
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
    await _tap(tester, '找回账号');
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
    final colors = Theme.of(
      tester.element(find.byKey(const ValueKey('displayed-recovery-code'))),
    ).colorScheme;
    double contrast(Color first, Color second) {
      final a = first.computeLuminance(), b = second.computeLuminance();
      return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
    }

    for (final pair in [
      (colors.primary, colors.onPrimary),
      (colors.primary, colors.surface),
      (colors.surface, colors.onSurface),
      (colors.secondaryContainer, colors.onSecondaryContainer),
    ]) {
      expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
    await _snapshot(tester, 'auth-recovery-code-dark-375px');
    await h.finish(tester);
  });
}
