import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import '../auth/auth_session_controller.dart';
import '../auth/auth_store.dart';
import '../identity/identity_api.dart';
import '../posts/post_photo_picker.dart';
import 'dm_protocol.dart';
import 'dm_controller.dart';
import 'direct_message_models.dart';
import 'direct_message_inbox.dart';
import 'direct_message_screen.dart';

part 'dm_chat_ui.dart';

class DmRuntime {
  DmRuntime({
    required this.controller,
    required this.sessions,
    required this.authStore,
    required this.identityApi,
    this.openPost,
    this.identityChanges,
  }) {
    sessions.addListener(_changed);
    authStore.addListener(_changed);
    identityChanges?.addListener(_identityChanged);
    _changed();
  }
  final DmController controller;
  final AuthSessionController sessions;
  final AuthStore authStore;
  final IdentityApi identityApi;
  final Listenable? identityChanges;
  final void Function(BuildContext, String)? openPost;
  List<DmIdentity> identities = [];
  String? _token;
  int _authority = -1, _epoch = 0;
  bool _disposed = false;
  final _closedAccounts = <String>{};
  Timer? _retry;
  void _identityChanged() {
    _authority = -1;
    _changed();
  }

  void _changed() {
    final record = authStore.current?.session;
    final token =
        record != null &&
            !_closedAccounts.contains(record.accountId) &&
            sessions.isCurrentToken(record.token)
        ? record.token
        : null;
    if (token == _token && sessions.authorityVersion == _authority) return;
    _token = token;
    _authority = sessions.authorityVersion;
    final epoch = ++_epoch;
    _retry?.cancel();
    identities = [];
    unawaited(() async {
      await controller.detach();
      if (token == null || record == null || _disposed || epoch != _epoch) {
        return;
      }
      try {
        final directory = await identityApi.identities(token);
        if (_disposed || epoch != _epoch || !sessions.isCurrentToken(token)) {
          return;
        }
        identities = directory.identities
            .map((i) => DmIdentity(id: i.id, name: i.nickname))
            .toList();
        await controller.bind(
          account: record.accountId,
          token: token,
          identities: identities.map((i) => i.id).toList(),
          isCurrent: () =>
              !_disposed && epoch == _epoch && sessions.isCurrentToken(token),
        );
      } catch (_) {
        // A transient identity fetch must not strand this session forever.
        if (!_disposed && epoch == _epoch && sessions.isCurrentToken(token)) {
          _retry = Timer(const Duration(seconds: 4), _identityChanged);
        }
      }
    }());
  }

  /// The auth flow owns the CLOSED decision; ordinary logout/replacement only
  /// detaches and leaves encrypted local history intact.
  Future<void> purgeClosedAccount(String accountId) async {
    _closedAccounts.add(accountId);
    if (authStore.current?.session?.accountId == accountId ||
        controller.accountId == accountId) {
      _epoch++;
      _token = null;
      _authority = -1;
      _retry?.cancel();
      identities = [];
    }
    await controller.purgeClosedAccount(accountId);
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _retry?.cancel();
    sessions.removeListener(_changed);
    authStore.removeListener(_changed);
    identityChanges?.removeListener(_identityChanged);
    controller.dispose();
  }
}

