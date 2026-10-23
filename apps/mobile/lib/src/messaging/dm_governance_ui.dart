import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../reports/report_screens.dart';
import '../system_notifications/notification_models.dart';
import 'dm_controller.dart';

Future<void> showDmBlock(
  BuildContext context,
  DmController controller,
  Map<String, dynamic> row,
) async {
  final scope = controller.scope;
  final blocked = (row['ownBlockId'] as String?)?.isNotEmpty == true;
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(blocked ? '解除拉黑？' : '确认拉黑？'),
          subtitle: const Text('聊天记录保留。拉黑期间双方暂停发送私信。'),
        ),
        ListTile(
          title: Text(blocked ? '解除拉黑' : '确认拉黑'),
          onTap: () => Navigator.pop(context, 'block'),
        ),
        if (!blocked)
          ListTile(
            title: const Text('举报'),
            onTap: () => Navigator.pop(context, 'report'),
          ),
        ListTile(title: const Text('取消'), onTap: () => Navigator.pop(context)),
      ],
    ),
  );
  if (!context.mounted || scope != controller.scope || !controller.available) {
    return;
  }
  if (action == 'report') {
    await openDmReport(context, controller, row);
    return;
  }
  if (action != 'block') return;
  try {
    await controller.setBlocked(row['identityId'], row['id'], !blocked);
    if (context.mounted && scope == controller.scope) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.error ?? '操作已保存，正在同步')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作未保存，请重试')));
    }
  }
}

class DmBlacklistScreen extends StatefulWidget {
  const DmBlacklistScreen({super.key, required this.controller});
  final DmController controller;
  @override
  State<DmBlacklistScreen> createState() => _DmBlacklistScreenState();
}

class _DmBlacklistScreenState extends State<DmBlacklistScreen> {
  late final String _scope = widget.controller.scope;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await widget.controller.blocks();
      if (mounted && _scope == widget.controller.scope) {
        setState(() => _rows = rows);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '黑名单读取失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('黑名单')),
      body: !widget.controller.available || _scope != widget.controller.scope
          ? const Center(child: Text('会话已变化，请重新进入'))
          : ListView(
              children: [
                const ListTile(subtitle: Text('仅显示拉黑时选择的身份。解除后才可继续发送。')),
                if (_error != null)
                  ListTile(title: Text(_error!), onTap: _load),
                if (_busy) const LinearProgressIndicator(),
                if (_rows?.isEmpty == true)
                  const ListTile(title: Text('暂无拉黑记录')),
                for (final row in _rows ?? <Map<String, dynamic>>[])
                  ListTile(
                    title: Text(row['peerName']),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await showDmBlock(context, widget.controller, {
                                ...row,
                                'id': row['conversationId'],
                                'ownBlockId': row['id'],
                              });
                              if (mounted &&
                                  _scope == widget.controller.scope) {
                                await _load();
                              }
                            },
                      child: const Text('解除'),
                    ),
                  ),
              ],
            ),
    ),
  );
}

Future<void> openDmReport(
  BuildContext context,
  DmController controller,
  Map<String, dynamic> row,
) async {
  final governance = GovernanceScope.maybeOf(context);
  if (governance == null || !governance.available) return;
  final scope = controller.scope;
  final reason = await Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const _DmReportReason()));
  if (reason == null ||
      !context.mounted ||
      scope != controller.scope ||
      !controller.available) {
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _DmReportDetails(controller: controller, row: row, reason: reason),
    ),
  );
}

class _DmReportReason extends StatefulWidget {
  const _DmReportReason();
  @override
  State<_DmReportReason> createState() => _DmReportReasonState();
}

class _DmReportReasonState extends State<_DmReportReason> {
  String? _reason;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('举报原因')),
    body: ListView(
      children: [
        for (final entry in reportReasons.entries)
          ListTile(
            title: Text(entry.value),
            trailing: Icon(
              _reason == entry.key
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            onTap: () => setState(() => _reason = entry.key),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: _reason == null
                ? null
                : () => Navigator.pop(context, _reason),
            child: const Text('下一步'),
          ),
        ),
      ],
    ),
  );
}

