import 'dart:typed_data';

enum IdentityOperation { create, rename, delete, avatar }

class ManagedIdentity {
  const ManagedIdentity({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.isOriginal,
    required this.createdAt,
    this.renameAvailableAt,
  });
  final String id, nickname, avatar;
  final bool isOriginal;
  final DateTime createdAt;
  final DateTime? renameAvailableAt;
}

/// Dates and counts are server authority, never recomputed with the phone clock.
class IdentityDirectory {
  /// The identity contract and C enforce this maximum; cooling down is separate.
  static const maximumIdentities = 3;
  const IdentityDirectory({
    required this.identities,
    required this.createdCount,
    required this.serverTime,
    required this.sessionExpiresAt,
    this.nextCreateAt,
  });
  final List<ManagedIdentity> identities;
  final int createdCount;
  final DateTime serverTime, sessionExpiresAt;
  final DateTime? nextCreateAt;
  bool get creationCoolingDown =>
      nextCreateAt != null && nextCreateAt!.isAfter(serverTime);
  bool get canCreate =>
      identities.length < maximumIdentities && !creationCoolingDown;
  bool canRename(ManagedIdentity identity) =>
      identity.renameAvailableAt == null ||
      !identity.renameAvailableAt!.isAfter(serverTime);
}

class IdentityChangeOutcome {
  const IdentityChangeOutcome({
    required this.committed,
    required this.sessionExpiresAt,
    this.operation,
    this.identityId,
    this.errorCode,
  });
  final bool committed;
  final IdentityOperation? operation;
  final String? identityId;
  final String? errorCode;
  bool get rejected => errorCode != null;
  final DateTime sessionExpiresAt;
}

abstract interface class IdentityApi {
  Future<IdentityDirectory> identities(String sessionToken);
  Future<IdentityChangeOutcome> changeIdentity({
    required String sessionToken,
    required String idempotencyKey,
    required IdentityOperation operation,
    String? identityId,
    String? nickname,
    String? avatar,
  });
  Future<IdentityChangeOutcome> identityChangeResult({
    required String sessionToken,
    required String idempotencyKey,
  });
}

bool validIdentityAvatar(Object? value) =>
    value is String &&
    (value == 'default-v1' ||
        RegExp(
              r'^avatar-v1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(value) &&
            value != 'avatar-v1:00000000-0000-0000-0000-000000000000');

class IdentityAvatarResult {
  const IdentityAvatarResult({
    required this.avatar,
    required this.sessionExpiresAt,
    this.bytes,
  });
  final String avatar;
  final DateTime sessionExpiresAt;
  final Uint8List? bytes;
}

abstract interface class IdentityAvatarApi {
  Future<IdentityAvatarResult> uploadIdentityAvatar({
    required String sessionToken,
    required String assetId,
    required Uint8List bytes,
    required String mime,
  });
  Future<IdentityAvatarResult> readIdentityAvatar({
    required String sessionToken,
    required String avatar,
  });
  Future<DateTime> abandonIdentityAvatar({
    required String sessionToken,
    required String avatar,
  });
}
