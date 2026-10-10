import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A public development RP can be pinned while the actual C/V APIs stay behind
/// verified private-CA loopback HTTPS. Release builds reject this test setting.
String? developmentPasskeyRp({
  required Uri community,
  required Uri verifier,
  String rp = const String.fromEnvironment('AUTH_DEV_PASSKEY_RP_ID'),
  String developmentCa = const String.fromEnvironment('AUTH_DEV_CA_BASE64'),
}) {
  if (rp.isEmpty) return null;
  if (!kDebugMode || developmentCa.isEmpty) {
    throw StateError(
      'Development RP requires explicit debug development trust',
    );
  }
  validateDevelopmentOrigins(community, verifier);
  return rp;
}

/// Explicit trust for an owned, USB-forwarded development cluster only.
/// HTTPS chain/hostname validation stays enabled; no device CA is installed.
HttpClient createAppHttpClient({
  required Uri community,
  required Uri verifier,
  String developmentCa = const String.fromEnvironment('AUTH_DEV_CA_BASE64'),
}) {
  if (developmentCa.isEmpty) return HttpClient();
  if (!kDebugMode) {
    throw StateError('Development CA requires a debug build');
  }
  validateDevelopmentOrigins(community, verifier);
  final bytes = base64Decode(developmentCa);
  if (bytes.isEmpty || bytes.length > 16384) {
    throw ArgumentError('Development CA size is invalid');
  }
  final trust = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(bytes);
  return HttpClient(context: trust);
}

void validateDevelopmentOrigins(Uri community, Uri verifier) {
  for (final origin in [community, verifier]) {
    if (origin.scheme != 'https' ||
        !{'127.0.0.1', '::1', 'localhost'}.contains(origin.host) ||
        !origin.hasPort ||
        origin.port < 1024 ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError(
        'Development CA requires fixed loopback HTTPS origins',
      );
    }
  }
  if (community.origin == verifier.origin) {
    throw ArgumentError('Independent C/V origins are required');
  }
}
