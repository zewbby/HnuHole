/// Trusted deployment configuration. Keep the historical scope bytes intact.
class MobileEnvironment {
  MobileEnvironment({
    required this.communityBaseUri,
    required this.verifierBaseUri,
  }) {
    _validateOrigin(communityBaseUri);
    _validateOrigin(verifierBaseUri);
  }

  final Uri communityBaseUri;
  final Uri verifierBaseUri;

  String get storageScope =>
      'hnuhole.isolated.auth.v1|$communityBaseUri|$verifierBaseUri';

  static void _validateOrigin(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw ArgumentError('A fixed HTTPS origin is required');
    }
  }
}
