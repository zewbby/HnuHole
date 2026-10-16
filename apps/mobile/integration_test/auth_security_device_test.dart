import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_device_scenarios.dart';

const _account = '00000000-0000-4000-8000-000000000001';
String _bytes(int n, int value) => AuthCrypto.encode(List.filled(n, value));

// This owned API verifies that startup never tries to authorize a token with a
// durable logout marker. It does not simulate/prove PostgreSQL or C's Gate.
class _NoAuthorityApi implements AuthApi {
  int currentCalls = 0;
  @override
  Future<CurrentSession> currentSession(String token) async {
    currentCalls++;
    throw const AuthFailure(kind: AuthFailureKind.unauthorized, code: 'SESSION_INVALID');
  }
  @override
  Future<void> revokeSession(String secret) async =>
      throw const AuthFailure(kind: AuthFailureKind.timeout);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoChannels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) async =>
      throw StateError('No logged-out device may load a directory');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.isAndroid || Platform.isIOS;

  testWidgets('real platform AuthStore preserves original result without plaintext secrets', (tester) async {
    final namespace = 'native.security.test.${AuthCrypto.randomEncoded(16)}';
    final vault = FlutterAuthVault(namespace: namespace);
    final token = _bytes(32, 3);
    final first = AuthStore(vault, scope: namespace);
    addTearDown(first.dispose);
    await first.update((s) => s.copyWith(
      session: SessionRecord(token: token, accountId: _account,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30))),
      pendingCredentialChange: {'v': 1, 'kind': 'ROTATION',
        'intentId': _bytes(32, 4), 'key': _bytes(32, 5), 'accountId': _account,
        'originalTokenDigest': sessionTokenDigest(token), 'state': 'UNKNOWN'},
    ));
    final second = AuthStore(FlutterAuthVault(namespace: namespace), scope: namespace);
    addTearDown(second.dispose);
    final state = await second.read();
    expect(state.pendingCredentialChange?['key'], _bytes(32, 5));
    expect(state.pendingCredentialChange?['state'], 'UNKNOWN');
    final serialized = await vault.read();
    expect(serialized, isNot(contains('password')));
    expect(serialized, isNot(contains('newRecoveryCode')));
    expect(serialized, isNot(contains('attestation')));
    await second.update((_) => const AuthState());
  }, skip: !native);

  const phase = String.fromEnvironment('AUTH_DEVICE_PHASE');
  const namespace = String.fromEnvironment('AUTH_DEVICE_NAMESPACE');
  registerIdentityDeviceScenarios(phase, namespace, native);
  testWidgets('external process restart keeps logout fence and original credential result', (tester) async {
    expect(RegExp(r'^native\.security\.test\.[A-Za-z0-9_-]{1,80}$').hasMatch(namespace), isTrue,
      reason: 'Use the same unique test namespace for both runs');
    expect({'write', 'read'}, contains(phase));
    final vault = FlutterAuthVault(namespace: namespace);
    final processVault = FlutterAuthVault(namespace: '$namespace.pid');
    final store = AuthStore(vault, scope: namespace);
    addTearDown(store.dispose);
    final token = _bytes(32, 6);
    if (phase == 'write') {
      await store.update((_) => AuthState(
        session: SessionRecord(token: token, accountId: _account,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 30))),
        logouts: [LogoutTask(tokenDigest: sessionTokenDigest(token))],
        pendingCredentialChange: {'v': 1, 'kind': 'ROTATION',
          'intentId': _bytes(32, 7), 'key': _bytes(32, 8), 'accountId': _account,
          'originalTokenDigest': sessionTokenDigest(token), 'state': 'UNKNOWN'},
      ));
      await processVault.write(jsonEncode({'pid': pid}));
      return; // Retain only this explicit test namespace for the second run.
    }
    final priorProcess = jsonDecode((await processVault.read())!) as Map<String, dynamic>;
    expect(priorProcess['pid'], isNot(pid), reason: 'Must launch a distinct app process');
    final state = await store.read();
    expect(state.logouts.single.tokenDigest, sessionTokenDigest(token));
    expect(state.pendingCredentialChange?['key'], _bytes(32, 8));
    final api = _NoAuthorityApi();
    final directory = ChannelDirectoryController(repository: _NoChannels());
    final sessions = AuthSessionController(api: api, store: store, directory: directory);
    addTearDown(() { sessions.dispose(); directory.dispose(); });
    await sessions.start();
    expect(api.currentCalls, 0);
    expect(sessions.isAuthenticated, isFalse);
    expect(store.current?.session, isNull);
    expect(store.current?.logouts.single.revocationSecret, isNotNull);
    expect(store.current?.pendingCredentialChange?['key'], _bytes(32, 8));
    await store.update((_) => const AuthState());
    await processVault.write(jsonEncode({'cleaned': true}));
  }, skip: !native || phase.isEmpty);
}
