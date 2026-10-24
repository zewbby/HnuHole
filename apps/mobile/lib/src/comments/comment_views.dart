import '../rate_limit_notice.dart';

import 'dart:async';
import 'dart:typed_data';

import '../messaging/dm_runtime.dart';

import 'package:flutter/material.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import '../design_system/detail_components.dart';
import '../posts/x_feed.dart';
import '../identity/identity_api.dart';
import '../identity/identity_management_screen.dart';
import '../posts/post_images.dart';
import '../posts/post_models.dart';
import '../posts/post_photo_picker.dart';
import '../reports/report_screens.dart';
import 'comment_editor.dart';
import 'comment_http.dart';
import 'comment_models.dart';
import 'comment_runtime.dart';
import 'quick_reply_dialog.dart';

class CommentRow {
  CommentRow(Object? raw)
    : data = Map<String, dynamic>.from(
        PostJson.record(raw, {
          'id',
          'postId',
          'rootCommentId',
          'targetCommentId',
          'body',
          'image',
          'author',
          'replyTo',
          'isPostAuthor',
          'publishedAt',
          'likeCount',
          'likedByMe',
          'replyCount',
        }),
      ) {
    PostJson.id(data, 'id');
    PostJson.id(data, 'postId');
    PostJson.utc(data['publishedAt']);
    PostJson.integer(data, 'likeCount', 0, 9007199254740991);
    PostJson.integer(data, 'replyCount', 0, 10000);
    final author = PostJson.record(data['author'], {
      'ref',
      'nickname',
      'avatar',
      'state',
    });
    if (author['state'] == 'ACTIVE'
        ? !validIdentityAvatar(author['avatar'])
        : author['avatar'] != 'inactive-v1') {
      throw const FormatException('Invalid comment avatar');
    }
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get post => data['postId'] as String;
  String? get root => data['rootCommentId'] as String?;
  String get body => data['body'] as String;
  String get nickname => (data['author'] as Map)['nickname'] as String;
  String get avatar => (data['author'] as Map)['avatar'] as String;
  int get likes => data['likeCount'] as int;
  bool get liked => data['likedByMe'] as bool;
  int get replyCount => data['replyCount'] as int;
}

class CommentHistoryScreen extends StatefulWidget {
  const CommentHistoryScreen({
    super.key,
    required this.runtime,
    required this.onOpen,
  });
  final CommentRuntime runtime;
  final void Function(CommentRow) onOpen;
  @override
  State<CommentHistoryScreen> createState() => _CommentHistoryScreenState();
}

class _CommentHistoryScreenState extends State<CommentHistoryScreen> {
  late final epoch = widget.runtime.authorityVersion;
  List<ManagedIdentity> identities = [];
  String? selected, cursor, error;
  final items = <CommentRow>[];
  bool loading = false;
  bool get current => mounted && widget.runtime.current(epoch);
  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_changed);
    unawaited(_start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    try {
      final d = await widget.runtime.directory();
      if (!current) return;
      identities = d.identities;
      selected = identities.firstOrNull?.id;
      await _load();
    } catch (_) {
      if (current) setState(() => error = '暂时无法读取发言记录。');
    }
  }

