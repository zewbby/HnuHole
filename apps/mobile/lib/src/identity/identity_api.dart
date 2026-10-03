enum IdentityOperation { create, rename, delete }

class ManagedIdentity {
  const ManagedIdentity({required this.id, required this.nickname,
    required this.avatar, required this.isOriginal, required this.createdAt,
    this.renameAvailableAt});
  final String id, nickname, avatar;
  final bool isOriginal;
  final DateTime createdAt;
  final DateTime? renameAvailableAt;
}

/// Dates and counts are server authority, never recomputed with the phone clock.
class IdentityDirectory {
  const IdentityDirectory({required this.identities, required this.createdCount,
    required this.serverTime, required this.sessionExpiresAt, this.nextCreateAt});
  final List<ManagedIdentity> identities;
  final int createdCount;
  final DateTime serverTime, sessionExpiresAt;
  final DateTime? nextCreateAt;
  bool get creationCoolingDown =>
      nextCreateAt != null && nextCreateAt!.isAfter(serverTime);
  bool get canCreate => identities.length < 3 && !creationCoolingDown;
  bool canRename(ManagedIdentity identity) => identity.renameAvailableAt == null ||
      !identity.renameAvailableAt!.isAfter(serverTime);
}

class IdentityChangeOutcome {
  const IdentityChangeOutcome({required this.committed,
    required this.sessionExpiresAt, this.operation, this.identityId, this.errorCode});
  final bool committed;
  final IdentityOperation? operation;
  final String? identityId;
  final String? errorCode;
  bool get rejected => errorCode != null;
  final DateTime sessionExpiresAt;
}

abstract interface class IdentityApi {
  Future<IdentityDirectory> identities(String sessionToken);
  Future<IdentityChangeOutcome> changeIdentity({required String sessionToken,
    required String idempotencyKey, required IdentityOperation operation,
    String? identityId, String? nickname});
  Future<IdentityChangeOutcome> identityChangeResult({required String sessionToken,
    required String idempotencyKey});
}
