import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/main.dart' as app;

/// Candidate adapter only: historical B5 APK evidence predates this root type.
app.HnuholeApp b5CandidateRoot(WidgetTester tester) =>
    tester.widget<app.HnuholeApp>(find.byType(app.HnuholeApp));
