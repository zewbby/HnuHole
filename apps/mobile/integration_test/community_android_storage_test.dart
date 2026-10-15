import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_auth_vault/hnuhole_auth_vault.dart';
import 'package:hnuhole_mobile/src/storage/post_store.dart';
import 'package:integration_test/integration_test.dart';

/// Synthetic local fixtures through the real registered plugins and PostStore.
/// No session is minted, HTTP called, or authoritative account closure claimed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const driver = MethodChannel('hnuhole/owned_device_driver');
  const run = String.fromEnvironment('COMMUNITY_STORAGE_RUN_ID');
  testWidgets('owned native storage across actual Android processes', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    expect(RegExp(r'^community-storage-[0-9a-f]{16}$').hasMatch(run), isTrue);
    final phase = await driver.invokeMethod<String>('phase');
    expect(
      {
        'storage-write',
        'storage-read',
        'storage-reboot-read',
        'storage-purge',
        'storage-closed',
      }.contains(phase),
      isTrue,
    );
    final device = await driver.invokeMapMethod<String, dynamic>('deviceState');
    expect(device!['pid'], greaterThan(0));
    const environment = 'https://$run.invalid';
    final aScope = PostStore.scopeFor(environment, 'synthetic-account-a');
    final bScope = PostStore.scopeFor(environment, 'synthetic-account-b');
    final aVault = DurableBusinessVault(aScope);
    final bVault = DurableBusinessVault(bScope);
    final auth = DurableAuthVault('$run.auth');
    final authState = jsonEncode({
      'synthetic': true,
      'phase': 'revocation_pending',
      'run': run,
    });
    final aData = <String, dynamic>{
      'title': '原生持久草稿',
      'body': '中文\n换行🙂',
      'identityId': 'fixed-identity',
      'channelId': 'fixed-channel',
    };
    final intent = StoredPostIntent(
      commandId: '$run-original-command',
      operation: 'CREATE',
      digest: '$run-original-digest',
      payload: aData,
    );
    PostStore? a;
    PostStore? b;
    final flags = <String, bool>{};
    Future<PostStore> open(String account) => PostStore.openNative(
      environment: environment,
      accountId: 'synthetic-account-$account',
    );
    Future<void> checkB() async {
      b = await open('b');
      expect((await b!.list()).length, 1);
      expect((await b!.get('b-draft'))!.data['body'], '另一账号草稿');
      expect(await b!.get('a-draft'), isNull);
      expect(await b!.get('a-command'), isNull);
      flags['otherAccountPreserved'] = true;
    }

    try {
      if (phase == 'storage-write') {
        expect(await auth.read(), isNull);
        // The run ID is fixed at build time and every execution is latched by
        // the host runner. Never purge or overwrite an uncertain prior run.
        expect(await aVault.read(), isNull);
        expect(await bVault.read(), isNull);
        await auth.write(authState);
        a = await open('a');
        b = await open('b');
        expect(await a.list(), isEmpty);
        expect(await b!.list(), isEmpty);
        await a.createDraft('a-draft', aData);
        await a.createDraft('a-command', aData);
        await a.submitDraft('a-command', 1, intent, aData);
        await b!.createDraft('b-draft', {'body': '另一账号草稿'});
        flags['durableWritesAcknowledged'] = true;
      } else {
        expect(await auth.read(), authState);
        flags['nativeAuthRecordPreserved'] = true;
        await checkB();
        if (phase == 'storage-closed') {
          await expectLater(open('a'), throwsA(isA<PostStorageFailure>()));
          await expectLater(aVault.read(), throwsA(isA<PlatformException>()));
          // The marker remains durable; its exact contents and lack of files
          // are also inspected inside the native 7-test suite.
          final bPath = await bVault.databasePath();
          final root = File(bPath).parent;
          expect(await File('${root.path}/$aScope.closed').exists(), isTrue);
          for (final suffix in [
            '.auth',
            '.sqlite3',
            '.sqlite3-journal',
            '.sqlite3-wal',
            '.sqlite3-shm',
          ]) {
            expect(await File('${root.path}/$aScope$suffix').exists(), isFalse);
          }
          flags['closedMarkerSurvivesNewProcess'] = true;
          flags['closedKeyAndDatabaseFilesAbsent'] = true;
        } else {
          a = await open('a');
          expect((await a.list()).length, 2);
          expect((await a.get('a-draft'))!.data, aData);
          expect(await a.get('b-draft'), isNull);
          final command = (await a.get('a-command'))!;
          expect(command.state, 'submitted');
          expect(command.intents.single.toJson(), intent.toJson());
          flags['draftAndOriginalIntentRestored'] = true;
          if (phase == 'storage-purge') {
            await a.close();
            a = null;
            await PostStore.purgeNativeClosedAccount(
              environment: environment,
              accountId: 'synthetic-account-a',
            );
            // This is local adapter cleanup using synthetic fixtures, not
            // evidence that the server authorized CLOSED (task 1 covers that).
            await expectLater(open('a'), throwsA(isA<PostStorageFailure>()));
            expect(await auth.read(), authState);
            flags['nativeLocalPurgeCompleted'] = true;
          }
        }
      }
      await a?.close();
      a = null;
      await b?.close();
      b = null;
      if (phase != 'storage-purge' && phase != 'storage-closed') {
        final path = await aVault.databasePath();
        expect(path, contains('/no_backup/hnuhole-business-v1/'));
        final bytes = await File(path).readAsBytes();
        expect(ascii.decode(bytes.take(16).toList()), 'SQLite format 3\u0000');
        final disk = latin1.decode(bytes);
        for (final value in [
          aData['body'] as String,
          aData['title'] as String,
          intent.commandId,
          intent.digest,
        ]) {
          expect(disk, isNot(contains(latin1.decode(utf8.encode(value)))));
        }
        flags['realSqliteWithoutPayloadPlaintext'] = true;
      }
      binding.reportData = {
        'phase': phase,
        'pid': device['pid'],
        'flags': flags,
        'nativeVault': true,
        'nativeBusinessSqlite': true,
        'syntheticFixturesOnly': true,
        'actualMainCalled': false,
        'systemPasskeyCeremony': false,
        'manualImeVerified': false,
      };
    } finally {
      await a?.close();
      await b?.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
