import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import 'hnuhole_mobile.dart';
import 'src/development/app_transport.dart';

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
  final repository = HttpChannelRepository(
    baseUri: communityBaseUri,
    client: createAppHttpClient(
      community: communityBaseUri,
      verifier: verifierBaseUri,
    ),
  );
  final directory = ChannelDirectoryController(repository: repository);
  final api = HttpAuthApi(
    communityBaseUri: communityBaseUri,
    verifierBaseUri: verifierBaseUri,
    passkeyRpId: developmentPasskeyRp(
      community: communityBaseUri,
      verifier: verifierBaseUri,
    ),
    client: createAppHttpClient(
      community: communityBaseUri,
      verifier: verifierBaseUri,
    ),
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
  });

  final ChannelDirectoryController directory;
  final HttpChannelRepository repository;
  final HttpAuthApi api;
  final AuthSessionController sessions;
  final AuthFlows flows;
  final SecurityManagementController management;
  final IdentityManagementController identities;
  final AuthStore store;

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
              onManageAccount: _openAuth,
            ),
          ),
        )
        .whenComplete(() => _settingsRouteOpen = false);
  }

  void _openIdentity() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _identityRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _identityRouteOpen = true;
    navigator
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.management.dispose();
    widget.identities.dispose();
    widget.flows.dispose();
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
        onProfilePressed: _openSettings,
        onChannelSelected: (channel) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Open ${channel.displayName}')),
          );
        },
      ),
    );
  }
}
