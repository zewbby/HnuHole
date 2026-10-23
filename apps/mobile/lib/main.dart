import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hnuhole_auth_passkey/hnuhole_auth_passkey.dart';

import 'hnuhole_mobile.dart';
import 'src/comments/comment_runtime.dart';
import 'src/comments/comment_http.dart';
import 'src/comments/comment_journal.dart';
import 'src/development/app_transport.dart';
import 'src/navigation/community_material_labels.dart';
import 'src/navigation/app_navigation.dart';
import 'src/messaging/direct_messages_unavailable.dart';
import 'src/messaging/dm_runtime.dart';
import 'src/messaging/dm_controller.dart';
import 'src/messaging/dm_store.dart';
import 'src/messaging/dm_notifications.dart';
import 'src/messaging/dm_governance_ui.dart';
import 'src/messaging/direct_message_models.dart';
import 'src/design_system/telegram_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HhTelegramTheme.registerFontLicenses();
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
  final environment = MobileEnvironment(
    communityBaseUri: communityBaseUri,
    verifierBaseUri: verifierBaseUri,
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
  final storageScope = environment.storageScope;
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
  final postApi = HttpPostUploadApi(
    communityBaseUri: communityBaseUri,
    client: createAppHttpClient(
      community: communityBaseUri,
      verifier: verifierBaseUri,
    ),
  );
  final posts = PostController(
    api: postApi,
    mediaApi: postApi,
    uploadApi: postApi,
    photoPicker: NativePostPhotoPicker(),
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
  final postMedia = PostMediaRepository(posts);
  final governanceApi = HttpGovernanceApi(
    baseUri: communityBaseUri,
    client: createAppHttpClient(
      community: communityBaseUri,
      verifier: verifierBaseUri,
    ),
  );
  final moderationAccess = ModerationAccess(
    api: governanceApi,
    vault: FlutterAuthVault(
      namespace: 'hnuhole.moderation-access.v1.$storageNamespace',
    ),
  );
  final governance = GovernanceController(
    api: governanceApi,
    sessions: sessions,
    authStore: store,
    identitiesApi: api,
    restrictedAccess: moderationAccess,
    pendingStore: GovernancePendingStore(
      GovernanceMaterialVault(
        openStore: () => PostStore.openNative(
          environment: '$storageScope|governance-material-v1',
          accountId: 'governance-pending-owners',
        ),
      ),
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
  final comments = CommentRuntime(
    http: CommentHttp(
      communityBaseUri,
      client: createAppHttpClient(
        community: communityBaseUri,
        verifier: verifierBaseUri,
      ),
    ),
    sessions: sessions,
    authStore: store,
    identities: api,
    identityManagement: identities,
    journal: NativeCommentJournal(
      (account) => PostStore.openNative(
        environment: '$storageScope|comments-v1',
        accountId: account,
      ),
      purgeStore: (account) => PostStore.purgeNativeClosedAccount(
        environment: '$storageScope|comments-v1',
        accountId: account,
      ),
    ),
  );
  comments.openRetarget = (context, input, bytes) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            controller: posts,
            postId: input.binding.postId,
            loadImages: postMedia.load,
            initialCommentInput: input,
            initialCommentOriginal: bytes,
          ),
        ),
      );
  late final DmRuntime dm;
  final dmNotifications = DmNotifications(
    environment: storageScope,
    preferences: FlutterAuthVault(
      namespace: 'hnuhole.dm.notification.$storageNamespace',
    ),
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
    onAccountClosed: (accountId) async {
      await dm.purgeClosedAccount(accountId);
      await dmNotifications.purge(accountId);
      await posts.purgeClosedAccount(accountId);
      await comments.purgeClosedAccount(accountId);
      await governance.purgeClosedAccount(accountId);
    },
  );

  dm = DmRuntime(
    controller: DmController(
      chatEnabled: true,
      api: postApi,
      openStore: (account) => DmStore.openNative(storageScope, account),
      purgeStore: (account) => DmStore.purgeNativeClosedAccount(
        environment: storageScope,
        accountId: account,
      ),
      onIncoming: (items, account) =>
          dmNotifications.incoming(items, account, dm.controller),
      onUnauthorized: sessions.sessionUnauthorized,
      onUnavailable: sessions.sessionUnavailable,
      onMetadata: (token, expires, current) async {
        await sessions.persistSessionMetadata(token, expires, current);
      },
    ),
    sessions: sessions,
    authStore: store,
    identityApi: api,
    identityChanges: identities,
    openPost: (context, id) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          controller: posts,
          postId: id,
          loadImages: postMedia.load,
        ),
      ),
    ),
  );
  runApp(
    HnuholeApp(
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
      postMedia: postMedia,
      loadPostImages: postMedia.load,
      comments: comments,
      governance: governance,
      governanceApi: governanceApi,
      dm: dm,
      dmNotifications: dmNotifications,
    ),
  );
}