class DmScope extends InheritedWidget {
  const DmScope({super.key, required this.runtime, required super.child});
  final DmRuntime? runtime;
  static DmRuntime? of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<DmScope>()?.runtime;
  @override
  bool updateShouldNotify(DmScope oldWidget) => runtime != oldWidget.runtime;
  static Future<void> contact(
    BuildContext context,
    String post, {
    String comment = '',
  }) async {
    final r = of(context);
    if (r == null || !r.controller.available) return;
    final scope = r.controller.scope;
    try {
      final target = await r.controller.contact(post, comment);
      if (!context.mounted ||
          scope != r.controller.scope ||
          target['self'] == true) {
        return;
      }
      final bound = target['boundIdentityId'] as String;
      DmIdentity? own;
      if (bound.isNotEmpty) {
        own = r.identities.where((i) => i.id == bound).firstOrNull;
      } else {
        own = await showModalBottomSheet<DmIdentity>(
          context: context,
          builder: (c) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('选择本次联系使用的身份')),
                for (final i in r.identities)
                  ListTile(
                    title: Text(i.name),
                    onTap: () => Navigator.pop(c, i),
                  ),
              ],
            ),
          ),
        );
      }
      if (!context.mounted || own == null || scope != r.controller.scope) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DmChatRoute(
            runtime: r,
            own: own!,
            peer: DmIdentity(id: target['peerId'], name: target['peerName']),
            sourcePost: post,
            sourceComment: comment,
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法联系，请稍后重试')));
      }
    }
  }
}

class DmInboxRoute extends StatefulWidget {
  const DmInboxRoute({super.key, required this.runtime, this.navigation});
  final DmRuntime runtime;
  final Widget? navigation;
  @override
  State<DmInboxRoute> createState() => _DmInboxRouteState();
}

