import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Only C-provided publicKey options belong here. A returned credential still
/// needs C's challenge, signature, session/version and final Gate checks.
abstract interface class PasskeyClient {
  Future<Map<String, dynamic>> create(Map<String, dynamic> publicKey);
  Future<Map<String, dynamic>> get(Map<String, dynamic> publicKey);
}

class PasskeyFailure implements Exception {
  const PasskeyFailure(this.code);
  final String code;
  @override
  String toString() => 'PasskeyFailure($code)';
}

abstract interface class CancellablePasskeyClient implements PasskeyClient {
  Future<void> cancel();
}

class NativePasskeyClient implements CancellablePasskeyClient {
  NativePasskeyClient({MethodChannel? channel, TargetPlatform? platform})
      : _channel = channel ?? const MethodChannel('hnuhole/auth_passkey'),
        _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final TargetPlatform _platform;
  bool _busy = false;
  int _version = 0;
  static const _codes = {
    'PASSKEY_CANCELLED', 'PASSKEY_UNAVAILABLE', 'PASSKEY_NOT_FOUND',
    'PASSKEY_BUSY', 'PASSKEY_INVALID_OPTIONS', 'PASSKEY_INVALID_RESPONSE',
    'PASSKEY_FAILED',
  };

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> publicKey) =>
      _perform('create', publicKey);
  @override
  Future<Map<String, dynamic>> get(Map<String, dynamic> publicKey) =>
      _perform('get', publicKey);

  /// Call when abandoning a flow, including logout. Cancellation cannot undo
  /// a platform credential already created; C records it only after verification.
  @override
  Future<void> cancel() async {
    ++_version;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // No platform operation exists.
    } on PlatformException {
      // The operation version still suppresses a late completion.
    }
  }

  Future<Map<String, dynamic>> _perform(
      String method, Map<String, dynamic> publicKey) async {
    if (kIsWeb || (_platform != TargetPlatform.android &&
        _platform != TargetPlatform.iOS)) {
      throw const PasskeyFailure('PASSKEY_UNAVAILABLE');
    }
    if (_busy) throw const PasskeyFailure('PASSKEY_BUSY');
    final String json;
    try {
      json = jsonEncode(publicKey);
      if (utf8.encode(json).length > 32768) throw const FormatException();
      final copy = _object(jsonDecode(json));
      _validateOptions(copy, method == 'create');
    } catch (_) {
      throw const PasskeyFailure('PASSKEY_INVALID_OPTIONS');
    }
    _busy = true;
    final version = ++_version;
    try {
      final raw = await _channel.invokeMethod<String>(method, {'publicKey': json});
      if (version != _version) throw const PasskeyFailure('PASSKEY_CANCELLED');
      try {
        if (raw == null || utf8.encode(raw).length > 32768) {
          throw const FormatException();
        }
        final credential = _object(jsonDecode(raw));
        _validateCredential(credential, method == 'create');
        return credential;
      } catch (_) {
        throw const PasskeyFailure('PASSKEY_INVALID_RESPONSE');
      }
    } on PlatformException catch (error) {
      throw PasskeyFailure(version != _version ? 'PASSKEY_CANCELLED' :
          (_codes.contains(error.code) ? error.code : 'PASSKEY_FAILED'));
    } on MissingPluginException {
      throw const PasskeyFailure('PASSKEY_UNAVAILABLE');
    } on PasskeyFailure {
      rethrow;
    } catch (_) {
      throw const PasskeyFailure('PASSKEY_FAILED');
    } finally {
      _busy = false;
    }
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> required,
    [Set<String> optional = const {}]) {
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.any((key) => !required.contains(key) && !optional.contains(key))) {
    throw const FormatException();
  }
}

String _encoded(Object? value, int minimum, int maximum) {
  if (value is! String || value.length > (maximum * 4 + 2) ~/ 3 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException();
  }
  final bytes = base64Url.decode(base64Url.normalize(value));
  if (bytes.length < minimum || bytes.length > maximum ||
      base64Url.encode(bytes).replaceAll('=', '') != value) {
    throw const FormatException();
  }
  return value;
}

void _rp(Object? value) {
  if (value is! String || value.length > 253 ||
      !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$').hasMatch(value) ||
      value.split('.').any((part) => part.length > 63) ||
      value.codeUnits.any((unit) => !(unit >= 97 && unit <= 122) &&
          !(unit >= 48 && unit <= 57) && unit != 45 && unit != 46) ||
      RegExp(r'^[0-9.]+$').hasMatch(value)) {
    throw const FormatException();
  }
}

void _validateOptions(Map<String, dynamic> value, bool create) {
  _keys(value, create ? {
    'challenge', 'rp', 'user', 'pubKeyCredParams', 'timeout',
    'excludeCredentials', 'authenticatorSelection', 'attestation',
  } : {'challenge', 'rpId', 'timeout', 'userVerification'});
  _encoded(value['challenge'], 32, 32);
  if (value['timeout'] is! int || value['timeout'] != 60000) {
    throw const FormatException();
  }
  if (!create) {
    _rp(value['rpId']);
    if (value['userVerification'] != 'required') throw const FormatException();
    return; // No allowCredentials: the platform must discover the account.
  }
  final rp = _object(value['rp']);
  _keys(rp, {'id', 'name'});
  _rp(rp['id']);
  if (rp['name'] != 'Hnuhole') throw const FormatException();
  final user = _object(value['user']);
  _keys(user, {'id', 'name', 'displayName'});
  _encoded(user['id'], 32, 32);
  if (user['name'] != user['id'] || user['displayName'] != 'Hnuhole account') {
    throw const FormatException();
  }
  final parameters = value['pubKeyCredParams'];
  if (parameters is! List || parameters.length != 1) throw const FormatException();
  final parameter = _object(parameters.single);
  _keys(parameter, {'type', 'alg'});
  if (parameter['type'] != 'public-key' || parameter['alg'] is! int ||
      parameter['alg'] != -7) throw const FormatException();
  final selection = _object(value['authenticatorSelection']);
  _keys(selection, {'residentKey', 'requireResidentKey', 'userVerification'});
  if (selection['residentKey'] != 'required' ||
      selection['requireResidentKey'] != true ||
      selection['userVerification'] != 'required' || value['attestation'] != 'none') {
    throw const FormatException();
  }
  final exclude = value['excludeCredentials'];
  if (exclude is! List || exclude.length > 10) throw const FormatException();
  final seen = <String>{};
  for (final raw in exclude) {
    final item = _object(raw);
    _keys(item, {'id', 'type'});
    if (item['type'] != 'public-key' ||
        !seen.add(_encoded(item['id'], 1, 1023))) throw const FormatException();
  }
}

void _validateCredential(Map<String, dynamic> value, bool create) {
  _keys(value, {'id', 'rawId', 'type', 'response', 'clientExtensionResults'});
  final id = _encoded(value['id'], 1, 1023);
  if (value['rawId'] != id || value['type'] != 'public-key' ||
      _object(value['clientExtensionResults']).isNotEmpty) throw const FormatException();
  final response = _object(value['response']);
  _keys(response, create ? {'clientDataJSON', 'attestationObject'} :
      {'clientDataJSON', 'authenticatorData', 'signature', 'userHandle'});
  _encoded(response['clientDataJSON'], 1, 3072);
  if (create) {
    _encoded(response['attestationObject'], 1, 4096);
  } else {
    _encoded(response['authenticatorData'], 37, 2048);
    _encoded(response['signature'], 8, 1024);
    _encoded(response['userHandle'], 32, 32);
  }
}
