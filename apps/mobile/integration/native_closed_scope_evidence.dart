import 'dart:io';

import 'package:hnuhole_mobile/src/storage/post_store.dart';

/// Test-only independent file evidence for the native plugin's opaque refusal.
/// The path must have been obtained from the same live scope before closure.
Future<bool> nativeClosedScopeEvidence(String databasePath) async {
  final database = File(databasePath);
  final name = database.uri.pathSegments.last;
  if (!RegExp(r'^[0-9a-f]{64}\.sqlite3$').hasMatch(name)) return false;
  final scope = name.substring(0, name.length - '.sqlite3'.length);
  final prefix = '${database.parent.path}/$scope';
  try {
    final marker = File('$prefix.closed');
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    final bytes = await marker.readAsBytes();
    if (bytes.length != 1 || bytes.single != 1) return false;
    for (final suffix in [
      '.sqlite3',
      '.sqlite3-journal',
      '.sqlite3-wal',
      '.sqlite3-shm',
      '.auth',
      '.auth.bak',
      '.auth.new',
    ]) {
      if (await FileSystemEntity.type('$prefix$suffix', followLinks: false) !=
          FileSystemEntityType.notFound) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

Future<bool> nativeClosedScopeRejectsReopen(
  String databasePath,
  Future<void> Function() reopen,
) async {
  if (!await nativeClosedScopeEvidence(databasePath)) return false;
  try {
    await reopen();
    return false;
  } on PostStorageFailure {
    // A generic I/O failure alone never proves closure. Recheck the independent
    // marker and absence of every database/key artifact after the refusal.
    return nativeClosedScopeEvidence(databasePath);
  }
}
