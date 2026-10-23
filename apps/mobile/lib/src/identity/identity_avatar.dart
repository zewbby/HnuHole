import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_models.dart';
import '../auth/auth_store.dart';
import '../auth/auth_session_controller.dart';
import '../design_system/telegram_theme.dart';
import 'identity_api.dart';

/// Only the pinned authenticated transport resolves opaque avatar references.
/// Bytes stay in a bounded memory cache scoped to the exact authorization window.
class IdentityAvatarRepository extends ChangeNotifier {
  IdentityAvatarRepository(this.api, this.sessions, this.store) {
    sessions.addListener(_changed);
    _changed();
  }
  final IdentityAvatarApi api;
  final AuthStore store;
  final AuthSessionController sessions;
  final _cache = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _providers = <(String, int), ImageProvider>{};
  Object? _window;
  bool _disposed = false;
  void _changed() {
    final session = store.current?.session;
    final next = sessions.isAuthenticated
        ? (session?.accountId, session?.token, sessions.authorityVersion)
        : null;
    if (next != _window) {
      _window = next;
      _cache.clear();
      _pending.clear();
      _clearProviders();
      notifyListeners();
    }
  }

  ImageProvider imageFor(String avatar, Uint8List bytes, int width) {
    final key = (avatar, width);
    final old = _providers.remove(key);
    final provider =
        old ?? ResizeImage.resizeIfNeeded(width, null, MemoryImage(bytes));
    _providers[key] = provider;
    while (_providers.length > 72) {
      unawaited(_providers.remove(_providers.keys.first)!.evict());
    }
    return provider;
  }

  void _clearProviders() {
    for (final provider in _providers.values) {
      unawaited(provider.evict());
    }
    _providers.clear();
  }

  Future<Uint8List?> load(String avatar) {
    if (_disposed ||
        _window == null ||
        !validIdentityAvatar(avatar) ||
        avatar == 'default-v1') {
      return Future.value();
    }
    final cached = _cache.remove(avatar);
    if (cached != null) {
      _cache[avatar] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(avatar, () => _fetch(avatar));
  }

  Future<Uint8List?> _fetch(String avatar) async {
    final window = _window, token = store.current!.session!.token;
    bool current() =>
        !_disposed && _window == window && sessions.isCurrentToken(token);
    try {
      final result = await api.readIdentityAvatar(
        sessionToken: token,
        avatar: avatar,
      );
      if (!current() || result.bytes == null) return null;
      if (!await sessions.persistSessionMetadata(
            token,
            result.sessionExpiresAt,
            current,
          ) ||
          !current()) {
        return null;
      }
      _cache[avatar] = result.bytes!;
      while (_cache.length > 24) {
        final expired = _cache.keys.first;
        _cache.remove(expired);
        for (final key
            in _providers.keys.where((key) => key.$1 == expired).toList()) {
          unawaited(_providers.remove(key)!.evict());
        }
      }
      return result.bytes;
    } on AuthFailure catch (failure) {
      if (current()) {
        if (failure.unauthorized) {
          sessions.sessionUnauthorized(token, failure.code);
        }
        if (failure.kind == AuthFailureKind.unavailable) {
          sessions.sessionUnavailable(token);
        }
      }
      return null;
    } on Object {
      return null;
    } finally {
      if (current()) _pending.remove(avatar);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    sessions.removeListener(_changed);
    _cache.clear();
    _pending.clear();
    _clearProviders();
    super.dispose();
  }
}

class IdentityAvatarScope extends InheritedNotifier<IdentityAvatarRepository> {
  const IdentityAvatarScope({
    super.key,
    required IdentityAvatarRepository repository,
    required super.child,
  }) : super(notifier: repository);
}

class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({
    super.key,
    this.avatar = 'default-v1',
    this.radius = 24,
    this.fallback,
  });
  final String avatar;
  final double radius;
  final Widget? fallback;
  @override
  Widget build(BuildContext context) {
    final palette = HhTelegramPalette.of(context);
    final placeholder =
        (avatar != 'inactive-v1' ? fallback : null) ??
        CircleAvatar(
          radius: radius,
          backgroundColor: palette.raised,
          foregroundColor: palette.secondary,
          child: Icon(
            avatar == 'inactive-v1'
                ? Icons.person_off_outlined
                : Icons.person_outline_rounded,
            size: radius * 1.25,
          ),
        );
    final repository = context
        .dependOnInheritedWidgetOfExactType<IdentityAvatarScope>()
        ?.notifier;
    if (repository == null || !avatar.startsWith('avatar-v1:')) {
      return placeholder;
    }
    return FutureBuilder<Uint8List?>(
      key: ValueKey((avatar, repository._window)),
      future: repository.load(avatar),
      builder: (context, result) => result.data == null
          ? placeholder
          : ClipOval(
              child: Image(
                image: repository.imageFor(
                  avatar,
                  result.data!,
                  (radius * 2 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                ),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: false,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}
