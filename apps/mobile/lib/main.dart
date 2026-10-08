import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import 'hnuhole_mobile.dart';

void main() {
  final communityBaseUri = Uri.parse(
    const String.fromEnvironment(
      'AUTH_COMMUNITY_BASE_URL',
      defaultValue: 'https://community.hnuhole.invalid',
    ),
  );
  final verifierBaseUri = Uri.parse(
    const String.fromEnvironment(
      'AUTH_VERIFIER_BASE_URL',
      defaultValue: 'https://verifier.hnuhole.invalid',
    ),
  );
  final repository = HttpChannelRepository(baseUri: communityBaseUri);
  final directory = ChannelDirectoryController(repository: repository);
  final api = HttpAuthApi(
    communityBaseUri: communityBaseUri,
    verifierBaseUri: verifierBaseUri,
  );
  final storageScope =
      'hnuhole.isolated.auth.v1|$communityBaseUri|$verifierBaseUri';
  final storageNamespace = AuthCrypto.domainDigest(
    'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1',
    utf8.encode(storageScope),
  );
  final store = AuthStore(
    FlutterAuthVault(namespace: 'hnuhole.auth.v1.$storageNamespace'),
    scope: storageScope,
  );
  final sessions = AuthSessionController(
    api: api,
    store: store,
    directory: directory,
  );
  final postApi = HttpPostApi(communityBaseUri: communityBaseUri);
  final posts = PostController(
    api: postApi,
    sessions: sessions,
    authStore: store,
    identities: api,
    openStore: (accountId) =>
        PostStore.openNative(environment: storageScope, accountId: accountId),
    purgeStore: (accountId) => PostStore.purgeNativeClosedAccount(
      environment: storageScope,
      accountId: accountId,
    ),
  );
  final passkey = NativePasskeyClient();
  final management = SecurityManagementController(
    api: api,
    store: store,
    passkey: passkey,
    sessions: sessions,
  );
  final identities = IdentityManagementController(
    api: api,
    store: store,
    sessions: sessions,
  );
  final flows = AuthFlows(
    api: api,
    store: store,
    acceptRegistrationSession: sessions.acceptSession,
    clearCommunityAccess: sessions.clearCommunityAccess,
    passkeyApi: api,
    passkey: passkey,
    sessionAuthorityVersion: () => sessions.authorityVersion,
    sessionAuthority: sessions,
    onAccountClosed: posts.purgeClosedAccount,
  );

  runApp(
    _HnuholeApp(
      directory: directory,
      repository: repository,
      api: api,
      sessions: sessions,
      flows: flows,
      management: management,
      identities: identities,
      store: store,
      posts: posts,
      postApi: postApi,
    ),
  );
}

class _HnuholeApp extends StatefulWidget {
  const _HnuholeApp({
    required this.directory,
    required this.repository,
    required this.api,
    required this.sessions,
    required this.flows,
    required this.management,
    required this.identities,
    required this.store,
    required this.posts,
    required this.postApi,
  });

  final ChannelDirectoryController directory;
  final HttpChannelRepository repository;
  final HttpAuthApi api;
  final AuthSessionController sessions;
  final AuthFlows flows;
  final SecurityManagementController management;
  final IdentityManagementController identities;
  final AuthStore store;
  final PostController posts;
  final HttpPostApi postApi;

  @override
  State<_HnuholeApp> createState() => _HnuholeAppState();
}

