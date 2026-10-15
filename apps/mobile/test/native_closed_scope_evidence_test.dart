import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';

import '../integration/native_closed_scope_evidence.dart';

void main() {
  late Directory directory;
  late String prefix;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('closed-evidence-');
    prefix = '${directory.path}/${'a' * 64}';
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<bool> refuses() => nativeClosedScopeRejectsReopen(
    '$prefix.sqlite3',
    () async => throw const PostStorageFailure(),
  );
  test(
    'ordinary storage error without exact marker cannot prove closure',
    () async {
      expect(await refuses(), isFalse);
      for (final bytes in [
        <int>[],
        [0],
        [1, 1],
      ]) {
        await File('$prefix.closed').writeAsBytes(bytes);
        expect(await refuses(), isFalse);
      }
    },
  );
  test(
    'every residual database or auth artifact rejects closed evidence',
    () async {
      await File('$prefix.closed').writeAsBytes([1]);
      for (final suffix in [
        '.sqlite3',
        '.sqlite3-journal',
        '.sqlite3-wal',
        '.sqlite3-shm',
        '.auth',
        '.auth.bak',
        '.auth.new',
      ]) {
        final residual = File('$prefix$suffix');
        await residual.writeAsBytes([0]);
        expect(await refuses(), isFalse);
        await residual.delete();
      }
    },
  );
  test(
    'exact durable marker and absence plus opaque native refusal prove closure',
    () async {
      await File('$prefix.closed').writeAsBytes([1]);
      expect(await refuses(), isTrue);
      expect(
        await nativeClosedScopeRejectsReopen('$prefix.sqlite3', () async {}),
        isFalse,
      );
    },
  );
  test(
    'successful reopen or new artifacts during refusal never pass',
    () async {
      await File('$prefix.closed').writeAsBytes([1]);
      expect(
        await nativeClosedScopeRejectsReopen('$prefix.sqlite3', () async {
          await File('$prefix.auth').writeAsBytes([0]);
          throw const PostStorageFailure();
        }),
        isFalse,
      );
    },
  );
  test('directory marker and malformed scope paths are rejected', () async {
    await Directory('$prefix.closed').create();
    expect(await refuses(), isFalse);
    expect(
      await nativeClosedScopeEvidence('${directory.path}/other.sqlite3'),
      isFalse,
    );
  });
}
