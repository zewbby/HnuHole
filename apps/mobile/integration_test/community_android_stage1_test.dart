import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../integration/community_stage1_scenario.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const config = <String, String>{
    'AUTH_COMMUNITY_BASE_URL': String.fromEnvironment(
      'AUTH_COMMUNITY_BASE_URL',
    ),
    'AUTH_VERIFIER_BASE_URL': String.fromEnvironment('AUTH_VERIFIER_BASE_URL'),
    'AUTH_DEV_CA_BASE64': String.fromEnvironment('AUTH_DEV_CA_BASE64'),
    'AUTH_DEVICE_MAILPIT_URL': String.fromEnvironment(
      'AUTH_DEVICE_MAILPIT_URL',
    ),
    'COMMUNITY_STAGE1_CONTROL_TOKEN': String.fromEnvironment(
      'COMMUNITY_STAGE1_CONTROL_TOKEN',
    ),
    'COMMUNITY_STAGE1_RUN_ID': String.fromEnvironment(
      'COMMUNITY_STAGE1_RUN_ID',
    ),
  };
  testWidgets('stage1 native main and owned real-service community flows', (
    tester,
  ) async {
    final result = await runCommunityStage1(tester, config, native: true);
    binding.reportData = result;
  }, timeout: const Timeout(Duration(minutes: 12)));
}
