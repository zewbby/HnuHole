import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:sqlite3/sqlite3.dart';

class _Key implements BusinessKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    expect(utf8.encode(next).length, lessThan(65536));
    if (value != null && value != next) throw const PostStorageFailure();
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File file;
  late _Key key;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'hnuhole-governance-store-',
    );
    file = File('${temporary.path}/governance.sqlite3');
    key = _Key();
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });
  GovernanceMaterialVault open({
    String environment = 'isolated|governance-v1',
    _Key? ownerKey,
  }) => GovernanceMaterialVault(
    openStore: () => PostStore.openFile(
      file,
      environment: environment,
      accountId: 'pending-owners',
      vault: ownerKey ?? key,
    ),
  );

  test('large evidence uses vault-keyed authenticated SQL chunks and restores after reopen', () async {
    final first = open();
    final value = jsonEncode({
      'private-marker': 'pending-report-material',
      'image': 'x' * (9 * 1024 * 1024),
    });
    await first.write(value);
    expect(await first.read(), value);
    await first.close();
    final disk = await file.readAsBytes();
    expect(latin1.decode(disk), isNot(contains('pending-report-material')));
    expect(key.value, isNot(contains('pending-report-material')));
    final second = open();
    expect(await second.read(), value);
    await second.write('{"v":1,"owners":{}}');
    expect(await second.read(), '{"v":1,"owners":{}}');
    await second.close();
    final database = sqlite3.open(file.path);
    try {
      expect(
        database
            .select(
              "SELECT count(*) AS n FROM post_entries WHERE state='mediaRoot'",
            )
            .single['n'],
        1,
      );
    } finally {
      database.close();
    }
  });
  test(
    'missing or different environment key does not overwrite saved material',
    () async {
      final first = open();
      await first.write('preserve-material');
      await first.close();
      final before = await file.readAsBytes();
      final missing = open(ownerKey: _Key());
      await expectLater(missing.read(), throwsA(isA<AuthStorageFailure>()));
      try {
        await missing.close();
      } on Object {
        /* Failed opening has no writable store. */
      }
      expect(await file.readAsBytes(), before);
      final wrongEnvironment = open(environment: 'another-origin');
      await expectLater(
        wrongEnvironment.read(),
        throwsA(isA<AuthStorageFailure>()),
      );
      try {
        await wrongEnvironment.close();
      } on Object {
        /* Preserve original. */
      }
      expect(await file.readAsBytes(), before);
    },
  );
}
