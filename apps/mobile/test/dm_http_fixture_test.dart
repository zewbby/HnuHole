import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/posts/post_api.dart';

// Explicit owned fixture only. No capabilities or development certificates are
// embedded in source; this does not substitute for Android Keystore acceptance.
void main() {
  final fixturePath = Platform.environment['DM_HOST_FIXTURE'];
  test(
    'real Dart HTTPS transport interoperates with the PostgreSQL DM fixture',
    () async {
      final f = jsonDecode(
        await File(fixturePath!).readAsString(),
      ) as Map<String, dynamic>;
      final context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(f['DM_CA'] as String));
      final api = HttpPostApi(
        communityBaseUri: Uri.parse(f['DM_ORIGIN'] as String)
            .replace(port: int.parse(f['HOST_PORT'] as String)),
        client: HttpClient(context: context),
      );
      addTearDown(api.close);
      final a = f['DM_TOKEN_A'] as String, b = f['DM_TOKEN_B'] as String;
      final own = f['DM_IDENTITY_A'] as String,
          peer = f['DM_IDENTITY_B'] as String;
      final contact = await api.dmRequest(
        a,
        'GET',
        'contact',
        query: {'postId': f['DM_POST'] as String},
      );
      expect(contact.value['peerId'], peer);
      final resource = 'commands/${dmId()}';
      await expectLater(
        api.dmRequest(
          a,
          'PUT',
          resource,
          body: {
            'identityId': own,
            'peerId': peer,
            'conversationId': '',
            'sourcePostId': f['DM_POST'] as String,
            'sourceCommentId': '',
            'text': '严格 Dart HTTPS 联调',
            'attempt': 1,
          },
        ),
        throwsA(
          isA<PostFailure>().having(
            (e) => e.kind,
            'kind',
            PostFailureKind.transport,
          ),
        ),
      );
      final receipt = await api.dmRequest(a, 'GET', resource);
      expect(receipt.value['state'], 'SENT');
      final pending = await api.dmRequest(b, 'GET', 'pending');
      final message = (pending.value['items'] as List).single as Map;
      expect(message['text'], '严格 Dart HTTPS 联调');
      expect(message['messageId'], receipt.value['messageId']);
      final ids = <String, Object>{
        'messageIds': [message['messageId']],
      };
      await api.dmRequest(b, 'POST', 'ack', body: ids);
      expect(
        (await api.dmRequest(b, 'GET', 'pending')).value['items'],
        isEmpty,
      );
      Future<int> unread() async =>
          (((await api.dmRequest(
                            b,
                            'GET',
                            'conversations',
                            query: {'identityId': peer},
                          )).value['items']
                          as List)
                      .single
                  as Map)['unread']
              as int;
      expect(await unread(), 1);
      await api.dmRequest(b, 'POST', 'read', body: ids);
      expect(await unread(), 0);
    },
    skip: fixturePath == null
        ? 'Set DM_HOST_FIXTURE to an exclusive TestDMDevicePostgres fixture'
        : false,
  );
}
