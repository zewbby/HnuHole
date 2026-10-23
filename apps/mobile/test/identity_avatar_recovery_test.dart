import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

import 'identity_test_support.dart';

String asset(int n) =>
    '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  test('upload timeout recovery preserves initial directory and can finish one creation', () async {
    final api = IdentityAvatarTestApi()..drops = 1;
    final f = await IdentityTestFixture.create(api: api);
    addTearDown(f.dispose);
    await f.controller.load();
    expect(
      await f.controller.uploadAvatar(
        asset(1),
        Uint8List.fromList([1]),
        'image/png',
      ),
      isNull,
    );
    expect(f.controller.directory!.identities, isEmpty);
    final ref = await f.controller.recoverAvatar(target: 'CREATE');
    expect(ref, 'avatar-v1:${asset(1)}');
    expect(await f.controller.saveInitialDraft('恢复海风', avatar: ref), isTrue);
    await f.controller.create('恢复海风', avatar: ref);
    expect(f.controller.entryReady, isTrue);
    expect(api.submissions.length, 1);
    expect(f.controller.pendingAvatar, isNull);
    expect(api.uploads, [asset(1)]);
  });
  test('three lost PUT receipts recover by original ID across restart without storing image bytes', () async {
    final api = IdentityAvatarTestApi()..drops = 3;
    final f = await IdentityTestFixture.create(api: api);
    addTearDown(f.dispose);
    await f.controller.load();
    final bytes = Uint8List(5 * 1024 * 1024)..fillRange(0, 5 * 1024 * 1024, 72);
    for (var n = 1; n <= 3; n++) {
      expect(
        await f.controller.uploadAvatar(asset(n), bytes, 'image/jpeg'),
        isNull,
      );
      expect(f.controller.pendingAvatar!['assetId'], asset(n));
      expect(utf8.encode(f.vault.value!).length, lessThan(4096));
    }
    expect(api.assets.length, 1);
    expect(api.abandons.length, 2);
    final restarted = await IdentityTestFixture.create(
      vault: f.vault,
      initialize: false,
      api: api,
    );
    addTearDown(restarted.dispose);
    await restarted.controller.load();
    expect(
      await restarted.controller.recoverAvatar(target: 'CREATE'),
      'avatar-v1:${asset(3)}',
    );
    expect(api.uploads.length, 3);
    expect(
      await restarted.controller.uploadAvatar(
        asset(4),
        Uint8List.fromList([1]),
        'image/png',
      ),
      'avatar-v1:${asset(4)}',
    );
    expect(api.assets.length, 1);
  });
  test('four confirmed previews release old unbound assets and two bound replacements clear anchors', () async {
    final api = IdentityAvatarTestApi()
      ..items = [identityTestItem()]
      ..createdCount = 1;
    final f = await IdentityTestFixture.create(api: api);
    addTearDown(f.dispose);
    await f.controller.load();
    for (var n = 1; n <= 4; n++) {
      expect(
        await f.controller.uploadAvatar(
          asset(n),
          Uint8List.fromList([n]),
          'image/png',
          target: identityTestId,
        ),
        'avatar-v1:${asset(n)}',
      );
    }
    expect(api.assets.length, 1);
    await f.controller.changeAvatar(identityTestId, 'avatar-v1:${asset(4)}');
    expect(f.controller.pendingAvatar, isNull);
    expect(f.controller.entryReady, isTrue);
    expect(
      await f.controller.uploadAvatar(
        asset(5),
        Uint8List.fromList([5]),
        'image/png',
        target: identityTestId,
      ),
      'avatar-v1:${asset(5)}',
    );
    await f.controller.rename(
      identityTestId,
      '新海风',
      avatar: 'avatar-v1:${asset(5)}',
    );
    expect(f.controller.pendingAvatar, isNull);
    expect(api.abandons, hasLength(3));
  });
  test('confirmed nonempty entry remains available during AVATAR unknown, authority change clears it', () async {
    final api = IdentityAvatarTestApi()
      ..items = [identityTestItem()]
      ..createdCount = 1;
    final f = await IdentityTestFixture.create(api: api);
    addTearDown(f.dispose);
    await f.controller.load();
    api.submitFailure = const AuthFailure(kind: AuthFailureKind.timeout);
    await f.controller.changeAvatar(identityTestId, 'default-v1');
    expect(f.controller.hasPending, isTrue);
    expect(f.controller.entryReady, isTrue);
    final restarted = await IdentityTestFixture.create(
      vault: f.vault,
      initialize: false,
      api: api,
    );
    addTearDown(restarted.dispose);
    await restarted.controller.load();
    expect(restarted.controller.entryReady, isTrue);
    await f.sessions.logout();
    expect(f.controller.entryReady, isFalse);
  });
  test('legacy persisted intents replay without inventing avatar or changing fingerprint version', () async {
    for (final operation in ['CREATE', 'RENAME', 'DELETE']) {
      final f = await IdentityTestFixture.create();
      addTearDown(f.dispose);
      await f.store.update(
        (s) => s.copyWith(
          identityChanges: {
            identityTestAccount: {
              'v': 1,
              'username': 'private_user',
              'key': AuthCrypto.randomEncoded(16),
              'operation': operation,
              'state': 'UNKNOWN',
              if (operation != 'CREATE') 'identityId': identityTestId,
              if (operation != 'DELETE') 'nickname': '海风',
            },
          },
        ),
      );
      f.api.applySubmission = false;
      final original = Map<String, dynamic>.from(
        f.store.current!.identityChanges[identityTestAccount] as Map,
      );
      await f.controller.retryPending();
      expect(f.api.submissions.single['avatar'], isNull);
      expect(f.api.submissions.single['key'], original['key']);
      expect(
        f.api.submissions.single['operation']
            .toString()
            .split('.')
            .last
            .toUpperCase(),
        operation,
      );
      expect(f.api.submissions.single['identityId'], original['identityId']);
      expect(f.api.submissions.single['nickname'], original['nickname']);
      expect(f.store.current!.identityChanges, isEmpty);
    }
  });
}