  Future<void> _load({bool more = false}) async {
    if (!current || selected == null || loading) return;
    setState(() => loading = true);
    final identity = selected;
    try {
      final p = await widget.runtime.request(
        'GET',
        '/api/v1/me/comments',
        query: {
          'identityId': identity!,
          if (more && cursor != null) 'cursor': cursor!,
        },
      );
      if (!current || selected != identity) return;
      setState(() {
        if (!more) items.clear();
        items.addAll((p['items'] as List).map(CommentRow.new));
        cursor = p['nextCursor'] as String?;
        error = null;
      });
    } catch (_) {
      if (current) setState(() => error = '暂时无法读取发言记录。');
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我发出的评论')),
    body: !current
        ? const Center(child: Text('会话已变化，请返回。'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButton<String>(
                value: selected,
                items: [
                  for (final i in identities)
                    DropdownMenuItem(value: i.id, child: Text(i.nickname)),
                ],
                onChanged: loading
                    ? null
                    : (id) {
                        setState(() => selected = id);
                        unawaited(_load());
                      },
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                TextButton(onPressed: _load, child: Text(error!)),
              for (final row in items)
                ListTile(
                  title: Text(
                    row.body.isEmpty ? '图片评论' : row.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(row.root == null ? '主评论' : '回复'),
                  onTap: () => widget.onOpen(row),
                ),
              if (cursor != null)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: const Text('更多记录'),
                ),
              if (!loading && items.isEmpty) const Text('当前身份还没有已发布的评论。'),
            ],
          ),
  );
}

/// Body and comments have independent scrolling. The editor belongs to this
/// open post; collapse preserves it, leaving this widget clears it immediately.
class CommentPostPane extends StatefulWidget {
  const CommentPostPane({
    super.key,
    required this.runtime,
    required this.postId,
    required this.postBody,
    required this.body,
    this.initialCommentId,
    this.initialInput,
    this.initialOriginal,
    this.onCountChanged,
    this.onTotalChanged,
    this.continuous = false,
    this.onBodyScroll,
    this.photoPicker,
    this.bodyReady = true,
    this.overlayComposer = false,
  });
  final CommentRuntime runtime;
  final String postId, postBody;
  final Widget body;
  final String? initialCommentId;
  final CommentRejectedInput? initialInput;
  final Uint8List? initialOriginal;
  final VoidCallback? onCountChanged;
  final ValueChanged<int>? onTotalChanged;
  final bool continuous;
  final VoidCallback? onBodyScroll;
  final PostPhotoPicker? photoPicker;
  final bool bodyReady;
  final bool overlayComposer;

  static void composeFrom(BuildContext context) {
    final state = context.findAncestorStateOfType<_CommentPostPaneState>();
    if (state != null) unawaited(state._compose());
  }

  @override
  State<CommentPostPane> createState() => _CommentPostPaneState();
}

class _LocalComment {
  _LocalComment(this.entry, this.identity);
  final createdAt = DateTime.now();
  CommentJournalEntry entry;
  ManagedIdentity? identity;
  String? publishedId;
  CommentRow? publishedRow;
  Future<Uint8List>? imageBytes;
}

class _CommentPostPaneState extends State<CommentPostPane> {
  late final int epoch = widget.runtime.authorityVersion;
  late CommentEditor editor = CommentEditor(
    CommentTarget(postId: widget.postId),
  );
  final rows = <CommentRow>[];
  final replies = <String, List<CommentRow>>{};
  final replyCursors = <String, String?>{};
  final expanded = <String>{};
  final originals = <String, Uint8List>{};
  final keys = <String, GlobalKey>{};
  final completed = <String>{};
  final _seenDeleted = <String>{};
  String? cursor, highlight, error;
  String sort = 'relevant';
  bool composing = false, composerFull = false, _openingComposer = false;
  CommentRow? composerTarget;
  String? initialAttachment;
  ManagedIdentity? speakingIdentity;
  final _publishing = <String>{};
  final _localComments = <String, _LocalComment>{};
  final _publicationRetries = <String, Timer>{};
  final _identitiesById = <String, ManagedIdentity>{};
  Set<String> get _localPublishedIds => {
    for (final local in _localComments.values)
      if (local.publishedId != null) local.publishedId!,
  };
  int get _displayTotal =>
      total +
      _localComments.values
          .where(
            (local) =>
                local.publishedId == null ||
                !own.contains(local.publishedId) &&
                    !rows
                        .followedBy(replies.values.expand((v) => v))
                        .any((row) => row.id == local.publishedId),
          )
          .length;

  List<String> _syncLocalComments() {
    final added = <String>[];
    final active = <String>{};
    for (final entry in widget.runtime.core.entries) {
      if (entry.intent.binding.postId != widget.postId) continue;
      final eligible =
          entry.content != null &&
          !entry.identityDeleted &&
          entry.rateLimitWait == null &&
          entry.rejectionCode == null &&
          (entry.transport != CommentTransportState.settled ||
              entry.task?.state == CommentTaskState.accepted);
      if (eligible) {
        active.add(entry.localId);
        final local = _localComments[entry.localId];
        if (local == null) {
          final id = entry.intent.binding.identityId;
          _localComments[entry.localId] = _LocalComment(
            entry,
            _identitiesById[id] ??
                (speakingIdentity?.id == id ? speakingIdentity : null),
          );
          added.add(entry.localId);
        } else {
          if (local.entry.content?.image?.blobId !=
              entry.content?.image?.blobId) {
            local.imageBytes = null;
          }
          local.entry = entry;
        }
      } else if (_localComments.remove(entry.localId) != null &&
          (entry.task?.state == CommentTaskState.failed ||
              entry.rejectionCode != null ||
              entry.rateLimitWait != null)) {
        _notice = entry.rateLimitWait != null
            ? widget.runtime.core.rateLimitMessage
            : entry.rejectionCode == null
            ? '评论发送失败，可在系统消息中重试。'
            : '评论未能发出，原内容已保留。';
      }
    }
    for (final task in widget.runtime.core.resolvedTasks) {
      if (task.state == CommentTaskState.published) {
        _localComments[task.taskId]?.publishedId = task.commentId;
      }
    }
    _localComments.removeWhere(
      (id, local) =>
          !active.contains(id) && local.publishedId == null ||
          widget.runtime.deleted.contains(
            local.entry.intent.binding.rootCommentId,
          ) ||
          widget.runtime.deleted.contains(local.publishedId),
    );
    return added;
  }

  Widget _localComment(String id, _LocalComment local) {
    final row =
        rows
            .followedBy(replies.values.expand((v) => v))
            .where((row) => row.id == local.publishedId)
            .firstOrNull ??
        local.publishedRow;
    final content = local.entry.content!;
    final identity = local.identity;
    final binding = local.entry.intent.binding;
    final target = rows
        .followedBy(replies.values.expand((v) => v))
        .where((row) => row.id == binding.targetCommentId)
        .firstOrNull;
    return Container(
      key: keys.putIfAbsent('local:$id', GlobalKey.new),
      child: row != null
          ? Column(
              children: [
                _row(row, reply: row.root != null),
                if (row.root == null)
                  for (final child
                      in (replies[row.id] ?? <CommentRow>[])
                          .where((r) => !_localPublishedIds.contains(r.id))
                          .take(expanded.contains(row.id) ? 10000 : 5))
                    _row(child, reply: true),
              ],
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (identity != null)
                    DetailAvatar(
                      name: identity.nickname,
                      avatar: identity.avatar,
                      radius: 20,
                    )
                  else
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.person_outline),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: identity?.nickname ?? '我',
                                      style: detailType(
                                        context,
                                        14,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' · ${local.createdAt.month}月${local.createdAt.day}日',
                                      style: detailType(
                                        context,
                                        12.5,
                                        color: Theme.of(context).hintColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: DetailChromeIcon(
                                DetailChrome.more,
                                color: Theme.of(context).hintColor,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        if (binding.targetCommentId != null)
                          Text(
                            '回复 ${target?.nickname ?? '该评论'}',
                            style: detailType(context, 12),
                          ),
                        if (content.body.isNotEmpty)
                          Text(content.body, style: detailType(context, 14)),
                        if (content.image case final image?)
                          SizedBox(
                            width: 160,
                            height: 160,
                            child: FutureBuilder<Uint8List>(
                              future: local.imageBytes ??= widget
                                  .runtime
                                  .journal
                                  .bytes(widget.runtime.accountId!, image),
                              builder: (context, snapshot) => snapshot.hasData
                                  ? Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.image_outlined),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image_outlined),
                                    ),
                            ),
                          ),
                        const Row(
                          children: [
                            DetailAction(
                              action: FeedAction.comment,
                              label: '回复',
                              size: 18,
                            ),
                            SizedBox(width: 36),
                            DetailAction(
                              action: FeedAction.like,
                              label: '点赞',
                              count: '0',
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  final _inlineComposerKey = GlobalKey<_CommentComposerState>();
  int total = 0;
  bool open = false, loading = false;
  Completer<void>? _reading;
  double bodyFraction = 2 / 3;
  Timer? _highlightTimer;
  String? _notice;
  final _scroll = ScrollController();
  final _replyReads = <String, Completer<void>>{};
  final _queuedReplies = <String>{};
  final _replyFailures = <String>{};
  int _listVersion = 0;
  int _contextReadVersion = 0;
  Set<String> own = {};
  bool get current => mounted && widget.runtime.current(epoch);
  @override
  void initState() {
    super.initState();
    // Resolved tasks from earlier visits are history, not new publications.
    completed.addAll(widget.runtime.core.resolvedTasks.map((t) => t.taskId));
    widget.runtime.addListener(_changed);
    _syncLocalComments();
    final recovered = widget.initialInput;
    if (recovered != null && recovered.binding.postId == widget.postId) {
      editor = CommentEditor(
        CommentTarget(
          postId: widget.postId,
          rootCommentId: recovered.binding.rootCommentId,
          commentId: recovered.binding.targetCommentId,
        ),
      );
      editor.body = recovered.content.body;
      if (recovered.content.image case final image?
          when widget.initialOriginal != null) {
        editor.setImage(image);
        originals[image.blobId] = widget.initialOriginal!;
      }
      open = true;
      unawaited(_load());
    }
    if (widget.continuous && !open) {
      open = true;
      unawaited(_load());
    }
    unawaited(_loadContext());
    if (widget.initialCommentId != null) {
      open = true;
      unawaited(_load().then((_) => _locate(widget.initialCommentId!)));
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_changed);
    _highlightTimer?.cancel();
    for (final timer in _publicationRetries.values) {
      timer.cancel();
    }
    _localComments.clear();
    _scroll.dispose();
    originals.clear();
    editor.leave();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (current && widget.runtime.deleted.any(_seenDeleted.add)) {
      widget.onCountChanged?.call();
    }
    if (!current) {
      _localComments.clear();
      for (final timer in _publicationRetries.values) {
        timer.cancel();
      }
      _publicationRetries.clear();
      editor.leave();
      rows.clear();
      replies.clear();
    }
    rows.removeWhere((r) => widget.runtime.deleted.contains(r.id));
    replies.removeWhere((id, _) => widget.runtime.deleted.contains(id));
    for (final list in replies.values) {
      list.removeWhere((r) => widget.runtime.deleted.contains(r.id));
    }
    final added = current ? _syncLocalComments() : <String>[];
    setState(() {});
    if (current) {
      widget.onTotalChanged?.call(_displayTotal);
      if (added.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (current) unawaited(_revealComment('local:${added.last}'));
        });
      }
      for (final t in widget.runtime.core.resolvedTasks) {
        if (t.state == CommentTaskState.published &&
            t.binding.postId == widget.postId &&
            completed.add(t.taskId)) {
          widget.onCountChanged?.call();
          open = true;
          own.add(t.commentId!);
          unawaited(_published(t.commentId!));
        }
      }
    }
  }

  Future<void> _published(String id, {int attempt = 0}) async {
    _publishing.add(id);
    if (current) setState(() {});
    await _locate(id, userInitiated: false);
    if (!current) return;
    _publishing.remove(id);
    final row = rows
        .followedBy(replies.values.expand((v) => v))
        .where((r) => r.id == id)
        .firstOrNull;
    for (final local in _localComments.values) {
      if (local.publishedId == id) local.publishedRow = row;
    }
    if (row == null && attempt < 3 && _localPublishedIds.contains(id)) {
      _publicationRetries.remove(id)?.cancel();
      _publicationRetries[id] = Timer(Duration(seconds: attempt + 1), () {
        _publicationRetries.remove(id);
        if (current) unawaited(_published(id, attempt: attempt + 1));
      });
    }
    await _loadContext();
    if (current) setState(() {});
  }

  bool get _sending =>
      _publishing.isNotEmpty ||
      widget.runtime.core.entries.any(
        (e) =>
            e.intent.binding.postId == widget.postId &&
            e.rejectionCode == null &&
            !e.identityDeleted &&
            (e.transport != CommentTransportState.settled ||
                e.task?.state == CommentTaskState.accepted),
      );

  void _hint(String text) {
    if (current) setState(() => _notice = text);
  }

  Widget _noticeView() => Material(
    key: const ValueKey('comment-notice'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(_notice!, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: '关闭提示',
            onPressed: () => setState(() => _notice = null),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    ),
  );

  Future<void> _loadContext() async {
    final version = ++_contextReadVersion;
    try {
      final (c, directory) = await (
        widget.runtime.contextFor(widget.postId),
        widget.runtime.directory(),
      ).wait;
      if (!current || version != _contextReadVersion) return;
      setState(() {
        own = (c['ownCommentIds'] as List).cast<String>().toSet();
        total = c['totalCount'] as int;
      });
      widget.onTotalChanged?.call(_displayTotal);
      if (current) {
        setState(() {
          _identitiesById
            ..clear()
            ..addEntries(
              directory.identities.map(
                (identity) => MapEntry(identity.id, identity),
              ),
            );
          for (final local in _localComments.values) {
            local.identity =
                _identitiesById[local.entry.intent.binding.identityId];
          }
          final previous = speakingIdentity;
          speakingIdentity = directory.identities
              .where((i) => i.id == c['boundIdentityId'])
              .firstOrNull;
          if (c['boundIdentityId'] == null) {
            speakingIdentity ??=
                directory.identities
                    .where((i) => i.id == previous?.id)
                    .firstOrNull ??
                directory.identities.where((i) => i.isOriginal).firstOrNull ??
                (directory.identities.length == 1
                    ? directory.identities.single
                    : null);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _load({bool more = false}) async {
    if (!current) return;
    final pending = _reading;
    if (pending != null) {
      await pending.future;
      if (more && current && cursor != null) await _load(more: true);
      return;
    }
    if (more && cursor == null) return;
    final reading = Completer<void>();
    _reading = reading;
    setState(() => loading = true);
    try {
      final p = await widget.runtime.request(
        'GET',
        '/api/v1/posts/${widget.postId}/comments',
        query: more && cursor != null
            ? {'cursor': cursor!}
            : (sort == 'relevant' ? null : {'sort': sort}),
      );
      if (!current) return;
      setState(() {
        if (!more) {
          _listVersion++;
          _replyReads.clear();
          rows.clear();
          replies.clear();
          replyCursors.clear();
          expanded.clear();
          _queuedReplies.clear();
          _replyFailures.clear();
        }
        for (final raw in p['comments'] as List) {
          final row = CommentRow(raw);
          if (!rows.any((r) => r.id == row.id)) rows.add(row);
        }
        cursor = p['nextCursor'] as String?;
        total = p['totalCount'] as int;
        error = null;
      });
      for (final row
          in rows
              .where((r) => !widget.continuous && r.replyCount > 0)
              .toList()) {
        if (!current) return;
        if (!replies.containsKey(row.id)) await _replies(row.id);
      }
    } catch (e) {
      if (current) {
        setState(() {
          if (e is CommentHttpFailure && {403, 404}.contains(e.status)) {
            _localComments.clear();
            rows.clear();
            replies.clear();
            replyCursors.clear();
            expanded.clear();
            cursor = null;
            own.clear();
            total = 0;
          }
          error = '评论暂时无法读取，请重新核对。';
        });
      }
    } finally {
      if (current) setState(() => loading = false);
      _reading = null;
      reading.complete();
    }
  }

  Future<void> _replies(String root, {bool more = false}) async {
    final pending = _replyReads[root];
    if (pending != null) return pending.future;
    final reading = Completer<void>();
    _replyReads[root] = reading;
    final listVersion = _listVersion;
    try {
      final p = await widget.runtime.request(
        'GET',
        '/api/v1/posts/${widget.postId}/comments/$root/replies',
        query: more
            ? {
                'expanded': 'true',
                if (replyCursors[root] != null) 'cursor': replyCursors[root]!,
              }
            : null,
      );
      if (!current || listVersion != _listVersion) return;
      setState(() {
        _replyFailures.remove(root);
        final list = replies.putIfAbsent(root, () => []);
        for (final raw in p['comments'] as List) {
          final row = CommentRow(raw);
          if (!list.any((r) => r.id == row.id)) list.add(row);
        }
        replyCursors[root] = p['nextCursor'] as String?;
      });
    } catch (e) {
      if (!current || listVersion != _listVersion) return;
      if (current) setState(() => _replyFailures.add(root));
      if (current && e is CommentHttpFailure && {403, 404}.contains(e.status)) {
        setState(() {
          rows.removeWhere((r) => r.id == root);
          replies.remove(root);
          replyCursors.remove(root);
          expanded.remove(root);
          own.remove(root);
        });
      }
      _hint('回复暂时无法读取，请重试。');
    } finally {
      if (identical(_replyReads[root], reading)) _replyReads.remove(root);
      reading.complete();
    }
  }

  Future<void> _locate(String id, {bool userInitiated = true}) async {
    if (!current) return;
    try {
      final reading = _reading;
      if (reading != null) await reading.future;
      if (!current) return;
      final location = userInitiated
          ? await widget.runtime.request(
              'GET',
              '/api/v1/posts/${widget.postId}/comments/$id/location',
            )
          : <String, dynamic>{};
      final raw = await widget.runtime.request(
        'GET',
        '/api/v1/posts/${widget.postId}/comments/$id',
      );
      final target = CommentRow(raw);
      final floor = target.root ?? id;
      final laterReading = _reading;
      if (laterReading != null) await laterReading.future;
      if (!current) return;
      // A fresh deep link starts at the server's authenticated containing page.
      // An existing reader keeps its captured membership/order and follows only
      // that snapshot's cursors before merging this owner's new publication.
      if (rows.isEmpty && cursor == null && location['cursor'] != null) {
        final page = await widget.runtime.request(
          'GET',
          '/api/v1/posts/${widget.postId}/comments',
          query: {'cursor': location['cursor'] as String},
        );
        if (!current) return;
        rows.addAll((page['comments'] as List).map(CommentRow.new));
        cursor = page['nextCursor'] as String?;
        total = page['totalCount'] as int;
      }
      while (userInitiated &&
          !rows.any((r) => r.id == floor) &&
          cursor != null) {
        final previous = cursor;
        await _load(more: true);
        if (!current) return;
        if (cursor == previous) throw StateError('Captured page unavailable');
      }
      if (!rows.any((r) => r.id == floor)) {
        final root = target.root == null
            ? target
            : CommentRow(
                await widget.runtime.request(
                  'GET',
                  '/api/v1/posts/${widget.postId}/comments/$floor',
                ),
              );
        if (!current) return;
        if (userInitiated &&
            !own.contains(root.id) &&
            widget.initialCommentId != id) {
          throw StateError('Outside captured snapshot');
        }
        rows.insert(_insertAt(rows, root, 10), root);
      }
      if (target.root != null) {
        expanded.add(floor);
        if (!replies.containsKey(floor)) await _replies(floor);
        if (!current) return;
        final list = replies.putIfAbsent(floor, () => []);
        while (userInitiated &&
            !list.any((r) => r.id == id) &&
            replyCursors[floor] != null) {
          final previous = replyCursors[floor];
          await _replies(floor, more: true);
          if (!current) return;
          if (replyCursors[floor] == previous) {
            throw StateError('Captured replies unavailable');
          }
        }
        if (!list.any((r) => r.id == id)) {
          if (userInitiated &&
              !own.contains(id) &&
              widget.initialCommentId != id) {
            throw StateError('Outside captured replies');
          }
          list.insert(_insertAt(list, target, 5), target);
        }
      }
      if (!current) return;
      setState(() {
        open = true;
        highlight = id;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_revealComment(id));
      });
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (current && highlight == id) setState(() => highlight = null);
      });
    } catch (e) {
      if (current && e is CommentHttpFailure && {403, 404}.contains(e.status)) {
        setState(() {
          _localComments.removeWhere((_, local) => local.publishedId == id);
          rows.removeWhere((r) => r.id == id);
          replies.remove(id);
          for (final list in replies.values) {
            list.removeWhere((r) => r.id == id);
          }
        });
        if (userInitiated) _hint('这条评论暂时无法查看。');
      } else if (userInitiated) {
        _hint('暂时无法定位，请重试。');
      }
    }
  }

  Future<void> _revealComment(String id) async {
    final localId = _localComments.entries
        .where((entry) => entry.value.publishedId == id)
        .firstOrNull
        ?.key;
    if (localId != null) id = 'local:$localId';
    // A lazy list has no RenderObject for distant rows. Seek using the loaded
    // order and the measured neighbouring rows, then align the concrete target.
    final ordered = [
      for (final id in _localComments.keys.toList().reversed) 'local:$id',
      for (final r in rows.where(
        (r) => !_localPublishedIds.contains(r.id),
      )) ...[
        r.id,
        for (final reply in (replies[r.id] ?? <CommentRow>[]).take(
          expanded.contains(r.id) ? 10000 : 5,
        ))
          reply.id,
      ],
    ];
    final index = ordered.indexOf(id);
    if (index < 0) return;
    double lower = 0;
    double? upper;
    for (var attempt = 0; attempt < 60 && current && !composing; attempt++) {
      final target = keys[id]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0,
          duration: const Duration(milliseconds: 180),
        );
        return;
      }
      if (!widget.continuous || !_scroll.hasClients) return;
      final position = _scroll.position;
      final visible = <int>[
        for (var i = 0; i < ordered.length; i++)
          if (keys[ordered[i]]?.currentContext != null) i,
      ];
      var next = position.pixels + position.viewportDimension;
      if (visible.isNotEmpty) {
        if (index < visible.first) {
          upper = position.pixels;
        } else {
          lower = position.pixels;
        }
        final near = index < visible.first ? visible.first : visible.last;
        final box = keys[ordered[near]]!.currentContext!.findRenderObject();
        if (box is RenderBox) {
          next = position.pixels + (index - near) * box.size.height;
        }
      }
      if (upper != null) next = (lower + upper) / 2;
      next = next.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((next - position.pixels).abs() < 1) return;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  int _insertAt(List<CommentRow> list, CommentRow target, int top) {
    final a = DateTime.parse(target.data['publishedAt'] as String);
    if (widget.continuous && top == 10 && sort != 'relevant') {
      for (var i = 0; i < list.length; i++) {
        final b = DateTime.parse(list[i].data['publishedAt'] as String);
        final before = sort == 'recent'
            ? a.isAfter(b) || a == b && target.id.compareTo(list[i].id) < 0
            : target.likes > list[i].likes ||
                  target.likes == list[i].likes &&
                      (a.isBefore(b) ||
                          a == b && target.id.compareTo(list[i].id) < 0);
        if (before) return i;
      }
      return list.length;
    }
    for (var i = top; i < list.length; i++) {
      final b = DateTime.parse(list[i].data['publishedAt'] as String);
      if (a.isBefore(b) || a == b && target.id.compareTo(list[i].id) < 0) {
        return i;
      }
    }
    return list.length;
  }

  Future<void> _compose([
    CommentRow? row,
    String? attachment,
    bool full = false,
  ]) async {
    if (!current ||
        !widget.bodyReady ||
        _openingComposer ||
        (_inlineComposerKey.currentState?.busy ?? false)) {
      return;
    }
    _openingComposer = true;
    try {
      if (composing) {
        _inlineComposerKey.currentState?._stash();
      }
      if (row == null && editor.hasInput && editor.target.commentId != null) {
        row = rows
            .followedBy(replies.values.expand((v) => v))
            .where((r) => r.id == editor.target.commentId)
            .firstOrNull;
      }

      final rejected = widget.runtime.core.entries
          .where(
            (e) =>
                e.intent.operation == CommentOperation.create &&
                e.rejectionCode != null &&
                e.intent.binding.postId == widget.postId,
          )
          .firstOrNull;
      if (rejected != null && !editor.hasInput) {
        final image = rejected.content?.image;
        Uint8List? bytes;
        if (image != null) {
          try {
            bytes = await widget.runtime.journal.bytes(
              widget.runtime.accountId!,
              image,
            );
          } catch (_) {}
        }
        if (!current) return;
        final recovered = await widget.runtime.core.releaseRejected(
          localId: rejected.localId,
          activePostId: widget.postId,
        );
        if (!current || recovered == null) return;
        editor.leave();
        editor = CommentEditor(
          CommentTarget(
            postId: widget.postId,
            rootCommentId: recovered.binding.rootCommentId,
            commentId: recovered.binding.targetCommentId,
          ),
        );
        editor.body = recovered.content.body;
        if (image != null && bytes != null) {
          editor.setImage(image);
          originals[image.blobId] = bytes;
        }
        row = rows
            .followedBy(replies.values.expand((r) => r))
            .where((r) => r.id == recovered.binding.targetCommentId)
            .firstOrNull;
      }

      final next = CommentTarget(
        postId: widget.postId,
        rootCommentId: row == null ? null : row.root ?? row.id,
        commentId: row?.id,
      );
      final switched = await editor.switchTarget(
        next,
        confirm: (_) => showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('更换回复对象？'),
            content: Text('改为回复 ${row?.nickname ?? '当前帖子'}，保留已输入的文字和图片。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('保留原对象'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('更换'),
              ),
            ],
          ),
        ).then((v) => v == true),
      );
      if (!mounted || !current || !switched) return;
      editor.expand();
      if (widget.continuous) {
        setState(() {
          composerTarget = row;
          initialAttachment = attachment;
          composing = true;
          composerFull = full;
        });
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => CommentComposer(
            runtime: widget.runtime,
            editor: editor,
            originals: originals,
            replyContext: row,
            contextText: row == null
                ? widget.postBody
                : '${row.nickname}\n${row.body}',
            onSubmitted: () {
              if (current) {
                setState(
                  () => editor = CommentEditor(
                    CommentTarget(postId: widget.postId),
                  ),
                );
              }
            },
          ),
        ),
      );
      if (current) setState(editor.collapse);
    } finally {
      _openingComposer = false;
    }
  }

  Future<void> _chooseSort() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (c) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '对回复排序',
                  style: detailType(c, 22, weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final option in [
                  ('recent', '最近'),
                  ('relevant', '最相关'),
                  ('likes', '最多点赞'),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.$2),
                    trailing: Icon(
                      sort == option.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: sort == option.$1
                          ? Theme.of(c).colorScheme.primary
                          : Theme.of(c).hintColor,
                    ),
                    selected: sort == option.$1,
                    onTap: () => Navigator.pop(c, option.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!current || selected == null || selected == sort) return;
    final reading = _reading;
    if (reading != null) await reading.future;
    if (!current) return;
    setState(() {
      sort = selected;
      cursor = null;
      rows.clear();
      replies.clear();
      replyCursors.clear();
      expanded.clear();
    });
    await _load();
  }

  void _closeInline() {
    if (_inlineComposerKey.currentState?.busy ?? false) return;
    _inlineComposerKey.currentState?._stash();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      composing = false;
      composerFull = false;
      editor.collapse();
    });
  }

  Future<void> _mutate(CommentRow row, {bool delete = false}) async {
    if (!current) return;
    final pending = widget.runtime.mutations.values.any(
      (m) => m['comment'] == row.id,
    );
    final wanted = !row.liked;
    if (!delete && !pending) {
      setState(() {
        row.data['likedByMe'] = wanted;
        row.data['likeCount'] = row.likes + (wanted ? 1 : -1);
      });
    }
    try {
      await widget.runtime.mutate(row.id, liked: delete ? null : wanted);
      if (!current) return;
      if (widget.runtime.deleted.contains(row.id)) {
        setState(() {
          rows.removeWhere((r) => r.id == row.id);
          replies.remove(row.id);
          for (final list in replies.values) {
            list.removeWhere((r) => r.id == row.id);
          }
        });
        await _loadContext();
        return;
      }
      if (!delete &&
          !widget.runtime.mutations.values.any((m) => m['comment'] == row.id)) {
        final raw = await widget.runtime.request(
          'GET',
          '/api/v1/posts/${widget.postId}/comments/${row.id}',
        );
        if (current) setState(() => row.data.addAll(CommentRow(raw).data));
      }
    } catch (_) {
      _hint('操作结果尚未确认，请核对。');
    }
  }

  Widget _row(CommentRow r, {bool reply = false}) => widget.continuous
      ? _timelineRow(r)
      : Container(
          key: keys.putIfAbsent(r.id, GlobalKey.new),
          color: highlight == r.id
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          padding: EdgeInsets.fromLTRB(reply ? 24 : 12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DetailAvatar(name: r.nickname, avatar: r.avatar, radius: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${r.nickname}${r.data['isPostAuthor'] == true ? ' · 楼主' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (r.data['replyTo'] case final Map relation)
                TextButton(
                  onPressed: () => _locate(relation['commentId'] as String),
                  child: Text('回复 ${(relation['author'] as Map)['nickname']}'),
                ),
              if (r.body.isNotEmpty)
                CommentBody(text: r.body, onReply: () => _compose(r)),
              if (r.data['image'] != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 160,
                    child: CommentImageView(runtime: widget.runtime, row: r),
                  ),
                ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _mutate(r),
                    icon: Icon(
                      r.liked ? Icons.favorite : Icons.favorite_border,
                    ),
                    label: Text('${r.likes}'),
                  ),
                  TextButton(
                    onPressed: () => _compose(r),
                    child: const Text('回复'),
                  ),
                  if (GovernanceScope.maybeOf(context) case final governance?)
                    TextButton(
                      onPressed: current && governance.available
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ReportScreen(
                                  controller: governance,
                                  postId: r.post,
                                  commentId: r.id,
                                  title: r.root == null ? '举报主评论' : '举报回复',
                                ),
                              ),
                            )
                          : null,
                      child: const Text('举报'),
                    ),
                  if (own.contains(r.id))
                    TextButton(
                      onPressed: () => _mutate(r, delete: true),
                      child: const Text('删除'),
                    ),
                ],
              ),
            ],
          ),
        );
  Widget _timelineRow(CommentRow r) => Container(
    key: keys.putIfAbsent(r.id, GlobalKey.new),
    color: highlight == r.id
        ? Theme.of(context).colorScheme.secondaryContainer
        : null,
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () =>
              unawaited(DmScope.contact(context, r.post, comment: r.id)),
          child: DetailAvatar(name: r.nickname, avatar: r.avatar, radius: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => unawaited(
                        DmScope.contact(context, r.post, comment: r.id),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: r.nickname,
                              style: detailType(
                                context,
                                14,
                                weight: FontWeight.w500,
                              ),
                            ),
                            if (r.data['isPostAuthor'] == true)
                              TextSpan(
                                text: '  楼主',
                                style: detailType(
                                  context,
                                  11.5,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            TextSpan(
                              text: ' · ${_commentTime(r)}',
                              style: detailType(
                                context,
                                12.5,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '评论操作',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: DetailChromeIcon(
                      DetailChrome.more,
                      color: Theme.of(context).hintColor,
                      size: 18,
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'reply', child: Text('回复')),
                      if (GovernanceScope.maybeOf(context)?.available == true)
                        const PopupMenuItem(value: 'report', child: Text('举报')),
                      if (own.contains(r.id))
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                    onSelected: (value) {
                      if (!current) return;
                      if (value == 'reply') unawaited(_compose(r));
                      if (value == 'delete') {
                        unawaited(_mutate(r, delete: true));
                      }
                      if (value == 'report') {
                        final governance = GovernanceScope.maybeOf(context);
                        if (governance?.available != true) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ReportScreen(
                              controller: governance!,
                              postId: r.post,
                              commentId: r.id,
                              title: r.root == null ? '举报主评论' : '举报回复',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              if (r.data['replyTo'] case final Map relation)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _locate(relation['commentId'] as String),
                  child: Text('回复 ${(relation['author'] as Map)['nickname']}'),
                ),
              if (r.body.isNotEmpty)
                DefaultTextStyle(
                  style: detailType(context, 14),
                  child: CommentBody(text: r.body, onReply: () => _compose(r)),
                ),
              if (r.data['image'] != null)
                SizedBox(
                  width: 160,
                  child: CommentImageView(runtime: widget.runtime, row: r),
                ),
              Row(
                children: [
                  DetailAction(
                    action: FeedAction.comment,
                    label: '回复${r.nickname}',
                    size: 18,
                    count: r.replyCount > 0 ? '${r.replyCount}' : null,
                    onPressed: () => _compose(r),
                  ),
                  const SizedBox(width: 36),
                  DetailAction(
                    action: FeedAction.like,
                    label: r.liked ? '取消点赞' : '点赞',
                    size: 18,
                    selected: r.liked,
                    count: '${r.likes}',
                    onPressed: () => _mutate(r),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _commentTime(CommentRow row) {
    final date = DateTime.tryParse(row.data['publishedAt'] as String? ?? '')
        ?.toLocal();
    return date == null ? '' : '${date.month}月${date.day}日';
  }

  Widget _threadRow(CommentRow row, {required CommentRow root}) {
    final children = (replies[root.id] ?? <CommentRow>[])
        .where((r) => !_localPublishedIds.contains(r.id))
        .take(expanded.contains(root.id) ? 10000 : 5);
    return Stack(
      children: [
        if (children.isNotEmpty)
          Positioned(
            left: 27.5,
            top: row.id == root.id ? 46 : 0,
            bottom: row.id == children.last.id ? 65 : 0,
            child: const ColoredBox(
              color: Color(0xFFDADFE1),
              child: SizedBox(width: 1),
            ),
          ),
        _row(row, reply: row.id != root.id),
      ],
    );
  }

  Widget _continuousList() {
    return ListView(
      key: PageStorageKey('comment-list:${widget.postId}:$epoch'),
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        widget.body,
        const Divider(height: 1),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('comment-sort'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).hintColor,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(48, 44),
            ),
            onPressed: _chooseSort,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(switch (sort) {
                  'recent' => '最近',
                  'likes' => '最多点赞',
                  _ => '相关',
                }, style: detailType(context, 14)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          TextButton(onPressed: () => _load(), child: Text(error!)),
        for (final entry in _localComments.entries.toList().reversed)
          Builder(
            key: ValueKey('local-comment:${entry.key}'),
            builder: (_) => _localComment(entry.key, entry.value),
          ),
        for (final r in rows.where(
          (r) => !_localPublishedIds.contains(r.id),
        )) ...[
          Builder(
            key: ValueKey('root-row:${r.id}'),
            builder: (_) {
              if (r.replyCount > 0 &&
                  !replies.containsKey(r.id) &&
                  !_replyFailures.contains(r.id) &&
                  _queuedReplies.add(r.id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (current && rows.contains(r)) unawaited(_replies(r.id));
                });
              }
              return _threadRow(r, root: r);
            },
          ),
          for (final reply
              in (replies[r.id] ?? <CommentRow>[])
                  .where((r) => !_localPublishedIds.contains(r.id))
                  .take(expanded.contains(r.id) ? 10000 : 5))
            Builder(
              key: ValueKey('reply-row:${reply.id}'),
              builder: (_) => _threadRow(reply, root: r),
            ),
          if (_replyFailures.contains(r.id))
            TextButton(
              onPressed: () => _replies(r.id),
              child: const Text('重试回复'),
            ),
          if (r.replyCount > 5)
            TextButton(
              onPressed: () async {
                if (expanded.remove(r.id)) {
                  setState(() {});
                } else {
                  setState(() => expanded.add(r.id));
                  if (replyCursors[r.id] != null) {
                    await _replies(r.id, more: true);
                  }
                }
              },
              child: Text(
                expanded.contains(r.id)
                    ? '收起回复'
                    : '展开其余 ${r.replyCount - 5} 条回复',
              ),
            ),
          if (expanded.contains(r.id) && replyCursors[r.id] != null)
            TextButton(
              onPressed: () => _replies(r.id, more: true),
              child: const Text('更多回复'),
            ),
          const Divider(height: 1),
        ],

        if (rows.isEmpty &&
            _localComments.isEmpty &&
            !loading &&
            error == null &&
            !_sending)
          const Padding(padding: EdgeInsets.all(20), child: Text('暂无评论')),
        if (cursor != null)
          TextButton(
            onPressed: () => _load(more: true),
            child: const Text('更多评论'),
          ),
        Builder(
          builder: (context) => SizedBox(
            height:
                24 +
                (widget.overlayComposer
                    ? MediaQuery.viewInsetsOf(context).bottom +
                          MediaQuery.paddingOf(context).bottom +
                          (composing
                              ? 132 +
                                    (composerTarget == null ? 0 : 24) +
                                    ((_inlineComposerKey.currentState?.picked !=
                                                null ||
                                            _inlineComposerKey
                                                    .currentState
                                                    ?.error !=
                                                null)
                                        ? 108
                                        : 0)
                              : 58)
                    : 0),
          ),
        ),
      ],
    );
  }

  Widget _continuous() {
    final timeline = _continuousList();
    return PopScope(
      canPop: !composing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && composing) _closeInline();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboard = widget.overlayComposer
              ? MediaQuery.viewInsetsOf(context).bottom
              : 0.0;
          final available = (constraints.maxHeight - keyboard).clamp(
            0.0,
            constraints.maxHeight,
          );
          final composer = composing
              ? SizedBox(
                  height: composerFull
                      ? available
                      : (132.0 +
                                MediaQuery.paddingOf(context).bottom +
                                (composerTarget == null ? 0 : 24) +
                                ((_inlineComposerKey.currentState?.picked !=
                                            null ||
                                        _inlineComposerKey
                                                .currentState
                                                ?.error !=
                                            null)
                                    ? 108
                                    : 0))
                            .clamp(0.0, available),
                  child: CommentComposer(
                    key: _inlineComposerKey,
                    runtime: widget.runtime,
                    editor: editor,
                    originals: originals,
                    contextText: composerTarget == null
                        ? widget.postBody
                        : '${composerTarget!.nickname}\n${composerTarget!.body}',
                    replyContext: composerTarget,
                    docked: true,
                    photoPicker: widget.photoPicker,
                    initialIdentity: speakingIdentity,
                    onIdentityChanged: (person) {
                      if (current) setState(() => speakingIdentity = person);
                    },
                    onContentChanged: () {
                      if (current) setState(() {});
                    },
                    expanded: composerFull,
                    initialAttachment: initialAttachment,
                    onClose: _closeInline,
                    onExpand: () =>
                        setState(() => composerFull = !composerFull),
                    onSubmitted: () {
                      if (!current) return;
                      setState(() {
                        composing = false;
                        composerFull = false;
                        editor = CommentEditor(
                          CommentTarget(postId: widget.postId),
                        );
                      });
                    },
                  ),
                )
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          _SpeakingAvatar(identity: speakingIdentity),
                          Expanded(
                            child: InkWell(
                              onTap: () => _compose(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 14,
                                ),
                                child: Text(
                                  editor.hasInput ? '继续输入' : '发布你的回复',
                                  style: detailType(
                                    context,
                                    14,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '选择一张图片',
                            icon: const Icon(Icons.image_outlined, size: 21),
                            onPressed: () => _compose(null, 'image'),
                          ),
                          IconButton(
                            tooltip: '展开回复输入',
                            icon: const Icon(Icons.open_in_full, size: 19),
                            onPressed: () => _compose(null, null, true),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
          final reader = Offstage(
            offstage: composerFull,
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                widget.onBodyScroll?.call();
                return false;
              },
              child: timeline,
            ),
          );
          if (!widget.overlayComposer) {
            return Column(
              children: [
                Expanded(child: reader),
                composer,
              ],
            );
          }
          // The keyboard moves the input surface, not the reading viewport.
          // This preserves scroll position and avoids relaying out the thread on
          // every native IME animation frame. A footer keeps the last row reachable.
          return Stack(
            children: [
              Positioned.fill(child: reader),
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: composer,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const Center(child: Text('会话已变化，请重新进入帖子。'));
    final content = widget.continuous ? _continuous() : _split();
    return Column(
      children: [
        if (_notice != null) _noticeView(),
        for (final entry in widget.runtime.core.entries.where(
          (e) =>
              e.rateLimitWait != null &&
              e.intent.binding.postId == widget.postId &&
              !e.identityDeleted,
        ))
          Material(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RateLimitDraftNotice(
                    remaining: () =>
                        widget.runtime.core.rateLimitedSeconds(entry),
                    onRetry: () =>
                        widget.runtime.core.retryRateLimited(entry.localId),
                  ),
                  Text(
                    entry.content?.body ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }

  Widget _split() => Column(
    children: [
      Expanded(
        flex: open ? (bodyFraction * 1000).round() : 1,
        child: widget.body,
      ),
      SafeArea(
        top: false,
        bottom: !open,
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    open = !open;
                    bodyFraction = 2 / 3;
                  });
                  if (open) unawaited(_load());
                },
                icon: Icon(
                  open ? Icons.expand_more : Icons.chat_bubble_outline,
                ),
                label: Text(open ? '收起评论' : '评论 $_displayTotal'),
              ),
            ),
            TextButton(
              onPressed: () => _compose(),
              child: Text(editor.hasInput ? '继续输入' : '写评论'),
            ),
          ],
        ),
      ),
      if (open)
        Semantics(
          label: '调整正文与评论区域高度',
          onIncrease: () =>
              setState(() => bodyFraction = (bodyFraction - .1).clamp(.2, .8)),
          onDecrease: () =>
              setState(() => bodyFraction = (bodyFraction + .1).clamp(.2, .8)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => setState(
              () => bodyFraction =
                  (bodyFraction +
                          d.delta.dy / MediaQuery.sizeOf(context).height)
                      .clamp(.2, .8),
            ),
            child: const SizedBox(
              height: 16,
              width: double.infinity,
              child: Center(child: Icon(Icons.drag_handle, size: 16)),
            ),
          ),
        ),
      if (open)
        Expanded(
          flex: ((1 - bodyFraction) * 1000).round(),
          child: Column(
            children: [
              Row(children: [Expanded(child: Text('评论 $total'))]),
              Expanded(
                // Eager layout of the loaded page makes concrete targets
                // addressable even outside the viewport; network pagination
                // still bounds the initial content and keeps its snapshot.
                child: SingleChildScrollView(
                  key: PageStorageKey('comment-list:${widget.postId}:$epoch'),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        TextButton(
                          onPressed: () => _load(),
                          child: Text(error!),
                        ),
                      for (final entry
                          in _localComments.entries.toList().reversed)
                        _localComment(entry.key, entry.value),
                      for (final r in rows.where(
                        (r) => !_localPublishedIds.contains(r.id),
                      )) ...[
                        _row(r),
                        for (final reply
                            in (replies[r.id] ?? <CommentRow>[])
                                .where(
                                  (r) => !_localPublishedIds.contains(r.id),
                                )
                                .take(expanded.contains(r.id) ? 10000 : 5))
                          _row(reply, reply: true),
                        if (r.replyCount > 5)
                          TextButton(
                            onPressed: () async {
                              if (expanded.remove(r.id)) {
                                setState(() {});
                              } else {
                                setState(() => expanded.add(r.id));
                                if (replyCursors[r.id] != null) {
                                  await _replies(r.id, more: true);
                                }
                              }
                            },
                            child: Text(
                              expanded.contains(r.id)
                                  ? '收起回复'
                                  : '展开其余 ${r.replyCount - 5} 条回复',
                            ),
                          ),
                        if (expanded.contains(r.id) &&
                            replyCursors[r.id] != null)
                          TextButton(
                            onPressed: () => _replies(r.id, more: true),
                            child: const Text('更多回复'),
                          ),
                        const Divider(),
                      ],

                      if (rows.isEmpty &&
                          _localComments.isEmpty &&
                          !loading &&
                          error == null &&
                          !_sending)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('暂无评论'),
                        ),
                      if (cursor != null)
                        TextButton(
                          onPressed: () => _load(more: true),
                          child: const Text('更多评论'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _SpeakingAvatar extends StatelessWidget {
  const _SpeakingAvatar({required this.identity});
  final ManagedIdentity? identity;
  @override
  Widget build(BuildContext context) {
    final person = identity;
    if (person != null) {
      return DetailAvatar(
        name: person.nickname,
        avatar: person.avatar,
        radius: 16,
      );
    }
    return const SizedBox(
      width: 32,
      height: 32,
      child: Icon(Icons.person_outline, size: 24),
    );
  }
}

class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.runtime,
    required this.editor,
    required this.contextText,
    required this.onSubmitted,
    required this.originals,
    this.replyContext,
    this.quickReplyTo,
    this.onOpenRejected,
    this.docked = false,
    this.expanded = false,
    this.initialAttachment,
    this.onClose,
    this.onExpand,
    this.photoPicker,
    this.onContentChanged,
    this.initialIdentity,
    this.onIdentityChanged,
  });
  final CommentRuntime runtime;
  final CommentEditor editor;
  final Map<String, Uint8List> originals;
  final CommentRow? replyContext;

  /// List entry only; the existing full-screen detail composer is unchanged.
  final String? quickReplyTo;
  final VoidCallback? onOpenRejected;
  final VoidCallback? onContentChanged;
  final ManagedIdentity? initialIdentity;
  final ValueChanged<ManagedIdentity?>? onIdentityChanged;
  final PostPhotoPicker? photoPicker;
  final bool docked, expanded;
  final String? initialAttachment;
  final VoidCallback? onClose, onExpand;
  final String contextText;
  final VoidCallback onSubmitted;
  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer>
    with WidgetsBindingObserver {
  bool _keyboardWasVisible = false, _choosingIdentity = false;
  late final epoch = widget.runtime.authorityVersion;
  late final text = TextEditingController(text: widget.editor.body);
  final inputFocus = FocusNode();
  ManagedIdentity? displayedIdentity;
  String? identity, error;
  List<ManagedIdentity> identities = [];
  bool bound = false, busy = false;
  bool identitiesReady = false, identityConfirmed = false;
  Route<dynamic>? _childRoute;
  Uint8List? picked;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.runtime.addListener(_changed);
    displayedIdentity = widget.initialIdentity;
    identity = displayedIdentity?.id;
    picked = widget.originals[widget.editor.image?.blobId];
    unawaited(_identities());
    if (widget.docked && widget.initialAttachment != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current) {
          unawaited(_pick());
        }
      });
    }
  }

  bool get current =>
      mounted && widget.runtime.current(epoch) && widget.editor.active;
  void _changed() {
    if (mounted &&
        !widget.runtime.current(epoch) &&
        widget.quickReplyTo != null) {
      widget.editor.leave();
      text.clear();
      final route = ModalRoute.of(context);
      final picker = _childRoute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _identities() async {
    try {
      final (c, d) = await (
        widget.runtime.contextFor(widget.editor.target.postId),
        widget.runtime.directory(),
      ).wait;
      if (!current) return;
      setState(() {
        identitiesReady = true;
        identityConfirmed = false;
        error = null;
        identities = d.identities;
        final boundId = c['boundIdentityId'] as String?;
        bound = boundId != null;
        identity = boundId ?? identity;
        if (!bound && !identities.any((i) => i.id == identity)) {
          identity = identities.where((i) => i.isOriginal).firstOrNull?.id;
          if (identity == null && identities.length == 1) {
            identity = identities.single.id;
          }
        }
        if (bound && !identities.any((i) => i.id == identity)) {
          identity = null;
          error = '帖内身份已不可用，无法继续回复。';
        }
        displayedIdentity = identities
            .where((i) => i.id == identity)
            .firstOrNull;
      });
      widget.onIdentityChanged?.call(displayedIdentity);
    } catch (_) {
      if (current) setState(() => error = '无法核对发言身份，请重试。');
    }
  }

  Future<void> _pick() async {
    if (!current || busy) return;
    var cancelled = false;
    setState(() => busy = true);
    inputFocus.unfocus();
    try {
      final files = await (widget.photoPicker ?? NativePostPhotoPicker()).pick(
        1,
      );
      if (files.isEmpty) {
        cancelled = true;
        return;
      }
      final result = await inspectPostPhoto(files.single, commentUUID());
      if (!current) return;
      setState(() {
        if (widget.editor.image != null) {
          widget.originals.remove(widget.editor.image!.blobId);
        }
        picked = result.bytes;
        widget.editor.setImage(
          CommentImage(blobId: commentUUID(), selection: result.selection),
        );
        widget.originals[widget.editor.image!.blobId] = result.bytes;
        error = null;
      });
    } catch (_) {
      if (current) setState(() => error = '图片无法读取，请重新选择。文字和对象已保留。');
    } finally {
      if (current) {
        setState(() => busy = false);
        widget.onContentChanged?.call();
        if (widget.docked && cancelled && !widget.expanded) {
          _stash();
          widget.onClose?.call();
        } else if (widget.docked) {
          inputFocus.requestFocus();
        }
      }
    }
  }

  Future<void> _send() async {
    if (!current || busy || identity == null) return;
    widget.editor.body = text.text;
    setState(() => busy = true);
    try {
      final content = widget.editor.content();
      final image = content.image;
      if (image != null && picked != null) {
        widget.runtime.journal.staged[image.blobId] = picked!;
      }
      final t = widget.editor.target;
      await widget.runtime.core.submit(
        taskId: commentUUID(),
        commandId: commentKey(),
        binding: CommentBinding(
          postId: t.postId,
          identityId: identity!,
          rootCommentId: t.rootCommentId,
          targetCommentId: t.commentId,
        ),
        content: content,
        onJournaled: () {
          if (!current) return;
          FocusManager.instance.primaryFocus?.unfocus();
          widget.originals.clear();
          text.clear();
          widget.onSubmitted();
          if (!widget.docked) Navigator.pop(context);
        },
      );
    } catch (_) {
      if (current) setState(() => error = '尚未发送，请检查内容或恢复任务存储后重试。');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onContentChanged?.call();
      }
    }
  }

  Future<void> _quickSend() async {
    if (!current || busy || !identitiesReady || !widget.runtime.core.ready) {
      return;
    }
    if (_quickRejected != null) return;
    if (!bound && !identityConfirmed) {
      final navigator = Navigator.of(context);
      final route = DialogRoute<String>(
        context: context,
        builder: (pickerContext) => AlertDialog(
          title: const Text('选择发言身份'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in identities)
                    ListTile(
                      title: Text(item.nickname),
                      onTap: () => Navigator.pop(pickerContext, item.id),
                    ),
                  if (identities.isEmpty) const Text('请先在身份设置中创建发言身份。'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(pickerContext),
              child: const Text('取消'),
            ),
            if (identities.isEmpty)
              TextButton(
                onPressed: () async {
                  Navigator.pop(pickerContext);
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IdentityManagementScreen(
                        controller: widget.runtime.identityManagement,
                        sessions: widget.runtime.sessions,
                      ),
                    ),
                  );
                  if (current) await _identities();
                },
                child: const Text('身份设置'),
              ),
          ],
        ),
      );
      _childRoute = route;
      final selected = await navigator.push(route);
      _childRoute = null;
      if (!current ||
          selected == null ||
          !identities.any((item) => item.id == selected)) {
        return;
      }
      setState(() {
        identity = selected;
        identityConfirmed = true;
      });
      // Choosing an identity does not itself publish a comment.
      return;
    }
    await _send();
  }

  CommentJournalEntry? get _quickRejected => widget.runtime.core.entries
      .where(
        (entry) =>
            entry.intent.operation == CommentOperation.create &&
            entry.rejectionCode != null &&
            entry.intent.binding.postId == widget.editor.target.postId,
      )
      .firstOrNull;

  bool get _canRestoreQuick {
    final entry = _quickRejected;
    return entry != null &&
        entry.transport == CommentTransportState.settled &&
        !entry.identityDeleted &&
        entry.intent.binding.targetCommentId == null &&
        entry.content != null &&
        entry.content!.image == null;
  }

  Future<void> _restoreQuickReply() async {
    if (!current || busy || !_canRestoreQuick) return;
    final entry = _quickRejected!;
    setState(() => busy = true);
    try {
      if (text.text.isNotEmpty && text.text != entry.content!.body) {
        final route = DialogRoute<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('恢复之前的评论？'),
            content: const Text('恢复原内容会替换当前输入。之前的评论尚未被服务器接收。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留当前输入'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('恢复原内容'),
              ),
            ],
          ),
        );
        _childRoute = route;
        final replace = await Navigator.of(context).push(route);
        _childRoute = null;
        if (!current || replace != true) return;
      }
      final recovered = await widget.runtime.core.releaseRejected(
        localId: entry.localId,
        activePostId: widget.editor.target.postId,
      );
      if (!current || recovered == null) return;
      text.text = recovered.content.body;
      widget.editor.body = recovered.content.body;
      await _identities();
      // Recovery edits input only. A new explicit Reply action is required.
    } catch (_) {
      if (current) setState(() => error = '暂时无法恢复，原内容仍已保留，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (widget.editor.active) widget.editor.body = text.text;
    WidgetsBinding.instance.removeObserver(this);
    text.dispose();
    inputFocus.dispose();
    widget.runtime.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !widget.docked) return;
    final visible = View.of(context).viewInsets.bottom > 0;
    final dismissed = _keyboardWasVisible && !visible;
    _keyboardWasVisible = visible;
    if (dismissed && !widget.expanded && !busy && !_choosingIdentity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && !busy && !widget.expanded && !_choosingIdentity) {
          widget.onClose?.call();
        }
      });
    }
  }

  void _stash() {
    if (widget.editor.active) widget.editor.body = text.text;
  }

  Future<void> _selectIdentity() async {
    if (!current || busy) return;
    if (!identitiesReady) {
      await _identities();
      return;
    }
    _choosingIdentity = true;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                bound ? '帖内身份已固定' : '选择发言身份',
                style: Theme.of(c).textTheme.titleMedium,
              ),
              for (final i in identities.where(
                (i) => !bound || i.id == identity,
              ))
                ListTile(
                  leading: DetailAvatar(
                    name: i.nickname,
                    avatar: i.avatar,
                    radius: 18,
                  ),
                  title: Text(i.nickname),
                  trailing: i.id == identity ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(c, i.id),
                ),
              ListTile(
                title: const Text('身份设置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, 'manage'),
              ),
            ],
          ),
        ),
      ),
    );
    _choosingIdentity = false;
    if (!mounted || !current || selected == null) return;
    if (selected == 'manage') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IdentityManagementScreen(
            controller: widget.runtime.identityManagement,
            sessions: widget.runtime.sessions,
          ),
        ),
      );
      if (current) await _identities();
    } else if (!bound) {
      setState(() {
        identity = selected;
        displayedIdentity = identities
            .where((i) => i.id == selected)
            .firstOrNull;
      });
      widget.onIdentityChanged?.call(displayedIdentity);
    }
  }

  Widget _docked() {
    if (!current) return const Center(child: Text('会话已变化，请返回帖子。'));
    final person = displayedIdentity;
    final canSend =
        !busy &&
        identitiesReady &&
        identity != null &&
        widget.runtime.core.ready &&
        (text.text.trim().isNotEmpty || widget.editor.image != null);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: '发言身份',
                      onPressed: busy ? null : _selectIdentity,
                      icon: _SpeakingAvatar(identity: person),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.replyContext != null)
                              Text(
                                '回复 ${widget.replyContext!.nickname}',
                                style: detailType(
                                  context,
                                  12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            TextField(
                              key: const ValueKey('inline-comment-input'),
                              focusNode: inputFocus,
                              controller: text,
                              autofocus: widget.initialAttachment == null,
                              enabled: !busy,
                              minLines: 1,
                              maxLines: null,
                              style: detailType(context, 14),
                              onChanged: (v) {
                                widget.editor.body = v;
                                setState(() {});
                              },
                              decoration: const InputDecoration(
                                hintText: '发布你的回复',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.only(bottom: 8),
                              ),
                            ),
                            if (picked != null)
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      picked!,
                                      height: 88,
                                      width: 120,
                                      fit: BoxFit.cover,
                                      cacheWidth: 240,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      tooltip: '移除图片',
                                      icon: const Icon(Icons.cancel),
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                              widget.originals.remove(
                                                widget.editor.image?.blobId,
                                              );
                                              widget.editor.setImage(null);
                                              picked = null;
                                              widget.onContentChanged?.call();
                                            }),
                                    ),
                                  ),
                                ],
                              ),
                            if (error != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: widget.expanded ? '缩小回复输入' : '展开回复输入',
                      icon: Icon(
                        widget.expanded
                            ? Icons.close_fullscreen
                            : Icons.open_in_full,
                        size: 19,
                      ),
                      onPressed: busy ? null : widget.onExpand,
                    ),
                    if (widget.expanded)
                      IconButton(
                        tooltip: '收起回复',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: busy ? null : widget.onClose,
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: '选择一张图片',
                    onPressed: busy ? null : _pick,
                    icon: const Icon(Icons.image_outlined, size: 21),
                  ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSend ? _send : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(60, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('回复'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.docked
      ? _docked()
      : widget.quickReplyTo != null
      ? PopScope(
          canPop: !busy,
          child: QuickReplyDialog(
            targetName: current ? widget.quickReplyTo! : '',
            controller: text,
            busy: busy,
            onReply:
                current &&
                    identitiesReady &&
                    widget.runtime.core.ready &&
                    _quickRejected == null &&
                    (!bound || identity != null)
                ? _quickSend
                : null,
            onClose: busy ? null : () => Navigator.pop(context),
            error: _quickRejected == null
                ? error
                : error ??
                      (_canRestoreQuick
                          ? '这条帖子有一条未被接收的评论，原内容已保留，请先恢复。'
                          : '这条帖子有一条未被接收的回复，请前往原帖打开回复输入框，恢复原对象和内容。'),
            onRetry: _quickRejected == null
                ? (error == null ? null : _identities)
                : (_canRestoreQuick
                      ? _restoreQuickReply
                      : widget.onOpenRejected),
            retryLabel: _quickRejected == null
                ? '重试'
                : (_canRestoreQuick ? '恢复未发送内容' : '前往原帖恢复'),
            identityCaption: !bound && identityConfirmed
                ? '以 ${identities.where((i) => i.id == identity).firstOrNull?.nickname ?? '所选身份'} 回复'
                : null,
          ),
        )
      : Scaffold(
          appBar: AppBar(
            title: const Text('评论与回复'),
            actions: [
              TextButton(
                onPressed:
                    current &&
                        !busy &&
                        identity != null &&
                        widget.runtime.core.ready
                    ? _send
                    : null,
                child: const Text('发布'),
              ),
            ],
          ),
          body: !current
              ? const Center(child: Text('会话已变化，请返回帖子。'))
              : SafeArea(
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .25,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(widget.contextText),
                              if (widget.replyContext case final row?
                                  when row.data['image'] != null)
                                CommentImageView(
                                  runtime: widget.runtime,
                                  row: row,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: TextField(
                          controller: text,
                          onChanged: (v) => widget.editor.body = v,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: '写下评论，最多 3000 字',
                            contentPadding: EdgeInsets.all(16),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (error != null)
                        Semantics(liveRegion: true, child: Text(error!)),
                      if (widget.editor.image != null)
                        ListTile(
                          leading: picked == null
                              ? null
                              : SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: Image.memory(
                                    picked!,
                                    fit: BoxFit.contain,
                                    cacheWidth: 128,
                                    cacheHeight: 128,
                                  ),
                                ),
                          title: const Text('已选择 1 张原图'),
                          trailing: IconButton(
                            tooltip: '移除图片',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    if (widget.editor.image != null) {
                                      widget.originals.remove(
                                        widget.editor.image!.blobId,
                                      );
                                    }
                                    picked = null;
                                    widget.editor.setImage(null);
                                  }),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '选择一张图片',
                            onPressed: busy ? null : _pick,
                            icon: const Icon(Icons.image_outlined),
                          ),
                          DropdownButton<String>(
                            hint: const Text('选择身份'),
                            value: identities.any((i) => i.id == identity)
                                ? identity
                                : null,
                            items: [
                              for (final i in identities)
                                DropdownMenuItem(
                                  value: i.id,
                                  child: Text(i.nickname),
                                ),
                            ],
                            onChanged: bound || busy
                                ? null
                                : (id) => setState(() => identity = id),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            IdentityManagementScreen(
                                              controller: widget
                                                  .runtime
                                                  .identityManagement,
                                              sessions: widget.runtime.sessions,
                                            ),
                                      ),
                                    );
                                    if (current) await _identities();
                                  },
                            child: Text(bound ? '帖内身份已固定' : '身份设置'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        );
}

class CommentImageView extends StatefulWidget {
  const CommentImageView({super.key, required this.runtime, required this.row});
  final CommentRuntime runtime;
  final CommentRow row;
  @override
  State<CommentImageView> createState() => _CommentImageViewState();
}

class _CommentImageViewState extends State<CommentImageView> {
  Future<PostImages> _load(String _) async {
    final r = widget.runtime;
    final epoch = r.authorityVersion;
    final row = widget.row;
    final m = row.data['image'] as Map;
    final access = ValueNotifier(true);
    final providers = <ImageProvider>[];
    Timer? timer;
    var expired = false;
    final clock = Stopwatch()..start();
    bool current() =>
        r.current(epoch) &&
        !r.deleted.contains(row.id) &&
        !r.deleted.contains(row.root);
    late void Function() changed;
    void revoke() {
      if (!access.value) return;
      timer?.cancel();
      r.removeListener(changed);
      access.value = false;
      for (final p in providers) {
        unawaited(p.evict());
      }
    }

    // Assigned before a listener can fire; the lease is terminal.
    changed = () {
      if (!current()) revoke();
    };
    Future<Uint8List> bytes() async {
      // Deferred thumbnail loaders may start during layout; normalize even a
      // local session failure to async before notifying the owning media group.
      await Future<void>.value();
      if (!current() || !access.value) throw StateError('Image access ended');
      try {
        final token = r.authStore.current!.session!.token;
        final result = await r.http.image(
          token,
          '/api/v1/posts/${row.post}/comments/${row.id}/images/${m['contentVersionId']}/original',
          m['mimeType'] as String,
        );
        if (!current() || !access.value || clock.elapsed >= result.lease) {
          expired = clock.elapsed >= result.lease;
          revoke();
          throw StateError('Image lease ended');
        }
        timer ??= Timer(result.lease - clock.elapsed, () {
          expired = true;
          revoke();
        });
        return result.bytes;
      } on CommentHttpFailure catch (error) {
        // Keep a transport retry inside the existing deadline. The timer and
        // authority listener still end access; an HTTP denial ends it here.
        if (error.status != null) revoke();
        rethrow;
      } catch (_) {
        revoke();
        rethrow;
      }
    }

    Future<ImageProvider> provider() async {
      final p = MemoryImage(await bytes());
      providers.add(p);
      // PostImagesSection owns the bounded thumbnail decode. Nesting a second
      // ResizeImage here gives Flutter two competing decode-size callbacks.
      return p;
    }

    r.addListener(changed);
    return PostImages(
      postId: row.id,
      accessGranted: access,
      isExpired: () => expired,
      onRelease: revoke,
      images: [
        PostImage.deferred(
          loadThumbnail: provider,
          registerDecodeProvider: providers.add,
          animated: m['mimeType'] == 'image/gif',
          item: ViewerItem(
            id: m['contentVersionId'] as String,
            semanticLabel: '评论图片',
            saveAllowed: true,
            loadSource: () async => ViewerSource(
              provider: await provider(),
              pixelSize: Size(
                (m['pixelWidth'] as int).toDouble(),
                (m['pixelHeight'] as int).toDouble(),
              ),
            ),
            resolveOriginal: () async =>
                ViewerOriginal.bytes(await bytes(), switch (m['mimeType']) {
                  'image/jpeg' => ViewerOriginalFormat.jpeg,
                  'image/png' => ViewerOriginalFormat.png,
                  'image/gif' => ViewerOriginalFormat.gif,
                  _ => ViewerOriginalFormat.webp,
                }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => CommentViewportMedia(
    builder: (_) => PostImagesSection(
      postId: widget.row.id,
      expectedCount: 1,
      compactSingle: true,
      loadImages: _load,
      authority: widget.runtime,
      isCurrent: () =>
          widget.runtime.available &&
          !widget.runtime.deleted.contains(widget.row.id) &&
          !widget.runtime.deleted.contains(widget.row.root),
    ),
  );
}

/// Offscreen loaded rows keep their layout for exact positioning, but never
/// mount media or hold decoded originals. The visible thumbnail has a bounded
/// decode size; full-size bytes remain behind the existing authorized viewer.
class CommentViewportMedia extends StatefulWidget {
  const CommentViewportMedia({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<CommentViewportMedia> createState() => _CommentViewportMediaState();
}

class _CommentViewportMediaState extends State<CommentViewportMedia> {
  ScrollableState? _scrollable;
  bool _visible = false, _scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context);
    if (next != _scrollable) {
      _scrollable?.position.removeListener(_schedule);
      _scrollable = next;
      next?.position.addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final viewport = _scrollable?.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      var visible = rect.overlaps(Offset.zero & MediaQuery.sizeOf(context));
      if (viewport is RenderBox && viewport.hasSize) {
        visible =
            visible &&
            rect.overlaps(viewport.localToGlobal(Offset.zero) & viewport.size);
      }
      if (_visible != visible) setState(() => _visible = visible);
    });
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 160,
    child: _visible
        ? widget.builder(context)
        : const Center(child: Icon(Icons.image_outlined)),
  );
}

class CommentBody extends StatefulWidget {
  const CommentBody({super.key, required this.text, this.onReply});
  final String text;
  final VoidCallback? onReply;
  @override
  State<CommentBody> createState() => _CommentBodyState();
}

class _CommentBodyState extends State<CommentBody> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.text,
          style: DefaultTextStyle.of(context).style,
        ),
        textDirection: Directionality.of(context),
        maxLines: 4,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth);
      final overflow = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            widget.text,
            minLines: 1,
            maxLines: expanded ? null : 4,
            onTap: widget.onReply,
          ),
          if (overflow)
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? '收起全文' : '展开全文'),
            ),
        ],
      );
    },
  );
}
