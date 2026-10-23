import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import 'post_api.dart';
import 'post_controller.dart';
import 'post_images.dart';
import 'post_media_api.dart';

typedef _MediaKey = (String?, int, String);

/// Shares protected bytes within their original authorization deadline. Idle
/// resources use a bounded LRU; displayed resources remain owned by consumers.
/// Nothing is written to disk, and saving always reauthorizes original bytes.
class PostMediaRepository {
  PostMediaRepository(
    this.posts, {
    this.maxIdleEntries = 12,
    this.maxIdleBytes = 48 * 1024 * 1024,
  }) : assert(maxIdleEntries >= 0),
       assert(maxIdleBytes >= 0) {
    posts.addListener(_authorityChanged);
  }
  final PostController posts;
  final int maxIdleEntries, maxIdleBytes;
  final _entries = <_MediaKey, _MediaLease>{};
  final _manifests = <_MediaKey, Future<_MediaLease>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  bool _disposed = false;

  @visibleForTesting
  int get idleGroupCount =>
      _entries.values.where((l) => l.references == 0).length;
  @visibleForTesting
  int get idleBytes => _entries.values
      .where((l) => l.references == 0)
      .fold(0, (sum, l) => sum + l.weight);

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
    for (final lease in _entries.values.toList()) {
      if (!lease.current) lease.revoke();
    }
  }

  Future<PostImages> load(String postId) async {
    final key = (posts.accountId, posts.authorityVersion, postId);
    bool current() =>
        !_disposed &&
        posts.available &&
        posts.accountId == key.$1 &&
        posts.authorityVersion == key.$2 &&
        !posts.isPostDeleted(postId);
    if (!current()) throw const PostFailure(kind: PostFailureKind.unauthorized);
    final cached = _entries[key];
    if (cached != null && cached.current) {
      _touch(cached);
      return cached.acquire();
    }
    cached?.revoke();
    final future = _manifests.putIfAbsent(key, () async {
      final elapsed = Stopwatch()..start();
      final response = await posts.loadImageManifest(postId);
      final manifest = response.value;
      final lifetime = manifest.accessValidUntil.difference(
        response.serverTime,
      );
      if (!current() ||
          manifest.postId != postId ||
          lifetime <= elapsed.elapsed ||
          lifetime > const Duration(seconds: 60) ||
          manifest.accessValidUntil.isAfter(response.sessionExpiresAt)) {
        throw const PostFailure(kind: PostFailureKind.invalidResponse);
      }
      final lease = _MediaLease(
        this,
        key,
        manifest,
        current,
        elapsed,
        lifetime,
      );
      _entries[key] = lease;
      lease.start();
      return lease;
    });
    try {
      final lease = await future;
      if (!current()) {
        lease.revoke();
        throw const PostFailure(kind: PostFailureKind.unauthorized);
      }
      return lease.acquire();
    } finally {
      if (identical(_manifests[key], future)) _manifests.remove(key);
    }
  }

  void _touch(_MediaLease lease) {
    if (identical(_entries[lease.key], lease)) {
      _entries.remove(lease.key);
      _entries[lease.key] = lease;
    }
  }

  void _idle(_MediaLease lease) {
    if (lease.references != 0) return;
    // An abandoned request must not occupy a byte slot or publish late bytes.
    if (lease.inFlight != 0) {
      lease.revoke();
      return;
    }
    _touch(lease);
    while (idleGroupCount > maxIdleEntries || idleBytes > maxIdleBytes) {
      _entries.values.firstWhere((l) => l.references == 0).revoke();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    posts.removeListener(_authorityChanged);
    for (final lease in _entries.values.toList()) {
      lease.revoke();
    }
    _manifests.clear();
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
    this.key,
    this.manifest,
    this.authorized,
    this.elapsed,
    this.lifetime,
  );
  final PostMediaRepository owner;
  final _MediaKey key;
  final PostMediaManifest manifest;
  final bool Function() authorized;
  final Stopwatch elapsed;
  final Duration lifetime;
  final _consumers = <ValueNotifier<bool>>{};
  final _providers = <ImageProvider>{};
  final _pending = <String, Future<MemoryImage>>{};
  final _decodeKeys = <(ImageProvider, int?, int?, ResizeImagePolicy)>{};
  Timer? _timer;
  bool _revoked = false;
  int inFlight = 0, weight = 0;
  String get postId => key.$3;
  int get references => _consumers.length;
  bool get current => !_revoked && authorized() && elapsed.elapsed < lifetime;
  void start() => _timer = Timer(lifetime - elapsed.elapsed, revoke);
  void check() {
    if (!current) {
      revoke();
      throw const PostFailure(kind: PostFailureKind.unauthorized);
    }
  }

  void revoke() {
    if (_revoked) return;
    _revoked = true;
    _timer?.cancel();
    _pending.clear();
    for (final provider in _providers) {
      unawaited(provider.evict());
    }
    _providers.clear();
    _decodeKeys.clear();
    if (identical(owner._entries[key], this)) owner._entries.remove(key);
    for (final access in _consumers.toList()) {
      access.value = false;
    }
    _consumers.clear();
    weight = 0;
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
      if (current &&
          ({401, 403, 404, 503}.contains(error.statusCode) ||
              error.kind == PostFailureKind.unauthorized ||
              error.kind == PostFailureKind.unavailable)) {
        revoke();
      }
      rethrow;
    }
  }

  Future<MemoryImage> provider(PostMediaImage item) {
    check();
    final existing = _pending[item.path];
    if (existing != null) return existing;
    inFlight++;
    final future = (() async {
      try {
        final response = await read(
          () => owner.posts.loadImageBytes(postId, item),
        );
        final image = MemoryImage(response.value);
        _providers.add(image);
        // Conservative decoded-size estimate; resized variants are tracked too.
        weight +=
            response.value.length +
            item.pixelWidth * item.pixelHeight * item.frames * 4;
        return image;
      } catch (_) {
        _pending.remove(item.path);
        rethrow;
      } finally {
        inFlight--;
      }
    })();
    _pending[item.path] = future;
    return future;
  }

  Future<MemoryImage> retryProvider(PostMediaImage item) async {
    check();
    final previous = _pending.remove(item.path);
    if (previous != null) {
      MemoryImage? image;
      try {
        image = await previous;
      } catch (_) {
        // Failed transfers already remove themselves from the pending map.
      }
      check();
      if (image != null) {
        final removed = _providers
            .where(
              (p) => p == image || p is ResizeImage && p.imageProvider == image,
            )
            .toList();
        for (final p in removed) {
          _providers.remove(p);
          weight -= p is ResizeImage
              ? (p.width ?? 640) * (p.height ?? 640) * item.frames * 4
              : image.bytes.length +
                    item.pixelWidth * item.pixelHeight * item.frames * 4;
        }
        _decodeKeys.removeWhere((k) => k.$1 == image);
        await Future.wait([for (final p in removed) p.evict()]);
      }
    }
    check();
    return provider(item);
  }

  PostImages acquire() {
    check();
    final access = ValueNotifier(true);
    _consumers.add(access);
    void held() {
      check();
      if (!access.value) {
        throw const PostFailure(kind: PostFailureKind.unauthorized);
      }
    }

    return PostImages(
      postId: postId,
      accessGranted: access,
      onRelease: () {
        if (!_consumers.remove(access)) return;
        access.value = false;
        owner._idle(this);
      },
      images: [
        for (var i = 0; i < manifest.images.length; i++)
          _image(manifest.images[i], i, manifest.images.length, held),
      ],
    );
  }

  PostImage _image(
    PostMediaImage item,
    int index,
    int count,
    VoidCallback held,
  ) => PostImage.deferred(
    pixelSize: Size(item.pixelWidth.toDouble(), item.pixelHeight.toDouble()),
    animated: item.frames > 1,
    registerDecodeProvider: (provider) {
      held();
      if (provider is ResizeImage &&
          _decodeKeys.add((
            provider.imageProvider,
            provider.width,
            provider.height,
            provider.policy,
          ))) {
        _providers.add(provider);
        weight +=
            (provider.width ?? 640) *
            (provider.height ?? 640) *
            item.preview.frames *
            4;
      }
    },
    loadThumbnail: () async {
      held();
      final image = await provider(item.preview);
      held();
      return image;
    },
    retryThumbnail: () async {
      held();
      final image = await retryProvider(item.preview);
      held();
      return image;
    },
    item: ViewerItem(
      id: item.contentVersionId,
      semanticLabel: '第${index + 1}张图片，共$count张',
      saveAllowed: item.saveAllowed,
      loadSource: () async {
        held();
        final image = await provider(item);
        held();
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
              held();
              final response = await read(
                () => owner.posts.loadImageBytes(postId, item),
              );
              held();
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