/// Copies only the explicitly chosen sequence interval. Missing or unverifiable
/// records are fixed as gaps; never replaced from a later directory or callback.
Future<Map<String, dynamic>> dmEvidenceSnapshot({
  required Map<String, dynamic> directory,
  required List<Map<String, dynamic>> rows,
  required int first,
  required int last,
  required Future<Uint8List> Function(String, String) photo,
}) async {
  if (first < 1 || last < first || last - first >= 200) {
    throw const FormatException('Evidence range limit');
  }
  final bySequence = <int, Map<String, dynamic>>{};
  for (final row in rows) {
    final receipt = row['outgoing'] == true ? (row['receipt'] as Map?) : row;
    final sequence = receipt?['sequence'];
    if (sequence is int && sequence >= first && sequence <= last) {
      bySequence[sequence] = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(row)),
      );
    }
  }
  final entries = <Map<String, dynamic>>[];
  var bytes = 0, authenticated = 0;
  for (var sequence = first; sequence <= last; sequence++) {
    final row = bySequence[sequence];
    final sent = row?['outgoing'] == true;
    final receipt = sent ? (row?['receipt'] as Map?) : row;
    final body = sent ? (row?['intent'] as Map?) : row;
    final image = row?['messageType'] == 'IMAGE' || row?['kind'] == 'IMAGE';
    var gap = row == null
        ? 'LOCAL_UNAVAILABLE'
        : row['recalled'] == true || row['_state'] == 'retracted'
        ? 'RETRACTED'
        : !image && receipt?['evidenceVersion'] != 1
        ? 'UNVERIFIABLE'
        : '';
    var text = '', data = '';
    if (gap.isEmpty) {
      if (image) {
        final media = sent ? body : row?['media'] as Map?;
        try {
          final original = await photo(
            media!['mediaId'] as String,
            sent ? directory['identityId'] : row!['senderId'],
          );
          if (bytes + original.length > 24 * 1024 * 1024) {
            throw const FormatException(
              'Evidence budget: choose a shorter range',
            );
          } else {
            data = base64Encode(original);
            bytes += original.length;
          }
        } on FormatException {
          rethrow;
        } catch (_) {
          gap = 'LOCAL_UNAVAILABLE';
        }
      } else {
        text = body?['text'] as String? ?? '';
        bytes += utf8.encode(text).length;
        if (text.isEmpty) gap = 'LOCAL_UNAVAILABLE';
      }
      if (gap.isEmpty) authenticated++;
    }
    entries.add({
      'messageId': receipt?['messageId'] ?? '', 'sequence': sequence,
      'kind': row == null
          ? 'UNKNOWN'
          : image
          ? 'IMAGE'
          : 'TEXT',
      'text': text,
      'data': data,
      'gap': gap,
      // UI-only direction is stripped by the submit adapter.
      'outgoing': sent,
    });
  }
  if (authenticated == 0) throw const FormatException('No verifiable evidence');
  return {
    'identityId': directory['identityId'],
    'conversationId': directory['id'],
    'firstSequence': first,
    'lastSequence': last,
    'entries': entries,
  };
}

class _DmReportDetails extends StatefulWidget {
  const _DmReportDetails({
    required this.controller,
    required this.row,
    required this.reason,
  });
  final DmController controller;
  final Map<String, dynamic> row;
  final String reason;
  @override
  State<_DmReportDetails> createState() => _DmReportDetailsState();
}

class _DmReportDetailsState extends State<_DmReportDetails> {
  late final String _scope = widget.controller.scope;
  Map<String, dynamic>? _snapshot;
  bool _authorized = false, _selecting = false;
  String? _error;
  Future<void> _select() async {
    if (_selecting) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) =>
              _DmEvidencePicker(controller: widget.controller, row: widget.row),
        ),
      );
      if (mounted && _scope == widget.controller.scope && result != null) {
        setState(() {
          _snapshot = result;
          _authorized = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '证据无法读取，请重新选择');
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final governance = GovernanceScope.maybeOf(context)!;
    return AnimatedBuilder(
      animation: Listenable.merge([governance, widget.controller]),
      builder: (context, _) => MaterialEvidenceForm(
        controller: governance,
        title: '举报详情',
        textLimit: 200,
        imageLimit: 6,
        hasExtraInput: _snapshot != null,
        enabled:
            _authorized &&
            _snapshot != null &&
            _scope == widget.controller.scope &&
            widget.controller.available,
        summary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reportReasons[widget.reason]!),
            const Text('选择首尾消息，提交该区间双方全部可用记录。旧记录无法认证或本地缺失时会明确标注。'),
            OutlinedButton(
              onPressed:
                  governance.pending != null || governance.busy || _selecting
                  ? null
                  : _select,
              child: Text(_snapshot == null ? '选择聊天证据' : '重选聊天区间'),
            ),
            if (_snapshot != null) ...[
              Text(
                '已固定第 ${_snapshot!['firstSequence']}–${_snapshot!['lastSequence']} 条',
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DmEvidencePreview(
                      snapshot: _snapshot!,
                      controller: widget.controller,
                      scope: _scope,
                    ),
                  ),
                ),
                child: const Text('预览本次证据'),
              ),
              CheckboxListTile(
                value: _authorized,
                onChanged: governance.pending != null || governance.busy
                    ? null
                    : (v) => setState(() => _authorized = v == true),
                title: const Text('授权平台查看此区间的可用记录和已知缺口'),
              ),
            ],
            if (_error != null) Text(_error!),
          ],
        ),
        onSubmit: (text, images) => governance.submitDmReport(
          {
            ..._snapshot!,
            'authorized': true,
            'entries': [
              for (final row in _snapshot!['entries'] as List)
                Map<String, dynamic>.from(row)..remove('outgoing'),
            ],
          },
          widget.reason,
          text,
          images,
        ),
      ),
    );
  }
}

