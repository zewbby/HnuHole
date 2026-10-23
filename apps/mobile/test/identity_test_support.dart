import 'dart:async';
import 'dart:typed_data';

import 'package:hnuhole_mobile/hnuhole_mobile.dart';

const identityTestAccount = '00000000-0000-0000-0000-000000000001';
const identityTestId = '00000000-0000-0000-0000-000000000011';
const identityTestSecondId = '00000000-0000-0000-0000-000000000012';
final identityTestToken = AuthCrypto.encode(List<int>.filled(32, 1));
final identityTestOtherToken = AuthCrypto.encode(List<int>.filled(32, 2));
final identityTestExpiry = DateTime.utc(2031, 1, 1);
final identityTestRenewed = DateTime.utc(2031, 1, 31);

/// Atomic-value fake only. This does not test Android Keystore/iOS Keychain.
class IdentityTestVault implements AuthVault {
  String? value;
  String? failContaining;
  bool commitUnknown = false;
  Completer<void>? nextReadWait;
  final readBlocked = Completer<void>();
  @override
  Future<String?> read() async {
    final wait = nextReadWait;
    nextReadWait = null;
    if (wait != null) {
      if (!readBlocked.isCompleted) readBlocked.complete();
      await wait.future;
    }
    return value;
  }

  @override
  Future<void> write(String next) async {
    if (failContaining != null && next.contains(failContaining!)) {
      failContaining = null;
      if (commitUnknown) value = next;
      throw const AuthStorageFailure();
    }
    value = next;
  }
}

class IdentityTestSessionApi implements AuthApi {
  String account = identityTestAccount, username = 'private_user';
  @override
  Future<CurrentSession> currentSession(String token) async => CurrentSession(
    accountId: account,
    username: username,
    expiresAt: identityTestExpiry,
  );
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required String installationId,
    required String idempotencyKey,
  }) async => AuthSession(
    accountId: account,
    sessionToken: identityTestOtherToken,
    expiresAt: identityTestExpiry,
  );
  @override
  Future<void> revokeSession(String secret) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unused authentication operation');
}

class IdentityTestChannels implements ChannelRepository {
  @override
  Future<ChannelDirectoryResult> loadChannels({
    required String sessionToken,
  }) async => ChannelDirectoryResult(
    expiresAt: identityTestExpiry,
    channels: [
      for (var i = 0; i < ChannelDirectory.requiredCodes.length; i++)
        Channel(
          id: '00000000-0000-0000-0000-00000000000${i + 1}',
          code: ChannelDirectory.requiredCodes[i],
          name: 'Channel $i',
          initiallyVisible: i < 5,
          displayOrder: i + 1,
        ),
    ],
  );
}

ManagedIdentity identityTestItem({
  String id = identityTestId,
  String name = '面具一',
  String avatar = 'default-v1',
  bool original = true,
  DateTime? renameAt,
}) => ManagedIdentity(
  id: id,
  nickname: name,
  avatar: avatar,
  isOriginal: original,
  createdAt: DateTime.utc(2026, 10, 2),
  renameAvailableAt: renameAt,
);

class IdentityTestApi implements IdentityApi {
  List<ManagedIdentity> items = [];
  int createdCount = 0, reads = 0;
  DateTime? nextCreateAt;
  final submissions = <Map<String, dynamic>>[];
  final queries = <Map<String, String>>[];
  final submissionStarted = Completer<void>(), readStarted = Completer<void>();
  Completer<IdentityChangeOutcome>? submitWait;
  Completer<IdentityDirectory>? readWait;
  AuthFailure? submitFailure, queryFailure, readFailure;
  IdentityChangeOutcome? queryOutcome;
  void Function()? beforeSubmit;
  bool applySubmission = true;

  IdentityDirectory directory() => IdentityDirectory(
    identities: List.unmodifiable(items),
    createdCount: createdCount,
    nextCreateAt: nextCreateAt,
    serverTime: DateTime.utc(2026, 10, 3),
    sessionExpiresAt: identityTestRenewed,
  );
  @override
  Future<IdentityDirectory> identities(String token) async {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    if (readFailure != null) throw readFailure!;
    return readWait != null ? await readWait!.future : directory();
  }

  @override
  Future<IdentityChangeOutcome> changeIdentity({
    required String sessionToken,
    required String idempotencyKey,
    required IdentityOperation operation,
    String? identityId,
    String? nickname,
    String? avatar,
  }) async {
    submissions.add({
      'token': sessionToken,
      'key': idempotencyKey,
      'operation': operation,
      'identityId': identityId,
      'nickname': nickname,
      'avatar': avatar,
    });
    beforeSubmit?.call();
    if (!submissionStarted.isCompleted) submissionStarted.complete();
    if (submitFailure != null) throw submitFailure!;
    if (submitWait != null) return await submitWait!.future;
    if (applySubmission) {
      switch (operation) {
        case IdentityOperation.create:
          items = [
            ...items,
            identityTestItem(name: nickname!, avatar: avatar ?? 'default-v1'),
          ];
          createdCount++;
        case IdentityOperation.rename:
          items = [
            for (final item in items)
              item.id == identityId
                  ? identityTestItem(
                      id: item.id,
                      name: nickname!,
                      avatar: avatar ?? item.avatar,
                      original: item.isOriginal,
                      renameAt: DateTime.utc(2026, 11, 2),
                    )
                  : item,
          ];
        case IdentityOperation.delete:
          items = items.where((item) => item.id != identityId).toList();
        case IdentityOperation.avatar:
          items = [
            for (final item in items)
              if (item.id == identityId)
                identityTestItem(
                  id: item.id,
                  name: item.nickname,
                  avatar: avatar!,
                  original: item.isOriginal,
                  renameAt: item.renameAvailableAt,
                )
              else
                item,
          ];
      }
    }
    return IdentityChangeOutcome(
      committed: true,
      operation: operation,
      identityId: identityId ?? identityTestId,
      sessionExpiresAt: identityTestRenewed,
    );
  }

