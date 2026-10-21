import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

class _Preferences implements AuthVault {
  String? value;
  Completer<String?>? pendingRead;
  bool unavailable = false;
  final writes = <String>[];

  @override
  Future<String?> read() async {
    if (unavailable) throw const AuthStorageFailure();
    return pendingRead == null ? value : pendingRead!.future;
  }

  @override
  Future<void> write(String value) async {
    if (unavailable) throw const AuthStorageFailure();
    writes.add(value);
    this.value = value;
  }
}

void main() {
  test('appearance persists only version, theme and language and restores the latest selection', () async {
    final preferences = _Preferences();
    final first = AuthPresentationController(preferences: preferences);
    first.toggleTheme(Brightness.light);
    first.toggleLanguage();
    await pumpEventQueue();
    final record = jsonDecode(preferences.value!) as Map<String, dynamic>;
    expect(record.keys.toSet(), {'version', 'theme', 'language'});
    expect(record, {'version': 1, 'theme': 'dark', 'language': 'en'});
    final restored = AuthPresentationController(preferences: preferences);
    await restored.load();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.english, isTrue);
    first.dispose();
    restored.dispose();
  });

  test('a late preference read cannot overwrite a user choice', () async {
    final preferences = _Preferences()..pendingRead = Completer<String?>();
    final controller = AuthPresentationController(preferences: preferences);
    final load = controller.load();
    controller.toggleLanguage();
    preferences.pendingRead!.complete(
      jsonEncode({'version': 1, 'theme': 'dark', 'language': 'zh'}),
    );
    await load;
    expect(controller.english, isTrue);
    expect(controller.themeMode, ThemeMode.system);
    await pumpEventQueue();
    controller.dispose();
  });

  test(
    'unavailable or malformed preferences do not block authentication UI',
    () async {
      final preferences = _Preferences()..unavailable = true;
      final controller = AuthPresentationController(preferences: preferences);
      await controller.load();
      controller.toggleTheme(Brightness.light);
      controller.toggleLanguage();
      await pumpEventQueue();
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.english, isTrue);
      preferences.unavailable = false;
      preferences.value = '{invalid';
      final next = AuthPresentationController(preferences: preferences);
      await next.load();
      expect(next.themeMode, ThemeMode.system);
      expect(next.english, isFalse);
      controller.dispose();
      next.dispose();
    },
  );

  test(
    'disposing during preference load cannot publish a notification',
    () async {
      final preferences = _Preferences()..pendingRead = Completer<String?>();
      final controller = AuthPresentationController(preferences: preferences);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final load = controller.load();
      controller.dispose();
      preferences.pendingRead!.complete(
        jsonEncode({'version': 1, 'theme': 'dark', 'language': 'en'}),
      );
      await load;
      expect(notifications, 0);
    },
  );
}
