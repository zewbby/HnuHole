import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final target = Platform.environment['DM_CHAT_SCREENSHOTS'];
    if (target == null || !RegExp(r'^dm-p2-[a-z-]+$').hasMatch(name)) {
      return false;
    }
    final directory = Directory(target);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes, flush: true);
    return true;
  },
);
