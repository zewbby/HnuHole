import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

String _bytes(int n) => AuthCrypto.encode(List<int>.filled(32, n));
final _expiry = DateTime.utc(2026, 11, 1);
const _account = '00000000-0000-4000-8000-000000000001';
const _code = 'AAAAAAAAAAAAAAAAAAAAAAAAAA';

class _Vault implements AuthVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

class _Api implements AuthApi, CredentialManagementApi {
  int commits = 0;
  bool lost = false;
  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: _account,
    username: 'private_name',
    expiresAt: _expiry,
  );
  @override
  Future<void> revokeSession(String secret) async {}
  @override
  Future<DeviceDirectory> devices(String token) async => DeviceDirectory(
    currentSignedInAt: DateTime.utc(2026, 10, 2),
    sessionExpiresAt: _expiry,
    lastReplacedSignedInAt: DateTime.utc(2026, 10, 1),
    lastReplacedAt: DateTime.utc(2026, 10, 2),
  );
  @override
  Future<RecoveryCredentialSummary> recoveryCredentials(String token) async =>
      RecoveryCredentialSummary(passkeys: const [], sessionExpiresAt: _expiry);
  @override
  Future<RecoveryCodeRotation> createRecoveryCodeRotation({
    required String sessionToken,
    required String password,
  }) async => RecoveryCodeRotation(
    rotationIntentId: _bytes(2),
    expiresAt: _expiry,
    newRecoveryCode: _code,
    sessionExpiresAt: _expiry,
  );
  @override
  Future<DateTime> confirmRecoveryCodeRotation({
    required String sessionToken,
    required String rotationIntentId,
    required String newRecoveryCodeConfirmation,
    required String idempotencyKey,
  }) async {
    commits++;
    if (lost) throw const AuthFailure(kind: AuthFailureKind.timeout);
    return _expiry;
  }

  @override
  Future<CredentialChangeOutcome> credentialChangeResult({
    required String sessionToken,
    required String changeId,
    required String idempotencyKey,
  }) async => CredentialChangeOutcome(
    state: CredentialChangeState.committed,
    sessionExpiresAt: _expiry,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

class _Passkey implements PasskeyClient {
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> options) async =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> get(Map<String, dynamic> options) async =>
      throw UnimplementedError();
}

void main() {
  late _Vault vault;
  late AuthStore store;
  late _Api api;
  late ChannelDirectoryController directory;
  late AuthSessionController sessions;
  late SecurityManagementController manager;
  setUp(() async {
    vault = _Vault();
    store = AuthStore(vault);
    api = _Api();
    directory = ChannelDirectoryController(repository: _Channels());
    sessions = AuthSessionController(
      api: api,
      store: store,
      directory: directory,
    );
    await store.update(
      (s) => s.copyWith(
        session: SessionRecord(
          token: _bytes(1),
          accountId: _account,
          expiresAt: _expiry,
        ),
      ),
    );
    await sessions.start();
    manager = SecurityManagementController(
      api: api,
      store: store,
      sessions: sessions,
      passkey: _Passkey(),
    );
  });
  tearDown(() {
    manager.dispose();
    sessions.dispose();
    directory.dispose();
    store.dispose();
  });
  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    await tester.runAsync(manager.load);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SecurityManagementScreen(controller: manager, sessions: sessions),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(
    WidgetTester tester,
    String text, {
    bool Function()? settled,
  }) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    // Button handlers start asynchronous crypto/storage work. Let those real
    // futures finish outside FakeAsync while still exercising the UI wiring.
    await tester.runAsync(() async {
      await tester.tap(target);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (manager.busy || (settled != null && !settled())) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Button action did not settle: $text');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();
  }

  Future<void> rotate(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('management-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('management-password')),
      'correct long current password',
    );
    await tap(tester, '轮换恢复码');
  }

  testWidgets(
    'shows current and replaced devices and password-required operations',
    (tester) async {
      await open(tester);
      expect(find.text('当前设备'), findsOneWidget);
      expect(find.text('最近被接替的设备'), findsOneWidget);
      await tap(tester, '轮换恢复码');
      expect(find.text('请输入当前密码'), findsOneWidget);
      expect(api.commits, 0);
    },
  );

  testWidgets(
    'once-only code is hidden before full confirmation and unknown outcome is queried',
    (tester) async {
      await open(tester);
      await rotate(tester);
      expect(
        find.byKey(const ValueKey('rotation-displayed-code')),
        findsOneWidget,
      );
      expect(vault.value, isNot(contains(_code)));
      await tap(tester, '我已保存，隐藏原码并确认');
      expect(
        find.byKey(const ValueKey('rotation-displayed-code')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('rotation-confirmation')),
        _code,
      );
      api.lost = true;
      await tap(tester, '确认并激活新恢复码');
      expect(manager.status, SecurityManagementStatus.pending);
      expect(vault.value, isNot(contains(_code)));
      await tap(tester, '核对原结果');
      expect(find.text('变更已确认提交。'), findsOneWidget);
      expect(api.commits, 1);
    },
  );

  testWidgets(
    'logout clears protected rows and keeps the existing logout protocol',
    (tester) async {
      await open(tester);
      await tap(
        tester,
        '退出本机',
        settled: () =>
            !sessions.isAuthenticated && store.current!.session == null,
      );
      expect(sessions.isAuthenticated, isFalse);
      expect(find.text('当前设备'), findsNothing);
      expect(manager.credentials, isNull);
      expect(store.current!.session, isNull);
    },
  );

  testWidgets(
    'small screen and enlarged text keep forms scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, scale: 2);
      await rotate(tester);
      await tap(tester, '我已保存，隐藏原码并确认');
      expect(
        find.byKey(const ValueKey('rotation-confirmation')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