  @override
  Future<IdentityChangeOutcome> identityChangeResult({
    required String sessionToken,
    required String idempotencyKey,
  }) async {
    queries.add({'token': sessionToken, 'key': idempotencyKey});
    if (queryFailure != null) throw queryFailure!;
    return queryOutcome ??
        IdentityChangeOutcome(
          committed: false,
          sessionExpiresAt: identityTestRenewed,
        );
  }
}

class IdentityAvatarTestApi extends IdentityTestApi
    implements IdentityAvatarApi {
  final assets = <String, Uint8List>{};
  final tombstones = <String>{}, bound = <String>{};
  final uploads = <String>[], abandons = <String>[];
  int drops = 0;
  @override
  Future<IdentityAvatarResult> uploadIdentityAvatar({
    required String sessionToken,
    required String assetId,
    required Uint8List bytes,
    required String mime,
  }) async {
    uploads.add(assetId);
    if (tombstones.contains(assetId)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'IDENTITY_AVATAR_INVALID',
      );
    }
    if (!assets.containsKey(assetId) &&
        assets.keys.where((id) => !bound.contains(id)).length >= 3) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'IDENTITY_AVATAR_LIMIT',
      );
    }
    assets[assetId] = bytes;
    if (drops > 0) {
      drops--;
      throw const AuthFailure(kind: AuthFailureKind.timeout);
    }
    return IdentityAvatarResult(
      avatar: 'avatar-v1:$assetId',
      sessionExpiresAt: identityTestRenewed,
    );
  }

  @override
  Future<IdentityAvatarResult> readIdentityAvatar({
    required String sessionToken,
    required String avatar,
  }) async {
    final data = assets[avatar.substring(10)];
    if (data == null) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'IDENTITY_AVATAR_NOT_FOUND',
      );
    }
    return IdentityAvatarResult(
      avatar: avatar,
      bytes: data,
      sessionExpiresAt: identityTestRenewed,
    );
  }

  @override
  Future<DateTime> abandonIdentityAvatar({
    required String sessionToken,
    required String avatar,
  }) async {
    final id = avatar.substring(10);
    abandons.add(id);
    if (bound.contains(id)) {
      throw const AuthFailure(
        kind: AuthFailureKind.rejected,
        code: 'IDENTITY_AVATAR_INVALID',
      );
    }
    assets.remove(id);
    tombstones.add(id);
    return identityTestRenewed;
  }

  @override
  Future<IdentityChangeOutcome> changeIdentity({
    required String sessionToken,
    required String idempotencyKey,
    required IdentityOperation operation,
    String? identityId,
    String? nickname,
    String? avatar,
  }) async {
    final result = await super.changeIdentity(
      sessionToken: sessionToken,
      idempotencyKey: idempotencyKey,
      operation: operation,
      identityId: identityId,
      nickname: nickname,
      avatar: avatar,
    );
    if (avatar?.startsWith('avatar-v1:') == true) {
      bound.add(avatar!.substring(10));
    }
    return result;
  }
}

class IdentityTestFixture {
  IdentityTestFixture(
    this.vault,
    this.store,
    this.sessionApi,
    this.sessions,
    this.directory,
    this.api,
    this.controller,
  );
  final IdentityTestVault vault;
  final AuthStore store;
  final IdentityTestSessionApi sessionApi;
  final AuthSessionController sessions;
  final ChannelDirectoryController directory;
  final IdentityTestApi api;
  final IdentityManagementController controller;
  static Future<IdentityTestFixture> create({
    IdentityTestVault? vault,
    bool initialize = true,
    IdentityTestApi? api,
  }) async {
    final storage = vault ?? IdentityTestVault();
    final store = AuthStore(storage);
    if (initialize) {
      await store.update(
        (s) => s.copyWith(
          session: SessionRecord(
            token: identityTestToken,
            accountId: identityTestAccount,
            expiresAt: identityTestExpiry,
          ),
        ),
      );
    }
    final sessionApi = IdentityTestSessionApi();
    final directory = ChannelDirectoryController(
      repository: IdentityTestChannels(),
    );
    final sessions = AuthSessionController(
      api: sessionApi,
      store: store,
      directory: directory,
    );
    await sessions.start();
    final identityApi = api ?? IdentityTestApi();
    final controller = IdentityManagementController(
      api: identityApi,
      store: store,
      sessions: sessions,
    );
    return IdentityTestFixture(
      storage,
      store,
      sessionApi,
      sessions,
      directory,
      identityApi,
      controller,
    );
  }

  void dispose() {
    controller.dispose();
    sessions.dispose();
    directory.dispose();
    store.dispose();
  }
}