/// The production root used by main and by the real-transport integration test.
/// Dependencies remain the shipped controllers/adapters; native ports are
/// replaced only in the host fixture, whose proof does not cover devices.
class HnuholeApp extends StatefulWidget {
  const HnuholeApp({
    super.key,
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
    this.loadPostImages,
    this.postMedia,
    this.governance,
    this.governanceApi,
    this.comments,
    this.dm,
    this.dmNotifications,
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
  final PostImagesLoader? loadPostImages;
  final PostMediaRepository? postMedia;
  final GovernanceController? governance;
  final CommentRuntime? comments;
  final HttpGovernanceApi? governanceApi;
  final DmRuntime? dm;
  final DmNotifications? dmNotifications;

  @override
  State<HnuholeApp> createState() => _HnuholeAppState();
}

class _HnuholeAppState extends State<HnuholeApp> with WidgetsBindingObserver {
  final _authPresentation = AuthPresentationController(
    preferences: FlutterAuthVault(namespace: 'hnuhole.presentation.v1'),
  );
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _authRouteOpen = false;
  bool _securityRouteOpen = false;
  bool _settingsRouteOpen = false;
  bool _identityRouteOpen = false;
  bool _personalRouteOpen = false;
  final _postWindow = ValueNotifier<(String?, int)>((null, -1));
  // Navigation preference is local to this app run and to its owning account.
  final _homeChannels = <String, String?>{};
  late final Listenable _postRouteChanges;
  bool _messagesRouteOpen = false;
  bool _directMessagesRouteOpen = false;
  bool _handlingDmTap = false;
  Future<void> _dmNotificationChanged() async {
    final n = widget.dmNotifications, c = widget.dm?.controller;
    if (n == null || c == null || !mounted) return;
    await n.bind(c.available ? c.accountId : null);
    await n.reconcile(c);
    if (!mounted || _handlingDmTap || n.pending == null) return;
    final target = n.pending!;
    final account = widget.store.current?.session?.accountId;
    if (account != null && target.scope != n.scopeFor(account)) {
      n.pending = null;
      return;
    }
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    if (!c.available || c.accountId == null) return;
    if (target.scope != n.scopeFor(c.accountId!)) {
      n.pending = null;
      return;
    }
    final row = c.conversations
        .where(
          (r) =>
              r['id'] == target.conversation &&
              r['identityId'] == target.identity,
        )
        .firstOrNull;
    final own = widget.dm!.identities
        .where((i) => i.id == target.identity)
        .firstOrNull;
    // A cold local directory may still be waiting for its first server sync.
    if (row == null || own == null) return;
    if (row['deleted'] == true) {
      n.pending = null;
      return;
    }
    _handlingDmTap = true;
    n.pending = null;
    final navigator = _navigatorKey.currentState;
    if (navigator != null) {
      navigator.popUntil((r) => r.isFirst);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => DmInboxRoute(
              runtime: widget.dm!,
              initialIdentity: own.id,
              navigation: _primaryNavigation(AppDestination.directMessages),
            ),
          ),
        ),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => DmChatRoute(
              runtime: widget.dm!,
              own: own,
              peer: DmIdentity(id: row['peerId'], name: row['peerName']),
              sourcePost: row['sourcePostId'],
              conversation: row['id'],
            ),
          ),
        ),
      );
    }
    _handlingDmTap = false;
    if (mounted && n.pending != null) _scheduleDmNotification();
  }

  void _scheduleDmNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_dmNotificationChanged());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _primaryNavigation(AppDestination selected) => HhAppNavigation(
    selected: selected,
    onSelected: (destination) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null || !mounted) return;
      navigator.popUntil((route) => route.isFirst);
      switch (destination) {
        case AppDestination.home:
          break;
        case AppDestination.messages:
          unawaited(_openMessages());
        case AppDestination.directMessages:
          unawaited(_openDirectMessages());
        case AppDestination.personal:
          _openPersonal();
      }
    },
  );

  Future<void> _openDirectMessages() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _directMessagesRouteOpen) return;
    if (!widget.sessions.isAuthenticated) {
      _openAuth();
      return;
    }
    _directMessagesRouteOpen = true;
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => widget.dm != null
              ? DmInboxRoute(
                  runtime: widget.dm!,
                  navigation: _primaryNavigation(AppDestination.directMessages),
                )
              : DirectMessagesUnavailableScreen(
                  navigation: _primaryNavigation(AppDestination.directMessages),
                ),
        ),
      );
    } finally {
      _directMessagesRouteOpen = false;
    }
  }

  final _notifiedFailures = <String>{};
  void _commentChanged() {
    final comments = widget.comments;
    if (comments == null || !comments.available) return;
    for (final failure in comments.core.failures) {
      if (!_notifiedFailures.add(
        '${comments.accountId}:${failure.taskId}:${failure.task.attemptVersion}',
      )) {
        continue;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !comments.available) return;
        _scaffoldMessengerKey.currentState?.showMaterialBanner(
          MaterialBanner(
            content: const Text('评论发送失败，原内容已保留。'),
            actions: [
              TextButton(
                onPressed: () {
                  _scaffoldMessengerKey.currentState
                      ?.hideCurrentMaterialBanner();
                  unawaited(() async {
                    final g = widget.governance;
                    if (g != null) {
                      await g.loadIdentities();
                      await g.selectIdentity(failure.ownerIdentityId);
                    }
                    await _openMessages();
                  }());
                },
                child: const Text('进入系统通知'),
              ),
              TextButton(
                onPressed: () => _scaffoldMessengerKey.currentState
                    ?.hideCurrentMaterialBanner(),
                child: const Text('稍后'),
              ),
            ],
          ),
        );
      });
    }
  }

  Future<void> _openMessages() async {
    final navigator = _navigatorKey.currentState,
        governance = widget.governance;
    if (navigator == null || governance == null || _messagesRouteOpen) return;
    _messagesRouteOpen = true;
    try {
      if (!governance.available) {
        final access = governance.restrictedAccess;
        if (access == null) {
          _openAuth();
          return;
        }
        final result = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => ModerationAccessScreen(access: access),
          ),
        );
        if (result != true || !mounted || !governance.available) return;
      }
      final owner = governance.accountId,
          authority = governance.authorityVersion;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => SystemNotificationsScreen(
            controller: governance,
            navigation: _primaryNavigation(AppDestination.messages),
            onOpenComment: (postId, commentId) async {
              if (!widget.posts.available ||
                  governance.restricted ||
                  governance.accountId != owner ||
                  governance.authorityVersion != authority) {
                return;
              }
              await navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => PostDetailScreen(
                    controller: widget.posts,
                    postId: postId,
                    initialCommentId: commentId,
                    loadImages: widget.loadPostImages,
                    onAuthenticationRequired: _openAuth,
                  ),
                ),
              );
            },
            onOpenPost: (postId) async {
              if (!widget.posts.available ||
                  governance.accountId != owner ||
                  governance.authorityVersion != authority) {
                return;
              }
              await navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => PostDetailScreen(
                    controller: widget.posts,
                    postId: postId,
                    loadImages: widget.loadPostImages,
                    onAuthenticationRequired: _openAuth,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      _messagesRouteOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_authPresentation.load());
    WidgetsBinding.instance.addObserver(this);
    widget.comments?.addListener(_commentChanged);
    _postRouteChanges = Listenable.merge([_postWindow, widget.directory]);
    widget.posts.addListener(_postWindowChanged);
    _postWindowChanged();
    _startAuthentication();
    widget.dm?.controller.addListener(_scheduleDmNotification);
    widget.dmNotifications?.onTap = _scheduleDmNotification;
    unawaited(
      widget.dmNotifications?.start().then((_) => _scheduleDmNotification()),
    );
  }

  void _postWindowChanged() {
    final posts = widget.posts;
    final account = posts.accountId;
    if (posts.available && account != null && posts.timelineLoading) {
      _homeChannels[account] = posts.timelineChannelId;
    }
    // Data/loading notifications can arrive while a different route builds.
    // Only a changed authority window invalidates the route's local state.
    _postWindow.value = (widget.posts.accountId, widget.posts.authorityVersion);
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
              onAuthenticated: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
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
              onBlacklist: widget.dm == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DmBlacklistScreen(
                          controller: widget.dm!.controller,
                        ),
                      ),
                    ),
              onDmNotifications:
                  widget.dmNotifications == null ||
                      widget.dm?.controller.accountId == null
                  ? null
                  : () {
                      final account = widget.dm!.controller.accountId!;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DmNotificationSettings(
                            notifications: widget.dmNotifications!,
                            account: account,
                            current: () =>
                                widget.dm!.controller.available &&
                                widget.dm!.controller.accountId == account,
                          ),
                        ),
                      );
                    },
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
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => AnimatedBuilder(
              animation: _postRouteChanges,
              builder: (context, _) {
                final window = _postWindow.value;
                final account = window.$1;
                final authority = window.$2;
                // Recreate only this account hub. Old editors/details retain
                // their original fences and old callbacks keep their window.
                return PersonalPostsScreen(
                  navigation: _primaryNavigation(AppDestination.personal),
                  key: ValueKey((account, authority)),
                  controller: widget.posts,
                  loadImages: widget.loadPostImages,
                  channelNames: {
                    for (final channel in widget.directory.channels)
                      channel.id: channel.displayName,
                  },
                  onManageIdentities: _openIdentity,
                  onAuthenticationRequired: _openAuth,
                  onOpenSettings: _openSettings,
                  onChooseChannel: () =>
                      navigator.popUntil((route) => route.isFirst),
                  onPublishedToChannel: (channelId) {
                    if (!widget.posts.available ||
                        widget.posts.accountId != account ||
                        widget.posts.authorityVersion != authority) {
                      return;
                    }
                    final channel = widget.directory.channels
                        .where((item) => item.id == channelId)
                        .firstOrNull;
                    if (channel == null) return;
                    unawaited(widget.posts.loadTimeline(channelId: channelId));
                    navigator.popUntil((route) => route.isFirst);
                  },
                );
              },
            ),
          ),
        )
        .whenComplete(() => _personalRouteOpen = false);
  }

  @override
  void dispose() {
    widget.dm?.controller.removeListener(_scheduleDmNotification);
    widget.dmNotifications?.dispose();
    widget.dm?.dispose();
    _authPresentation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.comments?.removeListener(_commentChanged);
    widget.comments?.dispose();
    widget.posts.removeListener(_postWindowChanged);
    _postWindow.dispose();
    widget.management.dispose();
    widget.identities.dispose();
    widget.flows.dispose();
    widget.postMedia?.dispose();
    widget.governance?.dispose();
    widget.governance?.restrictedAccess?.dispose();
    widget.governanceApi?.close();
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
    return AnimatedBuilder(
      animation: _authPresentation,
      builder: (context, _) => MaterialApp(
        title: 'Hnuhole',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [CommunityMaterialLabels.delegate],
        scaffoldMessengerKey: _scaffoldMessengerKey,
        navigatorKey: _navigatorKey,
        themeMode: _authPresentation.themeMode,
        builder: (context, child) => DmScope(
          runtime: widget.dm,
          child: AuthPresentationScope(
            controller: _authPresentation,
            child: CommentScopeHost(
              runtime: widget.comments,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerUp: (_) {
                  // Let the requested action (including logout) start first. Activity
                  // is a user gesture, never a background timer or a build side effect.
                  scheduleMicrotask(widget.sessions.onActivity);
                },
                child: CommunitySpokenLocale(
                  child: widget.governance == null
                      ? child ?? const SizedBox.shrink()
                      : GovernanceScope(
                          controller: widget.governance!,
                          child: child ?? const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
          ),
        ),
        theme: HhTelegramTheme.applyAppearance(ThemeData(useMaterial3: true)),
        darkTheme: HhTelegramTheme.applyAppearance(
          ThemeData(useMaterial3: true, brightness: Brightness.dark),
        ),
        home: AnimatedBuilder(
          animation: Listenable.merge([
            widget.sessions,
            _postRouteChanges,
            if (widget.governance != null) widget.governance!,
          ]),
          builder: (context, _) {
            if (widget.sessions.isAuthenticated &&
                widget.posts.available &&
                widget.directory.status == ChannelDirectoryStatus.ready) {
              return FeedScreen(
                // New authorization owns fresh protected data. Its channel
                // preference survives within this app run for the same account.
                key: ValueKey(_postWindow.value),
                controller: widget.posts,
                channels: widget.directory.channels,
                composeChannel: widget.directory.channels.first,
                initialChannelId: _homeChannels[widget.posts.accountId],
                loadImages: widget.loadPostImages,
                onOpenMessages: widget.governance == null
                    ? null
                    : _openMessages,
                onOpenPersonal: _openPersonal,
                onOpenDirectMessages: _openDirectMessages,
                onManageIdentities: _openIdentity,
                onAuthenticationRequired: _openAuth,
              );
            }
            return EntryScreen(
              directory: widget.directory,
              restoringSession:
                  widget.sessions.status == AuthStatus.starting ||
                  widget.sessions.status == AuthStatus.restoring,
              onLoginRequested: _openAuth,
              onMessagesPressed: widget.governance == null
                  ? null
                  : _openMessages,
              messagesUnread: widget.governance?.hasUnread == true,
            );
          },
        ),
      ),
    );
  }
}

class CommentScopeHost extends StatelessWidget {
  const CommentScopeHost({super.key, this.runtime, required this.child});
  final CommentRuntime? runtime;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      runtime == null ? child : CommentScope(runtime: runtime!, child: child);
}
