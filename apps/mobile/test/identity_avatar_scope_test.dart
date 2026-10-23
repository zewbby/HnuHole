import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/identity/identity_api.dart';
import 'package:hnuhole_mobile/src/identity/identity_avatar.dart';

import 'identity_test_support.dart';

class DelayedAvatarApi extends IdentityAvatarTestApi {
  Completer<IdentityAvatarResult>? hold;
  int avatarReads = 0;
  @override
  Future<IdentityAvatarResult> readIdentityAvatar({
    required String sessionToken,
    required String avatar,
  }) {
    avatarReads++;
    return hold?.future ??
        super.readIdentityAvatar(sessionToken: sessionToken, avatar: avatar);
  }
}

void main() {
  test(
    'avatar bytes never publish after logout; replacement authority refetches',
    () async {
      final f = await IdentityTestFixture.create();
      addTearDown(f.dispose);
      final api = DelayedAvatarApi();
      final repository = IdentityAvatarRepository(api, f.sessions, f.store);
      addTearDown(repository.dispose);
      const id = '10000000-0000-4000-8000-000000000001', ref = 'avatar-v1:$id';
      final hold = Completer<IdentityAvatarResult>();
      api.hold = hold;
      final late = repository.load(ref);
      expect(identical(late, repository.load(ref)), isTrue);
      await f.sessions.logout();
      hold.complete(
        IdentityAvatarResult(
          avatar: ref,
          sessionExpiresAt: identityTestRenewed,
          bytes: Uint8List.fromList([1]),
        ),
      );
      expect(await late, isNull);
      expect(await repository.load(ref), isNull);
      await f.sessions.login('private_user', 'valid password');
      api.hold = null;
      api.assets[id] = Uint8List.fromList([2]);
      expect(await repository.load(ref), [2]);
      expect(api.avatarReads, 2);
      expect(await repository.load(ref), [2]);
      expect(api.avatarReads, 2);
    },
  );
}
