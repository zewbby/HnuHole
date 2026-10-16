import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'community_stage1_scenario.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['COMMUNITY_STAGE1_HOST_CONFIG'];
  if (path == null) {
    test('owned stage1 host opt-in', () {}, skip: 'use owned stage1 lab');
    return;
  }
  HttpOverrides.global = null;
  testWidgets('stage1 actual TLS/cmd/SQL and product root rehearsal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final config =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final result = await runCommunityStage1(tester, config, native: false);
      File('$path.result.json').writeAsStringSync(jsonEncode(result));
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}
