import 'dart:async';

import 'package:flutter/material.dart';

import '../posts/post_protocol.dart';
import '../reports/report_screens.dart';
import 'governance_controller.dart';
import 'notification_models.dart';

String _date(DateTime d) =>
    '${d.toLocal().year}-${d.toLocal().month.toString().padLeft(2, '0')}-${d.toLocal().day.toString().padLeft(2, '0')} ${d.toLocal().hour.toString().padLeft(2, '0')}:${d.toLocal().minute.toString().padLeft(2, '0')}';

class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({
    super.key,
    required this.controller,
    this.onOpenPost,
  });
  final GovernanceController controller;
  final Future<void> Function(String)? onOpenPost;
  @override
  State<SystemNotificationsScreen> createState() =>
      _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.controller.available) return;
    await widget.controller.loadIdentities();
    if (widget.controller.available) {
      await widget.controller.loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: const Text('系统通知'),
          actions: [
            if (c.restricted)
              IconButton(
                tooltip: '退出处理通知',
                onPressed: () async {
                  await c.restrictedAccess!.clear();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.logout),
              ),
            IconButton(
              tooltip: '刷新通知',
              onPressed: c.available && !c.loading ? _load : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !c.available
            ? const Center(child: Text('请先恢复会话，再查看系统通知。'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey(c.selectedIdentityId),
                    initialValue: c.selectedIdentityId ?? '',
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.switch_account_outlined),
                      labelText: '切换身份',
                      helperText: '查看不同身份的消息；账号通知始终可见',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('账号通知')),
                      for (final i in c.identities)
                        DropdownMenuItem(value: i.id, child: Text(i.nickname)),
                    ],
                    onChanged: c.loading
                        ? null
                        : (id) => c.selectIdentity(id == '' ? null : id),
                  ),
                  const SizedBox(height: 24),
                  if (c.pending != null) PendingGovernancePanel(controller: c),
                  if (c.loading && c.items.isEmpty)
                    const Center(child: CircularProgressIndicator()),
                  if (!c.loading && c.items.isEmpty)
                    Text(c.error == null ? '暂无系统通知' : '通知暂时无法读取'),
                  for (final notice in c.items)
                    InkWell(
                      key: ValueKey(notice.id),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SystemNoticeDetailScreen(
                              controller: c,
                              noticeId: notice.id,
                              targetIdentityId: notice.identityId,
                              onOpenPost: widget.onOpenPost,
                            ),
                          ),
                        );
                        if (c.available) await c.loadNotifications();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                if (notice.unread) ...[
                                  Semantics(
                                    label: '未读',
                                    child: const Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  _date(notice.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              notice.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (notice.body.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(notice.body),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (c.nextBefore != null)
                    TextButton(
                      onPressed: c.loading
                          ? null
                          : () => c.loadNotifications(more: true),
                      child: const Text('加载更多'),
                    ),
                  if (c.error != null)
                    Semantics(liveRegion: true, child: Text(c.error!)),
                ],
              ),
      );
    },
  );
}

class SystemNoticeDetailScreen extends StatefulWidget {
  const SystemNoticeDetailScreen({
    super.key,
    required this.controller,
    required this.noticeId,
    this.targetIdentityId,
    this.onOpenPost,
  });
  final GovernanceController controller;
  final String noticeId;
  final String? targetIdentityId;
  final Future<void> Function(String)? onOpenPost;
  @override
  State<SystemNoticeDetailScreen> createState() =>
      _SystemNoticeDetailScreenState();
}

class _SystemNoticeDetailScreenState extends State<SystemNoticeDetailScreen> {
  late final int _epoch = widget.controller.authorityVersion;
  SystemNotice? _notice;
  Map<String, dynamic>? _resource;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.controller.available ||
        widget.controller.authorityVersion != _epoch) {
      return;
    }
    setState(() => _loading = true);
    final notice = await widget.controller.openNotice(
      widget.noticeId,
      targetIdentityId: widget.targetIdentityId,
    );
    final resource = notice == null
        ? null
        : await widget.controller.readResource(notice.route);
    if (mounted && widget.controller.authorityVersion == _epoch) {
      setState(() {
        _notice = notice;
        _resource = resource;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(title: const Text('通知详情')),
        body: !c.available || c.authorityVersion != _epoch
            ? const Center(child: Text('会话已变化，请返回重新进入。'))
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_notice case final n?) ...[
                    Text(
                      _date(n.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      n.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(n.body),
                    const SizedBox(height: 24),
                    if (n.route.name == 'COMMENT_FAILURE')
                      const Text('评论失败任务接口已预留，当前版本尚未接入评论发布任务。'),
                    if (_resource case final r?)
                      GovernanceResourceView(
                        controller: c,
                        route: n.route,
                        resource: r,
                        onOpenPost: widget.onOpenPost,
                        onRefresh: _load,
                      ),
                  ] else
                    const Text('暂时无法读取通知。'),
                  if (c.error != null)
                    Semantics(liveRegion: true, child: Text(c.error!)),
                  if (_notice == null || _resource == null)
                    TextButton(onPressed: _load, child: const Text('重新核对')),
                ],
              ),
      );
    },
  );
}

