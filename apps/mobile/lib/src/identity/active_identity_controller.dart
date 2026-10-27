import 'package:flutter/foundation.dart';

import 'identity_management_controller.dart';

/// One active browsing identity for the authenticated account. Submitted tasks
/// and existing post/conversation bindings keep their original identities.
class ActiveIdentityController extends ChangeNotifier {
  ActiveIdentityController(this.management) {
    management.addListener(_changed);
    _changed();
  }
  final IdentityManagementController management;
  Object? _owner;
  String? _selectedId;
  Set<String> _ids = {};
  String? get selectedId => _selectedId;
  Object? get owner => _owner;
  String? get accountId => switch (_owner) {
    (String id, _, _) => id,
    _ => null,
  };
  bool selectConfirmed(
    String id,
    Iterable<String> ownIds, {
    required String? account,
  }) {
    if (account == null ||
        account != accountId ||
        management.authorityKey != _owner ||
        !ownIds.contains(id)) {
      return false;
    }
    _ids.add(id);
    return select(id);
  }

  bool select(String id) {
    if (_owner == null || !_ids.contains(id)) return false;
    if (_selectedId == id) return true;
    _selectedId = id;
    notifyListeners();
    return true;
  }

  void _changed() {
    var changed = false;
    final owner = management.authorityKey;
    if (owner != _owner) {
      _owner = owner;
      _ids = {};
      _selectedId = null;
      changed = true;
    }
    final directory = management.directory;
    if (owner != null &&
        directory != null &&
        management.status == IdentityManagementStatus.ready) {
      _ids = {for (final identity in directory.identities) identity.id};
      if (!_ids.contains(_selectedId)) {
        final selected =
            directory.identities.where((i) => i.isOriginal).firstOrNull ??
            directory.identities.firstOrNull;
        final next = selected?.id;
        changed = changed || next != _selectedId;
        _selectedId = next;
      }
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    management.removeListener(_changed);
    super.dispose();
  }
}
