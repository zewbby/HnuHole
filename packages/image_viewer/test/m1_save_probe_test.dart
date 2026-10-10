import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

class TempProvider extends PathProviderPlatform {
  TempProvider(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  final calls = <String>[];
  const channel = MethodChannel('gal');
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hnuhole-image-m1-test-');
    PathProviderPlatform.instance = TempProvider(temporary.path);
    calls.clear();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });
  void mock(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return handler(call);
        });
  }

  test(
    'no source, permission or write calls when saving is forbidden',
    () async {
      mock((call) async => true);
      expect(
        await M1SaveProbe().save(Uint8List(0), 'gif', allowed: false),
        'notAllowed',
      );
      expect(calls, isEmpty);
    },
  );
  test('original animation bytes and extension reach gal, then owned temporary is cleaned', () async {
    final bytes = await File('example/assets/fixtures/animation.webp')
        .readAsBytes();
    String? captured;
    mock((call) async {
      if (call.method == 'hasAccess') return true;
      if (call.method == 'putImage') {
        captured = (call.arguments as Map)['path'] as String;
        expect(captured, endsWith('.webp'));
        expect(await File(captured!).readAsBytes(), bytes);
      }
      return null;
    });
    expect(await M1SaveProbe().save(bytes, 'webp'), 'written');
    expect(calls, ['hasAccess', 'requestAccess', 'putImage']);
    expect(File(captured!).existsSync(), isFalse);
    expect(temporary.listSync(), isEmpty);
  });
  test('permission denial performs no write', () async {
    mock((call) async => false);
    expect(await M1SaveProbe().save(Uint8List(3), 'gif'), 'accessDenied');
    expect(calls, ['hasAccess', 'requestAccess']);
  });
  test(
    'duplicate click while platform write is pending produces one write',
    () async {
      final pending = Completer<void>();
      mock((call) async {
        if (call.method == 'hasAccess') return true;
        if (call.method == 'putImage') await pending.future;
        return null;
      });
      final saver = M1SaveProbe();
      final first = saver.save(Uint8List(3), 'gif');
      await Future<void>.delayed(Duration.zero);
      expect(await saver.save(Uint8List(3), 'gif'), 'busy');
      pending.complete();
      expect(await first, 'written');
      expect(calls.where((m) => m == 'putImage').length, 1);
    },
  );
  test('invalidation during permission request stops before writing', () async {
    final pending = Completer<bool>();
    mock((call) async => call.method == 'hasAccess' ? false : pending.future);
    final saver = M1SaveProbe();
    final first = saver.save(Uint8List(3), 'gif');
    await Future<void>.delayed(Duration.zero);
    saver.invalidate();
    pending.complete(true);
    expect(await first, 'cancelledBeforeWrite');
    expect(calls.contains('putImage'), isFalse);
  });
  test(
    'invalidation after commit cannot claim to cancel the system write',
    () async {
      final pending = Completer<void>();
      final entered = Completer<void>();
      mock((call) async {
        if (call.method == 'hasAccess') return true;
        if (call.method == 'putImage') {
          entered.complete();
          await pending.future;
        }
        return null;
      });
      final saver = M1SaveProbe();
      final first = saver.save(Uint8List(3), 'gif');
      await entered.future;
      saver.invalidate();
      pending.complete();
      expect(await first, 'writtenAfterInvalidation');
      expect(await saver.save(Uint8List(3), 'gif'), 'notAllowed');
    },
  );
  test('format failure cleans owned files and maps gal error', () async {
    mock((call) async {
      if (call.method == 'hasAccess') return true;
      throw PlatformException(code: 'NOT_SUPPORTED_FORMAT');
    });
    final result = await M1SaveProbe().save(Uint8List(3), 'gif');
    expect(result, 'notSupportedFormat');
    expect(temporary.listSync(), isEmpty);
  });

  for (final code in [
    'ACCESS_DENIED',
    'NOT_ENOUGH_SPACE',
    'NOT_SUPPORTED_FORMAT',
    'UNEXPECTED',
  ]) {
    test(
      'platform $code is reported without retry and owned files are cleaned',
      () async {
        mock((call) async {
          if (call.method == 'hasAccess') return true;
          if (call.method == 'requestAccess') return null;
          throw PlatformException(code: code);
        });
        final result = await M1SaveProbe().save(Uint8List(3), 'gif');
        expect(
          result,
          {
            'ACCESS_DENIED': 'accessDenied',
            'NOT_ENOUGH_SPACE': 'notEnoughSpace',
            'NOT_SUPPORTED_FORMAT': 'notSupportedFormat',
            'UNEXPECTED': 'unexpected',
          }[code],
        );
        expect(calls.where((m) => m == 'putImage').length, 1);
        expect(temporary.listSync(), isEmpty);
      },
    );
  }
  test('missing plugin is reported and never silently retried', () async {
    mock((call) async => throw MissingPluginException());
    expect(await M1SaveProbe().save(Uint8List(3), 'gif'), 'pluginUnavailable');
    expect(calls, ['hasAccess']);
  });
}
