import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hnuhole_image_viewer/image_viewer.dart';

import '../identity/identity_api.dart';
import '../identity/identity_management_screen.dart';
import '../posts/post_images.dart';
import '../posts/post_models.dart';
import '../posts/post_photo_picker.dart';
import 'comment_editor.dart';
import 'comment_http.dart';
import 'comment_models.dart';
import 'comment_runtime.dart';

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
    PostJson.record(data['author'], {'ref', 'nickname', 'avatar', 'state'});
  }
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get post => data['postId'] as String;
  String? get root => data['rootCommentId'] as String?;
  String get body => data['body'] as String;
  String get nickname => (data['author'] as Map)['nickname'] as String;
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
  });
  final CommentRuntime runtime;
  final String postId, postBody;
  final Widget body;
  final String? initialCommentId;
  final CommentRejectedInput? initialInput;
  final Uint8List? initialOriginal;
  @override
  State<CommentPostPane> createState() => _CommentPostPaneState();
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
  String? cursor, highlight, error;
  int total = 0;
  bool open = false, loading = false;
  Completer<void>? _reading;
  double bodyFraction = 2 / 3;
  Timer? _highlightTimer;
  Set<String> own = {};
  bool get current => mounted && widget.runtime.current(epoch);
  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_changed);
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
    originals.clear();
    editor.leave();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (!current) {
      editor.leave();
      rows.clear();
      replies.clear();
    }
    rows.removeWhere((r) => widget.runtime.deleted.contains(r.id));
    replies.removeWhere((id, _) => widget.runtime.deleted.contains(id));
    for (final list in replies.values) {
      list.removeWhere((r) => widget.runtime.deleted.contains(r.id));
    }
    setState(() {});
    if (current) {
      for (final t in widget.runtime.core.resolvedTasks) {
        if (t.state == CommentTaskState.published &&
            t.binding.postId == widget.postId &&
            completed.add(t.taskId)) {
          open = true;
          own.add(t.commentId!);
          unawaited(_locate(t.commentId!));
          unawaited(_loadContext());
        }
      }
    }
  }

  void _hint(String text) {
    if (current) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _loadContext() async {
    try {
      final c = await widget.runtime.contextFor(widget.postId);
      if (current) {
        setState(() {
          own = (c['ownCommentIds'] as List).cast<String>().toSet();
          total = c['totalCount'] as int;
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
        query: more && cursor != null ? {'cursor': cursor!} : null,
      );
      if (!current) return;
      setState(() {
        if (!more) {
          rows.clear();
          replies.clear();
          replyCursors.clear();
          expanded.clear();
        }
        for (final raw in p['comments'] as List) {
          final row = CommentRow(raw);
          if (!rows.any((r) => r.id == row.id)) rows.add(row);
        }
        cursor = p['nextCursor'] as String?;
        total = p['totalCount'] as int;
        error = null;
      });
      for (final row in rows.where((r) => r.replyCount > 0).toList()) {
        if (!current) return;
        if (!replies.containsKey(row.id)) await _replies(row.id);
      }
    } catch (e) {
      if (current) {
        setState(() {
          if (e is CommentHttpFailure && {403, 404}.contains(e.status)) {
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
      if (!current) return;
      setState(() {
        final list = replies.putIfAbsent(root, () => []);
        for (final raw in p['comments'] as List) {
          final row = CommentRow(raw);
          if (!list.any((r) => r.id == row.id)) list.add(row);
        }
        replyCursors[root] = p['nextCursor'] as String?;
      });
    } catch (e) {
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
    }
  }

  Future<void> _locate(String id) async {
    if (!current) return;
    try {
      final reading = _reading;
      if (reading != null) await reading.future;
      if (!current) return;
      final location = await widget.runtime.request(
        'GET',
        '/api/v1/posts/${widget.postId}/comments/$id/location',
      );
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
      while (!rows.any((r) => r.id == floor) && cursor != null) {
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
        if (!own.contains(root.id) && widget.initialCommentId != id) {
          throw StateError('Outside captured snapshot');
        }
        rows.insert(_insertAt(rows, root, 10), root);
      }
      if (target.root != null) {
        expanded.add(floor);
        if (!replies.containsKey(floor)) await _replies(floor);
        if (!current) return;
        final list = replies.putIfAbsent(floor, () => []);
        while (!list.any((r) => r.id == id) && replyCursors[floor] != null) {
          final previous = replyCursors[floor];
          await _replies(floor, more: true);
          if (!current) return;
          if (replyCursors[floor] == previous) {
            throw StateError('Captured replies unavailable');
          }
        }
        if (!list.any((r) => r.id == id)) {
          if (!own.contains(id) && widget.initialCommentId != id) {
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
        final c = keys[id]?.currentContext;
        if (current && c != null) {
          Scrollable.ensureVisible(
            c,
            alignment: 0,
            duration: const Duration(milliseconds: 250),
          );
        }
      });
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (current && highlight == id) setState(() => highlight = null);
      });
    } catch (e) {
      if (current && e is CommentHttpFailure && {403, 404}.contains(e.status)) {
        setState(() {
          rows.removeWhere((r) => r.id == id);
          replies.remove(id);
          for (final list in replies.values) {
            list.removeWhere((r) => r.id == id);
          }
        });
        _hint('评论已经删除');
      } else {
        _hint('暂时无法定位，请重试。');
      }
    }
  }

  int _insertAt(List<CommentRow> list, CommentRow target, int top) {
    final a = DateTime.parse(target.data['publishedAt'] as String);
    for (var i = top; i < list.length; i++) {
      final b = DateTime.parse(list[i].data['publishedAt'] as String);
      if (a.isBefore(b) || a == b && target.id.compareTo(list[i].id) < 0) {
        return i;
      }
    }
    return list.length;
  }

  Future<void> _compose([CommentRow? row]) async {
    if (!current) return;
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

  Widget _row(CommentRow r, {bool reply = false}) => Container(
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
            const CircleAvatar(
              radius: 14,
              child: Icon(Icons.person_outline, size: 18),
            ),
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
              icon: Icon(r.liked ? Icons.favorite : Icons.favorite_border),
              label: Text('${r.likes}'),
            ),
            TextButton(onPressed: () => _compose(r), child: const Text('回复')),
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
  @override
  Widget build(BuildContext context) {
    if (!current) return const Center(child: Text('会话已变化，请重新进入帖子。'));
    return Column(
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
                  label: Text(open ? '收起评论' : '评论 $total'),
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
            onIncrease: () => setState(
              () => bodyFraction = (bodyFraction - .1).clamp(.2, .8),
            ),
            onDecrease: () => setState(
              () => bodyFraction = (bodyFraction + .1).clamp(.2, .8),
            ),
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
                        for (final r in rows) ...[
                          _row(r),
                          for (final reply
                              in (replies[r.id] ?? <CommentRow>[]).take(
                                expanded.contains(r.id) ? 10000 : 5,
                              ))
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
                        if (rows.isEmpty && !loading && error == null)
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
  });
  final CommentRuntime runtime;
  final CommentEditor editor;
  final Map<String, Uint8List> originals;
  final CommentRow? replyContext;
  final String contextText;
  final VoidCallback onSubmitted;
  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  late final epoch = widget.runtime.authorityVersion;
  late final text = TextEditingController(text: widget.editor.body);
  String? identity, error;
  List<ManagedIdentity> identities = [];
  bool bound = false, busy = false;
  Uint8List? picked;
  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_changed);
    picked = widget.originals[widget.editor.image?.blobId];
    unawaited(_identities());
  }

  bool get current =>
      mounted && widget.runtime.current(epoch) && widget.editor.active;
  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _identities() async {
    try {
      final c = await widget.runtime.contextFor(widget.editor.target.postId),
          d = await widget.runtime.directory();
      if (!current) return;
      setState(() {
        identities = d.identities;
        identity = c['boundIdentityId'] as String?;
        bound = identity != null;
        if (!bound && !identities.any((i) => i.id == identity)) {
          identity = identities.where((i) => i.isOriginal).firstOrNull?.id;
          if (identity == null && identities.length == 1) {
            identity = identities.single.id;
          }
        }
        if (bound && !identities.any((i) => i.id == identity)) {
          identity = null;
        }
      });
    } catch (_) {
      if (current) setState(() => error = '无法核对发言身份，请重试。');
    }
  }

  Future<void> _pick() async {
    setState(() => busy = true);
    try {
      final files = await NativePostPhotoPicker().pick(1);
      if (files.isEmpty) return;
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
      if (current) setState(() => busy = false);
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
          widget.onSubmitted();
          Navigator.pop(context);
        },
      );
    } catch (_) {
      if (current) setState(() => error = '尚未发送，请检查内容或恢复任务存储后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (widget.editor.active) widget.editor.body = text.text;
    text.dispose();
    widget.runtime.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('评论与回复'),
      actions: [
        TextButton(
          onPressed:
              current && !busy && identity != null && widget.runtime.core.ready
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
                          CommentImageView(runtime: widget.runtime, row: row),
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
                                  builder: (_) => IdentityManagementScreen(
                                    controller:
                                        widget.runtime.identityManagement,
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
      if (!current() || !access.value) throw StateError('Image access ended');
      try {
        final token = r.authStore.current!.session!.token;
        final result = await r.http.image(
          token,
          '/api/v1/posts/${row.post}/comments/${row.id}/images/${m['contentVersionId']}/original',
          m['mimeType'] as String,
        );
        if (!current() || !access.value || clock.elapsed >= result.lease) {
          revoke();
          throw StateError('Image lease ended');
        }
        timer ??= Timer(result.lease - clock.elapsed, revoke);
        return result.bytes;
      } catch (_) {
        revoke();
        rethrow;
      }
    }

    Future<ImageProvider> provider({bool thumbnail = false}) async {
      final p = MemoryImage(await bytes());
      providers.add(p);
      if (thumbnail) {
        final resized = ResizeImage(
          p,
          width: 320,
          height: 320,
          policy: ResizeImagePolicy.fit,
        );
        providers.add(resized);
        return resized;
      }
      return p;
    }

    r.addListener(changed);
    return PostImages(
      postId: row.id,
      accessGranted: access,
      onRelease: revoke,
      images: [
        PostImage.deferred(
          loadThumbnail: () => provider(thumbnail: true),
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
