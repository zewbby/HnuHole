// Pure Dart VM transport probe for the isolated Go C/V/TLS/PostgreSQL harness.
// Usage: dart --packages=<mobile package_config> governance_live_probe.dart
//        <private fixture.json> <report|appeal|result|limited> <result.json>
import 'dart:convert';
import 'dart:io';

import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';
import 'package:hnuhole_mobile/src/system_notifications/governance_api.dart';
import 'package:hnuhole_mobile/src/system_notifications/notification_models.dart';

class _Check implements Exception {
  const _Check(this.name);
  final String name;
}

void _check(bool condition, String name) {
  if (!condition) throw _Check(name);
}

Map<String, dynamic> _object(Object? value, String name) {
  _check(value is Map<String, dynamic>, name);
  return value as Map<String, dynamic>;
}

String _string(Map<String, dynamic> value, String key) {
  _check(
    value[key] is String && (value[key] as String).isNotEmpty,
    'missing_$key',
  );
  return value[key] as String;
}

String _uuid(Object? value) {
  _check(
    value is String &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(value) &&
        value != '00000000-0000-0000-0000-000000000000',
    'invalid_resource_id',
  );
  return value as String;
}

void _privateFields(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      _check(
        !{
          'email',
          'accountId',
          'targetAccountId',
          'reporterAccountId',
          'reporterIdentityId',
          'platformNumber',
          'originalActorNumber',
          'eligibilitySlot',
          'identities',
        }.contains(entry.key),
        'private_field_in_self_response',
      );
      _privateFields(entry.value);
    }
  } else if (value is List) {
    for (final entry in value) {
      _privateFields(entry);
    }
  }
}

