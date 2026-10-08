import 'dart:convert';

import 'auth_crypto.dart';

/// Validated during every vault read/write, before startup can interpret a
/// pending operation as a permission to use a stored session.
class AuthWorkflowCodec {
  static void validate({
    Map<String, dynamic>? registration,
    Map<String, dynamic>? pendingReset,
    Map<String, dynamic>? pendingClosure,
    Map<String, dynamic>? pendingCredentialChange,
    Map<String, dynamic>? identityChanges,
    Map<String, dynamic>? identityDrafts,
    String? cInstallationId,
    String? vInstallationId,
  }) {
    if (identityDrafts != null) {
      if (identityDrafts.length > 32) {
        throw const FormatException('Too many identity drafts');
      }
      for (final entry in identityDrafts.entries) {
        if (!_uuid(entry.key)) {
          throw const FormatException('Invalid identity draft owner');
        }
        final draft = _optionalMap(entry.value);
        if (draft == null) {
          throw const FormatException('Missing identity draft');
        }
        _fields(
          draft,
          {'v', 'username', 'nickname'},
          {'v', 'username', 'nickname'},
        );
        _version(draft);
        final nickname = draft['nickname'];
        if (!RegExp(r'^[a-z][a-z0-9_]{5,23}$')
                .hasMatch(_string(draft, 'username')) ||
            nickname is! String ||
            utf8.encode(nickname).length > 512) {
          throw const FormatException('Invalid identity draft');
        }
      }
    }
    if (identityChanges != null) {
      if (identityChanges.length > 32) {
        throw const FormatException('Too many unresolved identity owners');
      }
      for (final entry in identityChanges.entries) {
        if (!_uuid(entry.key)) {
          throw const FormatException('Invalid identity owner');
        }
        final change = _optionalMap(entry.value);
        if (change == null) {
          throw const FormatException('Missing identity intent');
        }
        _fields(
          change,
          {
            'v',
            'key',
            'username',
            'operation',
            'identityId',
            'nickname',
            'state',
          },
          {'v', 'key', 'username', 'operation', 'state'},
        );
        _version(change);
        _encoded(change, 'key', 16);
        _state(change, {'UNKNOWN', 'COMMITTED'});
        if (!RegExp(r'^[a-z][a-z0-9_]{5,23}$')
                .hasMatch(_string(change, 'username')) ||
            !{'CREATE', 'RENAME', 'DELETE'}.contains(change['operation'])) {
          throw const FormatException('Invalid identity intent');
        }
        if ((change['operation'] == 'CREATE') !=
                !change.containsKey('identityId') ||
            (change['operation'] == 'DELETE') !=
                !change.containsKey('nickname')) {
          throw const FormatException('Invalid identity intent shape');
        }
        if (change.containsKey('identityId') &&
            !_uuid(_string(change, 'identityId'))) {
          throw const FormatException('Invalid identity target');
        }
        if (change.containsKey('nickname') &&
            utf8.encode(_string(change, 'nickname')).length > 512) {
          throw const FormatException('Invalid identity name');
        }
      }
    }
    if (pendingCredentialChange != null) {
      final change = pendingCredentialChange;
      _fields(
        change,
        {
          'v',
          'kind',
          'intentId',
          'key',
          'accountId',
          'originalTokenDigest',
          'state',
          'credentialId',
        },
        {
          'v',
          'kind',
          'intentId',
          'key',
          'accountId',
          'originalTokenDigest',
          'state',
        },
      );
      _version(change);
      if (!{
        'ROTATION',
        'PASSKEY_BINDING',
        'PASSKEY_REMOVAL',
      }.contains(change['kind'])) {
        throw const FormatException('Invalid credential operation');
      }
      _state(change, {'UNKNOWN', 'EXPIRED', 'COMMITTED', 'NOT_COMMITTED'});
      _encoded(change, 'intentId', 32);
      _encoded(change, 'key', 32);
      _encoded(change, 'originalTokenDigest', 32);
      if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(_string(change, 'accountId'))) {
        throw const FormatException('Invalid credential account');
      }
      if (change['kind'] == 'PASSKEY_REMOVAL') {
        AuthCrypto.decode(_string(change, 'credentialId'), maxBytes: 1023);
      } else if (change.containsKey('credentialId')) {
        throw const FormatException('Unexpected credential operation target');
      }
    }
    if (registration != null) {
      _fields(
        registration,
        {
          'v',
          'seed',
          'publicKey',
          'slotId',
          'request',
          'confirmation',
          'ticket',
          'commit',
        },
        {'v', 'seed', 'publicKey', 'slotId'},
      );
      _version(registration);
      if (cInstallationId == null ||
          vInstallationId == null ||
          cInstallationId == vInstallationId) {
        throw const FormatException('Invalid installation separation');
      }
      AuthCrypto.decode(cInstallationId, bytes: 16);
      AuthCrypto.decode(vInstallationId, bytes: 16);
      _encoded(registration, 'seed', 32);
      _encoded(registration, 'publicKey', 32);
      _encoded(registration, 'slotId', 32);
      if (AuthCrypto.slotId(_string(registration, 'publicKey')) !=
          registration['slotId']) {
        throw const FormatException('Invalid bootstrap slot binding');
      }
      final request = _optionalMap(registration['request']);
      if (request != null) {
        _fields(
          request,
          {'email', 'key', 'state', 'requestedAt', 'waitUntil', 'flowId'},
          {'email', 'key', 'state', 'requestedAt', 'waitUntil'},
        );
        _encoded(request, 'key', 32);
        final email = _string(request, 'email');
        if (utf8.encode(email).length > 254 ||
            !RegExp(r'^[^\x00-\x20\x7F\s@]+@hainanu\.edu\.cn$')
                .hasMatch(email)) {
          throw const FormatException('Invalid precise email');
        }
        _state(request, {'UNKNOWN', 'ACCEPTED', 'EXPIRED'});
        _utc(_string(request, 'requestedAt'));
        _utc(_string(request, 'waitUntil'));
        if (request['state'] == 'ACCEPTED' && request['flowId'] == null) {
          throw const FormatException('Missing accepted flow');
        }
        if (request.containsKey('flowId')) {
          _encoded(request, 'flowId', 32);
        }
      }
      final confirmation = _optionalMap(registration['confirmation']);
      if (confirmation != null) {
        _fields(
          confirmation,
          {'key', 'flowId', 'releaseReceipt', 'expired'},
          {'key', 'flowId'},
        );
        _encoded(confirmation, 'key', 32);
        _encoded(confirmation, 'flowId', 32);
        if (request == null || confirmation['flowId'] != request['flowId']) {
          throw const FormatException('Invalid confirmation flow binding');
        }
        if (confirmation.containsKey('expired') &&
            confirmation['expired'] != true) {
          throw const FormatException('Invalid expired operation marker');
        }
        if (confirmation.containsKey('releaseReceipt')) {
          _encoded(confirmation, 'releaseReceipt', 120);
        }
      }
      if (registration.containsKey('ticket')) {
        final ticket = AuthCrypto.parseRegistrationTicket(
          _string(registration, 'ticket'),
        );
        if (ticket.slotId != registration['slotId'] ||
            ticket.bootstrapPublicKey != registration['publicKey'] ||
            confirmation != null) {
          throw const FormatException('Invalid ticket binding');
        }
      }
      final commit = _optionalMap(registration['commit']);
      if (commit != null) {
        _fields(commit, {'key', 'intentId'}, {'key', 'intentId'});
        _encoded(commit, 'key', 32);
        _encoded(commit, 'intentId', 32);
        if (!registration.containsKey('ticket')) {
          throw const FormatException('Missing committed eligibility');
        }
      }
    }
    if (pendingReset != null) {
      _fields(
        pendingReset,
        {'v', 'intentId', 'key', 'state', 'originalTokenDigest'},
        {'v', 'intentId', 'key', 'state'},
      );
      _version(pendingReset);
      _state(pendingReset, {
        'UNKNOWN',
        'COMMITTED',
        'NOT_COMMITTED',
        'EXPIRED',
      });
      _encoded(pendingReset, 'intentId', 32);
      _encoded(pendingReset, 'key', 32);
      if (pendingReset.containsKey('originalTokenDigest')) {
        _encoded(pendingReset, 'originalTokenDigest', 32);
      }
    }
    if (pendingClosure != null) {
      _fields(
        pendingClosure,
        {
          'v',
          'closureId',
          'statusSecret',
          'statusDigest',
          'originalBearer',
          'originalAccountId',
          'state',
          'dueAt',
          'releaseReceipt',
        },
        {'v', 'closureId', 'statusSecret', 'statusDigest', 'state'},
      );
      _version(pendingClosure);
      _state(pendingClosure, {
        'UNKNOWN',
        'PENDING',
        'FINALIZING',
        'CANCELLED',
        'CLOSED_RELEASE_PENDING',
        'RELEASED',
      });
      _encoded(pendingClosure, 'closureId', 32);
      if (pendingClosure.containsKey('originalAccountId') &&
          !_uuid(_string(pendingClosure, 'originalAccountId'))) {
        throw const FormatException('Invalid closure business owner');
      }
      _encoded(pendingClosure, 'statusSecret', 32);
      _encoded(pendingClosure, 'statusDigest', 32);
      if (pendingClosure['statusDigest'] !=
          AuthCrypto.closureStatusDigest(
            _string(pendingClosure, 'statusSecret'),
          )) {
        throw const FormatException('Invalid closure capability binding');
      }
      if (pendingClosure.containsKey('originalBearer')) {
        if (pendingClosure['state'] != 'UNKNOWN') {
          throw const FormatException('Unexpected historical bearer');
        }
        _encoded(pendingClosure, 'originalBearer', 32);
      }
      final hasDeadline =
          pendingClosure['state'] == 'PENDING' ||
          pendingClosure['state'] == 'FINALIZING';
      if (hasDeadline != pendingClosure.containsKey('dueAt')) {
        throw const FormatException('Invalid closure deadline shape');
      }
      if (hasDeadline) {
        _utc(_string(pendingClosure, 'dueAt'));
      }
      if (pendingClosure.containsKey('releaseReceipt')) {
        if (pendingClosure['state'] != 'CLOSED_RELEASE_PENDING' &&
            pendingClosure['state'] != 'RELEASED') {
          throw const FormatException('Unexpected release receipt');
        }
        _encoded(pendingClosure, 'releaseReceipt', 120);
      }
      if (pendingClosure['state'] == 'RELEASED' &&
          !pendingClosure.containsKey('releaseReceipt')) {
        throw const FormatException('Missing release receipt');
      }
    }
  }

  static void _version(Map<String, dynamic> value) {
    if (value['v'] is! int || value['v'] != 1) {
      throw const FormatException('Unsupported workflow version');
    }
  }

  static bool _uuid(String value) =>
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(value);

  static void _state(Map<String, dynamic> value, Set<String> allowed) {
    if (!allowed.contains(value['state'])) {
      throw const FormatException('Unsupported workflow state');
    }
  }

  static String _string(Map<String, dynamic> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw const FormatException('Invalid workflow field');
    }
    return item;
  }

  static void _encoded(Map<String, dynamic> value, String key, int length) =>
      AuthCrypto.decode(_string(value, key), bytes: length);
  static Map<String, dynamic>? _optionalMap(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid workflow object');
    }
    return value;
  }

  static void _fields(
    Map<String, dynamic> value,
    Set<String> allowed,
    Set<String> required,
  ) {
    if (value.keys.any((key) => !allowed.contains(key)) ||
        required.any((key) => !value.containsKey(key)) ||
        value.values.any((value) => value == null)) {
      throw const FormatException('Unsupported workflow object shape');
    }
  }

  static void _utc(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
        .hasMatch(value)) {
      throw const FormatException('Invalid UTC timestamp');
    }
    final parsed = DateTime.parse(value);
    if (!parsed.isUtc ||
        parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      throw const FormatException('Invalid UTC timestamp');
    }
  }
}
