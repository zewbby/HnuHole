// Opt-in isolated Android acceptance. Credentials arrive only in this test
// package's private cache; they are never compiled into the APK.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../integration/comment_snapshot_live_probe.dart' as probe;
import '../test/comment_views_test.dart' as scenarios;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory.systemTemp.path;
  scenarios.snapshotRecoveryTests();
  testWidgets('native pinned TLS snapshot reader with real SQL and Redis', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fixture = File('$root/comment-snapshot-native-fixture.json');
      final phaseFile = File('$root/comment-snapshot-native-phase.txt');
      final output = '$root/comment-snapshot-native-output.json';
      try {
        final phase = (await phaseFile.readAsString()).trim();
        if (phase != 'live' && phase != 'down') {
          throw StateError('Unsupported owned fixture phase');
        }
        await probe.main([fixture.path, phase, output]);
      } catch (error) {
        await File(output).writeAsString(
          jsonEncode({'status': 'FAIL', 'errorType': '${error.runtimeType}'}),
          flush: true,
        );
        rethrow;
      } finally {
        if (await fixture.exists()) await fixture.delete();
        if (await phaseFile.exists()) await phaseFile.delete();
      }
    });
  });
  binding.allTestsPassed.future.then((passed) async {
    await File('$root/comment-snapshot-native-suite.json').writeAsString(
      jsonEncode({
        'status': passed ? 'PASS' : 'FAIL',
        'scope': 'nine fixture UI scenarios plus native production TLS reader',
        'results': binding.results.map(
          (name, result) => MapEntry(name, result.toString()),
        ),
      }),
      flush: true,
    );
  });
}
