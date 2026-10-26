// Nine scoped production-widget scenarios on an isolated native test package.
// Page data/authorities are fixtures; the separate compiled Dart probe verifies
// production TLS + Redis + SQL. This does not claim native vault acceptance.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test.dart';

import '../test/comment_views_test.dart' as scenarios;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.allTestsPassed.future.then((passed) async {
    await File(
      '${Directory.systemTemp.path}/comment-snapshot-device-result.json',
    ).writeAsString(
      jsonEncode({
        'status': passed ? 'PASS' : 'FAIL',
        'scope': 'production comment widgets with fixture page data',
        'results': binding.results.map(
          (name, result) => MapEntry(name, result.toString()),
        ),
      }),
      flush: true,
    );
  });
  scenarios.snapshotRecoveryTests();
}