class _HnuholeAppState extends State<_HnuholeApp> with WidgetsBindingObserver {
  final ChannelTreeSession _treeSession = ChannelTreeSession();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _authRouteOpen = false;
  bool _securityRouteOpen = false;
  bool _settingsRouteOpen = false;
  bool _identityRouteOpen = false;
  bool _personalRouteOpen = false;
  String? _channelRouteId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAuthentication();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.sessions.onActivity());
    }
  }

  Future<void> _startAuthentication() async {
    await widget.sessions.start();
    await widget.flows.restorePending();
    if (!mounted) return;
    if ({
      AuthStatus.closurePending,
      AuthStatus.resetPending,
      AuthStatus.unavailable,
      AuthStatus.storageFailure,
    }.contains(widget.sessions.status)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAuth();
      });
    }
  }

  void _openAuth() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _authRouteOpen) return;
    _authRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => AuthScreen(
              sessions: widget.sessions,
              flows: widget.flows,
              onAuthenticated: () => Navigator.of(context).pop(),
              onManageSecurity: _openSecurity,
            ),
          ),
        )
        .whenComplete(() => _authRouteOpen = false);
  }

  void _openSecurity() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _securityRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _securityRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => SecurityManagementScreen(
              controller: widget.management,
              sessions: widget.sessions,
              onAuthenticationRequired: () {
                Navigator.of(context).pop();
                _openAuth();
              },
            ),
          ),
        )
        .whenComplete(() => _securityRouteOpen = false);
  }

  void _openSettings() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _settingsRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _settingsRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => SettingsScreen(
              onManageIdentity: _openIdentity,
              onManageSecurity: _openSecurity,
            ),
          ),
        )
        .whenComplete(() => _settingsRouteOpen = false);
  }

  Future<void> _openIdentity() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _identityRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _identityRouteOpen = true;
    final account = widget.posts.accountId;
    final authority = widget.posts.authorityVersion;
    String identitySnapshot() =>
        widget.identities.directory?.identities
            .map(
              (identity) =>
                  '${identity.id}:${identity.nickname}:${identity.avatar}',
            )
            .join('|') ??
        '';
    final before = identitySnapshot();
    await navigator
        .push(
          MaterialPageRoute<void>(
            builder: (context) => IdentityManagementScreen(
              controller: widget.identities,
              sessions: widget.sessions,
              onAuthenticationRequired: () {
                Navigator.of(context).pop();
                _openAuth();
              },
            ),
          ),
        )
        .whenComplete(() => _identityRouteOpen = false);
    if (widget.posts.accountId == account &&
        widget.posts.authorityVersion == authority &&
        before != identitySnapshot()) {
      // 身份管理返回后读取当前投影；选择／创建身份仍不会自动发帖。
      await widget.posts.refreshPersonalProjections();
      await widget.posts.refreshKnownPosts();
    }
  }

  void _openPersonal() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _personalRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _personalRouteOpen = true;
    final account = widget.posts.accountId;
    final authority = widget.posts.authorityVersion;
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PersonalPostsScreen(
              controller: widget.posts,
              channelNames: {
                for (final channel in widget.directory.channels)
                  channel.id: channel.displayName,
              },
              onManageIdentities: _openIdentity,
              onAuthenticationRequired: _openAuth,
              onOpenSettings: _openSettings,
              onPublishedToChannel: (channelId) {
                if (widget.posts.accountId != account ||
                    widget.posts.authorityVersion != authority) {
                  return;
                }
                final channel = widget.directory.channels
                    .where((item) => item.id == channelId)
                    .firstOrNull;
                if (channel == null) return;
                if (_channelRouteId == channelId) {
                  navigator.popUntil(
                    (route) => route.settings.name == 'channel:$channelId',
                  );
                } else {
                  navigator.popUntil((route) => route.isFirst);
                  _openChannel(channel);
                }
              },
            ),
          ),
        )
        .whenComplete(() => _personalRouteOpen = false);
  }

  void _openChannel(Channel channel) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !widget.sessions.isAuthenticated) return;
    _channelRouteId = channel.id;
    final route = MaterialPageRoute<void>(
      settings: RouteSettings(name: 'channel:${channel.id}'),
      builder: (_) => ChannelPostsScreen(
        controller: widget.posts,
        channel: channel,
        onManageIdentities: _openIdentity,
        onAuthenticationRequired: _openAuth,
        onOpenPersonal: _openPersonal,
      ),
    );
    navigator.push(route).whenComplete(() {
      if (_channelRouteId == channel.id &&
          widget.posts.currentChannelId == channel.id) {
        _channelRouteId = null;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.management.dispose();
    widget.identities.dispose();
    widget.flows.dispose();
    widget.posts.dispose();
    widget.postApi.close();
    widget.sessions.dispose();
    widget.api.close();
    widget.directory.dispose();
    widget.repository.close();
    widget.store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hnuhole',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorKey: _navigatorKey,
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) {
          // Let the requested action (including logout) start first. Activity
          // is a user gesture, never a background timer or a build side effect.
          scheduleMicrotask(widget.sessions.onActivity);
        },
        child: child,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF76AFC8)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF76AFC8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: EntryScreen(
        directory: widget.directory,
        treeSession: _treeSession,
        onLoginRequested: _openAuth,
        onProfilePressed: _openPersonal,
        onChannelSelected: _openChannel,
      ),
    );
  }
}
