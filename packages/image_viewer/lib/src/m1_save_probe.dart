import 'dart:io';

import 'package:gal/gal.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Actual gal call only. Fake-channel tests cannot prove Photos/MediaStore.
class M1SaveProbe {
  bool _busy = false;
  bool _active = true;
  int _generation = 0;
  bool get busy => _busy;
  void invalidate() {
    _active = false;
    _generation++;
  }

  Future<String> save(
    Uint8List bytes,
    String extension, {
    bool allowed = true,
  }) async {
    if (!allowed || !_active) return 'notAllowed';
    if (_busy) return 'busy';
    if (!['png', 'jpg', 'gif', 'webp'].contains(extension)) {
      return 'unsupported';
    }
    _busy = true;
    final generation = _generation;
    Directory? temporary;
    var cleanupFailed = false;
    Future<String> perform() async {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        return 'accessDenied';
      }
      if (!_active || generation != _generation) return 'cancelledBeforeWrite';
      temporary = await Directory((await getTemporaryDirectory()).path)
          .createTemp('hnuhole-image-m1-');
      final file = File('${temporary!.path}/fixture.$extension');
      await file.writeAsBytes(bytes, flush: true);
      if (!_active || generation != _generation) return 'cancelledBeforeWrite';
      await Gal.putImage(file.path);
      return _active && generation == _generation
          ? 'written'
          : 'writtenAfterInvalidation';
    }

    String result;
    try {
      result = await perform();
    } on GalException catch (e) {
      result = e.type.name;
    } on MissingPluginException {
      result = 'pluginUnavailable';
    } on FileSystemException {
      result = 'temporaryFileFailed';
    } finally {
      // putImage future has finished before owned temporary files are deleted.
      try {
        if (temporary != null && await temporary!.exists()) {
          await temporary!.delete(recursive: true);
        }
      } catch (_) {
        cleanupFailed = true;
      } finally {
        _busy = false;
      }
    }
    // Preserve the known write result rather than replacing it with cleanup.
    return cleanupFailed ? '$result:temporaryCleanupFailed' : result;
  }
}
