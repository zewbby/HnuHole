import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_session_controller.dart';
import 'identity_api.dart';
import 'identity_management_controller.dart';
import 'identity_name_formatter.dart';

class DefaultIdentityAvatar extends StatelessWidget {
  const DefaultIdentityAvatar({super.key, this.radius = 24});
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
      child: Icon(Icons.person_outline_rounded, size: radius * 1.25),
    ),
  );
}

String identityDate(DateTime date) {
  // Creation calendar boundaries are defined by the server in Asia/Shanghai.
  final local = date.toUtc().add(const Duration(hours: 8));
  return '${local.year}年${local.month}月${local.day}日';
}

class IdentityManagementScreen extends StatefulWidget {
  const IdentityManagementScreen({
    super.key,
    required this.controller,
    required this.sessions,
    this.onAuthenticationRequired,
  });
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final VoidCallback? onAuthenticationRequired;
  @override
  State<IdentityManagementScreen> createState() =>
      _IdentityManagementScreenState();
}

class _IdentityManagementScreenState extends State<IdentityManagementScreen> {
  bool get _busy => widget.controller.busy || widget.sessions.busy;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.sessions.addListener(_changed);
    unawaited(widget.controller.load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    widget.controller.cancelView();
    super.dispose();
  }

  Future<void> _edit([ManagedIdentity? identity]) async {
    if (_busy) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _IdentityEditor(
        controller: widget.controller,
        sessions: widget.sessions,
        identity: identity,
      ),
    );
  }

  Future<void> _delete(ManagedIdentity identity) async {
    final directory = widget.controller.directory;
    if (_busy || directory == null || directory.identities.length < 2) return;
    final authority = widget.sessions.authorityVersion;
    final account = widget.sessions.currentSession?.accountId;
    var dismissed = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AnimatedBuilder(
        animation: widget.sessions,
        builder: (context, child) {
          if (!widget.sessions.isAuthenticated ||
              authority != widget.sessions.authorityVersion ||
              account != widget.sessions.currentSession?.accountId) {
            if (!dismissed) {
              dismissed = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.pop(context, false);
              });
            }
            return const SizedBox.shrink();
          }
          return child!;
        },
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('删除身份', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const DefaultIdentityAvatar(),
                  title: Text(identity.nickname),
                ),
                const SizedBox(height: 16),
                const Text(
                  '旧帖子和评论仍保留，头像与昵称会改为删除占位，无法再用此身份发言。'
                  '曾绑定此身份的帖子中，也不能换其他身份继续发言。',
                ),
                const SizedBox(height: 12),
                const Text(
                  '此身份的聊天框、聊天记录和私人备注将从本机清除；'
                  '对方已有的本地记录保留。此身份的旧帖及发布失败的帖子将从“我的”列表移除。'
                  '新身份不会继承旧内容或聊天。',
                ),
                if (directory.creationCoolingDown) ...[
                  const SizedBox(height: 12),
                  Text(
                    '删除仅释放名额，可于${identityDate(directory.nextCreateAt!)}创建新身份。',
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除身份'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true &&
        mounted &&
        widget.sessions.isAuthenticated &&
        authority == widget.sessions.authorityVersion &&
        account == widget.sessions.currentSession?.accountId) {
      await widget.controller.delete(identity.id);
    }
  }

  Widget _notice(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(liveRegion: true, child: Text(message)),
  );
  Widget _action(
    String label,
    Future<void> Function() action, {
    bool primary = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: primary
        ? FilledButton(
            onPressed: _busy ? null : () => unawaited(action()),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: _busy ? null : () => unawaited(action()),
            child: Text(label),
          ),
  );

  List<Widget> _content() {
    final controller = widget.controller;
    switch (controller.status) {
      case IdentityManagementStatus.ready:
        final directory = controller.directory!;
        return [
          Text('你的发言身份', style: Theme.of(context).textTheme.titleLarge),
          _notice('身份列表仅本人可见。最多保留 3 个身份，创建后至少保留 1 个。'),
          if (directory.identities.isEmpty)
            _notice('还没有发言身份，你仍可浏览社区。创建一个身份后再参与发言。'),
          for (final identity in directory.identities) ...[
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const DefaultIdentityAvatar(),
              title: Text(identity.nickname),
              subtitle: Text(identity.isOriginal ? '原始身份' : '预设身份'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => unawaited(_edit(identity)),
            ),
            if (!directory.canRename(identity))
              Text('可于${identityDate(identity.renameAvailableAt!)}再次改名'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy || directory.identities.length <= 1
                    ? null
                    : () => unawaited(_delete(identity)),
                child: Text(
                  directory.identities.length <= 1 ? '最后一个身份不能删除' : '删除此身份',
                ),
              ),
            ),
          ],
          const Divider(height: 32),
          Text(
            '当前 ${directory.identities.length}/3 个身份，累计创建 ${directory.createdCount} 次',
          ),
          if (directory.creationCoolingDown)
            _notice(
              '可于${identityDate(directory.nextCreateAt!)}创建新身份；删除身份不会缩短等待时间。',
            ),
          if (directory.identities.length == 3) _notice('身份名额已满。'),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
              key: const ValueKey('identity-add'),
              onPressed: _busy || !directory.canCreate
                  ? null
                  : () => unawaited(_edit()),
              child: const Text('添加身份'),
            ),
          ),
          _action('刷新身份列表', controller.load),
        ];
      case IdentityManagementStatus.pending:
      case IdentityManagementStatus.retryRequired:
        return [
          _notice(
            controller.status == IdentityManagementStatus.retryRequired
                ? '尚未查到提交记录。原请求仍可能到达，只能继续核对或重试同一次操作。'
                : '提交结果尚未确认，请先核对原操作。',
          ),
          _action('核对原结果', controller.reconcilePending, primary: true),
          if (controller.status == IdentityManagementStatus.retryRequired)
            _action('重试原操作', controller.retryPending),
        ];
      case IdentityManagementStatus.signedOut:
        return [
          _notice(widget.sessions.errorMessage ?? '请用原账号重新登录后管理身份并核对未完成操作。'),
          if (widget.onAuthenticationRequired != null)
            _action('前往登录', () async => widget.onAuthenticationRequired!()),
        ];
      case IdentityManagementStatus.storageFailure:
      case IdentityManagementStatus.unavailable:
        return [
          _notice('暂时无法核对账号状态，请恢复服务和安全存储后重试。'),
          _action('重新核对', () async {
            await widget.sessions.retry();
            await controller.load();
          }),
        ];
      case IdentityManagementStatus.loading:
        return [_notice('正在核对身份与可操作日期。')];
      case IdentityManagementStatus.idle:
        return [_action('核对身份列表', controller.load, primary: true)];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('身份管理')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (widget.controller.errorMessage != null)
                  _notice(widget.controller.errorMessage!),
                ..._content(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _IdentityEditor extends StatefulWidget {
  const _IdentityEditor({
    required this.controller,
    required this.sessions,
    this.identity,
  });
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final ManagedIdentity? identity;
  @override
  State<_IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends State<_IdentityEditor> {
  late final TextEditingController _name;
  late final IdentityNameFormatter _formatter;
  final _form = GlobalKey<FormState>();
  IdentityNameFeedback _feedback = IdentityNameFeedback.none;
  bool _submitting = false;
  bool _closing = false;
  late final bool _canRename;
  late final bool _initialSetup;
  Future<bool>? _draftWrite;
  int? _authority;
  String? _localError;
  @override
  void initState() {
    super.initState();
    _authority = widget.sessions.authorityVersion;
    _canRename =
        widget.identity == null ||
        widget.controller.directory?.canRename(widget.identity!) == true;
    _initialSetup =
        widget.identity == null &&
        widget.controller.directory?.identities.isEmpty == true;
    _name = TextEditingController(
      text:
          widget.identity?.nickname ??
          (_initialSetup ? widget.controller.initialNickname : ''),
    )..addListener(_draftChanged);
    _formatter = IdentityNameFormatter(
      onFeedback: (feedback) {
        _feedback = feedback;
        _localError = null;
      },
    );
    widget.controller.addListener(_changed);
    widget.sessions.addListener(_changed);
  }

  void _changed() {
    if (!mounted || _closing) return;
    if (!widget.sessions.isAuthenticated ||
        _authority != widget.sessions.authorityVersion) {
      _closing = true;
      _name.clear();
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  void _draftChanged() {
    if (!mounted || _closing) return;
    if (!_submitting &&
        _initialSetup &&
        _name.value.composing.isCollapsed &&
        !widget.controller.hasPending) {
      _draftWrite = widget.controller.saveInitialDraft(_name.text);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    _name.removeListener(_draftChanged);
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting ||
        widget.controller.busy ||
        !_name.value.composing.isCollapsed ||
        _feedback == IdentityNameFeedback.illegalCharacter ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final submitted = _name.text;
    if (submitted == widget.identity?.nickname) {
      setState(() => _localError = '请输入新的昵称');
      return;
    }
    setState(() {
      _submitting = true;
      _localError = null;
    });
    FocusScope.of(context).unfocus();
    if (_initialSetup && _draftWrite != null && !await _draftWrite!) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _localError = '请先确认昵称草稿已保存';
        });
      }
      return;
    }
    if (!mounted ||
        _authority != widget.sessions.authorityVersion ||
        !widget.sessions.isAuthenticated) {
      return;
    }
    if (widget.identity == null) {
      await widget.controller.create(submitted);
    } else {
      await widget.controller.rename(widget.identity!.id, submitted);
    }
    if (!mounted) return;
    _submitting = false;
    if (widget.controller.hasPending ||
        widget.controller.status == IdentityManagementStatus.ready ||
        !widget.sessions.isAuthenticated) {
      Navigator.pop(context);
    } else {
      setState(() => _localError = widget.controller.errorMessage);
    }
  }

  Future<void> _discard() async {
    if (_submitting || widget.controller.busy || widget.sessions.busy) return;
    setState(() => _submitting = true);
    final discarded = await widget.controller.discardInitialDraft();
    if (!mounted) return;
    if (discarded) {
      _closing = true;
      Navigator.pop(context);
    } else {
      setState(() {
        _submitting = false;
        _localError = '尚未确认放弃昵称，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    final canRename = _canRename;
    final busy = _submitting || widget.controller.busy || widget.sessions.busy;
    final feedback = switch (_feedback) {
      IdentityNameFeedback.illegalCharacter => '已移除非法字符；请继续编辑或删除后再保存',
      IdentityNameFeedback.maximumLength => '已达 12 字上限，后续字符未加入',
      IdentityNameFeedback.none => null,
    };
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  identity == null ? '创建发言身份' : '编辑身份',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                const Center(child: DefaultIdentityAvatar(radius: 32)),
                const SizedBox(height: 8),
                const Text('默认头像', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('identity-nickname'),
                  controller: _name,
                  enabled: !busy && canRename,
                  inputFormatters: [_formatter],
                  decoration: InputDecoration(
                    labelText: '昵称',
                    helperText: '2–12 个字，支持中英日韩、数字及标点；不含空格或表情',
                    helperMaxLines: 3,
                    counterText: '${_name.text.characters.length}/12',
                    errorText:
                        _localError ?? (feedback),
                  ),
                  validator: (value) =>
                      IdentityNameFormatter.validate(value ?? ''),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => unawaited(_save()),
                ),
                if (!canRename && identity?.renameAvailableAt != null) ...[
                  const SizedBox(height: 12),
                  Text('可于${identityDate(identity!.renameAvailableAt!)}再次改名'),
                ],
                const SizedBox(height: 12),
                const Text('成功改名后需满 30 天才能再次改名。'),
                if (_initialSetup) ...[
                  const SizedBox(height: 8),
                  const Text('已填昵称会在这台设备保留，使用同一账号可继续设置。'),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('identity-save'),
                  onPressed:
                      busy ||
                          !canRename ||
                          _feedback == IdentityNameFeedback.illegalCharacter ||
                          !_name.value.composing.isCollapsed
                      ? null
                      : () => unawaited(_save()),
                  child: Text(identity == null ? '创建身份' : '保存昵称'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                if (_initialSetup)
                  TextButton(
                    onPressed: busy ? null : () => unawaited(_discard()),
                    child: const Text('放弃已填昵称'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
