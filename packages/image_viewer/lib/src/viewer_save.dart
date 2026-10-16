import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Original formats accepted by the adapter; no conversion is performed.
enum ViewerOriginalFormat {
  png('png'),
  jpeg('jpg'),
  gif('gif'),
  webp('webp');

  const ViewerOriginalFormat(this.extension);
  final String extension;

  bool _matchesPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.$extension') ||
        (this == jpeg && lower.endsWith('.jpeg'));
  }
}

/// The caller resolves the complete original file, never a rendered preview.
///
/// This contract does not accept credentials. Bytes are snapshotted immediately
/// and written unchanged. A file remains caller-owned and must stay readable
/// until [ViewerSaveCoordinator.save] settles; the component never deletes it.
/// Format declarations and complete/valid media content are caller obligations.
sealed class ViewerOriginal {
  const ViewerOriginal._(this.format);

  factory ViewerOriginal.bytes(Uint8List bytes, ViewerOriginalFormat format) =
      _ViewerOriginalBytes;

  factory ViewerOriginal.file(String path, ViewerOriginalFormat format) =
      _ViewerOriginalFile;

  final ViewerOriginalFormat format;
}

class _ViewerOriginalBytes extends ViewerOriginal {
  _ViewerOriginalBytes(Uint8List bytes, super.format)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
      super._();
  final Uint8List bytes;
}

class _ViewerOriginalFile extends ViewerOriginal {
  _ViewerOriginalFile(this.path, super.format) : super._();
  final String path;
}

typedef ViewerOriginalResolver = Future<ViewerOriginal> Function();

/// Adapter seam. Fake implementations prove coordination, not system behavior.
abstract interface class ViewerGalleryWriter {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<void> putImage(String originalPath);
}

/// Opt-in gal adapter, requiring Android/iOS build and device validation.
///
/// Plugin completion, file integrity and actual gallery playback are separate
/// evidence. gal 2.3.3's iOS file-import force unwrap remains an unverified native
/// risk, especially for formats unsupported by Photos. No fallback conversion
/// or native bridge is introduced here. gal may also request access internally.
class GalViewerGalleryWriter implements ViewerGalleryWriter {
  const GalViewerGalleryWriter();
  @override
  Future<bool> hasAccess() => Gal.hasAccess();
  @override
  Future<bool> requestAccess() => Gal.requestAccess();
  @override
  Future<void> putImage(String originalPath) => Gal.putImage(originalPath);
}

enum ViewerSaveStatus {
  saved,
  busy,
  notAllowed,
  invalidItem,
  permissionDenied,
  permissionFailed,
  sourceFailed,
  invalidSource,
  resourceLimit,
  temporaryFileFailed,
  formatUnsupported,
  notEnoughSpace,
  pluginUnavailable,
  outcomeUnknown,
  cancelledBeforeWrite,
}

/// Contains no source path, URL or raw exception.
class ViewerSaveResult {
  const ViewerSaveResult({
    required this.itemId,
    required this.status,
    required this.systemWriteStarted,
    required this.isCurrent,
    this.cleanupFailed = false,
  });

  final String itemId;
  final ViewerSaveStatus status;

  /// True once the adapter has been called; cancellation is then not promised.
  final bool systemWriteStarted;

  /// Rechecked after cleanup. A false result must not produce viewer feedback.
  final bool isCurrent;

  /// A failed cleanup preserves the write result and can be retried separately.
  final bool cleanupFailed;

  String get message {
    final base = switch (status) {
      ViewerSaveStatus.saved => '已保存到相册',
      ViewerSaveStatus.busy => '正在保存，请稍候',
      ViewerSaveStatus.notAllowed => '此图片不允许保存',
      ViewerSaveStatus.invalidItem => '图片标识无效',
      ViewerSaveStatus.permissionDenied => '未获得相册保存权限，可允许权限后再试',
      ViewerSaveStatus.permissionFailed => '无法确认相册权限，请稍后再试',
      ViewerSaveStatus.sourceFailed => '无法取得原图片，可稍后重试',
      ViewerSaveStatus.invalidSource => '原图片内容或文件格式无效',
      ViewerSaveStatus.resourceLimit => '原图片超出保存上限，请选择其他图片',
      ViewerSaveStatus.temporaryFileFailed => '无法准备保存文件，请检查可用空间',
      ViewerSaveStatus.formatUnsupported => '系统相册不支持此图片格式',
      ViewerSaveStatus.notEnoughSpace => '可用空间不足，无法保存图片',
      ViewerSaveStatus.pluginUnavailable => '此环境无法使用相册保存功能',
      ViewerSaveStatus.outcomeUnknown => '保存结果未确认，请先检查相册；未自动重试',
      ViewerSaveStatus.cancelledBeforeWrite => '保存已停止',
    };
    return cleanupFailed ? '$base；临时文件清理失败' : base;
  }
}

