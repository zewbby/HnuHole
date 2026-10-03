import 'channel.dart';

/// The only data boundary used by the entry tree.
abstract interface class ChannelRepository {
  Future<ChannelDirectoryResult> loadChannels({required String sessionToken});
}

/// A complete directory and the deadline committed by C for this same token.
class ChannelDirectoryResult {
  ChannelDirectoryResult({required List<Channel> channels, required this.expiresAt})
    : channels = ChannelDirectory.validate(channels);

  final List<Channel> channels;
  final DateTime expiresAt;
}

class ChannelRepositoryException implements Exception {
  const ChannelRepositoryException({
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() {
    final suffix = requestId == null ? '' : ' (request $requestId)';
    return 'ChannelRepositoryException: $message$suffix';
  }
}
