import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_api.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_session_controller.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/channels/channel.dart';
import 'package:hnuhole_mobile/src/channels/channel_repository.dart';
import 'package:hnuhole_mobile/src/navigation/channel_directory_controller.dart';

String wire(int n, int b) => AuthCrypto.encode(List<int>.filled(n, b));
final oldToken = wire(32, 1), newToken = wire(32, 2);
const account = '00000000-0000-0000-0000-000000000001';
SessionRecord record(String token, {DateTime? expiry}) => SessionRecord(
  token: token,
  accountId: account,
  expiresAt: expiry ?? DateTime.now().toUtc().add(const Duration(days: 5)),
);

class MemoryVault implements AuthVault {
  String? value;
  int writes = 0;
  int? failAt;
  bool commitBeforeFailure = false;
  bool mismatch = false;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('native unavailable');
    return value;
  }

  @override
  Future<void> write(String next) async {
    writes++;
    if (writes == failAt) {
      if (commitBeforeFailure) value = next;
      throw StateError('native unavailable');
    }
    if (!mismatch) value = next;
  }
}

class Api implements AuthApi {
  final reads = <String>[], revocations = <String>[], renewals = <String>[];
  AuthFailure? readFailure, revokeFailure, renewalFailure;
  Completer<CurrentSession>? readWait;
  Completer<DateTime>? renewWait;
  int logins = 0;
  Completer<void>? revokeWait;
  DateTime expiry = DateTime.now().toUtc().add(const Duration(days: 5));
  @override
  Future<CurrentSession> currentSession(String token) async {
    reads.add(token);
    if (readFailure != null) throw readFailure!;
    return readWait != null
        ? await readWait!.future
        : CurrentSession(
            accountId: account,
            username: 'private_user',
            expiresAt: expiry,
          );
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async {
    logins++;
    return AuthSession(
      accountId: account,
      sessionToken: newToken,
      expiresAt: expiry,
    );
  }

  @override
  Future<void> revokeSession(String secret) async {
    revocations.add(secret);
    if (revokeFailure != null) throw revokeFailure!;
    await revokeWait?.future;
  }

  @override
  Future<DateTime> renewSession(String token) async {
    renewals.add(token);
    if (renewalFailure != null) throw renewalFailure!;
    return renewWait != null
        ? await renewWait!.future
        : DateTime.now().toUtc().add(const Duration(days: 30));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused operation');
}

class Channels implements ChannelRepository {
  final tokens = <String>[];
  ChannelRepositoryException? failure;
  @override
  Future<List<Channel>> loadChannels({required String sessionToken}) async {
    tokens.add(sessionToken);
    if (failure != null) throw failure!;
    throw const ChannelRepositoryException(
      message: 'isolated directory unavailable',
      statusCode: 503,
    );
  }
}

Future<
  ({
    AuthStore store,
    AuthSessionController sessions,
    Api api,
    Channels channels,
    ChannelDirectoryController directory,
  })
>
setup(MemoryVault vault, {AuthState? initial}) async {
  final store = AuthStore(vault);
  if (initial != null) await store.update((_) => initial);
  final api = Api(), channels = Channels();
  final directory = ChannelDirectoryController(repository: channels);
  final sessions = AuthSessionController(
    api: api,
    store: store,
    directory: directory,
  );
  addTearDown(sessions.dispose);
  addTearDown(directory.dispose);
  addTearDown(store.dispose);
  return (
    store: store,
    sessions: sessions,
    api: api,
    channels: channels,
    directory: directory,
  );
}

void main() {
  test(
    'stored expiry never bypasses server, including expired local metadata',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(
          session: record(oldToken, expiry: DateTime.utc(2000)),
        ),
      );
      await f.sessions.start();
      expect(f.api.reads, [oldToken]);
      expect(f.sessions.isAuthenticated, isTrue);
      expect(f.channels.tokens, [oldToken]);
    },
  );
  test(
    '503 retains token, hides all directory data and retry asks server',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(session: record(oldToken)),
      );
      f.api.readFailure = const AuthFailure(
        kind: AuthFailureKind.unavailable,
        statusCode: 503,
      );
      await f.sessions.start();
      expect(f.sessions.status, AuthStatus.unavailable);
      expect(f.store.current!.session!.token, oldToken);
      expect(f.directory.status, ChannelDirectoryStatus.failure);
      expect(f.channels.tokens, isEmpty);
      f.api.readFailure = null;
      await f.directory.retry();
      expect(f.sessions.isAuthenticated, isTrue);
    },
  );
  test(
    'server 401 removes only current token and reports replacement',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(session: record(oldToken)),
      );
      f.api.readFailure = const AuthFailure(
        kind: AuthFailureKind.unauthorized,
        statusCode: 401,
        code: 'session_replaced',
      );
      await f.sessions.start();
      expect(f.store.current!.session, isNull);
      expect(f.sessions.status, AuthStatus.signedOut);
      expect(f.channels.tokens, isEmpty);
      expect(f.sessions.error, contains('接替'));
    },
  );
  test(
    'logout marker durable before any revoke, failed write cannot claim logout',
    () async {
      final vault = MemoryVault();
      final f = await setup(
        vault,
        initial: AuthState(session: record(oldToken)),
      );
      await f.sessions.start();
      vault.failAt = vault.writes + 1;
      await f.sessions.logout();
      expect(f.sessions.status, AuthStatus.storageFailure);
      expect(f.api.revocations, isEmpty);
      expect((await f.store.read()).session!.token, oldToken);
    },
  );
  test(
    'failed second logout write leaves marker and startup finishes conversion',
    () async {
      final vault = MemoryVault();
      final f = await setup(
        vault,
        initial: AuthState(session: record(oldToken)),
      );
      vault.failAt = vault.writes + 2;
      await f.sessions.logout();
      expect(f.sessions.status, AuthStatus.storageFailure);
      expect(f.api.revocations, isEmpty);
      final pending = await f.store.read();
      expect(pending.session!.token, oldToken);
      expect(pending.logouts.single.revocationSecret, isNull);
      vault.failAt = null;
      await f.sessions.start();
      await f.sessions.retryPendingLogout();
      expect(f.api.reads, isEmpty);
      expect(f.store.current!.session, isNull);
      expect(f.api.revocations, [AuthCrypto.revocationSecret(oldToken)]);
    },
  );
  test('unknown marker write after commit is reconciled on next process before restore', () async {
    final vault = MemoryVault();
    final f = await setup(vault, initial: AuthState(session: record(oldToken)));
    vault.failAt = vault.writes + 1;
    vault.commitBeforeFailure = true;
    await f.sessions.logout();
    expect(f.sessions.status, AuthStatus.storageFailure);
    vault.failAt = null;
    final restarted = await setup(vault);
    await restarted.sessions.start();
    await restarted.sessions.retryPendingLogout();
    expect(restarted.api.reads, isEmpty);
    expect(restarted.api.revocations, [AuthCrypto.revocationSecret(oldToken)]);
    expect(restarted.store.current!.session, isNull);
    expect(restarted.store.current!.logouts, isEmpty);
  });
  test(
    'crash after marker before conversion never restores old bearer',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(
          session: record(oldToken),
          logouts: [LogoutTask(tokenDigest: sessionTokenDigest(oldToken))],
        ),
      );
      f.api.revokeFailure = const AuthFailure(kind: AuthFailureKind.timeout);
      await f.sessions.start();
      expect(f.api.reads, isEmpty);
      expect(f.store.current!.session, isNull);
      expect(f.sessions.hasPendingLogout, isTrue);
      expect(
        f.store.current!.logouts.single.revocationSecret,
        AuthCrypto.revocationSecret(oldToken),
      );
    },
  );
  test(
    'unknown renewal plus expired local expiry cannot drop revocation task',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(
          logouts: [
            LogoutTask(
              tokenDigest: sessionTokenDigest(oldToken),
              revocationSecret: AuthCrypto.revocationSecret(oldToken),
            ),
          ],
        ),
      );
      f.api.revokeFailure = const AuthFailure(
        kind: AuthFailureKind.unauthorized,
        statusCode: 401,
      );
      await f.sessions.start();
      expect(f.sessions.hasPendingLogout, isTrue);
      f.api.revokeFailure = null;
      await f.sessions.retry();
      await f.sessions.retryPendingLogout();
      expect(f.sessions.hasPendingLogout, isFalse);
    },
  );
  test(
    'old independent revocation retry never clears later explicit login',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(
          logouts: [
            LogoutTask(
              tokenDigest: sessionTokenDigest(oldToken),
              revocationSecret: AuthCrypto.revocationSecret(oldToken),
            ),
          ],
        ),
      );
      f.api.revokeFailure = const AuthFailure(
        kind: AuthFailureKind.unavailable,
      );
      await f.sessions.start();
      await f.sessions.login('private_user', 'a-long-password');
      expect(f.store.current!.session!.token, newToken);
      f.api.revokeFailure = null;
      await f.sessions.retry();
      await f.sessions.retryPendingLogout();
      expect(f.store.current!.session!.token, newToken);
      expect(f.sessions.isAuthenticated, isTrue);
      expect(f.api.revocations.toSet(), {
        AuthCrypto.revocationSecret(oldToken),
      });
    },
  );
  test(
    'late restore after durable logout marker never exposes nodes',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(session: record(oldToken)),
      );
      f.api.readWait = Completer<CurrentSession>();
      final work = f.sessions.start();
      while (f.api.reads.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await f.store.update(
        (s) => s.copyWith(
          logouts: [LogoutTask(tokenDigest: sessionTokenDigest(oldToken))],
        ),
      );
      f.api.readWait!.complete(
        CurrentSession(
          accountId: account,
          username: 'private_user',
          expiresAt: f.api.expiry,
        ),
      );
      await work;
      expect(f.sessions.isAuthenticated, isFalse);
      expect(f.channels.tokens, isEmpty);
    },
  );
  test('unknown reset startup is suspended; only explicit password login grants new session', () async {
    final intent = wire(32, 4);
    final f = await setup(
      MemoryVault(),
      initial: AuthState(
        session: record(oldToken),
        pendingReset: {
          'v': 1,
          'intentId': intent,
          'key': wire(32, 5),
          'state': 'UNKNOWN',
          'originalTokenDigest': sessionTokenDigest(oldToken),
        },
      ),
    );
    await f.sessions.start();
    expect(f.api.reads, isEmpty);
    expect(f.api.logins, 0);
    await f.sessions.login('private_user', 'a-long-password');
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.store.current!.session!.approvedPendingResetId, intent);
    await f.sessions.retry();
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.store.current!.pendingReset!['state'], 'UNKNOWN');
  });
  test(
    'active near expiry renews same token and far expiry does not',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(session: record(oldToken)),
      );
      await f.sessions.start();
      await f.sessions.onActivity();
      expect(f.api.renewals, [oldToken]);
      expect(f.store.current!.session!.token, oldToken);
      await f.sessions.onActivity();
      expect(f.api.renewals.length, 1);
    },
  );
  test(
    'frozen renewal retains token and requires authoritative restore',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(session: record(oldToken)),
      );
      await f.sessions.start();
      f.api.renewalFailure = const AuthFailure(
        kind: AuthFailureKind.unavailable,
        statusCode: 503,
      );
      await f.sessions.onActivity();
      expect(f.sessions.status, AuthStatus.unavailable);
      expect(f.store.current!.session!.token, oldToken);
      expect(f.directory.channels, isEmpty);
    },
  );
  test('late renewal cannot resurrect a token removed by workflow', () async {
    final f = await setup(
      MemoryVault(),
      initial: AuthState(session: record(oldToken)),
    );
    await f.sessions.start();
    f.api.renewWait = Completer<DateTime>();
    final renewal = f.sessions.onActivity();
    while (f.api.renewals.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await f.store.update((s) => s.copyWith(clearSession: true));
    f.api.renewWait!.complete(
      DateTime.now().toUtc().add(const Duration(days: 30)),
    );
    await renewal;
    expect(f.store.current!.session, isNull);
    expect(f.sessions.isAuthenticated, isFalse);
  });
  test('channel 401 fences session; channel 503 does not erase it', () async {
    final f = await setup(
      MemoryVault(),
      initial: AuthState(session: record(oldToken)),
    );
    f.channels.failure = const ChannelRepositoryException(
      message: 'replaced',
      statusCode: 401,
      code: 'session_replaced',
    );
    await f.sessions.start();
    await Future<void>.delayed(Duration.zero);
    expect(f.store.current!.session, isNull);
    expect(f.sessions.isAuthenticated, isFalse);
  });
  test(
    'missing bearer for incomplete marker is fail closed without any network',
    () async {
      final f = await setup(
        MemoryVault(),
        initial: AuthState(
          logouts: [LogoutTask(tokenDigest: sessionTokenDigest(oldToken))],
        ),
      );
      await f.sessions.start();
      expect(f.sessions.status, AuthStatus.storageFailure);
      expect(f.api.reads, isEmpty);
      expect(f.api.revocations, isEmpty);
    },
  );
  test('blocked old revocation does not delay restoring new token', () async {
    final f = await setup(
      MemoryVault(),
      initial: AuthState(
        session: record(newToken),
        logouts: [
          LogoutTask(
            tokenDigest: sessionTokenDigest(oldToken),
            revocationSecret: AuthCrypto.revocationSecret(oldToken),
          ),
        ],
      ),
    );
    f.api.revokeWait = Completer<void>();
    await f.sessions.start().timeout(const Duration(seconds: 2));
    expect(f.sessions.isAuthenticated, isTrue);
    expect(f.store.current!.session!.token, newToken);
    f.api.revokeWait!.complete();
    await f.sessions.retryPendingLogout();
    expect(f.store.current!.session!.token, newToken);
  });
  test('foreground activity retries pending logout without login', () async {
    final f = await setup(
      MemoryVault(),
      initial: AuthState(
        logouts: [
          LogoutTask(
            tokenDigest: sessionTokenDigest(oldToken),
            revocationSecret: AuthCrypto.revocationSecret(oldToken),
          ),
        ],
      ),
    );
    f.api.revokeFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.sessions.start();
    await f.sessions.retryPendingLogout();
    expect(f.sessions.hasPendingLogout, isTrue);
    f.api.revokeFailure = null;
    await f.sessions.onActivity();
    await f.sessions.retryPendingLogout();
    expect(f.sessions.hasPendingLogout, isFalse);
    expect(f.api.logins, 0);
    expect(f.api.reads, isEmpty);
  });
  test('parallel secure updates are serialized and readback mismatch invalidates cache', () async {
    final vault = MemoryVault();
    final store = AuthStore(vault);
    addTearDown(store.dispose);
    await Future.wait([
      store.update((s) => s.copyWith(cInstallationId: wire(16, 1))),
      store.update((s) => s.copyWith(vInstallationId: wire(16, 2))),
    ]);
    expect(store.current!.cInstallationId, wire(16, 1));
    expect(store.current!.vInstallationId, wire(16, 2));
    vault.mismatch = true;
    await expectLater(
      store.update((s) => s.copyWith(session: record(oldToken))),
      throwsA(isA<AuthStorageFailure>()),
    );
    expect(store.current, isNull);
  });
  test('corrupt or other deployment secure snapshot cannot become signed out silently', () async {
    for (final value in [
      '{',
      jsonEncode(const AuthState().toJson('other-environment')),
      jsonEncode({
        ...const AuthState().toJson('hnuhole.isolated.auth.v1'),
        'schema': 1.0,
      }),
      jsonEncode({
        ...const AuthState().toJson('hnuhole.isolated.auth.v1'),
        'pendingReset': {'v': 1, 'state': 'NORMAL'},
      }),
    ]) {
      final vault = MemoryVault()..value = value;
      final f = await setup(vault);
      await f.sessions.start();
      expect(f.sessions.status, AuthStatus.storageFailure);
      expect(f.api.reads, isEmpty);
    }
  });
}
