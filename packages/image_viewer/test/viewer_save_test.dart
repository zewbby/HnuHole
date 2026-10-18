import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';
import 'package:image/image.dart' as image;

/// These doubles cover coordinator behavior only, never Photos/MediaStore.
class FakeGalleryWriter implements ViewerGalleryWriter {
  final calls = <String>[];
  Future<bool> Function()? onHasAccess;
  Future<bool> Function()? onRequestAccess;
  Future<void> Function(String)? onWrite;

  @override
  Future<bool> hasAccess() async {
    calls.add('hasAccess');
    return await onHasAccess?.call() ?? true;
  }

  @override
  Future<bool> requestAccess() async {
    calls.add('requestAccess');
    return await onRequestAccess?.call() ?? true;
  }

  @override
  Future<void> putImage(String originalPath) async {
    calls.add('putImage');
    await onWrite?.call(originalPath);
  }
}

class FlakyOwnedDirectory extends Fake implements Directory {
  FlakyOwnedDirectory(this.real);
  final Directory real;
  bool failDelete = true;

  @override
  String get path => real.path;
  @override
  Future<bool> exists() => real.exists();
  @override
  Future<Directory> delete({bool recursive = false}) async {
    if (failDelete) {
      throw const FileSystemException('synthetic cleanup failure');
    }
    await real.delete(recursive: recursive);
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Uint8List webp;
  late FakeGalleryWriter gallery;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hnuhole-save-test-');
    webp = await File('example/assets/fixtures/animation.webp').readAsBytes();
    gallery = FakeGalleryWriter();
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  ViewerSaveCoordinator coordinator({
    Future<Directory> Function()? directoryFactory,
  }) {
    final saver = ViewerSaveCoordinator(
      gallery: gallery,
      createTemporaryDirectory:
          directoryFactory ?? () => temporary.createTemp('owned-'),
    );
    addTearDown(saver.dispose);
    return saver;
  }

  Future<ViewerOriginal> original() async =>
      ViewerOriginal.bytes(webp, ViewerOriginalFormat.webp);

  test(
    'forbidden, inactive, invalid IDs and stale leases read nothing',
    () async {
      final saver = coordinator();
      expect(saver.active, isTrue);
      var reads = 0;
      Future<ViewerOriginal> resolve() async {
        reads++;
        return original();
      }

      expect(
        (await saver.save(
          itemId: 'a',
          resolveOriginal: resolve,
          allowed: false,
        )).status,
        ViewerSaveStatus.notAllowed,
      );
      for (final id in ['', ' ', ' a']) {
        expect(
          (await saver.save(itemId: id, resolveOriginal: resolve)).status,
          ViewerSaveStatus.invalidItem,
        );
      }
      expect(
        (await saver.save(
          itemId: 'a',
          resolveOriginal: resolve,
          isCurrent: () => false,
        )).status,
        ViewerSaveStatus.cancelledBeforeWrite,
      );
      saver.invalidate();
      expect(saver.active, isFalse);
      expect(
        (await saver.save(itemId: 'a', resolveOriginal: resolve)).status,
        ViewerSaveStatus.notAllowed,
      );
      expect(reads, 0);
      expect(gallery.calls, isEmpty);
    },
  );

  test('permission denial does not resolve original or write', () async {
    gallery.onHasAccess = () async => false;
    gallery.onRequestAccess = () async => false;
    var reads = 0;
    final result = await coordinator().save(
      itemId: 'a',
      resolveOriginal: () async {
        reads++;
        return original();
      },
    );
    expect(result.status, ViewerSaveStatus.permissionDenied);
    expect(result.systemWriteStarted, isFalse);
    expect(reads, 0);
    expect(gallery.calls, ['hasAccess', 'requestAccess']);
    expect(temporary.listSync(), isEmpty);
  });

  test(
    'source failure is sanitized and allows a later explicit attempt',
    () async {
      final saver = coordinator();
      final failed = await saver.save(
        itemId: 'a',
        resolveOriginal: () async => throw StateError('private-source-secret'),
      );
      expect(failed.status, ViewerSaveStatus.sourceFailed);
      expect(failed.message, isNot(contains('private-source-secret')));
      expect(gallery.calls, ['hasAccess']);
      expect(saver.busy, isFalse);
      expect(
        (await saver.save(itemId: 'a', resolveOriginal: original)).status,
        ViewerSaveStatus.saved,
      );
    },
  );

  test('empty original and mismatched file extension are rejected', () async {
    final saver = coordinator();
    final file = File('${temporary.path}/caller.png');
    await file.writeAsBytes(webp);
    for (final source in [
      ViewerOriginal.bytes(Uint8List(0), ViewerOriginalFormat.webp),
      ViewerOriginal.file(file.path, ViewerOriginalFormat.webp),
      ViewerOriginal.file('relative.webp', ViewerOriginalFormat.webp),
    ]) {
      expect(
        (await saver.save(
          itemId: 'a',
          resolveOriginal: () async => source,
        )).status,
        ViewerSaveStatus.invalidSource,
      );
    }
    expect(gallery.calls.where((call) => call == 'putImage'), isEmpty);
    expect(await file.readAsBytes(), webp);
  });

  test('missing original file is source failure, never a write', () async {
    final result = await coordinator().save(
      itemId: 'a',
      resolveOriginal: () async => ViewerOriginal.file(
        '${temporary.path}/missing.webp',
        ViewerOriginalFormat.webp,
      ),
    );
    expect(result.status, ViewerSaveStatus.sourceFailed);
    expect(result.systemWriteStarted, isFalse);
    expect(gallery.calls, ['hasAccess']);
  });

  for (final name in ['animation.gif', 'animation.webp']) {
    test(
      'original $name bytes and extension reach adapter unchanged',
      () async {
        final bytes = await File('example/assets/fixtures/$name').readAsBytes();
        final format = name.endsWith('gif')
            ? ViewerOriginalFormat.gif
            : ViewerOriginalFormat.webp;
        final expectedHash = sha256.convert(bytes);
        String? captured;
        gallery.onWrite = (path) async {
          captured = path;
          expect(path, endsWith('.${format.extension}'));
          expect(sha256.convert(await File(path).readAsBytes()), expectedHash);
        };
        final result = await coordinator().save(
          itemId: name,
          resolveOriginal: () async => ViewerOriginal.bytes(bytes, format),
        );
        expect(result.status, ViewerSaveStatus.saved);
        expect(result.systemWriteStarted, isTrue);
        expect(result.isCurrent, isTrue);
        expect(File(captured!).existsSync(), isFalse);
        expect(temporary.listSync(), isEmpty);
      },
    );
  }

  test('byte snapshot cannot be changed during permission await', () async {
    final snapshot = Uint8List.fromList(webp);
    final source = ViewerOriginal.bytes(webp, ViewerOriginalFormat.webp);
    final pending = Completer<bool>();
    gallery.onHasAccess = () => pending.future;
    gallery.onWrite = (path) async {
      expect(await File(path).readAsBytes(), snapshot);
    };
    final saving = coordinator().save(
      itemId: 'a',
      resolveOriginal: () async => source,
    );
    webp.fillRange(0, webp.length, 0);
    pending.complete(true);
    expect((await saving).status, ViewerSaveStatus.saved);
  });

  test('caller files including .jpeg remain owned by caller', () async {
    final file = File('${temporary.path}/caller.jpeg');
    final bytes = image.encodeJpg(image.Image(width: 2, height: 2));
    await file.writeAsBytes(bytes);
    gallery.onWrite = (path) async => expect(path, file.path);
    final result = await coordinator().save(
      itemId: 'a',
      resolveOriginal: () async =>
          ViewerOriginal.file(file.path, ViewerOriginalFormat.jpeg),
    );
    expect(result.status, ViewerSaveStatus.saved);
    expect(await file.readAsBytes(), bytes);
    expect(temporary.listSync(), hasLength(1));
  });

  test(
    'duplicate click while system write awaits dispatches exactly once',
    () async {
      final entered = Completer<void>();
      final pending = Completer<void>();
      gallery.onWrite = (path) async {
        entered.complete();
        await pending.future;
      };
      final saver = coordinator();
      final saving = saver.save(itemId: 'a', resolveOriginal: original);
      await entered.future;
      expect(saver.busyListenable.value, isTrue);
      expect(
        (await saver.save(itemId: 'a', resolveOriginal: original)).status,
        ViewerSaveStatus.busy,
      );
      pending.complete();
      expect((await saving).status, ViewerSaveStatus.saved);
      expect(saver.busyListenable.value, isFalse);
      expect(gallery.calls.where((call) => call == 'putImage'), hasLength(1));
    },
  );

  test(
    'invalidation during permission request stops all later stages',
    () async {
      final pending = Completer<bool>();
      final entered = Completer<void>();
      gallery.onHasAccess = () async => false;
      gallery.onRequestAccess = () {
        entered.complete();
        return pending.future;
      };
      var reads = 0;
      final saver = coordinator();
      final saving = saver.save(
        itemId: 'a',
        resolveOriginal: () async {
          reads++;
          return original();
        },
      );
      await entered.future;
      saver.invalidate();
      pending.complete(true);
      final result = await saving;
      expect(result.status, ViewerSaveStatus.cancelledBeforeWrite);
      expect(result.isCurrent, isFalse);
      expect(result.systemWriteStarted, isFalse);
      expect(reads, 0);
      expect(gallery.calls, ['hasAccess', 'requestAccess']);
    },
  );

  test(
    'selection lease expires during resolver without staging or writing',
    () async {
      final pending = Completer<ViewerOriginal>();
      final entered = Completer<void>();
      var current = true;
      final saving = coordinator().save(
        itemId: 'a',
        isCurrent: () => current,
        resolveOriginal: () {
          entered.complete();
          return pending.future;
        },
      );
      await entered.future;
      current = false;
      pending.complete(await original());
      final result = await saving;
      expect(result.status, ViewerSaveStatus.cancelledBeforeWrite);
      expect(result.systemWriteStarted, isFalse);
      expect(result.isCurrent, isFalse);
      expect(temporary.listSync(), isEmpty);
      expect(gallery.calls, ['hasAccess']);
    },
  );

  test(
    'close during staging cleans owned directory before any system write',
    () async {
      final pending = Completer<Directory>();
      final entered = Completer<void>();
      var current = true;
      final saver = coordinator(
        directoryFactory: () {
          entered.complete();
          return pending.future;
        },
      );
      final saving = saver.save(
        itemId: 'a',
        resolveOriginal: original,
        isCurrent: () => current,
      );
      await entered.future;
      current = false;
      pending.complete(await temporary.createTemp('owned-'));
      final result = await saving;
      expect(result.status, ViewerSaveStatus.cancelledBeforeWrite);
      expect(result.systemWriteStarted, isFalse);
      expect(temporary.listSync(), isEmpty);
      expect(gallery.calls, ['hasAccess']);
    },
  );

  test(
    'post-dispatch dispose cannot cancel write or emit late busy callback',
    () async {
      final pending = Completer<void>();
      final entered = Completer<void>();
      String? captured;
      gallery.onWrite = (path) async {
        captured = path;
        entered.complete();
        await pending.future;
        expect(await File(path).exists(), isTrue);
      };
      final saver = coordinator();
      var notifications = 0;
      saver.busyListenable.addListener(() => notifications++);
      final saving = saver.save(itemId: 'a', resolveOriginal: original);
      await entered.future;
      saver.dispose();
      pending.complete();
      final result = await saving;
      expect(result.status, ViewerSaveStatus.saved);
      expect(result.isCurrent, isFalse);
      expect(result.systemWriteStarted, isTrue);
      expect(notifications, 1);
      expect(saver.busy, isFalse);
      expect(await File(captured!).exists(), isFalse);
    },
  );

  test(
    'temporary filesystem failure resets busy and never dispatches',
    () async {
      final saver = coordinator(
        directoryFactory: () async {
          throw const FileSystemException('synthetic staging failure');
        },
      );
      final result = await saver.save(itemId: 'a', resolveOriginal: original);
      expect(result.status, ViewerSaveStatus.temporaryFileFailed);
      expect(result.systemWriteStarted, isFalse);
      expect(saver.busy, isFalse);
      expect(gallery.calls, ['hasAccess']);
    },
  );

  test('cleanup failure preserves write result, resets busy and only retries cleanup', () async {
    late FlakyOwnedDirectory owned;
    final saver = coordinator(
      directoryFactory: () async {
        owned = FlakyOwnedDirectory(await temporary.createTemp('owned-'));
        return owned;
      },
    );
    final result = await saver.save(itemId: 'a', resolveOriginal: original);
    expect(result.status, ViewerSaveStatus.saved);
    expect(result.cleanupFailed, isTrue);
    expect(result.message, contains('临时文件清理失败'));
    expect(saver.busy, isFalse);
    expect(saver.pendingCleanupCount, 1);
    expect(await saver.retryCleanup(), isFalse);
    owned.failDelete = false;
    saver.dispose();
    expect(await saver.retryCleanup(), isTrue);
    expect(saver.pendingCleanupCount, 0);
    expect(temporary.listSync(), isEmpty);
    expect(gallery.calls.where((call) => call == 'putImage'), hasLength(1));
  });

  final statuses = {
    GalExceptionType.accessDenied: ViewerSaveStatus.permissionDenied,
    GalExceptionType.notSupportedFormat: ViewerSaveStatus.formatUnsupported,
    GalExceptionType.notEnoughSpace: ViewerSaveStatus.notEnoughSpace,
    GalExceptionType.unexpected: ViewerSaveStatus.outcomeUnknown,
  };
  for (final entry in statuses.entries) {
    test('adapter ${entry.key.name} maps safely without write retry', () async {
      gallery.onWrite = (path) async => throw GalException(
        type: entry.key,
        platformException: PlatformException(
          code: entry.key.code,
          message: 'private-error-secret',
        ),
        stackTrace: StackTrace.current,
      );
      final saver = coordinator();
      final result = await saver.save(itemId: 'a', resolveOriginal: original);
      expect(result.status, entry.value);
      expect(result.message, isNot(contains('private-error-secret')));
      expect(result.systemWriteStarted, isTrue);
      expect(saver.busy, isFalse);
      expect(temporary.listSync(), isEmpty);
      expect(gallery.calls.where((call) => call == 'putImage'), hasLength(1));
    });
  }

  test(
    'missing plugin during permission is distinct from an unknown write',
    () async {
      gallery.onHasAccess = () async => throw MissingPluginException();
      final result = await coordinator().save(
        itemId: 'a',
        resolveOriginal: original,
      );
      expect(result.status, ViewerSaveStatus.pluginUnavailable);
      expect(result.systemWriteStarted, isFalse);
      expect(gallery.calls, ['hasAccess']);
    },
  );

  test(
    'late unknown write retains uncertainty and suppresses current feedback',
    () async {
      final entered = Completer<void>();
      final pending = Completer<void>();
      var current = true;
      gallery.onWrite = (path) async {
        entered.complete();
        await pending.future;
        throw StateError('private-write-secret');
      };
      final saver = coordinator();
      final saving = saver.save(
        itemId: 'a',
        resolveOriginal: original,
        isCurrent: () => current,
      );
      await entered.future;
      current = false;
      pending.complete();
      final result = await saving;
      expect(result.status, ViewerSaveStatus.outcomeUnknown);
      expect(result.isCurrent, isFalse);
      expect(result.systemWriteStarted, isTrue);
      expect(result.message, contains('请先检查相册'));
      expect(result.message, isNot(contains('private-write-secret')));
      expect(gallery.calls.where((call) => call == 'putImage'), hasLength(1));
    },
  );
}
