import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/auth_models.dart';
import 'package:hnuhole_mobile/src/auth/auth_session_controller.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';
import 'package:hnuhole_mobile/src/identity/identity_api.dart';
import 'package:hnuhole_mobile/src/identity/identity_management_controller.dart';

/// Real Dart transport -> Go HTTPS handler -> SQL. The caller's in-memory vault
/// survives object reconstruction; this does not prove native/process durability.
Future<void> verifyIdentityHttpsScenarios({
  required HttpAuthApi api,
  required AuthStore Function() store,
  required AuthSessionController Function() sessions,
  required Future<void> Function() restartClient,
  required Future<Map<String, dynamic>> Function(String, Map<String, String>) fixture,
  required String username,
  required String password,
}) async {
  IdentityManagementController newManager() => IdentityManagementController(
    api: api, store: store(), sessions: sessions(),
  );
  var manager = newManager();
  Map<String, dynamic> pending() => Map<String, dynamic>.from(
    store().current!.identityChanges[store().current!.session!.accountId] as Map,
  );
  Future<void> reconstruct() async {
    manager.dispose();
    await restartClient();
    manager = newManager();
    await manager.load();
  }
  try {
    await manager.load();
    expect(manager.status, IdentityManagementStatus.ready);
    expect(manager.directory!.identities, isEmpty);
    expect(manager.directory!.createdCount, 0);
    expect(sessions().isAuthenticated, isTrue);

    await fixture('drop-next', {'path': '/api/v1/identities'});
    await manager.create('海风');
    expect(manager.status, IdentityManagementStatus.pending);
    final createKey = pending()['key'] as String;
    expect(pending()['state'], 'UNKNOWN');
    await reconstruct();
    expect(manager.status, IdentityManagementStatus.ready);
    expect(manager.directory!.identities, hasLength(1));
    expect(manager.directory!.createdCount, 1);
    final first = manager.directory!.identities.single;
    expect(first.nickname, '海风');
    expect(first.avatar, 'default-v1');
    expect(first.isOriginal, isTrue);
    final original = await api.identityChangeResult(
      sessionToken: store().current!.session!.token, idempotencyKey: createKey,
    );
    expect(original.committed, isTrue);
    expect(original.identityId, first.id);
    expect(store().current!.identityChanges, isEmpty);

    // Lose the rename response, then replace the session before reconciliation.
    await fixture('drop-next', {'path': '/api/v1/identities/${first.id}'});
    await manager.rename(first.id, '南风');
    expect(manager.status, IdentityManagementStatus.pending);
    final renameKey = pending()['key'] as String;
    final replacedToken = store().current!.session!.token;
    final replacement = await api.login(username: username, password: password,
      installationId: AuthCrypto.randomEncoded(16),
      idempotencyKey: AuthCrypto.randomEncoded(32));
    await sessions().retry();
    expect(manager.directory, isNull);
    expect(store().current!.session, isNull);
    await expectLater(api.identities(replacedToken), throwsA(
      isA<AuthFailure>().having((e) => e.code, 'code', 'session_replaced')));
    await sessions().acceptSession(replacement);
    expect(pending()['key'], renameKey);
    await manager.load();
    expect(manager.status, IdentityManagementStatus.ready);
    expect(manager.directory!.identities.single.id, first.id);
    expect(manager.directory!.identities.single.nickname, '南风');
    expect(manager.directory!.identities.single.renameAvailableAt, isNotNull);
    expect(store().current!.identityChanges, isEmpty);

    await manager.create('北风');
    expect(manager.directory!.createdCount, 2);
    final second = manager.directory!.identities.singleWhere((i) => i.id != first.id);
    await fixture('drop-next', {'path': '/api/v1/identities/${second.id}'});
    await manager.delete(second.id);
    expect(manager.status, IdentityManagementStatus.pending);
    final deleteKey = pending()['key'] as String;
    await reconstruct();
    expect(manager.directory!.identities.single.id, first.id);
    expect(manager.directory!.createdCount, 2);
    final deletion = await api.identityChangeResult(
      sessionToken: store().current!.session!.token, idempotencyKey: deleteKey);
    expect(deletion.operation, IdentityOperation.delete);
    expect(deletion.identityId, second.id);
    expect(deletion.committed, isTrue);

    // A lost definitive rejection is reconciled, never mistaken for a commit.
    await fixture('drop-next', {'path': '/api/v1/identities/${first.id}'});
    await manager.delete(first.id);
    expect(manager.status, IdentityManagementStatus.pending);
    final rejectedKey = pending()['key'] as String;
    await reconstruct();
    expect(manager.error!.code, 'IDENTITY_LAST_REQUIRED');
    expect(store().current!.identityChanges, isEmpty);
    final rejected = await api.identityChangeResult(
      sessionToken: store().current!.session!.token, idempotencyKey: rejectedKey);
    expect(rejected.rejected, isTrue);
    expect(rejected.committed, isFalse);
    expect(rejected.identityId, isNull);
    await manager.load();
    expect(manager.directory!.identities.single.id, first.id);
    await manager.create('西风');
    expect(manager.directory!.createdCount, 3);
    expect(manager.directory!.identities, hasLength(2));
    expect(manager.directory!.creationCoolingDown, isTrue);
    await manager.create('东风');
    expect(manager.error!.code, 'IDENTITY_CREATE_COOLDOWN');
    expect(store().current!.identityChanges, isEmpty);
    await manager.load();
    expect(manager.directory!.createdCount, 3);
    expect(manager.directory!.identities, hasLength(2));
  } finally {
    manager.dispose();
  }
}