class GovernanceResourceView extends StatelessWidget {
  const GovernanceResourceView({
    super.key,
    required this.controller,
    required this.route,
    required this.resource,
    required this.onRefresh,
    this.onOpenPost,
  });
  final GovernanceController controller;
  final NotificationRoute route;
  final Map<String, dynamic> resource;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String)? onOpenPost;
  Widget _line(String label, Object? value) => value == null || value == ''
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('$label：$value'),
        );
  String _state(Object? state) => switch (state) {
    'PENDING' => '待处理',
    'PROCESSING' => '处理中',
    'ENDED' => '已结束',
    'ACCEPTED' => '申诉通过',
    'REJECTED' => '申诉未通过',
    _ => '正在核对',
  };
  Future<void> _form(
    BuildContext context,
    String target, {
    bool supplement = false,
    int ordinal = 1,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => MaterialEvidenceForm(
            controller: controller,
            title: supplement ? '补充材料' : '申诉',
            textLimit: 500,
            imageLimit: supplement ? 3 : 6,
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('原处罚继续按期限执行，提交材料不代表申诉通过。'),
                const SizedBox(height: 12),
                Text('本次申诉 $ordinal/3'),
                const Text('最多可申诉 3 次，补充材料不占次数'),
                Text('本次最多 500 字、${supplement ? 3 : 6} 张图片'),
              ],
            ),
            submitLabel: supplement ? '提交补充材料' : '提交申诉',
            onSubmit: (text, images) => supplement
                ? controller.supplementAppeal(target, text, images)
                : controller.submitAppeal(target, text, images),
          ),
        ),
      ),
    );
    await onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (route.name == 'REPORT') {
      final r = resource['report'];
      if (r is! Map<String, dynamic>) return const Text('举报提交结果仍在核对。');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('状态', _state(r['state'])),
          _line('举报类别', reportReasons[r['reason']] ?? '其他'),
          _line('举报说明', r['description']),
          _line('处理结论', switch (r['outcome']) {
            'UPHELD' => '违规成立',
            'DISMISSED' => '未发现违规',
            'TARGET_DELETED' => '内容已删除，本次举报已结束',
            'REVERSED' => '原处理已复核纠正',
            _ => null,
          }),
          _line('简短说明', r['explanation']),
          if (r['postId'] is String && onOpenPost != null)
            TextButton(
              onPressed: () =>
                  onOpenPost!(PostProtocol.resourceId(r['postId'] as String)),
              child: const Text('查看来源帖子'),
            ),
        ],
      );
    }
    if (route.name == 'SANCTION') {
      final r = resource,
          count = resource['appealCount'] as int? ?? 0,
          active = resource['activeAppealId'];
      final action = switch (r['action']) {
        'TAKEDOWN' => '下架内容',
        'MUTE' => '账号禁言',
        'BAN' => '账号封禁',
        'RESET_NICKNAME' => '重置违规昵称',
        'RESET_AVATAR' => '重置违规头像',
        _ => '违规处理',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('处理措施', action),
          _line('处理原因', r['reason']),
          _line('开始时间', _date(DateTime.parse(r['startsAt'] as String))),
          _line(
            '结束时间',
            r['endsAt'] == null
                ? '无固定结束时间'
                : _date(DateTime.parse(r['endsAt'] as String)),
          ),
          _line(
            '撤销时间',
            r['revokedAt'] == null
                ? null
                : _date(DateTime.parse(r['revokedAt'] as String)),
          ),
          const Text('账号级处罚对本账号全部身份生效；其他有效处罚独立执行。'),
          if (active is String)
            FilledButton(
              onPressed: () async {
                final appeal = await controller.readResource(
                  NotificationRoute('APPEAL', active),
                );
                if (context.mounted && appeal != null) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ResourceScreen(
                        controller: controller,
                        route: NotificationRoute('APPEAL', active),
                        resource: appeal,
                        onOpenPost: onOpenPost,
                      ),
                    ),
                  );
                  await onRefresh();
                }
              },
              child: const Text('查看待复核申诉'),
            )
          else if (count < 3 && r['revokedAt'] == null)
            FilledButton(
              onPressed: () =>
                  _form(context, route.resourceId, ordinal: count + 1),
              child: const Text('申诉'),
            ),
          if (count >= 3) const Text('已使用三次独立申诉额度。'),
        ],
      );
    }
    if (route.name == 'APPEAL') {
      final r = resource;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('状态', r['state'] == 'PENDING' ? '待复核' : _state(r['state'])),
          _line('本次申诉', '${r['ordinal']}/3'),
          _line('复核说明', r['reason']),
          if (r['state'] == 'PENDING')
            const Text('材料已保留，等待另一名有权限人员复核，不承诺完成时限。'),
          AppealMaterialStream(
            controller: controller,
            appealId: route.resourceId,
            initialMaterials: r['materials'] as List,
            nextCursor: r['nextMaterialsCursor'] as String?,
          ),
          if (r['state'] == 'PENDING')
            FilledButton(
              onPressed: () => _form(
                context,
                route.resourceId,
                supplement: true,
                ordinal: r['ordinal'] as int? ?? 1,
              ),
              child: const Text('补充材料'),
            ),
          if (r['state'] == 'REJECTED')
            const Text('本次已结案，不再追加材料。有新材料时，可从原处罚通知在剩余额度内再次申诉。'),
          if (r['state'] == 'ACCEPTED')
            const Text('对应处罚已撤销，符合恢复条件的内容和违规记录已修正。其他有效处罚继续执行。'),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class AppealMaterialStream extends StatefulWidget {
  const AppealMaterialStream({
    super.key,
    required this.controller,
    required this.appealId,
    required this.initialMaterials,
    this.nextCursor,
  });
  final GovernanceController controller;
  final String appealId;
  final List initialMaterials;
  final String? nextCursor;
  @override
  State<AppealMaterialStream> createState() => _AppealMaterialStreamState();
}

class _AppealMaterialStreamState extends State<AppealMaterialStream> {
  late int _authority = widget.controller.authorityVersion;
  late String? _cursor = widget.nextCursor;
  final List<Map<String, dynamic>> _following = [];
  final Set<String> _loaded = {};
  bool _loading = false;
  String? _error;
  int _request = 0;
  bool get _current =>
      widget.controller.available &&
      widget.controller.authorityVersion == _authority;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_current) _request++;
    setState(() {});
  }

  @override
  void dispose() {
    _request++;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(AppealMaterialStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.appealId != widget.appealId ||
        !identical(oldWidget.initialMaterials, widget.initialMaterials)) {
      _request++;
      _authority = widget.controller.authorityVersion;
      _cursor = widget.nextCursor;
      _following.clear();
      _loaded.clear();
      _loading = false;
      _error = null;
    }
  }

  Future<void> _load() async {
    final cursor = _cursor;
    if (!_current || _loading || cursor == null || _loaded.contains(cursor)) {
      return;
    }
    final request = ++_request, appealId = widget.appealId;
    setState(() {
      _loading = true;
      _error = null;
    });
    final page = await widget.controller.readAppealMaterials(appealId, cursor);
    if (!mounted ||
        !_current ||
        request != _request ||
        appealId != widget.appealId) {
      return;
    }
    setState(() {
      _loading = false;
      if (page == null ||
          page.nextCursor != null && _loaded.contains(page.nextCursor)) {
        _error = '后续材料暂时无法读取，已显示的材料仍保留。';
      } else {
        _loaded.add(cursor);
        _following.addAll(page.items);
        _cursor = page.nextCursor;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const Text('会话已变化，请重新进入后查看材料。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final raw in [...widget.initialMaterials, ..._following])
          if (raw is Map) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('提交时间：${raw['createdAt']}'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('已提交材料：${raw['description']}'),
            ),
            if (raw['images'] is List)
              Wrap(
                spacing: 8,
                children: [
                  for (final image in raw['images'] as List)
                    if (image is Map<String, dynamic>)
                      _EvidencePreview(raw: image),
                ],
              ),
          ],
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_cursor != null)
          TextButton(
            onPressed: _loading ? null : _load,
            child: Text(_loading ? '读取后续材料中' : '加载后续材料'),
          ),
      ],
    );
  }
}

class _EvidencePreview extends StatelessWidget {
  const _EvidencePreview({required this.raw});
  final Map<String, dynamic> raw;
  @override
  Widget build(BuildContext context) {
    try {
      final image = EvidenceImage.parse(raw);
      return Image.memory(
        image.bytes,
        width: 96,
        height: 96,
        errorBuilder: (_, _, _) => const Text('图片暂不可预览'),
      );
    } on Object {
      return const Text('图片暂不可预览');
    }
  }
}

class _ResourceScreen extends StatelessWidget {
  const _ResourceScreen({
    required this.controller,
    required this.route,
    required this.resource,
    this.onOpenPost,
  });
  final GovernanceController controller;
  final NotificationRoute route;
  final Map<String, dynamic> resource;
  final Future<void> Function(String)? onOpenPost;
  @override
  Widget build(BuildContext context) {
    final epoch = controller.authorityVersion;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('申诉详情')),
        body: !controller.available || controller.authorityVersion != epoch
            ? const Center(child: Text('会话已变化'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: GovernanceResourceView(
                  controller: controller,
                  route: route,
                  resource: resource,
                  onOpenPost: onOpenPost,
                  onRefresh: () async {
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
      ),
    );
  }
}
