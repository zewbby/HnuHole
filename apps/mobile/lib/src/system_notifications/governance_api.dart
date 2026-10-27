import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../auth/auth_crypto.dart';
import '../posts/post_models.dart';
import '../posts/post_protocol.dart';

class GovernanceFailure implements Exception {
  const GovernanceFailure(this.status, this.code, {this.uncertain = false});
  final int? status;
  final String code;
  final bool uncertain;
  @override
  String toString() => 'GovernanceFailure($status, $code)';
}

class GovernanceResponse {
  const GovernanceResponse(this.value, this.expiresAt);
  final Map<String, dynamic> value;
  final DateTime expiresAt;
}

abstract interface class GovernanceApi {
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  });
}

class HttpGovernanceApi implements GovernanceApi {
  HttpGovernanceApi({
    required this.baseUri,
    HttpClient? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient() {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !{'', '/'}.contains(baseUri.path)) {
      throw ArgumentError('A fixed HTTPS community origin is required');
    }
  }
  final Uri baseUri;
  final Duration timeout;
  final HttpClient _client;
  void close() => _client.close(force: true);
  @override
  Future<GovernanceResponse> request(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => send(token, method, path, body: body, query: query);
  Future<GovernanceResponse> send(
    String? token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (token != null) AuthCrypto.decode(token, bytes: 32);
    if (!RegExp(
          r'^/api/v1/((reports|system-notifications|notifications|sanctions|appeals|moderation-access)(/[a-zA-Z0-9_-]+)*|dm/governance/reports/[a-f0-9-]{36})$',
        ).hasMatch(path) ||
        !{'GET', 'PUT', 'POST'}.contains(method)) {
      throw const FormatException('Invalid governance path');
    }
    final bytes = body == null ? null : utf8.encode(jsonEncode(body));
    if (bytes != null &&
        bytes.length >
            (path.startsWith('/api/v1/dm/') ? 48 : 12) * 1024 * 1024) {
      throw const FormatException('Material budget exceeded');
    }
    HttpClientRequest? active;
    int? status;
    var expired = false;
    try {
      return await (() async {
        final request = await _client.openUrl(
          method,
          baseUri.resolve(path).replace(queryParameters: query),
        );
        active = request;
        if (expired) {
          request.abort();
          throw const GovernanceFailure(null, 'TIMEOUT', uncertain: true);
        }
        request.followRedirects = false;
        request.maxRedirects = 0;
        if (token != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (bytes != null) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          );
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        final response = await request.close();
        status = response.statusCode;
        final success = response.statusCode >= 200 && response.statusCode < 300;
        final max = success ? 12 * 1024 * 1024 : 32768;
        if (response.contentLength > max) {
          throw const FormatException('Oversized response');
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (data.length + chunk.length > max) {
            throw const FormatException('Oversized response');
          }
          data.add(chunk);
        }
        String header(String name) {
          final values = response.headers[name];
          if (values == null || values.length != 1 || values.single.isEmpty) {
            throw const FormatException('Invalid response headers');
          }
          return values.single;
        }

        AuthCrypto.decode(header('x-request-id'), bytes: 16);
        if (header('cache-control') != 'no-store' ||
            response.headers['set-cookie'] != null) {
          throw const FormatException('Invalid response policy');
        }
        if (response.statusCode == 204 &&
            path == '/api/v1/moderation-access/session-revocations') {
          if (data.length != 0) {
            throw const FormatException('Unexpected revocation body');
          }
          return GovernanceResponse({}, DateTime.utc(1970));
        }
        if (ContentType.parse(header('content-type')).mimeType !=
            'application/json') {
          throw const FormatException('Invalid content type');
        }
        final raw = GovernanceStrictJson(
          utf8.decode(data.takeBytes(), allowMalformed: false),
        ).decode();
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Invalid response');
        }
        if (!success) {
          if (response.headers['session-expires-at'] != null) {
            throw const FormatException('Renewal on error');
          }
          final e = PostJson.record(raw, {'error', 'requestId'});
          if (e['requestId'] != header('x-request-id')) {
            throw const FormatException('Mismatched request');
          }
          final error = PostJson.record(e['error'], {'code', 'message'});
          throw GovernanceFailure(
            response.statusCode,
            PostJson.text(error, 'code', maxLength: 64),
            uncertain: response.statusCode >= 500,
          );
        }
        final expiry = path == '/api/v1/moderation-access/sessions'
            ? PostJson.date(raw, 'expiresAt')
            : PostJson.utc(header('session-expires-at'));
        return GovernanceResponse(raw, expiry);
      })().timeout(timeout);
    } on GovernanceFailure {
      rethrow;
    } on TimeoutException {
      expired = true;
      active?.abort();
      throw const GovernanceFailure(null, 'TIMEOUT', uncertain: true);
    } on IOException {
      active?.abort();
      throw const GovernanceFailure(null, 'TRANSPORT', uncertain: true);
    } on FormatException {
      active?.abort();
      throw GovernanceFailure(
        status == 401
            ? 401
            : status == 503
            ? 503
            : null,
        status == 401 ? 'SESSION_INVALID' : 'INVALID_RESPONSE',
        uncertain: status != 401,
      );
    }
  }
}

class GovernanceStrictJson {
  GovernanceStrictJson(this.input, {this.maxList = 50});
  final int maxList;
  final String input;
  int at = 0;
  Object? decode() {
    final value = _value(0);
    _space();
    if (at != input.length) throw const FormatException('Trailing JSON data');
    return value;
  }

