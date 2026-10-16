import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_session_controller.dart';
import 'auth_models.dart';
import 'security_management_controller.dart';

/// No original code, password, or native proof is serialized by this surface.
/// The controller publishes only after durable metadata/result reconciliation.
class SecurityManagementScreen extends StatefulWidget {
  const SecurityManagementScreen({
    super.key,
    required this.controller,
    required this.sessions,
    this.onAuthenticationRequired,
  });

  final SecurityManagementController controller;
  final AuthSessionController sessions;
  final VoidCallback? onAuthenticationRequired;

  @override
  State<SecurityManagementScreen> createState() =>
      _SecurityManagementScreenState();
}

class _SecurityManagementScreenState extends State<SecurityManagementScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  bool get _busy => widget.controller.busy || widget.sessions.busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    widget.sessions.addListener(_changed);
    if (widget.controller.status == SecurityManagementStatus.signedOut) {
      unawaited(widget.controller.load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _password.clear();
      _confirmation.clear();
      // Native providers can legitimately pause the app while presenting a
      // sheet; only a displayed code is hidden on background transition.
      if (widget.controller.status ==
          SecurityManagementStatus.rotationCodeShown) {
        widget.controller.hideRecoveryCode();
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!widget.sessions.isAuthenticated) {
      _password.clear();
      _confirmation.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    widget.controller.cancelEphemeral();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _withPassword(Future<void> Function(String) action) async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final password = _password.text;
    _password.clear();
    await action(password);
  }

  String _time(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _action(
    String text,
    Future<void> Function() action, {
    bool primary = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: primary
        ? FilledButton(
            onPressed: _busy ? null : () => unawaited(action()),
            child: Text(text),
          )
        : OutlinedButton(
            onPressed: _busy ? null : () => unawaited(action()),
            child: Text(text),
          ),
  );

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(liveRegion: true, child: Text(text)),
  );

  List<Widget> _content() {
    final controller = widget.controller;
    switch (controller.status) {
      case SecurityManagementStatus.signedOut:
        return [
          _notice(widget.sessions.errorMessage ?? '请重新登录后管理本账号。'),
          if (widget.onAuthenticationRequired != null)
            _action('前往登录', () async => widget.onAuthenticationRequired!()),
        ];
      case SecurityManagementStatus.storageFailure:
      case SecurityManagementStatus.unavailable:
        return [
          _notice('暂时无法核对账号状态。已停止展示凭据，请恢复服务和安全存储后重试。'),
          _action('重新核对', () async {
            await widget.sessions.retry();
            await controller.load();
          }),
          _action('退出本机', widget.sessions.logout),
        ];
      case SecurityManagementStatus.rotationCodeShown:
        return [
          Text('保存新的恢复码', style: Theme.of(context).textTheme.titleLarge),
          _notice('仅在这次画面展示。请写下或存入你选择的安全管理器。旧码在完整确认成功前仍有效。'),
          Container(
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              controller.recoveryCode ?? '',
              key: const ValueKey('rotation-displayed-code'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(letterSpacing: 1.5),
            ),
          ),
          _notice('拿到恢复码的人可能重设密码。系统截图可能同步到云端；应用不会自动保存或复制原码。'),
          _action('我已保存，隐藏原码并确认', () async {
            _confirmation.clear();
            controller.hideRecoveryCode();
          }, primary: true),
          _action('取消本次轮换', () async => controller.cancelEphemeral()),
        ];
      case SecurityManagementStatus.rotationCodeConfirmation:
        return [
          Text('完整重输已保存的恢复码', style: Theme.of(context).textTheme.titleLarge),
          _notice('原码已经隐藏。确认成功后新码生效，旧码失效。密码、Passkey 和当前会话保留。'),
          TextFormField(
            controller: _confirmation,
            key: const ValueKey('rotation-confirmation'),
            decoration: const InputDecoration(labelText: '新恢复码完整确认'),
            autocorrect: false,
            enableSuggestions: false,
            obscureText: true,
            validator: (v) => v == null || v.isEmpty ? '请完整输入保存的恢复码' : null,
          ),
          _action('确认并激活新恢复码', () async {
            if (!(_form.currentState?.validate() ?? false)) return;
            final confirmation = _confirmation.text;
            _confirmation.clear();
            await controller.confirmRecoveryCodeRotation(confirmation);
          }, primary: true),
          _action('取消本次轮换', () async => controller.cancelEphemeral()),
        ];
      case SecurityManagementStatus.removalConfirmation:
        return [
          _notice('确认移除这个 Passkey？移除后它不能再用于恢复；恢复码和其他 Passkey 保留。'),
          _action('确认移除', controller.confirmPasskeyRemoval, primary: true),
          _action('取消', () async => controller.cancelEphemeral()),
        ];
      case SecurityManagementStatus.pending:
        return [
          _notice('提交结果尚未确定。请核对原操作；应用不会自动重发新码或系统证明。'),
          _action('核对原结果', controller.reconcilePending, primary: true),
          _action('退出本机', widget.sessions.logout),
        ];
      case SecurityManagementStatus.committed:
      case SecurityManagementStatus.notCommitted:
        return [
          _notice(
            controller.status == SecurityManagementStatus.committed
                ? '变更已确认提交。'
                : '本次变更未提交，可重新输入密码开始。',
          ),
          _action('返回当前凭据', controller.acknowledgeResult, primary: true),
        ];
      case SecurityManagementStatus.resultExpired:
      case SecurityManagementStatus.previousSessionPending:
        return [
          _notice('上次操作属于旧会话或已超出核对保留期，当前无法确定提交结果。'),
          _action('核对当前凭据后继续', () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('结束上次结果核对'),
                content: const Text(
                  '上次结果仍无法确定。继续后会重新核对当前凭据，后续变更仍需重新输入密码；不会重发原提交。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('保留核对记录'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('继续'),
                  ),
                ],
              ),
            );
            if (confirmed == true && mounted) await controller.abandonPending();
          }),
        ];
      case SecurityManagementStatus.loading:
        return [_notice('正在核对当前会话与恢复凭据。')];
      case SecurityManagementStatus.ready:
        return _ready();
    }
  }

  List<Widget> _ready() {
    final controller = widget.controller;
    final devices = controller.devices;
    final credentials = controller.credentials;
    return [
      Text('设备与会话', style: Theme.of(context).textTheme.titleLarge),
      if (widget.sessions.username != null)
        _notice('私有用户名：${widget.sessions.username}'),
      if (devices != null) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.phone_android),
          title: const Text('当前设备'),
          subtitle: Text(
            '登录：${_time(devices.currentSignedInAt)}\n'
            '会话截止：${_time(devices.sessionExpiresAt)}',
          ),
        ),
        if (devices.lastReplacedAt != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_outlined),
            title: const Text('最近被接替的设备'),
            subtitle: Text(
              '登录：${_time(devices.lastReplacedSignedInAt!)}\n'
              '接替：${_time(devices.lastReplacedAt!)}',
            ),
          )
        else
          _notice('没有最近接替记录。'),
      ],
      _action('刷新会话与凭据', controller.load),
      _action('退出本机', widget.sessions.logout),
      const Divider(height: 40),
      Text('恢复凭据', style: Theme.of(context).textTheme.titleLarge),
      _notice('恢复码已设置，原码无法再次查看。每次变更都需重新输入密码。'),
      TextFormField(
        controller: _password,
        key: const ValueKey('management-password'),
        decoration: const InputDecoration(labelText: '重新输入当前密码'),
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.password],
        validator: (v) => v == null || v.isEmpty ? '请输入当前密码' : null,
      ),
      _action(
        '轮换恢复码',
        () => _withPassword(controller.beginRecoveryCodeRotation),
      ),
      const SizedBox(height: 24),
      Text('Passkey', style: Theme.of(context).textTheme.titleMedium),
      _notice('Passkey 可选，只用于账号恢复。系统或同步服务商可能知道你保存了本应用的凭据；恢复码仍可独立使用。'),
      _action('绑定新的 Passkey', () => _withPassword(controller.bindPasskey)),
      if (credentials != null && credentials.passkeys.isEmpty)
        _notice('尚未绑定 Passkey。'),
      for (final item in credentials?.passkeys ?? const <PasskeySummary>[]) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_outlined),
          title: Text('创建于 ${_time(item.createdAt)}'),
          subtitle: Text(item.backedUp ? '凭据报告已备份' : '凭据未报告已备份'),
        ),
        _action(
          '移除此 Passkey',
          () => _withPassword(
            (password) =>
                controller.beginPasskeyRemoval(item.credentialId, password),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设备与恢复凭据')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy)
                    Semantics(
                      label: '正在核对安全操作',
                      child: const LinearProgressIndicator(),
                    ),
                  if (widget.controller.errorMessage != null)
                    _notice(widget.controller.errorMessage!),
                  if (widget.sessions.hasPendingLogout)
                    _notice('本机已退出，服务端定向撤销仍待确认。'),
                  ..._content(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