enum _SavePhase { permission, source, temporaryFile, write }

/// One coordinator prevents overlapping saves, including after viewer closure.
///
/// Callers own and dispose it. [isCurrent] must include the viewer generation,
/// selection revision and stable ID; every async boundary checks that lease.
/// It must return false on close, access invalidation or source replacement.
/// An in-flight source read or system write may continue, but cannot start a
/// later stage after invalidation. No write is ever automatically retried.
///
/// The optional directory factory is an advanced adapter/testing seam: it must
/// create a fresh directory exclusively owned by this coordinator. Never return
/// a caller directory or shared cache. The default uses path_provider and an
/// operation-specific directory, retained only until the gallery future ends.
class ViewerSaveCoordinator {
  ViewerSaveCoordinator({
    required ViewerGalleryWriter gallery,
    this.maxOriginalBytes = 16 * 1024 * 1024,
    Future<Directory> Function()? createTemporaryDirectory,
    // Keep the public adapter argument named gallery and its storage private.
    // ignore: prefer_initializing_formals
  }) : _gallery = gallery,
       _createTemporaryDirectory =
           createTemporaryDirectory ?? _defaultTemporaryDirectory {
    if (maxOriginalBytes <= 0) {
      throw ArgumentError('Original byte limit must be positive.');
    }
  }

  final int maxOriginalBytes;

  final ViewerGalleryWriter _gallery;
  final Future<Directory> Function() _createTemporaryDirectory;
  final ValueNotifier<bool> _busyNotifier = ValueNotifier(false);
  final List<Directory> _failedCleanup = [];
  bool _busy = false;
  bool _active = true;
  bool _disposed = false;
  int _generation = 0;

  bool get busy => _busy;
  bool get active => _active && !_disposed;
  ValueListenable<bool> get busyListenable => _busyNotifier;
  int get pendingCleanupCount => _failedCleanup.length;

  static Future<Directory> _defaultTemporaryDirectory() async =>
      Directory((await getTemporaryDirectory()).path)
          .createTemp('hnuhole-image-viewer-');

  void _setBusy(bool value) {
    _busy = value;
    if (!_disposed) _busyNotifier.value = value;
  }

  /// Permanently stops new operations and invalidates any pending operation.
  /// The owner must rebuild/remove the saver when invalidating it directly;
  /// [busyListenable] reports busy changes rather than active-state changes.
  void invalidate() {
    if (!_active) return;
    _active = false;
    _generation++;
  }

