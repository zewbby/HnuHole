import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/messaging/dm_protocol.dart';
import 'package:hnuhole_mobile/src/posts/http_post_api.dart';
import 'package:hnuhole_mobile/src/system_notifications/governance_api.dart';

void main() {
  final fixture = Platform.environment['DM_CHAT_FIXTURE'];
  test(
    'real Dart TLS/SQL: block, accepted-before-block delivery, immutable ACKed report and notification receipt',
    () async {
      final config = Map<String, String>.from(
        jsonDecode(await File(fixture!).readAsString()),
      );
      final trust = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(config['DM_CA']!));
      final origin = Uri.parse('https://127.0.0.1:${config['HOST_PORT']}');
      final api = HttpPostApi(
        communityBaseUri: origin,
        client: HttpClient(context: trust),
      );
      final governance = HttpGovernanceApi(
        baseUri: origin,
        client: HttpClient(context: trust),
      );
      final a = config['DM_TOKEN_A']!,
          b = config['DM_TOKEN_B']!,
          ia = config['DM_IDENTITY_A']!,
          ib = config['DM_IDENTITY_B']!,
          conv = config['DM_CONVERSATION']!;
      try {
        final command = dmId();
        expect(
          (await api.dmRequest(a, 'GET', 'commands/$command')).value['state'],
          'ABSENT',
        );
        final text = {
          'identityId': ia,
          'peerId': ib,
          'conversationId': conv,
          'sourcePostId': '',
          'sourceCommentId': '',
          'text': 'P3固定证据，平台受理后允许落地',
          'attempt': 1,
        };
        final sent = (await api.dmRequest(
          a,
          'PUT',
          'commands/$command',
          body: text,
        )).value;
        expect(sent['state'], 'SENT');
        expect(sent['evidenceVersion'], 1);
        final block = dmId();
        expect(
          (await api.dmRequest(
            b,
            'PUT',
            'governance/blocks/$block',
            body: {'identityId': ib, 'conversationId': conv, 'blocked': true},
          )).value['state'],
          'APPLIED',
        );
        final blocks =
            (await api.dmRequest(b, 'GET', 'governance/blocks')).value['items']
                as List;
        expect(blocks.length, 1);
        expect(blocks.single['peerId'], ia);
        expect(blocks.single['conversationId'], conv);
        final directory =
            (await api.dmRequest(
                  a,
                  'GET',
                  'chat/conversations',
                  query: {'identityId': ia},
                )).value['items']
                as List;
        expect(directory.single['canSend'], false);
        final denied = (await api.dmRequest(
          a,
          'PUT',
          'commands/${dmId()}',
          body: {...text, 'text': '拉黑后不应受理'},
        )).value;
        expect(denied['state'], 'FAILED');
        expect(denied['errorCode'], 'CONTACT_UNAVAILABLE');
        final pending =
            (await api.dmRequest(b, 'GET', 'chat/pending')).value['items']
                as List;
        final delivered = pending.singleWhere(
          (r) => r['messageId'] == sent['messageId'],
        );
        expect(delivered['text'], text['text']);
        expect(delivered['evidenceVersion'], 1);
        await api.dmRequest(
          b,
          'POST',
          'ack',
          body: {
            'messageIds': [sent['messageId']],
          },
        );
        final id = dmId(), path = '/api/v1/dm/governance/reports/';
        final snapshot = <String, dynamic>{
          'identityId': ib,
          'conversationId': conv,
          'firstSequence': sent['sequence'],
          'lastSequence': sent['sequence'],
          'reason': 'HARASSMENT',
          'description': '合成验收证据',
          'images': <Object>[],
          'authorized': true,
          'entries': [
            {
              'messageId': sent['messageId'],
              'sequence': sent['sequence'],
              'kind': 'TEXT',
              'text': text['text'],
              'data': '',
              'gap': '',
            },
          ],
        };
        // Preview has already been fixed. Retraction cannot silently replace it.
        final retract = dmId();
        await api.dmRequest(
          a,
          'PUT',
          'chat/operations/$retract',
          body: {
            'identityId': ia,
            'conversationId': conv,
            'operation': 'RETRACT',
            'expectedVersion': 0,
            'messageId': sent['messageId'],
          },
        );
        final submitted = (await governance.request(
          b,
          'PUT',
          '$path$id',
          body: snapshot,
        )).value;
        expect(submitted['state'], 'SUBMITTED');
        expect(submitted['report']['conversationId'], conv);
        expect(submitted['report']['postId'], '');
        final original = (await governance.request(b, 'GET', '$path$id')).value;
        expect(original['report']['id'], id);
        expect(
          (await governance.request(
            b,
            'PUT',
            '$path$id',
            body: snapshot,
          )).value['report']['caseId'],
          original['report']['caseId'],
        );
        final notices =
            (await governance.request(
                  b,
                  'GET',
                  '/api/v1/system-notifications',
                  query: {'identityId': ib},
                )).value['items']
                as List;
        expect(
          notices.any(
            (v) =>
                v['route']['name'] == 'REPORT' &&
                v['route']['resourceId'] == id,
          ),
          true,
        );
        final stranger = config['DM_TOKEN_C']!;
        final foreign = (await governance.request(
          stranger,
          'GET',
          '/api/v1/reports/$id',
        )).value;
        expect(foreign['state'], 'NOT_SUBMITTED');
        expect(foreign.containsKey('report'), false);
        final absent = dmId();
        final sealed = (await governance.request(
          b,
          'GET',
          '$path$absent',
        )).value;
        expect(sealed['state'], 'NOT_SUBMITTED');
        expect(sealed['retryToken'], isA<String>());
        await expectLater(
          governance.request(b, 'PUT', '$path$absent', body: snapshot),
          throwsA(isA<GovernanceFailure>()),
        );
        expect(
          (await governance.request(
            b,
            'PUT',
            '$path$absent',
            body: {...snapshot, 'retryToken': sealed['retryToken']},
          )).value['state'],
          'SUBMITTED',
        );
        await api.dmRequest(
          b,
          'PUT',
          'governance/blocks/${dmId()}',
          body: {'identityId': ib, 'conversationId': conv, 'blocked': false},
        );
        expect(
          (await api.dmRequest(
            a,
            'PUT',
            'commands/${dmId()}',
            body: {...text, 'text': '明确解除后可发送'},
          )).value['state'],
          'SENT',
        );
      } finally {
        api.close();
        governance.close();
      }
    },
    skip: fixture == null
        ? 'requires owned real TLS/PostgreSQL P3 fixture'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
