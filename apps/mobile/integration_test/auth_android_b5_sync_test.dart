import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:integration_test/integration_test.dart';

import 'owned_auth_device_helpers.dart';

// Full product App. The host separately records the OEM transfer and SQL.
// Commands are scoped to this process and nonce. No automatic native retry.
const _owner = 'HNUHOLE_B5_20261016_V1';
const _root =
    '/data/user/0/org.hnuhole.hnuhole_mobile.acceptance20261012/files/';
const _privateRoot =
    '/data/user/0/org.hnuhole.hnuhole_mobile.acceptance20261012/no_backup/';
const _seed = String.fromEnvironment('AUTH_ALT_SEED');
final _username =
    'alt_${AuthCrypto.domainDigest('ALT-USER', utf8.encode(_seed)).substring(0, 12)}'
        .replaceAll('-', '_')
        .toLowerCase();
final _password =
    'Dev-${AuthCrypto.domainDigest('ALT-PASSWORD', utf8.encode(_seed))}#9';

Future<void> _write(String name, Map<String, dynamic> value) async {
  final destination = File(
    '${name.endsWith('.private.json') ? _privateRoot : _root}$name',
  );
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString(
    jsonEncode({...value, 'owner': _owner, 'pid': pid}),
    flush: true,
  );
  await temporary.rename(destination.path);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('B5 actual two-Android operator stages', (tester) async {
    expect(Platform.isAndroid && _seed == 'hnuhole-alternate-20261013', true);
    app.main();
    await tester.pump();
    final dynamic root = tester.widget(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_HnuholeApp'),
    );
    final store = root.store as AuthStore;
    final sessions = root.sessions as AuthSessionController;
    final security = root.management as SecurityManagementController;
    final api = root.api as HttpAuthApi;
    final flows = root.flows as AuthFlows;
    await waitOwned(
      tester,
      () =>
          !sessions.busy &&
          (store.current != null ||
              sessions.status == AuthStatus.storageFailure),
      'B5 native startup',
    );
    final nonce = AuthCrypto.randomEncoded(16);
    var sequence = 0;
    var state = 'READY';
    var migrationAccepted = false;
    var createAttempts = 0;
    var getAttempts = 0;
    var account = <String, dynamic>{};
    String? newRecovery;
    String? newPassword;

    Future<void> report(
      String next, [
      Map<String, dynamic> extra = const {},
    ]) async {
      state = next;
      await _write('b5-status.json', {
        'nonce': nonce,
        'sequence': sequence,
        'state': state,
        'authenticated': sessions.isAuthenticated,
        'nativeStorageFailure': sessions.status == AuthStatus.storageFailure,
        'sessionPresent': store.current?.session != null,
        'createAttempts': createAttempts,
        'getAttempts': getAttempts,
        'fixtureProtocol': 2,
        ...extra,
      });
    }

    Future<void> authRoute() async {
      if (find.byType(AuthScreen).evaluate().isEmpty) {
        await tapOwned(tester, find.text('登录或注册'));
      }
    }

    Future<void> login(String password) async {
      await inputOwned(tester, 'login-username', _username);
      await inputOwned(tester, 'login-password', password);
      await tapOwned(tester, find.text('登录并进入'));
      await waitOwned(
        tester,
        () =>
            sessions.isAuthenticated &&
            store.current?.session != null &&
            find.byType(AuthScreen).evaluate().isEmpty,
        'B5 explicit login',
      );
    }

    Future<void> denied(Future<dynamic> Function() action) async {
      await expectLater(
        action(),
        throwsA(
          isA<AuthFailure>().having((e) => e.statusCode, 'HTTP status', 401),
        ),
      );
    }

    await report('READY');
    final deadline = DateTime.now().add(const Duration(minutes: 90));
    while (DateTime.now().isBefore(deadline)) {
      final file = File('${_privateRoot}b5-command.json');
      Map<String, dynamic>? command;
      if (await file.exists()) {
        final candidate =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (candidate['owner'] == _owner &&
            candidate['pid'] == pid &&
            candidate['nonce'] == nonce &&
            candidate['sequence'] == sequence + 1) {
          command = candidate;
        }
      }
      if (command == null) {
        await tester.pump(const Duration(milliseconds: 250));
        continue;
      }
      sequence++;
      try {
        switch (command['step']) {
          case 'source-login':
            expect(state, 'READY');
            expect(sessions.status != AuthStatus.storageFailure, true);
            expect(store.current?.pendingReset, null);
            expect(store.current?.pendingCredentialChange, null);
            account = Map<String, dynamic>.from(command['account'] as Map);
            final reusedSourceSession = store.current?.session != null;
            if (!reusedSourceSession) {
              await authRoute();
              await login(_password);
            }
            expect(store.current!.session!.accountId, account['accountId']);
            expect(
              (await api.currentSession(store.current!.session!.token))
                  .accountId,
              account['accountId'],
            );
            account['oldSessionToken'] = store.current!.session!.token;
            await _write('b5-source.private.json', account);
            await report('SOURCE_AUTHENTICATED', {
              'explicitProductLogin': !reusedSourceSession,
              'restoredAcceptedSourceSession': reusedSourceSession,
            });
          case 'target-observe':
            expect(state, 'READY');
            expect(sessions.isAuthenticated, false);
            expect(store.current?.session, null);
            await authRoute();
            if (sessions.status == AuthStatus.storageFailure) {
              await waitOwned(
                tester,
                () => find.text('安全存储暂不可用').evaluate().isNotEmpty,
                'B5 OEM restored storage failure page',
              );
              await expectLater(
                store.read(),
                throwsA(isA<AuthStorageFailure>()),
              );
              await expectLater(
                store.update((_) => const AuthState()),
                throwsA(isA<AuthStorageFailure>()),
              );
              await report('MIGRATION_STORAGE_REJECTED', {
                'targetAuthorityCopied': false,
              });
            } else {
              final restored = await store.read();
              expect(restored.session, null);
              expect(restored.registration, null);
              expect(restored.pendingReset, null);
              expect(restored.pendingCredentialChange, null);
              expect(restored.pendingClosure, null);
              expect(
                restored.identityDrafts.isEmpty &&
                    restored.identityChanges.isEmpty,
                true,
              );
              await waitOwned(
                tester,
                () => find
                    .byKey(const ValueKey('login-username'))
                    .evaluate()
                    .isNotEmpty,
                'B5 actual unauthenticated login page',
              );
              migrationAccepted = true;
              await report('MIGRATION_EMPTY', {
                'targetAuthorityCopied': false,
                'actualUnauthenticatedProductRoute': true,
              });
            }
          case 'source-bind':
            expect(state, 'SOURCE_AUTHENTICATED');
            expect(createAttempts, 0);
            await security.load();
            expect(security.credentials!.passkeys.isEmpty, true);
            await const MethodChannel('hnuhole/auth_passkey')
                .invokeMethod<void>(
                  'acceptanceCreationLabel',
                  'HnuHole test 26ac0016',
                );
            createAttempts++;
            await report('CREATE_NATIVE_PENDING');
            var done = false;
            Object? failure;
            security
                .bindPasskey(_password)
                .then(
                  (_) => done = true,
                  onError: (Object e) {
                    failure = e;
                    done = true;
                  },
                );
            final until = DateTime.now().add(const Duration(minutes: 3));
            while (!done && DateTime.now().isBefore(until)) {
              await tester.pump(const Duration(milliseconds: 200));
            }
            expect(
              done &&
                  failure == null &&
                  security.status == SecurityManagementStatus.committed,
              true,
              reason: 'One original native creation must actually commit',
            );
            await security.acknowledgeResult();
            await security.load();
            expect(security.credentials!.passkeys.length, 1);
            account['credentialId'] =
                security.credentials!.passkeys.single.credentialId;
            await _write('b5-source.private.json', account);
            await report('SOURCE_BOUND', {
              'actualProductCCommit': true,
              'passkeyCount': 1,
            });
          case 'target-recover':
            expect(state, 'MIGRATION_EMPTY');
            expect(migrationAccepted && !sessions.isAuthenticated, true);
            expect(getAttempts, 0);
            account = Map<String, dynamic>.from(command['account'] as Map);
            expect(account['username'], _username);
            await tapOwned(tester, find.text('恢复账号'));
            getAttempts++;
            await report('GET_NATIVE_PENDING');
            await tapOwned(tester, find.text('使用 Passkey 恢复'));
            final until = DateTime.now().add(const Duration(minutes: 3));
            while (flows.status != AuthFlowStatus.resetCodeShown &&
                DateTime.now().isBefore(until)) {
              await tester.pump(const Duration(milliseconds: 200));
              if (!flows.busy && flows.errorMessage != null) break;
            }
            expect(
              flows.status,
              AuthFlowStatus.resetCodeShown,
              reason: 'Actual discoverable native assertion and C reset intent required',
            );
            await waitOwned(
              tester,
              () => find
                  .byKey(const ValueKey('displayed-recovery-code'))
                  .evaluate()
                  .isNotEmpty,
              'B5 actual new recovery code',
            );
            newRecovery = tester
                .widget<Text>(
                  find.byKey(const ValueKey('displayed-recovery-code')),
                )
                .data!;
            newPassword = 'B5-${AuthCrypto.randomEncoded(32)}#9';
            expect(sessions.isAuthenticated, false);
            expect(store.current!.session, null);
            await report('RESET_INTENT_READY', {
              'actualDiscoverableAndroidRecovery': true,
              'intentDidNotAutoLogin': true,
            });
          case 'confirm-reset':
            expect(state, 'RESET_INTENT_READY');
            expect(command['syntheticRecoveryAcknowledged'], true);
            expect(newRecovery != null && newPassword != null, true);
            await tapOwned(tester, find.text('我已保存，隐藏原码并确认'));
            expect(
              find
                  .byKey(const ValueKey('displayed-recovery-code'))
                  .evaluate()
                  .isEmpty,
              true,
            );
            await inputOwned(tester, 'reset-new-password', newPassword!);
            await inputOwned(tester, 'recovery-confirmation', newRecovery!);
            await report('RESET_COMMIT_PENDING');
            await tapOwned(tester, find.text('设置新密码并激活新恢复码'));
            await waitOwned(
              tester,
              () =>
                  flows.status == AuthFlowStatus.resetCommitted &&
                  find.text('密码已重设').evaluate().isNotEmpty,
              'B5 actual reset commit',
            );
            expect(sessions.isAuthenticated, false);
            expect((await store.read()).session, null);
            await _write('b5-reset.private.json', {
              'newPassword': newPassword,
              'newRecoveryCode': newRecovery,
              'accountId': account['accountId'],
            });
            await report('RESET_COMMITTED_NO_SESSION', {
              'actualFullCodeConfirmation': true,
              'resetDidNotAutoLogin': true,
            });
          case 'verify-login':
            expect(state, 'RESET_COMMITTED_NO_SESSION');
            await denied(
              () => api.currentSession(account['oldSessionToken'] as String),
            );
            await denied(
              () => api.login(
                username: _username,
                password: _password,
                installationId: AuthCrypto.randomEncoded(16),
                idempotencyKey: AuthCrypto.randomEncoded(32),
              ),
            );
            await denied(
              () => api.createCodeResetIntent(
                account['oldRecoveryCode'] as String,
              ),
            );
            await report('OLD_CREDENTIALS_REJECTED', {
              'oldSessionHttpStatus': 401,
              'oldPasswordHttpStatus': 401,
              'oldRecoveryCodeHttpStatus': 401,
            });
            await tapOwned(tester, find.text('前往登录'));
            await login(newPassword!);
            expect(store.current!.session!.accountId, account['accountId']);
            expect(
              (await api.recoveryCredentials(store.current!.session!.token))
                  .passkeys
                  .isEmpty,
              true,
            );
            await report('CROSS_DEVICE_RECOVERY_PASS', {
              'sameAccountRestored': true,
              'explicitProductLogin': true,
              'oldPasskeysAbsent': true,
            });
          default:
            throw StateError('Unknown or out-of-sequence B5 command');
        }
      } catch (_) {
        await report('FAILED_OR_UNKNOWN', {
          'failedStep': command['step'],
          'automaticRetryPermitted': false,
          'previousOperationPreserved': true,
        });
        rethrow;
      }
    }
  }, timeout: const Timeout(Duration(minutes: 95)));
}
