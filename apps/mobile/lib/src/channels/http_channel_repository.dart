import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'channel.dart';
import 'channel_repository.dart';

/// REST implementation for `GET /api/v1/channels`.
class HttpChannelRepository implements ChannelRepository {
  HttpChannelRepository({
    required this.baseUri,
    HttpClient? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? HttpClient() {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/')) {
      throw ArgumentError('A fixed HTTPS community origin is required');
    }
    _client.connectionTimeout = timeout;
  }

  final Uri baseUri;
  final Duration timeout;
  final HttpClient _client;

  @override
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken}) async {
    if (sessionToken.trim().isEmpty) {
      throw const ChannelRepositoryException(
        message: 'A session token is required',
        statusCode: 401,
        code: 'AUTHENTICATION_FAILED',
      );
    }

    final requestUri = baseUri.resolve('/api/v1/channels');
    HttpClientResponse response;
    late HttpClientRequest request;
    try {
      request = await _client.getUrl(requestUri).timeout(timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${sessionToken.trim()}',
      );
      response = await request.close().timeout(timeout);
    } on TimeoutException {
      throw const ChannelRepositoryException(
        message: 'The channel request timed out',
      );
    } on SocketException catch (error) {
      throw ChannelRepositoryException(
        message: 'The channel service is unavailable: $error',
      );
    }

    String body;
    try {
      body = await (() async {
        final data = <int>[];
        await for (final chunk in response.timeout(timeout)) {
          if (data.length + chunk.length > 262144) {
            throw const ChannelRepositoryException(
              message: 'The channel response is too large',
            );
          }
          data.addAll(chunk);
        }
        return utf8.decode(data);
      })().timeout(timeout);
    } on TimeoutException {
      request.abort();
      throw const ChannelRepositoryException(
        message: 'The channel request timed out',
      );
    } on FormatException {
      throw const ChannelRepositoryException(
        message: 'The channel response is malformed',
      );
    }
    final payload = _decodePayload(body);
    if (response.statusCode != HttpStatus.ok) {
      throw ChannelRepositoryException(
        message: _errorMessage(payload, response.statusCode),
        statusCode: response.statusCode,
        code: _errorField(payload, 'code'),
        requestId: _requestId(payload, response.headers),
      );
    }

    final rawChannels = _channelList(payload);
    try {
      final expiresAt = _sessionExpiry(response.headers);
      return ChannelDirectoryResult(
        expiresAt: expiresAt,
        channels: rawChannels
            .map((item) => Channel.fromJson(item))
            .toList(growable: false),
      );
    } on FormatException catch (error) {
      throw ChannelRepositoryException(
        message:
            'The channel service returned an invalid directory: ${error.message}',
        statusCode: response.statusCode,
        code: 'invalid_channel_directory',
      );
    }
  }

  void close() => _client.close(force: true);

  DateTime _sessionExpiry(HttpHeaders headers) {
    final values = headers['session-expires-at'];
    if (values == null || values.length != 1) {
      throw const FormatException('Missing or ambiguous session deadline');
    }
    final value = values.single;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$')
        .hasMatch(value)) {
      throw const FormatException('Invalid UTC session deadline');
    }
    final parsed = DateTime.parse(value);
    if (!parsed.isUtc ||
        parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      throw const FormatException('Invalid session deadline calendar date');
    }
    return parsed;
  }

  String? _requestId(dynamic payload, HttpHeaders headers) {
    final value = payload is Map ? payload['requestId'] : null;
    if (value is String && value.isNotEmpty) return value;
    final values = headers['x-request-id'];
    return values != null && values.length == 1 ? values.single : null;
  }

  dynamic _decodePayload(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return const <String, dynamic>{};
    }
  }

  List<Map<String, dynamic>> _channelList(dynamic payload) {
    final raw = payload is Map<String, dynamic> && payload.length == 1
        ? payload['channels']
        : null;
    if (raw is! List) {
      throw const ChannelRepositoryException(
        message: 'The channel service returned no channel list',
        statusCode: 200,
        code: 'invalid_channel_directory',
      );
    }
    try {
      return raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } on Object {
      throw const ChannelRepositoryException(
        message: 'The channel service returned malformed channels',
        statusCode: 200,
        code: 'invalid_channel_directory',
      );
    }
  }

  String _errorMessage(dynamic payload, int statusCode) {
    if (statusCode == 401) {
      return 'The session is no longer valid';
    }
    if (statusCode == 503) {
      return 'The channel service is temporarily unavailable';
    }
    return 'The channel service returned HTTP $statusCode';
  }

  String? _errorField(dynamic payload, String key) {
    if (payload is! Map) {
      return null;
    }
    final error = payload['error'];
    final value = error is Map ? error[key] : payload[key];
    return value is String ? value : null;
  }
}
