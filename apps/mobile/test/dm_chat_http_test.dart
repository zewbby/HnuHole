import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';

import 'dm_reliability_test.dart' show Vault;
import 'support/dm_chat_scenario.dart';

void main() {
  final fixture = Platform.environment['DM_CHAT_FIXTURE'];
  test(
    'P2 real Dart TLS and SQL: images, controls, private settings and fresh store',
    () async {
      final config = Map<String, String>.from(
        jsonDecode(await File(fixture!).readAsString()),
      );
      final root = Directory.systemTemp.createTempSync('dm-p2-real-');
      final vaults = <String, Vault>{};
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(config['DM_CA']!));
      final api = HttpPostApi(
        communityBaseUri: Uri.parse('https://127.0.0.1:${config['HOST_PORT']}'),
        client: HttpClient(context: trust),
      );
      Future<DmStore> open(String account) => DmStore.open(
        File('${root.path}/${base64Url.encode(utf8.encode(account))}.sqlite'),
        'p2-host',
        account,
        vaults.putIfAbsent(account, Vault.new),
      );
      try {
        final c = await exerciseDmChat(config, api, open);
        await c.detach();
        c.dispose();
      } finally {
        api.close();
        await root.delete(recursive: true);
      }
    },
    skip: fixture == null
        ? 'requires owned real TLS/PostgreSQL P2 fixture'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
