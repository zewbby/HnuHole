// Explicit Android-only, synthetic-account acceptance entrypoint. Credentials
// Session capabilities are injected into private files. This synthetic fixture's
// fixed login name/password are test-only constants compiled into the APK.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_mobile/src/auth/auth_store.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/auth/http_auth_api.dart';
import 'package:hnuhole_mobile/src/messaging/dm_store.dart';
import 'package:hnuhole_mobile/src/messaging/dm_controller.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

const driver = MethodChannel('hnuhole/owned_device_driver');
void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

class InterruptedApi implements DmApi {
  InterruptedApi(this.inner, this.phase);
  final HttpPostApi inner;
  final String phase;
  @override
  Future<PostResponse<Map<String, dynamic>>> dmRequest(
    String token,
    String method,
    String resource, {
    Map<String, Object>? body,
    Map<String, String>? query,
  }) async {
    if (phase == 'receive-stop' && method == 'POST' && resource == 'ack') {
      await driver.invokeMethod('stage', 'committed-before-ack');
      return Completer<PostResponse<Map<String, dynamic>>>().future;
    }
    final response = await inner.dmRequest(
      token,
      method,
      resource,
      body: body,
      query: query,
    );
    if (phase == 'send-stop' &&
        method == 'PUT' &&
        resource.startsWith('commands/')) {
      await driver.invokeMethod('stage', 'accepted-before-response');
      return Completer<PostResponse<Map<String, dynamic>>>().future;
    }
    return response;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final phase = await driver.invokeMethod<String>('phase');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text('独立私信恢复验收：$phase'))),
    ),
  );
  try {
    await exercise(phase!);
    await driver.invokeMethod('stage', 'pass-$phase');
  } catch (error) {
    // Bounded diagnostic labels only; no exception bodies or credentials.
    await driver.invokeMethod(
      'stage',
      'fail-$phase-${error.runtimeType.toString().toLowerCase()}',
    );
    if (error is StateError) {
      runApp(MaterialApp(home: Scaffold(body: Text('验收断言：${error.message}'))));
    }
  }
}