class _DmEvidencePicker extends StatefulWidget {
  const _DmEvidencePicker({required this.controller, required this.row});
  final DmController controller;
  final Map<String, dynamic> row;
  @override
  State<_DmEvidencePicker> createState() => _DmEvidencePickerState();
}

class _DmEvidencePickerState extends State<_DmEvidencePicker> {
  late final String _scope = widget.controller.scope;
  final List<Map<String, dynamic>> _rows = [];
  int? _first, _last;
  bool _busy = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  int? _sequence(Map row) {
    final value = row['outgoing'] == true ? (row['receipt'] as Map?) : row;
    return value?['sequence'] as int?;
  }

  String _text(Map row) {
    final value = row['outgoing'] == true ? (row['intent'] as Map?) : row;
    final text = value?['text'] as String?;
    return text?.isNotEmpty == true ? text! : '[图片]';
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rows = await widget.controller.history(
        widget.row['identityId'],
        widget.row['peerId'],
        before: _rows.isEmpty ? null : _rows.first['_sort'],
      );
      if (mounted && _scope == widget.controller.scope) {
        setState(() {
          _rows.insertAll(0, rows);
          _more = rows.length == 40;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '读取失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await dmEvidenceSnapshot(
        directory: widget.row,
        rows: _rows,
        first: _first!,
        last: _last ?? _first!,
        photo: (id, sender) => widget.controller.photo(id, senderId: sender),
      );
      if (!mounted || _scope != widget.controller.scope) return;
      final used = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DmEvidencePreview(
            snapshot: snapshot,
            select: true,
            controller: widget.controller,
            scope: _scope,
          ),
        ),
      );
      if (mounted && _scope == widget.controller.scope && used == true) {
        Navigator.pop(context, snapshot);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              '请选择含可认证消息的连续区间，最多200条、聊天图片合计24MiB；超出时请缩短区间，全部为旧版或缺失记录时无法提交。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('选择聊天证据')),
      body: !widget.controller.available || _scope != widget.controller.scope
          ? const Center(child: Text('会话已变化，请返回'))
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('依次点选首条、末条；区间内双方记录都会包含。再次选择可重设范围。'),
                ),
                if (_error != null) Text(_error!),
                if (_busy) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    children: [
                      if (_more)
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('加载更早消息'),
                        ),
                      for (final row in _rows)
                        if (_sequence(row) != null)
                          Align(
                            alignment: row['outgoing'] == true
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      final n = _sequence(row)!;
                                      if (_first == null || _last != null) {
                                        _first = n;
                                        _last = null;
                                      } else if (n < _first!) {
                                        _last = _first;
                                        _first = n;
                                      } else {
                                        _last = n;
                                      }
                                    }),
                              child: Text(
                                '${_sequence(row)} ${_text(row)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: _busy || _first == null ? null : _preview,
                      child: Text(
                        _first == null
                            ? '先选择消息'
                            : '预览 $_first–${_last ?? _first}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}

class DmEvidencePreview extends StatefulWidget {
  const DmEvidencePreview({
    super.key,
    required this.snapshot,
    required this.controller,
    required this.scope,
    this.select = false,
  });
  final Map<String, dynamic> snapshot;
  final DmController controller;
  final String scope;
  final bool select;
  @override
  State<DmEvidencePreview> createState() => _DmEvidencePreviewState();
}

class _DmEvidencePreviewState extends State<DmEvidencePreview> {
  final _images = <int, MemoryImage>{};
  void _clear() {
    for (final image in _images.values) {
      unawaited(image.evict());
    }
    _images.clear();
  }

  void _changed() {
    if (!widget.controller.available ||
        widget.scope != widget.controller.scope) {
      _clear();
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('固定证据预览')),
    body:
        !widget.controller.available || widget.scope != widget.controller.scope
        ? const Center(child: Text('会话已变化，请返回'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('仅包含以下区间及缺口。预览后新消息不会加入，后续撤回不改变本次快照。'),
              for (final row in widget.snapshot['entries'] as List)
                Align(
                  alignment: row['outgoing'] == true
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${row['sequence']} ${row['outgoing'] == true ? '本人' : '对方'}',
                        ),
                        if (row['gap'] != '')
                          Text(switch (row['gap']) {
                            'UNVERIFIABLE' => '缺口：旧记录无法认证',
                            'RETRACTED' => '缺口：消息已撤回',
                            _ => '缺口：本机记录不可用',
                          })
                        else if (row['kind'] == 'IMAGE')
                          Image(
                            image: _images.putIfAbsent(
                              row['sequence'],
                              () => MemoryImage(base64Decode(row['data'])),
                            ),
                            width: 240,
                            height: 180,
                            fit: BoxFit.contain,
                          )
                        else
                          Text(row['text']),
                      ],
                    ),
                  ),
                ),
              if (widget.select)
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('使用这份证据'),
                ),
            ],
          ),
  );
}
