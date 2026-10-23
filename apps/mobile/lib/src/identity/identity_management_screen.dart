import 'dart:async';
import 'dart:math';

import '../posts/post_photo_picker.dart';
import 'identity_avatar.dart';

import 'package:flutter/material.dart';

import '../auth/auth_session_controller.dart';
import 'identity_api.dart';
import 'identity_management_controller.dart';
import 'identity_name_formatter.dart';

class DefaultIdentityAvatar extends StatelessWidget {
  const DefaultIdentityAvatar({super.key, this.radius = 24});
  final double radius;
  @override
  Widget build(BuildContext context) => IdentityAvatar(radius: radius);
}

String identityDate(DateTime date) {
  // Creation calendar boundaries are defined by the server in Asia/Shanghai.
  final local = date.toUtc().add(const Duration(hours: 8));
  return '${local.year}年${local.month}月${local.day}日';
}

class IdentityPendingPanel extends StatelessWidget {
  const IdentityPendingPanel({
    super.key,
    required this.controller,
    required this.sessions,
    this.requiredInitial = false,
  });
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final bool requiredInitial;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          requiredInitial ? '完成身份设置' : '核对保存结果',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (controller.busy)
          const Center(child: CircularProgressIndicator())
        else ...[
          Text(
            controller.errorMessage ??
                (controller.hasPending ? '保存结果尚未确认，请核对后继续。' : '暂时无法读取身份，请重试。'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(
              controller.hasPending
                  ? controller.reconcilePending()
                  : controller.load(),
            ),
            child: const Text('重新核对'),
          ),
          if (controller.status == IdentityManagementStatus.retryRequired)
            TextButton(
              onPressed: () => unawaited(controller.retryPending()),
              child: const Text('重试原操作'),
            ),
        ],
        TextButton(
          onPressed: sessions.busy ? null : () => unawaited(sessions.logout()),
          child: const Text('退出登录'),
        ),
      ],
    ),
  );
}