  void _space() {
    while (at < input.length && ' \t\r\n'.contains(input[at])) {
      at++;
    }
  }

  Object? _value(int depth) {
    if (depth > 16) throw const FormatException('JSON nesting too deep');
    _space();
    if (at >= input.length) throw const FormatException('Missing JSON value');
    final c = input[at];
    if (c == '{') {
      at++;
      _space();
      final result = <String, Object?>{};
      if (_consume('}')) return result;
      while (true) {
        _space();
        final key = _string();
        _space();
        if (!_consume(':') || result.containsKey(key)) {
          throw const FormatException('Invalid JSON key');
        }
        result[key] = _value(depth + 1);
        _space();
        if (_consume('}')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON object');
      }
    }
    if (c == '[') {
      at++;
      _space();
      final result = <Object?>[];
      if (_consume(']')) return result;
      while (true) {
        if (result.length >= maxList) {
          throw const FormatException('JSON list too large');
        }
        result.add(_value(depth + 1));
        _space();
        if (_consume(']')) return result;
        if (!_consume(',')) throw const FormatException('Invalid JSON array');
      }
    }
    if (c == '"') return _string();
    if (input.startsWith('true', at)) {
      at += 4;
      return true;
    }
    if (input.startsWith('false', at)) {
      at += 5;
      return false;
    }
    if (input.startsWith('null', at)) {
      at += 4;
      return null;
    }
    final match = RegExp(r'-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?')
        .matchAsPrefix(input, at);
    if (match == null) throw const FormatException('Invalid JSON value');
    at = match.end;
    final number = num.tryParse(match.group(0)!);
    if (number == null || !number.isFinite) {
      throw const FormatException('Invalid JSON number');
    }
    return number;
  }

  String _string() {
    if (at >= input.length || input[at] != '"') {
      throw const FormatException('Missing JSON string');
    }
    final start = at++;
    while (at < input.length) {
      final c = input[at++];
      if (c == '"') {
        final value = jsonDecode(input.substring(start, at)) as String;
        PostContentRules.scalarText(value);
        return value;
      }
      if (c == '\\') {
        if (at >= input.length) {
          throw const FormatException('Incomplete JSON escape');
        }
        at++;
      }
    }
    throw const FormatException('Incomplete JSON string');
  }

  bool _consume(String c) {
    if (at < input.length && input[at] == c) {
      at++;
      return true;
    }
    return false;
  }
}