class _Probe {
  _Probe(this.api, this.fixture);
  final HttpGovernanceApi api;
  final Map<String, dynamic> fixture;
  String step = 'start';
  String get reporter => _string(fixture, 'reporterToken');
  String get owner => _string(fixture, 'ownerToken');
  String get identity => _uuid(fixture['reporterIdentityId']);
  String get post => _uuid(fixture['postId']);
  String get sanction => _uuid(fixture['sanctionId']);
  String get appeal => _uuid(fixture['appealId']);
  Future<Map<String, dynamic>> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final response = await api.request(
      token,
      method,
      path,
      body: body,
      query: query,
    );
    _check(response.expiresAt.isUtc, 'missing_session_metadata');
    _privateFields(response.value);
    return response.value;
  }

  Future<void> denied(
    Future<Object?> Function() call,
    Set<int> statuses, {
    String? code,
  }) async {
    try {
      await call();
    } on GovernanceFailure catch (error) {
      _check(statuses.contains(error.status), 'wrong_rejection_status');
      if (code != null) _check(error.code == code, 'wrong_rejection_code');
      return;
    }
    throw const _Check('unauthorized_operation_succeeded');
  }

  Future<List<SystemNotice>> notices(
    String token,
    String? identityId, {
    bool open = false,
  }) async {
    final query = {
      if (identityId != null) 'identityId': identityId,
      'limit': '50',
    };
    final page = await request(
      token,
      'GET',
      '/api/v1/system-notifications',
      query: query,
    );
    _check(page['items'] is List, 'missing_notification_items');
    final result = <SystemNotice>[];
    for (final raw in page['items'] as List) {
      final notice = SystemNotice.parse(raw);
      final original = _object(raw, 'invalid_notice');
      _check(
        notice.eventId == original['eventId'] &&
            notice.source == original['source'] &&
            notice.scope == original['scope'] &&
            notice.kind == original['kind'] &&
            notice.state == original['state'] &&
            notice.identityId == original['identityId'] &&
            notice.route.name == (original['route'] as Map)['name'] &&
            notice.route.resourceId == (original['route'] as Map)['resourceId'],
        'notification_metadata_lost',
      );
      _check(
        notice.scope == 'ACCOUNT' || notice.identityId == identityId,
        'cross_identity_notice',
      );
      result.add(notice);
      if (open) {
        final scopeQuery = identityId == null
            ? null
            : {'identityId': identityId};
        final detail = SystemNotice.parse(
          await request(
            token,
            'GET',
            '/api/v1/system-notifications/${notice.id}',
            query: scopeQuery,
          ),
        );
        _check(
          detail.id == notice.id &&
              detail.eventId == notice.eventId &&
              detail.identityId == notice.identityId,
          'wrong_notification_detail',
        );
        final read = SystemNotice.parse(
          await request(
            token,
            'POST',
            '/api/v1/system-notifications/${notice.id}/read',
            query: scopeQuery,
            body: {},
          ),
        );
        _check(
          read.id == notice.id &&
              read.eventId == notice.eventId &&
              read.readAt != null &&
              read.createdAt == notice.createdAt &&
              read.route.resourceId == notice.route.resourceId,
          'wrong_notification_read_receipt',
        );
      }
    }
    _check(
      page['nextBefore'] == null || page['nextBefore'] is String,
      'invalid_notification_cursor',
    );
    return result;
  }

  Map<String, dynamic> reportReceipt(Map<String, dynamic> value, String id) {
    _check(value['state'] == 'SUBMITTED', 'report_not_submitted');
    final report = _object(value['report'], 'missing_report');
    _check(
      report['id'] == id &&
          report['postId'] == post &&
          report['reason'] == 'OTHER' &&
          report['description'] == '合成举报联调材料',
      'report_receipt_mismatch',
    );
    _uuid(report['caseId']);
    _check(
      {'PENDING', 'PROCESSING', 'ENDED'}.contains(report['state']),
      'report_state_invalid',
    );
    return report;
  }

  Map<String, dynamic> appealReceipt(Map<String, dynamic> value) {
    _uuid(value['id']);
    _uuid(value['caseId']);
    _check(
      value['sanctionId'] == sanction &&
          value['version'] is int &&
          (value['version'] as int) >= 1 &&
          value['ordinal'] is int &&
          (value['ordinal'] as int) >= 1 &&
          (value['ordinal'] as int) <= 3 &&
          {'PENDING', 'ACCEPTED', 'REJECTED'}.contains(value['state']) &&
          value['materials'] is List,
      'invalid_appeal_dto',
    );
    _check(
      !value.containsKey('platformNumber') &&
          !value.containsKey('originalActorNumber'),
      'admin_fields_in_self_appeal',
    );
    for (final raw in value['materials'] as List) {
      final material = _object(raw, 'invalid_appeal_material');
      _check(
        material['description'] is String &&
            material['createdAt'] is String &&
            material['images'] is List &&
            !material.containsKey('retryToken'),
        'invalid_material_dto',
      );
      for (final image in material['images'] as List) {
        EvidenceImage.parse(image);
      }
    }
    return value;
  }

  Future<Map<String, dynamic>> reportPhase() async {
    final id = governanceId(), path = '/api/v1/reports/';
    step = 'report_original_not_submitted';
    final original = await request(reporter, 'GET', '$path$id');
    _check(
      original['state'] == 'NOT_SUBMITTED',
      'new_report_already_submitted',
    );
    final retry = _uuid(original['retryToken']);
    final body = <String, dynamic>{
      'postId': post,
      'identityId': identity,
      'reason': 'OTHER',
      'description': '合成举报联调材料',
      'images': <Object>[],
    };
    step = 'report_old_attempt_sealed';
    await denied(() => api.request(reporter, 'PUT', '$path$id', body: body), {
      409,
    }, code: 'REPORT_ATTEMPT_SEALED');
    step = 'report_new_attempt_submitted';
    final report = reportReceipt(
      await request(
        reporter,
        'PUT',
        '$path$id',
        body: {...body, 'retryToken': retry},
      ),
      id,
    );
    step = 'report_original_reconciled';
    final reconciled = reportReceipt(
      await request(reporter, 'GET', '$path$id'),
      id,
    );
    _check(reconciled['caseId'] == report['caseId'], 'report_case_changed');
    step = 'report_progress_notice';
    final list = await notices(reporter, identity);
    _check(
      list.any(
        (n) =>
            n.route.name == 'REPORT' &&
            n.route.resourceId == id &&
            n.scope == 'IDENTITY',
      ),
      'report_notice_missing',
    );
    return {'requestId': id, 'caseId': report['caseId']};
  }

  Future<Map<String, dynamic>> appealPhase() async {
    step = 'reporter_result_notice_read';
    final reporterNotices = await notices(reporter, identity, open: true);
    _check(reporterNotices.isNotEmpty, 'reporter_notifications_missing');
    step = 'owner_sanction_notice_read';
    final ownerNotices = await notices(owner, null, open: true);
    _check(
      ownerNotices.any(
        (n) => n.route.name == 'SANCTION' && n.route.resourceId == sanction,
      ),
      'sanction_notice_missing',
    );
    step = 'owner_sanction_detail';
    final current = await request(owner, 'GET', '/api/v1/sanctions/$sanction');
    _check(
      current['id'] == sanction &&
          current['postId'] == post &&
          current['appealCount'] == 0,
      'sanction_dto_mismatch',
    );
    final id = governanceId();
    step = 'appeal_submit';
    final submitted = appealReceipt(
      await request(
        owner,
        'PUT',
        '/api/v1/sanctions/$sanction/appeals/$id',
        body: {'description': '合成申诉联调材料', 'images': <Object>[]},
      ),
    );
    step = 'appeal_original_reconciled';
    final original = await request(
      owner,
      'GET',
      '/api/v1/sanctions/$sanction/appeal-requests/$id',
    );
    _check(original['state'] == 'SUBMITTED', 'appeal_original_not_submitted');
    final reconciled = appealReceipt(
      _object(original['appeal'], 'appeal_original_missing'),
    );
    _check(
      reconciled['id'] == submitted['id'] && reconciled['ordinal'] == 1,
      'appeal_receipt_mismatch',
    );
    return {'appealId': submitted['id'], 'appealRequestId': id};
  }

  Future<Map<String, dynamic>> resultPhase() async {
    step = 'appeal_result_detail';
    final result = appealReceipt(
      await request(owner, 'GET', '/api/v1/appeals/$appeal'),
    );
    _check(
      result['id'] == appeal &&
          {'ACCEPTED', 'REJECTED'}.contains(result['state']) &&
          (result['reason'] as String).isNotEmpty,
      'appeal_not_decided',
    );
    step = 'appeal_result_notice_read';
    final list = await notices(owner, null, open: true);
    _check(
      list.any((n) => n.route.name == 'APPEAL' && n.route.resourceId == appeal),
      'appeal_result_notice_missing',
    );
    return {
      'appealId': appeal,
      'state': result['state'],
      'readNotices': list.length,
    };
  }

  Future<Map<String, dynamic>> limitedPhase() async {
    step = 'banned_ordinary_session_rejected';
    await denied(
      () => api.request(owner, 'GET', '/api/v1/sanctions/$sanction'),
      {401},
    );
    step = 'moderation_self_login';
    final login = (await api.send(
      null,
      'POST',
      '/api/v1/moderation-access/sessions',
      body: {
        'username': _string(fixture, 'ownerUsername'),
        'password': _string(fixture, 'ownerPassword'),
      },
    )).value;
    _check(
      login.length == 4 && login['scope'] == 'MODERATION_SELF',
      'restricted_scope_invalid',
    );
    final token = _string(login, 'sessionToken'),
        subject = _string(login, 'moderationSubject');
    AuthCrypto.decode(token, bytes: 32);
    AuthCrypto.decode(subject, bytes: 32);
    step = 'moderation_self_account_notices';
    final list = await notices(token, null, open: true);
    _check(
      list.every(
        (n) =>
            n.scope == 'ACCOUNT' &&
            {'SANCTION', 'APPEAL_RESULT'}.contains(n.kind),
      ),
      'restricted_notification_scope_leaked',
    );
    step = 'moderation_self_sanction_and_appeal';
    _check(
      (await request(token, 'GET', '/api/v1/sanctions/$sanction'))['id'] ==
          sanction,
      'restricted_sanction_unavailable',
    );
    if (fixture['appealId'] != null) {
      appealReceipt(await request(token, 'GET', '/api/v1/appeals/$appeal'));
    }
    step = 'moderation_self_report_denied';
    await denied(
      () => api.request(
        token,
        'PUT',
        '/api/v1/reports/${governanceId()}',
        body: {
          'postId': post,
          'identityId': null,
          'reason': 'OTHER',
          'description': '',
          'images': <Object>[],
        },
      ),
      {401, 403},
    );
    step = 'ordinary_post_path_not_supported';
    var rejected = false;
    try {
      await api.request(token, 'GET', '/api/v1/posts/$post');
    } on FormatException {
      rejected = true;
    }
    _check(rejected, 'ordinary_post_path_accepted');
    step = 'moderation_self_logout';
    await api.send(
      token,
      'POST',
      '/api/v1/moderation-access/session-revocations',
    );
    return {
      'scope': 'MODERATION_SELF',
      'subjectValidated': true,
      'accountNotices': list.length,
      'ordinaryOwnerRejected': true,
      'reportRejected': true,
      'ordinaryPostPathRejected': true,
    };
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('Expected fixture, phase and result file.');
    exitCode = 2;
    return;
  }
  final phase = args[1], output = File(args[2]);
  HttpGovernanceApi? api;
  _Probe? probe;
  try {
    _check(
      {'report', 'appeal', 'result', 'limited'}.contains(phase),
      'invalid_phase',
    );
    _check(
      File(args[0]).absolute.path != output.absolute.path,
      'output_overwrites_fixture',
    );
    final fixture = _object(
      GovernanceStrictJson(await File(args[0]).readAsString()).decode(),
      'invalid_fixture',
    );
    final uri = Uri.parse(_string(fixture, 'url'));
    _check(
      uri.scheme == 'https' &&
          {'127.0.0.1', 'localhost', '::1'}.contains(uri.host),
      'fixture_must_use_loopback_https',
    );
    final trust = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        utf8.encode(_string(fixture, 'certificatePem')),
      );
    api = HttpGovernanceApi(
      baseUri: uri,
      client: HttpClient(context: trust),
    );
    probe = _Probe(api, fixture);
    final result = await switch (phase) {
      'report' => probe.reportPhase(),
      'appeal' => probe.appealPhase(),
      'result' => probe.resultPhase(),
      'limited' => probe.limitedPhase(),
      _ => throw const _Check('invalid_phase'),
    };
    await output.parent.create(recursive: true);
    await output.writeAsString(jsonEncode(result), flush: true);
    stdout.writeln('PASS $phase');
  } on Object catch (error) {
    await output.parent.create(recursive: true);
    await output.writeAsString(
      jsonEncode({
        'status': 'FAIL',
        'phase': phase,
        'step': probe?.step ?? 'fixture',
        'check': error is _Check
            ? error.name
            : error is GovernanceFailure
            ? 'http_rejected'
            : error.runtimeType.toString(),
        if (error is GovernanceFailure) 'httpStatus': error.status,
      }),
      flush: true,
    );
    stderr.writeln('FAIL $phase');
    exitCode = 1;
  } finally {
    api?.close();
  }
}
