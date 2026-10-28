import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/main.dart' as app;

import '../integration_test/b5_candidate_root.dart';
import 'production_startup_test_support.dart';

void main() {
  testWidgets('B5 candidate adapter discovers the actual current app root', (
    tester,
  ) async {
    await startProductionApp(tester);
    final root = b5CandidateRoot(tester);
    expect(find.byType(app.HnuholeApp), findsOneWidget);
    expect(root.store, isA<AuthStore>());
    expect(root.sessions, isA<AuthSessionController>());
    expect(root.management, isA<SecurityManagementController>());
    expect(root.api, isA<HttpAuthApi>());
    expect(root.flows, isA<AuthFlows>());
    expect(root.posts, isA<PostController>());
    // Host discovery is not native vault, Passkey or device acceptance.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
