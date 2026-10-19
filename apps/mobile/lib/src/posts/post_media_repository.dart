import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import 'post_api.dart';
import 'post_controller.dart';
import 'post_images.dart';
import 'post_media_api.dart';

/// A bounded, in-memory authorization window. No disk cache or credential-bearing
/// provider is created. Each saved original repeats the protected HTTP read.
class PostMediaRepository {
  PostMediaRepository(this.posts) {
    posts.addListener(_authorityChanged);
  }
  final PostController posts;
  final _leases = <_MediaLease>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  bool _disposed = false;

  Future<T> _read<T>(Future<T> Function() action) async {
    if (_disposed) throw const PostFailure(kind: PostFailureKind.unauthorized);
    if (_active >= 2) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  void _authorityChanged() {
    for (final lease in _leases.toList()) {
      if (!lease.current) lease.revoke();
    }
  }

  Future<PostImages> load(String postId) async {
    final epoch = posts.authorityVersion;
    bool current() =>
        !_disposed &&
        posts.available &&
        posts.authorityVersion == epoch &&
        !posts.isPostDeleted(postId);
    if (!current()) throw const PostFailure(kind: PostFailureKind.unauthorized);
    final elapsed = Stopwatch()..start();
    final response = await posts.loadImageManifest(postId);
    final manifest = response.value;
    final lifetime = manifest.accessValidUntil.difference(response.serverTime);
    if (!current() ||
        manifest.postId != postId ||
        lifetime <= elapsed.elapsed ||
        lifetime > const Duration(seconds: 60) ||
        manifest.accessValidUntil.isAfter(response.sessionExpiresAt)) {
      throw const PostFailure(kind: PostFailureKind.invalidResponse);
    }
    final lease = _MediaLease(this, postId, current, elapsed, lifetime);
    _leases.add(lease);
    lease.start();
    return PostImages(
      postId: postId,
      accessGranted: lease.access,
      onRelease: lease.revoke,
      images: [
        for (var i = 0; i < manifest.images.length; i++)
          lease.image(manifest.images[i], i, manifest.images.length),
      ],
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    posts.removeListener(_authorityChanged);
    for (final lease in _leases.toList()) {
      lease.revoke();
    }
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(
        const PostFailure(kind: PostFailureKind.unauthorized),
      );
    }
  }
}

class _MediaLease {
  _MediaLease(
    this.owner,
    this.postId,
    this.authorized,
    this.elapsed,
    this.lifetime,
  );
  final PostMediaRepository owner;
  final String postId;
  final bool Function() authorized;
  final Stopwatch elapsed;
  final Duration lifetime;
  final access = ValueNotifier(true);
  final _providers = <MemoryImage>{};
  final _pending = <String, Future<MemoryImage>>{};
  Timer? _timer;
  bool get current =>
      access.value && authorized() && elapsed.elapsed < lifetime;
  void start() => _timer = Timer(lifetime - elapsed.elapsed, revoke);
  void check() {
    if (!current) {
      revoke();
      throw const PostFailure(kind: PostFailureKind.unauthorized);
    }
  }

  void revoke() {
    if (!access.value) return;
    _timer?.cancel();
    _pending.clear();
    for (final provider in _providers) {
      unawaited(provider.evict());
    }
    _providers.clear();
    owner._leases.remove(this);
    access.value = false;
  }

  Future<PostResponse<T>> read<T>(
    Future<PostResponse<T>> Function() action,
  ) async {
    check();
    try {
      final response = await owner._read(() {
        check();
        return action();
      });
      check();
      return response;
    } on PostFailure catch (error) {
      if ({401, 403, 404, 503}.contains(error.statusCode) ||
          error.kind == PostFailureKind.unauthorized ||
          error.kind == PostFailureKind.unavailable) {
        // A denied byte request invalidates every open lease for this post.
        for (final lease
            in owner._leases.where((l) => l.postId == postId).toList()) {
          lease.revoke();
        }
      }
      rethrow;
    }
  }

  Future<MemoryImage> provider(PostMediaImage item) {
    check();
    final existing = _pending[item.contentVersionId];
    if (existing != null) return existing;
    final future = (() async {
      try {
        final response = await read(
          () => owner.posts.loadImageBytes(postId, item),
        );
        final image = MemoryImage(response.value);
        _providers.add(image);
        return image;
      } catch (_) {
        _pending.remove(item.contentVersionId);
        rethrow;
      }
    })();
    _pending[item.contentVersionId] = future;
    return future;
  }

  PostImage image(PostMediaImage item, int index, int count) =>
      PostImage.deferred(
        pixelSize: Size(item.pixelWidth.toDouble(), item.pixelHeight.toDouble()),
        loadThumbnail: () => provider(item),
        item: ViewerItem(
          id: item.contentVersionId,
          semanticLabel: '第${index + 1}张图片，共$count张',
          saveAllowed: item.saveAllowed,
          loadSource: () async {
            final image = await provider(item);
            check();
            return ViewerSource(
              provider: image,
              pixelSize: Size(
                item.pixelWidth.toDouble(),
                item.pixelHeight.toDouble(),
              ),
            );
          },
          resolveOriginal: item.saveAllowed
              ? () async {
                  final response = await read(
                    () => owner.posts.loadImageBytes(postId, item),
                  );
                  return ViewerOriginal.bytes(
                    response.value,
                    switch (item.mimeType) {
                      'image/jpeg' => ViewerOriginalFormat.jpeg,
                      'image/png' => ViewerOriginalFormat.png,
                      'image/gif' => ViewerOriginalFormat.gif,
                      'image/webp' => ViewerOriginalFormat.webp,
                      _ => throw const PostFailure(
                        kind: PostFailureKind.invalidResponse,
                      ),
                    },
                  );
                }
              : null,
        ),
      );
}