class _DmInboxRouteState extends State<DmInboxRoute> {
  String? _selected;
  String _query = '';
  Set<String> _searchMatches = {};
  int _searchGeneration = 0;
  bool _searching = false;
  String? _searchError;
  Future<void> _search(String query, String identity) async {
    final generation = ++_searchGeneration,
        controller = widget.runtime.controller;
    final scope = controller.scope;
    setState(() {
      _query = query;
      _searching = query.trim().isNotEmpty;
      _searchError = null;
      _searchMatches = {};
    });
    if (query.trim().isEmpty) return;
    try {
      final result = await controller.search(identity, query);
      if (mounted &&
          generation == _searchGeneration &&
          scope == controller.scope) {
        setState(() {
          _searchMatches = result;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted &&
          generation == _searchGeneration &&
          scope == controller.scope) {
        setState(() {
          _searchError = '本机搜索暂未完成，请重试';
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.runtime.controller,
    builder: (context, _) {
      final r = widget.runtime, c = r.controller;
      final own =
          r.identities.where((i) => i.id == _selected).firstOrNull ??
          r.identities.firstOrNull;
      if (!c.available || own == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('私信')),
          body: Center(child: Text(c.error ?? '正在核对私信身份')),
          bottomNavigationBar: widget.navigation,
        );
      }
      int unread(String id) => c.conversations
          .where(
            (v) =>
                v['identityId'] == id &&
                v['hidden'] != true &&
                v['deleted'] != true,
          )
          .fold(0, (n, v) => n + (v['unread'] as int));
      return HhDmInboxScreen(
        scopeKey: '${c.scope}:${own.id}',
        identity: own,
        identities: r.identities
            .map((i) => DmInboxIdentity(i, unread: unread(i.id)))
            .toList(),
        entries: c.conversations
            .where((v) => v['deleted'] != true)
            .map(
              (v) => DmInboxEntry(
                id: v['id'],
                selfIdentityId: v['identityId'],
                recipient: DmIdentity(id: v['peerId'], name: v['peerName']),
                preview:
                    v['localPreview'] as String? ??
                    (v['waiting'] == true ? '等待对方回复' : ''),
                outgoingState: switch (v['localState']) {
                  'queued' => DmSendState.sending,
                  'unknown' => DmSendState.unknown,
                  'failed' => DmSendState.failed,
                  'sent' => DmSendState.sent,
                  _ => null,
                },
                time: '',
                sourceTitle: v['sourceTitle'] as String? ?? '来自帖子',
                privateNote: (v['note'] as String?)?.isNotEmpty == true
                    ? v['note']
                    : null,
                pinned: v['pinned'] == true,
                hidden: v['hidden'] == true,
                localSearchText: _searchMatches.contains(v['id']) ? _query : '',
                unread: v['unread'],
              ),
            )
            .toList(),
        error: _searchError ?? c.error,
        loading: _searching,
        onSearchChanged: !c.chatEnabled
            ? null
            : (query) => unawaited(_search(query, own.id)),
        onRetry: () => unawaited(c.sync()),
        navigation: widget.navigation,
        onManage: !c.chatEnabled
            ? null
            : (target) {
                final dir = c.conversations
                    .where(
                      (v) =>
                          v['id'] == target.conversationId &&
                          v['identityId'] == target.identityId,
                    )
                    .firstOrNull;
                if (dir != null) unawaited(showDmManagement(context, c, dir));
              },
        onIdentitySelected: (i) => setState(() {
          _selected = i.id;
          _query = '';
          _searchMatches = {};
          _searchGeneration++;
          _searching = false;
          _searchError = null;
        }),
        onOpen: (target) {
          final v = c.conversations
              .where(
                (v) =>
                    v['id'] == target.conversationId &&
                    v['identityId'] == own.id,
              )
              .firstOrNull;
          if (v == null) return;
          if (c.chatEnabled && v['hidden'] == true) {
            unawaited(c.manage(v, 'RESTORE'));
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DmChatRoute(
                runtime: r,
                own: own,
                peer: DmIdentity(id: v['peerId'], name: v['peerName']),
                conversation: v['localOnly'] == true ? '' : v['id'],
                sourcePost: v['sourcePostId'],
                sourceComment: v['sourceCommentId'] as String? ?? '',
              ),
            ),
          );
        },
      );
    },
  );
}

class DmChatRoute extends StatefulWidget {
  const DmChatRoute({
    super.key,
    required this.runtime,
    required this.own,
    required this.peer,
    required this.sourcePost,
    this.sourceComment = '',
    this.conversation = '',
  });
  final DmRuntime runtime;
  final DmIdentity own, peer;
  final String sourcePost, sourceComment, conversation;
  @override
  State<DmChatRoute> createState() => _DmChatRouteState();
}

class _DmChatRouteState extends State<DmChatRoute> with WidgetsBindingObserver {
  DmController get c => widget.runtime.controller;
  late final String scope;
  List<Map<String, dynamic>> rows = [];
  String draft = '';
  bool restored = false, loading = false, more = false;
  bool historyFailed = false, _reloadPending = false;
  final _picker = NativePostPhotoPicker();
  List<DmImage> _draftImages = [];
  final _photoRequests = <String, Future<Uint8List>>{};
  final _photoProviders = <String, MemoryImage>{};
  ViewerController? _viewer;
  int _loadEpoch = 0;
  int _draftEditGeneration = 0, _draftRevision = 0;
  int _textSaveGeneration = 0;
  bool _draftDirty = false;
  @override
  void initState() {
    super.initState();
    scope = c.scope;
    c.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  void _changed() {
    if (scope != c.scope || !c.available) _releasePhotos();
    if (mounted) unawaited(_load());
  }

  Future<void> _load({bool older = false}) async {
    if (loading) {
      if (!older) _reloadPending = true;
      return;
    }
    if (!c.available || scope != c.scope) {
      if (mounted) setState(() => rows = []);
      return;
    }
    final epoch = ++_loadEpoch;
    final draftGeneration = _draftEditGeneration;
    setState(() {
      loading = true;
      historyFailed = false;
    });
    try {
      final next = await c.history(
        widget.own.id,
        widget.peer.id,
        before: older && rows.isNotEmpty ? rows.first['_sort'] as int : null,
      );
      final savedDraft = c.chatEnabled
          ? await c.draftState(widget.own.id, widget.peer.id)
          : null;
      final text =
          savedDraft?['text'] as String? ??
          (restored ? draft : await c.draft(widget.own.id, widget.peer.id));
      final photos = savedDraft?['photos'] as List? ?? const [];
      // Receipt reconciliation may move an outgoing row outside the newest
      // page. Refresh already displayed work by its stable local id as well.
      final updated = <Map<String, dynamic>>[];
      final retained = <Map<String, dynamic>>[];
      for (final row in rows) {
        final value = await c.message(row['_id']);
        if (value != null && value['_kind'] != 'hidden_message') {
          updated.add(value);
          retained.add(row);
        }
      }
      if (!mounted || epoch != _loadEpoch || scope != c.scope) return;
      if (rows.any(
        (old) =>
            old['messageType'] == 'IMAGE' &&
            old['recalled'] != true &&
            !updated.any(
              (v) => v['_id'] == old['_id'] && v['recalled'] != true,
            ),
      )) {
        _releasePhotos();
      }
      setState(() {
        final byId = <String, Map<String, dynamic>>{
          for (final r in retained) r['_id']: r,
          for (final r in updated) r['_id']: r,
          for (final r in next) r['_id']: r,
        };
        rows = byId.values.toList()
          ..sort((a, b) => (a['_sort'] as int).compareTo(b['_sort'] as int));
        if (older || !restored) more = next.length == 40;
        if (!restored ||
            (!_draftDirty && draftGeneration == _draftEditGeneration)) {
          final images = photos
              .map((p) => DmImage(id: p['mediaId'], description: '待发送图片'))
              .toList();
          final changed =
              !restored ||
              draft != text ||
              images.length != _draftImages.length ||
              images.indexed.any((p) => p.$2.id != _draftImages[p.$1].id);
          if (changed) {
            draft = text;
            _draftImages = images;
            _draftRevision++;
          }
          restored = true;
        }
      });
    } catch (_) {
      if (mounted && epoch == _loadEpoch) setState(() => historyFailed = true);
    } finally {
      if (mounted && epoch == _loadEpoch) {
        setState(() => loading = false);
        if (_reloadPending) {
          _reloadPending = false;
          unawaited(_load());
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.sync());
  }

  @override
  void dispose() {
    _releasePhotos();
    _loadEpoch++;
    c.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (scope != c.scope || !c.available) {
      return const Scaffold(body: Center(child: Text('请恢复当前账号后查看私信')));
    }
    final directory = c.conversations
        .where(
          (v) =>
              v['identityId'] == widget.own.id && v['peerId'] == widget.peer.id,
        )
        .firstOrNull;
    final conv = directory?['localOnly'] == true
        ? ''
        : directory?['id'] as String? ?? widget.conversation;
    final awaiting =
        directory?['waiting'] == true ||
        conv.isEmpty &&
            rows.any((r) => r['outgoing'] == true && r['_state'] != 'failed');
    final messages = c.chatEnabled
        ? _chatMessages()
        : rows.map((r) {
            final outgoing = r['outgoing'] == true;
            final data = outgoing
                ? Map<String, dynamic>.from(r['intent'] as Map)
                : r;
            final receipt = r['receipt'] as Map?;
            final rawDate = outgoing
                ? (receipt?['acceptedAt'])
                : r['acceptedAt'];
            final date = DateTime.tryParse(rawDate as String? ?? '')?.toLocal();
            return DmMessage(
              id: r['_id'],
              outgoing: outgoing,
              text: data['text'],
              time: date == null
                  ? ''
                  : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              dayLabel: date == null ? '' : '${date.month}月${date.day}日',
              state: switch (r['_state']) {
                'queued' => DmSendState.sending,
                'unknown' => DmSendState.unknown,
                'failed' => DmSendState.failed,
                _ => DmSendState.sent,
              },
            );
          }).toList();
    return HhDirectMessageScreen(
      syncError: c.error,
      view: DmConversationView(
        scopeKey: '$scope:${widget.own.id}:${widget.peer.id}',
        recipient: DmIdentity(
          id: widget.peer.id,
          name: directory?['peerName'] as String? ?? widget.peer.name,
        ),
        selfIdentity: widget.own,
        sourceTitle:
            directory?['sourceTitle'] as String? ??
            (widget.sourcePost.isEmpty ? '匿名私信' : '来自帖子'),
        sourceDeleted: widget.sourcePost.isEmpty,
        messages: messages,
        draftText: draft,
        draftImages: _draftImages,
        privateNote: (directory?['note'] as String?)?.isNotEmpty == true
            ? directory!['note']
            : null,
        draftRevision: _draftRevision,
        firstContact: conv.isEmpty || awaiting,
        firstTextAccepted: awaiting,
        canSend: restored && directory?['canSend'] != false,
        localSaveFailed:
            c.error?.contains('保存失败') == true ||
            c.error?.contains('未保存') == true,
        historyState: historyFailed
            ? DmHistoryState.failed
            : loading
            ? DmHistoryState.loading
            : more
            ? DmHistoryState.available
            : DmHistoryState.complete,
        historyCursor: rows.isEmpty ? null : '${rows.first['_sort']}',
      ),
      identities: widget.runtime.identities,
      imageBuilder: c.chatEnabled
          ? _photoWidget
          : (_, _) => const SizedBox.shrink(),
      onSend: (intent) async {
        final value = <String, Object>{
          'identityId': widget.own.id,
          'peerId': widget.peer.id,
          'conversationId': conv,
          'sourcePostId': conv.isEmpty ? widget.sourcePost : '',
          'sourceCommentId': conv.isEmpty ? widget.sourceComment : '',
          'text': intent.text,
          'attempt': 1,
        };
        final saved = await (intent.images.isEmpty
            ? c.send(value, peerName: widget.peer.name)
            : c.sendPhotos(value, intent.images.map((i) => i.id).toList()));
        if (saved && mounted && scope == c.scope) {
          _draftImages.removeWhere(
            (i) => intent.images.any((sent) => sent.id == i.id),
          );
        }
        return saved;
      },
      onDraftChanged: (text) {
        _draftEditGeneration++;
        final edit = ++_textSaveGeneration;
        _draftDirty = true;
        draft = text;
        unawaited(() async {
          final saved = await c.saveDraft(widget.own.id, widget.peer.id, text);
          if (mounted &&
              scope == c.scope &&
              edit == _textSaveGeneration &&
              saved) {
            _draftDirty = false;
          }
        }());
      },
      onIdentitySelected: (_) {},
      onPickImages: c.chatEnabled
          ? () async {
              _draftEditGeneration++;
              final selected = await _pickChatImages();
              _draftEditGeneration++;
              return selected;
            }
          : () async => [],
      onRemoveDraftImage: (image) async {
        _draftEditGeneration++;
        try {
          await c.removePhoto(widget.own.id, widget.peer.id, image.id);
          _draftImages.removeWhere((i) => i.id == image.id);
          return true;
        } catch (_) {
          return false;
        }
      },
      onManage:
          c.chatEnabled && directory != null && directory['localOnly'] != true
          ? () => unawaited(showDmManagement(context, c, directory))
          : null,
      onMessageAction: (target, action) async {
        if (c.chatEnabled && action != DmMessageAction.copy) {
          await _chatMessageAction(target, action, directory);
          return;
        }
        if (action == DmMessageAction.copy) {
          final text = messages
              .where((m) => m.id == target.messageId)
              .firstOrNull
              ?.text;
          if (text != null) await Clipboard.setData(ClipboardData(text: text));
        }
      },
      onRetry: (target) =>
          unawaited(c.retry(target.imageId ?? target.messageId)),
      onImage: c.chatEnabled ? _openPhoto : (_) {},
      onSource: () {
        if (widget.sourcePost.isNotEmpty) {
          widget.runtime.openPost?.call(context, widget.sourcePost);
        }
      },
      onBack: () => Navigator.pop(context),
      onLoadOlder: (_) async => _load(older: true),
      onSaveRetry: () => unawaited(c.sync()),
      onVisible: (ids) {
        if (ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(c.visible(ids));
        }
      },
      textOnly: !c.chatEnabled,
      reportEnabled: false,
    );
  }
}
