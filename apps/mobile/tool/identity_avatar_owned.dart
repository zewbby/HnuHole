import 'package:flutter/foundation.dart';
import 'package:hnuhole_mobile/main.dart' as app;
import 'package:hnuhole_mobile/src/development/app_transport.dart';

// Build only with HNUHOLE_IDENTITY_AVATAR=1 (.identityavatar). The owned build
// wrapper verifies the packaged application ID before exporting/installing it.
void main() {
  if (!kDebugMode ||
      !const bool.fromEnvironment('IDENTITY_AVATAR_OWNED') ||
      const String.fromEnvironment('AUTH_DEV_CA_BASE64').isEmpty) {
    throw StateError('Explicit owned debug avatar fixture required');
  }
  validateDevelopmentOrigins(
    Uri.parse(const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL')),
    Uri.parse(const String.fromEnvironment('AUTH_VERIFIER_BASE_URL')),
  );
  app.main();
}