Future<void> exercise(String phase) async {
  final config = Map<String, String>.from(
    jsonDecode(
      await File(
        '/data/user/0/org.hnuhole.hnuhole_mobile.dmrecovery/files/dm-recovery-fixture.json',
      ).readAsString(),
    ),
  );
  final trust = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(config['DM_CA']!));
  final origin = Uri.parse(config['DM_ORIGIN']!);
  final api = HttpPostApi(
    communityBaseUri: origin,
    client: HttpClient(context: trust),
  );
  final auth = HttpAuthApi(
    communityBaseUri: origin,
    verifierBaseUri: Uri.parse('https://127.0.0.1:58445'),
    client: HttpClient(context: trust),
  );
  final vault = FlutterAuthVault(namespace: 'dm.recovery.acceptance');
  final saved = await vault.read();
  final state = saved == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(jsonDecode(saved));
  final account = config['DM_ACCOUNT_B']!,
      own = config['DM_IDENTITY_B']!,
      peer = config['DM_IDENTITY_A']!;
  final conv = config['DM_CONVERSATION']!;
  final environment = 'dm-recovery:${config['DM_ACCOUNT_A']}';
  Future<void> persist() => vault.write(jsonEncode(state));
  if (['old-prime', 'new-takeover', 'old-retake'].contains(phase)) {
    state['installation'] ??= AuthCrypto.randomEncoded(16);
    final session = await auth.login(
      username: 'dm_chat_device_receiver',
      password: 'separate-community-privacy-audit-password',
      installationId: state['installation'],
      idempotencyKey: AuthCrypto.randomEncoded(32),
    );
    check(session.accountId == account, 'login-account');
    state['token'] = session.sessionToken;
    await persist();
  }
  final token = state['token'] as String;
  if (phase == 'old-prime') {
    final bytes = base64Decode(config['DM_IMAGE']!);
    final mediaId = dmId();
    final receipt = (await api.dmRequest(
      config['DM_TOKEN_A']!,
      'PUT',
      'chat/images/${dmId()}',
      body: {
        'identityId': peer,
        'peerId': own,
        'conversationId': conv,
        'attempt': 1,
        'groupId': dmId(),
        'groupSize': 1,
        'position': 0,
        'mediaId': mediaId,
        'sha256': hashes.sha256.convert(bytes).toString(),
        'byteLength': bytes.length,
        'mimeType': 'image/png',
        'width': 7,
        'height': 5,
        'data': base64Encode(bytes),
      },
    )).value;
    check(receipt['state'] == 'SENT', 'image-prime');
    state['oldImage'] = mediaId;
    await persist();
  }
  if (phase == 'old-replaced' || phase == 'new-replaced') {
    var denied = false;
    final c = DmController(
      api: api,
      chatEnabled: true,
      openStore: (a) => DmStore.openNative(environment, a),
      onUnauthorized: (_, __) {
        denied = true;
      },
    );
    await c.bind(
      account: account,
      token: token,
      identities: [own],
      isCurrent: () => true,
    );
    check(denied && !c.available, 'replacement-hidden');
    await c.detach();
    c.dispose();
    api.close();
    auth.close();
    return;
  }
  if (phase == 'old-prime' ||
      phase == 'receive-stop' ||
      phase == 'new-takeover') {
    final label = phase == 'old-prime'
        ? 'device-old-history'
        : 'crash-inbound-once';
    final receipt = (await api.dmRequest(
      config['DM_TOKEN_A']!,
      'PUT',
      'commands/${dmId()}',
      body: {
        'identityId': peer,
        'peerId': own,
        'conversationId': conv,
        'sourcePostId': '',
        'sourceCommentId': '',
        'text': label,
        'attempt': 1,
      },
    )).value;
    check(receipt['state'] == 'SENT', 'peer-send');
    state['lastInboundId'] = receipt['messageId'];
    await persist();
  }
  if (phase == 'send-stop') {
    final store = await DmStore.openNative(environment, account);
    await store.reconcileIdentities([own]);
    state['outboundCommand'] = await store.enqueue({
      'identityId': own,
      'peerId': peer,
      'conversationId': conv,
      'sourcePostId': '',
      'sourceCommentId': '',
      'text': 'crash-outbound-once',
      'attempt': 1,
    });
    await persist();
    await store.close();
  }
  final c = DmController(
    api: InterruptedApi(api, phase),
    chatEnabled: true,
    openStore: (a) => DmStore.openNative(environment, a),
  );
  await c.bind(
    account: account,
    token: token,
    identities: [own],
    isCurrent: () => true,
  );
  check(c.available && c.error == null, 'controller-ready');
  final rows = await c.history(own, peer);
  if (phase == 'new-takeover') {
    check(
      !rows.any((r) => r['text'] == 'device-old-history'),
      'no-cloud-old-history',
    );
    check(c.conversations.any((r) => r['id'] == conv), 'directory-restored');
    final row = c.conversations.firstWhere((r) => r['id'] == conv);
    check(row['note'] == 'device-private-note', 'note-restored');
    check((row['unavailableUnread'] as int) > 0, 'unread-not-falsely-cleared');
  }
  if (phase == 'old-prime') {
    check(
      rows.any((r) => r['text'] == 'device-old-history'),
      'old-history-present',
    );
    await c.manage(
      c.conversations.firstWhere((r) => r['id'] == conv),
      'SETTINGS',
      note: 'device-private-note',
    );
    check(await c.saveDraft(own, peer, 'device-unsent-draft'), 'draft-saved');
  }
  if (phase == 'old-retake' || phase == 'reboot-recover') {
    final photo = await c.photo(state['oldImage'], senderId: peer);
    check(
      hashes.sha256.convert(photo).toString() ==
          hashes.sha256.convert(base64Decode(config['DM_IMAGE']!)).toString(),
      'native-image-survives',
    );
    check(
      rows.any((r) => r['text'] == 'device-old-history'),
      'native-history-survives',
    );
    check(
      await c.draft(own, peer) == 'device-unsent-draft',
      'native-draft-survives',
    );
  }
  if (phase == 'receive-recover') {
    check(
      rows.where((r) => r['messageId'] == state['lastInboundId']).length == 1,
      'inbound-deduplicated',
    );
    final pending =
        (await api.dmRequest(token, 'GET', 'chat/pending')).value['items']
            as List;
    check(
      !pending.any((r) => r['messageId'] == state['lastInboundId']),
      'recovered-ack',
    );
  }
  if (phase == 'send-recover') {
    final command = state['outboundCommand'] as String;
    final receipt = (await api.dmRequest(
      token,
      'GET',
      'commands/$command',
    )).value;
    check(
      receipt['state'] == 'SENT' && receipt['attempt'] == 1,
      'original-command-retained',
    );
    check(
      rows
              .where((r) => r['receipt']?['messageId'] == receipt['messageId'])
              .length ==
          1,
      'outbound-deduplicated',
    );
  }
  await c.detach();
  c.dispose();
  api.close();
  auth.close();
}
