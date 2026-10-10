import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_mobile/src/development/app_transport.dart';

/// Dedicated installed release probe; never the production application target.
/// Native MainActivity receives the same opt-in driver extras as debug runners.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final checks = <String, bool>{
    'actualReleaseMode': kReleaseMode && !kDebugMode,
  };
  const channel = MethodChannel('hnuhole/owned_device_driver');
  for (final entry in <String, MethodChannel>{
    'variant': channel,
    'acceptanceLifecycle': channel,
    'acceptanceRecreate': channel,
    'acceptanceState': const MethodChannel('hnuhole/auth_passkey'),
    'acceptanceLateCallback': const MethodChannel('hnuhole/auth_passkey'),
    'acceptanceGetSelected': const MethodChannel('hnuhole/auth_passkey'),
    'acceptanceCreationLabel': const MethodChannel('hnuhole/auth_passkey'),
  }.entries) {
    try {
      await entry.value
          .invokeMethod<Object?>(entry.key)
          .timeout(const Duration(seconds: 5));
      checks['${entry.key}Unavailable'] = false;
    } on MissingPluginException {
      checks['${entry.key}Unavailable'] = true;
    } on Object {
      checks['${entry.key}Unavailable'] = false;
    }
  }
  try {
    await channel
        .invokeMethod<String>('phase')
        .timeout(const Duration(seconds: 5));
    checks['nativeOwnedDriverUnavailable'] = false;
  } on MissingPluginException {
    checks['nativeOwnedDriverUnavailable'] = true;
  } on Object {
    checks['nativeOwnedDriverUnavailable'] = false;
  }
  final c = Uri.parse(const String.fromEnvironment('AUTH_COMMUNITY_BASE_URL'));
  final v = Uri.parse(const String.fromEnvironment('AUTH_VERIFIER_BASE_URL'));
  const ca = String.fromEnvironment('AUTH_DEV_CA_BASE64');
  const rp = String.fromEnvironment('AUTH_DEV_PASSKEY_RP_ID');
  checks['explicitOwnedTestTrustPresent'] = ca.isNotEmpty && rp.isNotEmpty;
  try {
    final client = createAppHttpClient(
      community: c,
      verifier: v,
      developmentCa: ca,
    );
    client.close(force: true);
    checks['developmentCaRejected'] = false;
  } on StateError {
    checks['developmentCaRejected'] = true;
  } on Object {
    checks['developmentCaRejected'] = false;
  }
  try {
    developmentPasskeyRp(community: c, verifier: v, rp: rp, developmentCa: ca);
    checks['developmentRpRejected'] = false;
  } on StateError {
    checks['developmentRpRejected'] = true;
  } on Object {
    checks['developmentRpRejected'] = false;
  }
  final standard = createAppHttpClient(
    community: c,
    verifier: v,
    developmentCa: '',
  );
  standard.connectionTimeout = const Duration(seconds: 5);
  checks['normalHttpClientAvailable'] =
      standard.connectionTimeout == const Duration(seconds: 5);
  standard.close(force: true);
  final accepted = checks.values.every((value) => value);
  // This bounded record contains no endpoint, CA, RP, credential or VM URI.
  debugPrint(
    'HNUHOLE_RELEASE_BOUNDARY ${jsonEncode({'result': accepted ? 'PASS' : 'FAIL', 'checks': checks})}',
  );
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(accepted ? 'Release 边界检查通过' : 'Release 边界检查失败'),
        ),
      ),
    ),
  );
}
