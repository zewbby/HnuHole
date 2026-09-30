import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

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
  final flows = AuthFlows(
    api: api,
    store: store,
    acceptRegistrationSession: sessions.acceptSession,
    clearCommunityAccess: sessions.clearCommunityAccess,
  );

  runApp(
    _HnuholeApp(
      directory: directory,
      repository: repository,
      api: api,
      sessions: sessions,
      flows: flows,
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
  });

  final ChannelDirectoryController directory;
  final HttpChannelRepository repository;
  final HttpAuthApi api;
  final AuthSessionController sessions;
  final AuthFlows flows;

  @override
  State<_HnuholeApp> createState() => _HnuholeAppState();
}

class _HnuholeAppState extends State<_HnuholeApp> with WidgetsBindingObserver {
  final ChannelTreeSession _treeSession = ChannelTreeSession();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _authRouteOpen = false;

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
            ),
          ),
        )
        .whenComplete(() => _authRouteOpen = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.flows.dispose();
    widget.sessions.dispose();
    widget.api.close();
    widget.directory.dispose();
    widget.repository.close();
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
        onProfilePressed: _openAuth,
        onChannelSelected: (channel) {
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Open ${channel.displayName}')),
          );
        },
      ),
    );
  }
}