class IdentityManagementScreen extends StatefulWidget {
  const IdentityManagementScreen({
    super.key,
    required this.controller,
    required this.sessions,
    this.onAuthenticationRequired,
    this.initialCreate = false,
  });
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final VoidCallback? onAuthenticationRequired;
  final bool initialCreate;
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
    unawaited(_loadInitial());
  }

  Future<void> _loadInitial() async {
    final authority = widget.sessions.authorityVersion;
    await widget.controller.load();
    if (!mounted ||
        !widget.initialCreate ||
        authority != widget.sessions.authorityVersion ||
        !widget.sessions.isAuthenticated ||
        widget.controller.status != IdentityManagementStatus.ready ||
        widget.controller.directory?.canCreate != true) {
      return;
    }
    await _edit();
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
      builder: (context) => IdentityEditor(
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
                  leading: IdentityAvatar(avatar: identity.avatar),
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
              leading: IdentityAvatar(avatar: identity.avatar),
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

class IdentityEditor extends StatefulWidget {
  const IdentityEditor({
    super.key,
    required this.controller,
    required this.sessions,
    this.identity,
    this.requiredInitial = false,
    this.photoPicker,
  });
  final bool requiredInitial;
  final PostPhotoPicker? photoPicker;
  final IdentityManagementController controller;
  final AuthSessionController sessions;
  final ManagedIdentity? identity;
  @override
  State<IdentityEditor> createState() => _IdentityEditorState();
}

class _IdentityEditorState extends State<IdentityEditor> {
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
  late String _avatar;
  bool _picking = false;
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
    _avatar =
        widget.identity?.avatar ??
        (_initialSetup ? widget.controller.initialAvatar : 'default-v1');
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
    if (widget.controller.pendingAvatar?['target'] ==
        (widget.identity?.id ?? 'CREATE')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverAvatar());
      });
    }
  }

  void _changed() {
    if (!mounted || _closing) return;
    if (!widget.sessions.isAuthenticated ||
        _authority != widget.sessions.authorityVersion) {
      _closing = true;
      _name.clear();
      if (!widget.requiredInitial) Navigator.pop(context);
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
      _draftWrite = widget.controller.saveInitialDraft(
        _name.text,
        avatar: _avatar,
      );
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
        widget.controller.pendingAvatar != null &&
            _avatar !=
                'avatar-v1:${widget.controller.pendingAvatar!['assetId']}' ||
        widget.controller.busy ||
        !_name.value.composing.isCollapsed ||
        _feedback == IdentityNameFeedback.illegalCharacter ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final submitted = _name.text;
    if (submitted == widget.identity?.nickname &&
        _avatar == widget.identity?.avatar) {
      setState(() => _localError = '请修改昵称或头像');
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
      await widget.controller.create(submitted, avatar: _avatar);
    } else {
      if (submitted == widget.identity!.nickname) {
        await widget.controller.changeAvatar(widget.identity!.id, _avatar);
      } else {
        await widget.controller.rename(
          widget.identity!.id,
          submitted,
          avatar: _avatar != widget.identity!.avatar ? _avatar : null,
        );
      }
    }
    if (!mounted) return;
    _submitting = false;
    if (widget.controller.hasPending ||
        widget.controller.status == IdentityManagementStatus.ready ||
        !widget.sessions.isAuthenticated) {
      if (!widget.requiredInitial) {
        Navigator.pop(context);
      } else {
        setState(() {});
      }
    } else {
      setState(() => _localError = widget.controller.errorMessage);
    }
  }

  Future<void> _pickAvatar() async {
    if (_picking || _submitting || widget.controller.busy) return;
    setState(() {
      _picking = true;
      _localError = null;
    });
    try {
      final files = await (widget.photoPicker ?? NativePostPhotoPicker()).pick(
        1,
      );
      if (!mounted ||
          _closing ||
          _authority != widget.sessions.authorityVersion ||
          !widget.sessions.isAuthenticated ||
          files.isEmpty) {
        return;
      }
      // New selection owns a new UUID. Unknown uploads are never attached or
      // reused by a replacement account; only confirmed references enter vault.
      final random = Random.secure();
      final raw = List.generate(16, (_) => random.nextInt(256));
      raw[6] = (raw[6] & 15) | 64;
      raw[8] = (raw[8] & 63) | 128;
      final hex = raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final id =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      if (await files.single.length() > 5 * 1024 * 1024) {
        throw const FormatException('avatar too large');
      }
      final selected = await inspectPostPhoto(files.single, id);
      if (!mounted ||
          _closing ||
          _authority != widget.sessions.authorityVersion ||
          !widget.sessions.isAuthenticated) {
        return;
      }
      final avatar = await widget.controller.uploadAvatar(
        id,
        selected.bytes,
        selected.selection.mimeType,
        target: widget.identity?.id ?? 'CREATE',
      );
      if (!mounted ||
          _closing ||
          _authority != widget.sessions.authorityVersion) {
        return;
      }
      if (avatar == null) {
        setState(
          () => _localError =
              widget.controller.errorMessage ?? '头像上传结果尚未确认，请核对原图片或明确放弃后更换。',
        );
        return;
      }
      setState(() => _avatar = avatar);
      _draftChanged();
    } on Object {
      if (mounted && !_closing) {
        setState(() => _localError = '请选择不超过 5 MB 的静态 JPEG、PNG、WebP 或 GIF 图片。');
      }
    } finally {
      if (mounted && !_closing) setState(() => _picking = false);
    }
  }

  Future<void> _recoverAvatar() async {
    if (_picking || _submitting || widget.controller.busy) return;
    setState(() => _picking = true);
    final avatar = await widget.controller.recoverAvatar(
      target: widget.identity?.id ?? 'CREATE',
      retry: true,
    );
    if (mounted && !_closing) {
      setState(() {
        _picking = false;
        if (avatar != null) {
          _avatar = avatar;
          _localError = null;
        } else {
          _localError = '尚未找到原图片。可继续核对，或放弃后重新选择。';
        }
      });
      if (avatar != null) _draftChanged();
    }
  }

  Future<void> _defaultAvatar() async {
    if (!await widget.controller.abandonAvatar() || !mounted || _closing) {
      return;
    }
    setState(() {
      _avatar = 'default-v1';
      _localError = null;
    });
    _draftChanged();
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
    final busy =
        _submitting ||
        _picking ||
        widget.controller.busy ||
        widget.sessions.busy;
    final feedback = switch (_feedback) {
      IdentityNameFeedback.illegalCharacter => '已移除非法字符；请继续编辑或删除后再保存',
      IdentityNameFeedback.maximumLength => '已达 12 字上限，后续字符未加入',
      IdentityNameFeedback.none => null,
    };
    if (widget.controller.hasPending) {
      return IdentityPendingPanel(
        controller: widget.controller,
        sessions: widget.sessions,
        requiredInitial: widget.requiredInitial,
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 +
              (widget.requiredInitial
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom),
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
                  identity == null
                      ? (widget.requiredInitial ? '设置你的初始身份' : '创建发言身份')
                      : '编辑身份',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                Center(child: IdentityAvatar(avatar: _avatar, radius: 36)),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('identity-avatar-pick'),
                  onPressed: busy ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(_picking ? '正在保存头像…' : '从图库选择头像'),
                ),
                if (widget.controller.pendingAvatar != null &&
                    _avatar !=
                        'avatar-v1:${widget.controller.pendingAvatar!['assetId']}')
                  TextButton(
                    onPressed: busy ? null : _recoverAvatar,
                    child: const Text('核对原头像'),
                  ),
                if (_avatar != 'default-v1' ||
                    widget.controller.pendingAvatar != null)
                  TextButton(
                    onPressed: busy ? null : _defaultAvatar,
                    child: const Text('使用默认头像'),
                  ),
                if (_localError != null)
                  Text(
                    _localError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
                    errorText: _localError ?? (feedback),
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
                if (identity != null) const Text('成功改名后需满 30 天才能再次改名。'),
                if (_initialSetup && !widget.requiredInitial) ...[
                  const SizedBox(height: 8),
                  const Text('已填昵称会在这台设备保留，使用同一账号可继续设置。'),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('identity-save'),
                  onPressed:
                      busy ||
                          widget.controller.pendingAvatar != null &&
                              _avatar !=
                                  'avatar-v1:${widget.controller.pendingAvatar!['assetId']}' ||
                          _feedback == IdentityNameFeedback.illegalCharacter ||
                          !_name.value.composing.isCollapsed
                      ? null
                      : () => unawaited(_save()),
                  child: Text(
                    identity == null
                        ? (widget.requiredInitial ? '完成设置' : '创建身份')
                        : '保存资料',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => widget.requiredInitial
                            ? unawaited(widget.sessions.logout())
                            : Navigator.pop(context),
                  child: Text(widget.requiredInitial ? '退出登录' : '取消'),
                ),
                if (_initialSetup && !widget.requiredInitial)
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