  /// Does not claim to cancel a system write or delete a file still in use.
  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    _busyNotifier.dispose();
  }

  bool _current(int generation, bool Function()? isCurrent) {
    if (!_active || generation != _generation) return false;
    try {
      return isCurrent?.call() ?? true;
    } catch (_) {
      // A lease callback failure must fail closed, without leaking its error.
      return false;
    }
  }

  /// Attempts cleanup only for owned files whose system operation has settled.
  /// This never repeats gallery writes and remains usable after [dispose].
  Future<bool> retryCleanup() async {
    for (final directory in List<Directory>.of(_failedCleanup)) {
      if (await _removeOwned(directory)) _failedCleanup.remove(directory);
    }
    return _failedCleanup.isEmpty;
  }

  Future<bool> _removeOwned(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ViewerSaveResult> save({
    required String itemId,
    required ViewerOriginalResolver resolveOriginal,
    bool allowed = true,
    bool Function()? isCurrent,
  }) async {
    final generation = _generation;
    ViewerSaveResult immediate(ViewerSaveStatus status) => ViewerSaveResult(
      itemId: itemId,
      status: status,
      systemWriteStarted: false,
      isCurrent: _current(generation, isCurrent),
    );

    if (!allowed || !_active) return immediate(ViewerSaveStatus.notAllowed);
    if (itemId.trim().isEmpty || itemId.trim() != itemId) {
      return immediate(ViewerSaveStatus.invalidItem);
    }
    if (!_current(generation, isCurrent)) {
      return immediate(ViewerSaveStatus.cancelledBeforeWrite);
    }
    if (_busy) return immediate(ViewerSaveStatus.busy);

    _setBusy(true);
    var phase = _SavePhase.permission;
    var started = false;
    var cleanupFailed = false;
    Directory? temporary;
    var status = ViewerSaveStatus.outcomeUnknown;
    try {
      Future<ViewerSaveStatus> perform() async {
        if (!_current(generation, isCurrent)) {
          return ViewerSaveStatus.cancelledBeforeWrite;
        }
        final hasAccess = await _gallery.hasAccess();
        if (!_current(generation, isCurrent)) {
          return ViewerSaveStatus.cancelledBeforeWrite;
        }
        if (!hasAccess) {
          final granted = await _gallery.requestAccess();
          if (!_current(generation, isCurrent)) {
            return ViewerSaveStatus.cancelledBeforeWrite;
          }
          if (!granted) return ViewerSaveStatus.permissionDenied;
        }

        phase = _SavePhase.source;
        final original = await resolveOriginal();
        if (!_current(generation, isCurrent)) {
          return ViewerSaveStatus.cancelledBeforeWrite;
        }
        String path;
        switch (original) {
          case _ViewerOriginalFile():
            final file = File(original.path);
            if (!file.isAbsolute ||
                !original.format._matchesPath(original.path)) {
              return ViewerSaveStatus.invalidSource;
            }
            final length = await file.length();
            if (length == 0) return ViewerSaveStatus.invalidSource;
            if (length > maxOriginalBytes) {
              return ViewerSaveStatus.resourceLimit;
            }
            path = original.path;
          case _ViewerOriginalBytes():
            if (original.bytes.isEmpty) return ViewerSaveStatus.invalidSource;
            if (original.bytes.length > maxOriginalBytes) {
              return ViewerSaveStatus.resourceLimit;
            }
            phase = _SavePhase.temporaryFile;
            temporary = await _createTemporaryDirectory();
            if (!_current(generation, isCurrent)) {
              return ViewerSaveStatus.cancelledBeforeWrite;
            }
            final file = File(
              '${temporary!.path}/original.${original.format.extension}',
            );
            await file.writeAsBytes(original.bytes, flush: true);
            path = file.path;
        }

        if (!_current(generation, isCurrent)) {
          return ViewerSaveStatus.cancelledBeforeWrite;
        }
        phase = _SavePhase.write;
        started = true;
        await _gallery.putImage(path);
        return ViewerSaveStatus.saved;
      }

      status = await perform();
    } on GalException catch (error) {
      status = switch (error.type) {
        GalExceptionType.accessDenied => ViewerSaveStatus.permissionDenied,
        GalExceptionType.notEnoughSpace => ViewerSaveStatus.notEnoughSpace,
        GalExceptionType.notSupportedFormat =>
          ViewerSaveStatus.formatUnsupported,
        GalExceptionType.unexpected =>
          started
              ? ViewerSaveStatus.outcomeUnknown
              : ViewerSaveStatus.permissionFailed,
      };
    } on MissingPluginException {
      status = ViewerSaveStatus.pluginUnavailable;
    } catch (_) {
      status = switch (phase) {
        _SavePhase.permission => ViewerSaveStatus.permissionFailed,
        _SavePhase.source => ViewerSaveStatus.sourceFailed,
        _SavePhase.temporaryFile => ViewerSaveStatus.temporaryFileFailed,
        _SavePhase.write => ViewerSaveStatus.outcomeUnknown,
      };
    } finally {
      // Awaited putImage has settled; its file is no longer needed by the API.
      if (temporary != null) {
        cleanupFailed = !await _removeOwned(temporary!);
        if (cleanupFailed) _failedCleanup.add(temporary!);
      }
      _setBusy(false);
    }
    if (!started && !_current(generation, isCurrent)) {
      status = ViewerSaveStatus.cancelledBeforeWrite;
    }
    return ViewerSaveResult(
      itemId: itemId,
      status: status,
      systemWriteStarted: started,
      isCurrent: _current(generation, isCurrent),
      cleanupFailed: cleanupFailed,
    );
  }
}
