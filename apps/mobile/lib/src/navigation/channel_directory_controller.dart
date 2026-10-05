import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/channel_repository.dart';

enum ChannelDirectoryStatus { signedOut, loading, ready, failure }

/// Coordinates authentication state and an all-or-nothing directory load.
///
/// A failed or incomplete response never reaches the tree. This is important
/// for the entry contract: the UI must not present a partial or stale set of
/// channels as if it were current business data.
class ChannelDirectoryController extends ChangeNotifier {
  ChannelDirectoryController({required this._repository});

  final ChannelRepository _repository;
  void Function(String token, String? code)? onSessionUnauthorized;
  Future<void> Function()? onSessionRetry;

  /// Returns true only after this deadline is durably stored for the same
  /// authorized token. The fence must also be checked inside the store queue.
  Future<bool> Function(
    String token,
    DateTime expiresAt,
    bool Function() isCurrent,
  )?
  onSessionMetadata;
  ChannelDirectoryStatus _status = ChannelDirectoryStatus.signedOut;
  List<Channel> _channels = const <Channel>[];
  ChannelRepositoryException? _error;
  String? _sessionToken;
  int _requestVersion = 0;
  bool _disposed = false;

  ChannelDirectoryStatus get status => _status;
  List<Channel> get channels => _channels;
  ChannelRepositoryException? get error => _error;
  bool get isAuthenticated => _sessionToken != null;

  /// Starts a fresh directory load after verified account session setup.
  Future<void> setSessionToken(String? token) async {
    final normalized = token?.trim();
    _sessionToken = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    _requestVersion++;

    if (_sessionToken == null) {
      _clearToSignedOut();
      return;
    }
    await load();
  }

  /// Alias used by authentication adapters after community authentication succeeds.
  Future<void> authenticate(String sessionToken) =>
      setSessionToken(sessionToken);

  void signOut() {
    _sessionToken = null;
    _requestVersion++;
    _clearToSignedOut();
  }

  /// Hide protected data while authority is unavailable, without turning a
  /// temporary failure into logout or resetting the caller's tree position.
  void suspend() {
    _sessionToken = null;
    _requestVersion++;
    _status = ChannelDirectoryStatus.failure;
    _channels = const <Channel>[];
    _error = const ChannelRepositoryException(message: '会话暂时无法确认，请重试。');
    _notifyIfAlive();
  }

  Future<void> retry() => _sessionToken == null && onSessionRetry != null
      ? onSessionRetry!()
      : load();

  Future<void> load() async {
    final token = _sessionToken;
    if (token == null) {
      _clearToSignedOut();
      return;
    }

    final version = ++_requestVersion;
    _status = ChannelDirectoryStatus.loading;
    _channels = const <Channel>[];
    _error = null;
    _notifyIfAlive();

    try {
      final loaded = await _repository.loadChannels(sessionToken: token);
      if (!_isCurrent(version, token)) {
        return;
      }
      // Validate once more at this boundary for repositories that are not the
      // HTTP implementation (for example, an integration adapter).
      final channels = ChannelDirectory.validate(loaded.channels);
      if (!loaded.expiresAt.isUtc) {
        throw const FormatException('Invalid UTC session deadline');
      }
      final persist = onSessionMetadata;
      if (persist == null) {
        throw const ChannelRepositoryException(
          message: 'Session metadata cannot be durably confirmed',
        );
      }
      final persisted = await persist(
        token,
        loaded.expiresAt,
        () => _isCurrent(version, token),
      );
      if (!_isCurrent(version, token)) return;
      if (!persisted) {
        throw const ChannelRepositoryException(
          message: 'Session deadline needs authoritative confirmation',
        );
      }
      _channels = channels;
      _status = ChannelDirectoryStatus.ready;
      _error = null;
      _notifyIfAlive();
    } on ChannelRepositoryException catch (error) {
      if (!_isCurrent(version, token)) {
        return;
      }
      if (error.isUnauthorized) {
        onSessionUnauthorized?.call(token, error.code);
        _sessionToken = null;
        _clearToSignedOut();
        return;
      }
      _channels = const <Channel>[];
      _status = ChannelDirectoryStatus.failure;
      _error = error;
      _notifyIfAlive();
    } on FormatException {
      if (!_isCurrent(version, token)) {
        return;
      }
      _channels = const <Channel>[];
      _status = ChannelDirectoryStatus.failure;
      _error = const ChannelRepositoryException(
        message: 'The channel service returned an invalid directory',
        code: 'invalid_channel_directory',
      );
      _notifyIfAlive();
    } on Object {
      if (!_isCurrent(version, token)) {
        return;
      }
      _channels = const <Channel>[];
      _status = ChannelDirectoryStatus.failure;
      _error = const ChannelRepositoryException(
        message: 'Unable to load channels',
      );
      _notifyIfAlive();
    }
  }

  void _clearToSignedOut() {
    _status = ChannelDirectoryStatus.signedOut;
    _channels = const <Channel>[];
    _error = null;
    _notifyIfAlive();
  }

  bool _isCurrent(int version, String token) =>
      !_disposed && version == _requestVersion && token == _sessionToken;

  void _notifyIfAlive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
