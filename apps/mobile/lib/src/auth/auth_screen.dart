import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_flows.dart';
import 'auth_session_controller.dart';

enum _AuthMode { login, register, recover }

/// Authentication keeps the school-email admission step separate from access
/// to an existing account. Passwords and displayed recovery codes stay in this
/// page's memory only; the controllers own durable, non-replayable workflows.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.sessions,
    required this.flows,
    this.onAuthenticated,
    this.onManageSecurity,
  });

  final AuthSessionController sessions;
  final AuthFlows flows;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onManageSecurity;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _recoveryCode = TextEditingController();
  final _confirmation = TextEditingController();
  final _newPassword = TextEditingController();
  final _closurePassword = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  Timer? _countdown;
  bool _authenticated = false;
  bool _validateOtp = false;
  bool _explicitClosureLogin = false;
  bool _explicitRegistrationLogin = false;
  bool _explicitClosureRecovery = false;
  bool _explicitResetLogin = false;

  bool get _busy => widget.sessions.busy || widget.flows.busy;

  @override
  void initState() {
    super.initState();
    _authenticated = widget.sessions.status == AuthStatus.authenticated;
    widget.sessions.addListener(_changed);
    widget.flows.addListener(_changed);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.flows.otpWaitUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_changed);
    widget.flows.removeListener(_changed);
    widget.flows.cancelPasskeyRecovery();
    widget.flows.hideRecoveryCode();
    _countdown?.cancel();
    for (final controller in [
      _username,
      _password,
      _email,
      _otp,
      _recoveryCode,
      _confirmation,
      _newPassword,
      _closurePassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final authenticated = widget.sessions.status == AuthStatus.authenticated;
    if (authenticated && !_authenticated) {
      _password.clear();
      _newPassword.clear();
      _recoveryCode.clear();
      _confirmation.clear();
      _otp.clear();
      _email.clear();
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        widget.onAuthenticated?.call();
      }
    }
    _authenticated = authenticated;
    setState(() {});
  }

  void _selectMode(_AuthMode mode) {
    FocusScope.of(context).unfocus();
    widget.flows.resetFlow();
    _password.clear();
    _newPassword.clear();
    _recoveryCode.clear();
    _confirmation.clear();
    _closurePassword.clear();
    _validateOtp = false;
    setState(() => _mode = mode);
    widget.flows.restorePending();
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final sessionStatus = widget.sessions.status;
    final flowStatus = widget.flows.status;
    final error = widget.flows.errorMessage ?? widget.sessions.errorMessage;
    final content = _content(sessionStatus, flowStatus);
    return Scaffold(
      appBar: AppBar(title: const Text('账号与安全')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy) ...[
                      Semantics(
                        label: '正在核对账号状态',
                        child: const LinearProgressIndicator(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (error != null) ...[
                      _Notice(error, error: true),
                      const SizedBox(height: 16),
                    ],
                    if (widget.sessions.hasPendingLogout) ...[
                      const _Notice('本机已退出，服务端撤销仍待完成。联网后会继续定向撤销旧会话，不恢复旧登录。'),
                      const SizedBox(height: 16),
                    ],
                    ...content,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(AuthStatus session, AuthFlowStatus flow) {
    if (session == AuthStatus.starting || session == AuthStatus.restoring) {
      return const [_Title('正在核对登录状态', '恢复现有会话，不会主动登录或撤销注销申请。')];
    }
    if (session == AuthStatus.storageFailure) {
      return [
        const _Title('安全存储暂不可用', '恢复安全存储后再继续。账号凭据不会写入普通文件。'),
        _button('重试安全存储', widget.sessions.retry),
      ];
    }
    if (session == AuthStatus.unavailable) {
      return [
        const _Title('暂时无法核对会话', '已保留安全存储中的会话。服务恢复后重试，不需要重新注册。'),
        _button('重新核对会话', widget.sessions.retry),
        _secondary('退出本机', widget.sessions.logout),
      ];
    }
    if (session == AuthStatus.authenticated) return _account();
    if (_isClosureStatus(flow) &&
        !_explicitClosureLogin &&
        !_explicitClosureRecovery) {
      return _closureStatus(flow);
    }
    if (flow == AuthFlowStatus.resetUnknown && !_explicitResetLogin) {
      return [
        const _Title('正在核对密码重设结果', '请求结果尚未确定。请核对原结果，不要重新使用旧恢复码。'),
        const _Notice('若账号在注销缓冲期，主动登录会撤销注销申请；这里的结果核对不会登录。'),
        _button('核对重设结果', widget.flows.reconcileReset),
        if (widget.flows.error?.resultsExpired == true)
          _secondary('主动登录，缓冲期将撤销注销', () async {
            _explicitResetLogin = true;
            _selectMode(_AuthMode.login);
          }),
      ];
    }
    if (flow == AuthFlowStatus.resetCommitted) {
      return [
        const _Title('密码已重设', '新恢复码已生效，全部旧恢复码、Passkey 和会话已失效。'),
        const _Notice('密码重设不会自动登录，也不会撤销注销申请。缓冲期内使用新密码登录会撤销注销。'),
        _button('前往登录', () async {
          await widget.flows.acknowledgeResetResult();
          _explicitClosureRecovery = false;
          _explicitClosureLogin = widget.flows.closureStatus != null;
          _selectMode(_AuthMode.login);
          await widget.sessions.retry();
        }),
      ];
    }
    if (flow == AuthFlowStatus.resetNotCommitted) {
      return [
        const _Title('本次重设未提交', '受限意图已失效，可以重新用有效恢复凭据开始。'),
        _button('重新开始恢复', () async {
          await widget.flows.acknowledgeResetResult();
          _selectMode(_AuthMode.recover);
          await widget.sessions.retry();
        }),
      ];
    }
    if (flow == AuthFlowStatus.registrationCodeShown ||
        flow == AuthFlowStatus.resetCodeShown) {
      return _showRecoveryCode(isReset: flow == AuthFlowStatus.resetCodeShown);
    }
    if (flow == AuthFlowStatus.registrationCodeConfirmation ||
        flow == AuthFlowStatus.resetCodeConfirmation) {
      return _confirmRecoveryCode(
        isReset: flow == AuthFlowStatus.resetCodeConfirmation,
      );
    }
    if (flow == AuthFlowStatus.registrationUnknown &&
        !_explicitRegistrationLogin) {
      return [
        const _Title('开户结果待核对', '开户响应不会重发会话。请明确使用刚设置的用户名和密码登录；未建成账号时登录会失败。'),
        _secondary('前往用户名密码登录', () async {
          _explicitRegistrationLogin = true;
          _selectMode(_AuthMode.login);
        }),
      ];
    }
    if ((session == AuthStatus.resetPending && !_explicitResetLogin) ||
        (session == AuthStatus.closurePending &&
            !_explicitClosureLogin &&
            !_explicitClosureRecovery)) {
      return [
        const _Title('有待核对的账号操作', '先核对已保存的原请求结果，再继续账号操作。'),
        _button('核对原结果', widget.flows.restorePending),
      ];
    }
    if (_explicitRegistrationLogin || _explicitResetLogin) return _login();
    if (_explicitClosureRecovery) {
      return [
        ..._recovery(),
        _secondary('返回注销状态，不重设', () async {
          setState(() => _explicitClosureRecovery = false);
          await widget.flows.restorePending();
        }),
      ];
    }
    if (_explicitClosureLogin) {
      return [
        ..._login(),
        _secondary('返回注销状态，不登录', () async {
          setState(() => _explicitClosureLogin = false);
          await widget.flows.restorePending();
        }),
      ];
    }
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _modeButton('登录', _AuthMode.login),
          _modeButton('新注册', _AuthMode.register),
          _modeButton('恢复账号', _AuthMode.recover),
        ],
      ),
      const SizedBox(height: 24),
      ...switch (_mode) {
        _AuthMode.login => _login(),
        _AuthMode.register => _registration(flow),
        _AuthMode.recover => _recovery(),
      },
    ];
  }

  Widget _modeButton(String label, _AuthMode mode) => Semantics(
    selected: _mode == mode,
    child: OutlinedButton(
      onPressed: _busy ? null : () => _selectMode(mode),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(72, 48),
        backgroundColor: _mode == mode
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        foregroundColor: _mode == mode
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: _mode == mode ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ),
  );

  List<Widget> _login() => [
    const _Title('登录树洞', '使用私有用户名与密码。登录成功会接替其他移动设备；注销缓冲期内登录会撤销注销申请。'),
    _field('私有用户名', _username, key: 'login-username', username: true),
    _field('密码', _password, key: 'login-password', password: true),
    _button(
      '登录并进入',
      () =>
          _submit(() => widget.sessions.login(_username.text, _password.text)),
    ),
  ];

  List<Widget> _registration(AuthFlowStatus flow) {
    if (flow == AuthFlowStatus.eligibilityReady) {
      return [
        const _Title('设置新账号', '校邮只给新账号准入。私有用户名不是公开昵称，请使用独立密码。'),
        _field(
          '新账号用户名',
          _username,
          key: 'registration-username',
          username: true,
          newUsername: true,
        ),
        _field(
          '新账号密码',
          _password,
          key: 'registration-password',
          password: true,
          newPassword: true,
        ),
        const _Notice(
          '密码、恢复码和全部备用 Passkey 都丢失后，旧号不能找回，也不能仅凭重新收码用同一精确邮箱创建第二个账号。',
        ),
        _button(
          '生成并保存恢复码',
          () => _submit(
            () =>
                widget.flows.createRegistration(_username.text, _password.text),
          ),
        ),
      ];
    }
    final wait = widget.flows.otpWaitUntil;
    final seconds = wait == null
        ? 0
        : wait.difference(DateTime.now()).inSeconds.clamp(0, 3600);
    return [
      const _Title('校邮注册', '校园邮箱只用于新注册，不能登录或找回旧账号。邮箱只交给独立校邮验证方。'),
      _field('校园邮箱', _email, key: 'registration-email', email: true),
      _field('最新验证码', _otp, key: 'registration-otp', otp: true),
      const Text('请使用最新验证码。', style: TextStyle(fontSize: 14)),
      const SizedBox(height: 8),
      if (flow == AuthFlowStatus.otpRequestUnknown)
        _button(
          seconds > 20 ? '${seconds - 20} 秒后可核对申请' : '核对验证码申请',
          seconds > 20 ? null : widget.flows.reconcileOtpRequest,
        )
      else if (flow != AuthFlowStatus.otpConfirmationPending)
        _button(
          seconds > 0 ? '$seconds 秒后可重新获取' : '获取验证码',
          seconds > 0
              ? null
              : () {
                  _validateOtp = false;
                  return _submit(() => widget.flows.requestOtp(_email.text));
                },
        ),
      if (flow == AuthFlowStatus.otpRequested)
        _button('确认验证码', () {
          _validateOtp = true;
          return _submit(() => widget.flows.confirmOtp(_otp.text));
        }),
      if (flow == AuthFlowStatus.otpConfirmationPending) ...[
        _button('核对校邮确认结果', widget.flows.reconcileOtpConfirmation),
        _secondary('使用原验证码继续确认', () {
          _validateOtp = true;
          return _submit(() => widget.flows.confirmOtp(_otp.text));
        }),
      ],
      if (widget.flows.error?.resultsExpired == true)
        _secondary('结束过期操作，重新收码', widget.flows.abandonExpiredOtpOperation),
      const _Notice('如果可以发送，验证码将到达邮箱。投递结果未知时先核对原申请。'),
    ];
  }

  List<Widget> _recovery() => [
    const _Title('用恢复码找回旧号', '忘记用户名也可以恢复。校邮验证码不能找回已有账号。'),
    _field('已保存的恢复码', _recoveryCode, key: 'recovery-code'),
    _button(
      '验证恢复码',
      () => _submit(() => widget.flows.beginCodeReset(_recoveryCode.text)),
    ),
    if (widget.flows.supportsPasskeyRecovery)
      _secondary('使用 Passkey 恢复', widget.flows.beginPasskeyReset),
    const _Notice('Passkey 只用于找回旧号。验证后仍需设置新密码、保存并完整确认新恢复码，不会自动登录。'),
    const SizedBox(height: 16),
    const Text('密码、恢复码和全部备用 Passkey 都丢失后，旧号无法找回。不会按邮箱人工重置。'),
  ];

  List<Widget> _showRecoveryCode({required bool isReset}) => [
    _Title(
      isReset ? '保存新的恢复码' : '保存你的恢复码',
      '只在这次画面展示。请写下或存入你选择的安全管理器，下一页隐藏原码后需要完整重输。',
    ),
    if (isReset && widget.flows.resetUsername != null)
      Text('私有用户名：${widget.flows.resetUsername}'),
    const SizedBox(height: 16),
    DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          widget.flows.recoveryCode ?? '',
          key: const ValueKey('displayed-recovery-code'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(letterSpacing: 1.5),
          textAlign: TextAlign.center,
        ),
      ),
    ),
    const SizedBox(height: 16),
    const _Notice('恢复码是单次使用的账号控制凭据，拿到的人可能重设密码。系统截图可能同步到云端；应用不会替你自动保存或复制原码。'),
    if (!isReset)
      const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Text('密码、恢复码和所有备用 Passkey 均丢失时，旧号不能找回；再次收校邮验证码也不会释放旧号配额。'),
      ),
    _button('我已保存，隐藏原码并确认', () async {
      _recoveryCode.clear();
      _confirmation.clear();
      widget.flows.hideRecoveryCode();
    }),
  ];

  List<Widget> _confirmRecoveryCode({required bool isReset}) => [
    const _Title('完整重输已保存的恢复码', '原码已经隐藏。服务端会核对完整确认值。'),
    if (isReset)
      _field(
        '新密码',
        _newPassword,
        key: 'reset-new-password',
        password: true,
        newPassword: true,
      ),
    _field('恢复码确认', _confirmation, key: 'recovery-confirmation'),
    if (isReset) const _Notice('重设将废止全部旧恢复凭据与会话，不会自动登录或撤销注销申请。'),
    _button(
      isReset ? '设置新密码并激活新恢复码' : '确认恢复码并创建账号',
      () => _submit(
        () => isReset
            ? widget.flows.commitReset(_newPassword.text, _confirmation.text)
            : widget.flows.commitRegistration(_confirmation.text),
      ),
    ),
  ];

  List<Widget> _account() => [
    const _Title('账号已登录', '本账号只保持一个有效移动会话。恢复码原文不能再次查看。'),
    if (widget.sessions.username != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text('私有用户名：${widget.sessions.username}'),
      ),
    if (widget.flows.closureStatus != null) ...[
      _secondary('核对上次注销申请', widget.flows.reconcileClosure),
      if (widget.flows.status == AuthFlowStatus.closureCancelled)
        _secondary('已确认取消，清除上次状态', widget.flows.forgetClosureStatus),
      const SizedBox(height: 16),
    ],
    if (widget.onManageSecurity != null)
      _secondary('设备与恢复凭据', () async => widget.onManageSecurity!()),
    _button('退出本机', widget.sessions.logout),
    const Divider(height: 40),
    const _Title('申请注销账号', '七天缓冲期内主动登录会撤销申请。申请后退出全部设备，尚未公开的发送任务将取消，已公开内容仍保留。'),
    _field('重新输入密码', _closurePassword, key: 'closure-password', password: true),
    _secondary('查看并确认注销申请', () async {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('申请七天后注销'),
          content: const Text(
            '预计完成时间由服务端受理时确定。期间登录会撤销申请；尚未公开的发送任务将取消，公开内容仍保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('申请注销'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await widget.flows.requestClosure(_closurePassword.text);
        _closurePassword.clear();
      }
    }),
  ];

  bool _isClosureStatus(AuthFlowStatus status) => {
    AuthFlowStatus.closureUnknown,
    AuthFlowStatus.closurePending,
    AuthFlowStatus.closureCancelled,
    AuthFlowStatus.closureFinalizing,
    AuthFlowStatus.closureClosedReleasePending,
    AuthFlowStatus.closureReleased,
  }.contains(status);

  List<Widget> _closureStatus(AuthFlowStatus status) {
    final (title, message) = switch (status) {
      AuthFlowStatus.closurePending => (
        '注销缓冲期',
        '申请已受理，七天内主动登录会撤销申请。查看本页不会恢复登录。',
      ),
      AuthFlowStatus.closureCancelled => ('注销申请已取消', '可以主动登录继续使用。'),
      AuthFlowStatus.closureFinalizing => ('正式关闭处理中', '已经到达注销截止，不能再登录或恢复旧号。'),
      AuthFlowStatus.closureClosedReleasePending => (
        '账号已关闭，资格释放处理中',
        '等待验证方持久确认释放后，再用同一精确邮箱注册新号。',
      ),
      AuthFlowStatus.closureReleased => (
        '账号已关闭，资格已释放',
        '可以重新校邮注册全新账号。新号不会继承旧身份或内容。',
      ),
      _ => ('注销申请结果待核对', '尚不能确定请求结果。未查到状态也不能证明原申请未提交；请继续核对。'),
    };
    final dueAt = widget.flows.closureStatus?.dueAt;
    return [
      _Title(title, message),
      if (dueAt != null) Text('预计完成时间：${_deadline(dueAt)}'),
      _button('核对注销状态', widget.flows.reconcileClosure),
      if (status == AuthFlowStatus.closureUnknown) ...[
        const SizedBox(height: 16),
        _field(
          '原申请密码',
          _closurePassword,
          key: 'closure-retry-password',
          password: true,
        ),
        _secondary(
          '以原申请重新确认',
          () => _submit(() => widget.flows.retryClosure(_closurePassword.text)),
        ),
      ],
      if (status == AuthFlowStatus.closurePending ||
          status == AuthFlowStatus.closureCancelled)
        _secondary(
          status == AuthFlowStatus.closurePending ? '登录并撤销注销' : '前往登录',
          () async {
            _explicitClosureLogin = true;
            _selectMode(_AuthMode.login);
          },
        ),
      if (status == AuthFlowStatus.closurePending)
        _secondary('重设密码，继续保留注销', () async {
          _explicitClosureRecovery = true;
          _selectMode(_AuthMode.recover);
        }),
      if (status == AuthFlowStatus.closureReleased)
        _secondary('创建全新账号', () async {
          await widget.flows.forgetClosureStatus();
          _selectMode(_AuthMode.register);
          await widget.sessions.retry();
        }),
    ];
  }

  String _deadline(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required String key,
    bool password = false,
    bool username = false,
    bool newUsername = false,
    bool newPassword = false,
    bool email = false,
    bool otp = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      obscureText: password,
      autocorrect: false,
      enableSuggestions: !password && !otp,
      enableIMEPersonalizedLearning:
          !password && !otp && !key.contains('recovery'),
      keyboardType: email
          ? TextInputType.emailAddress
          : otp
          ? TextInputType.number
          : TextInputType.text,
      textInputAction: TextInputAction.next,
      autofillHints: password
          ? [newPassword ? AutofillHints.newPassword : AutofillHints.password]
          : username
          ? [newUsername ? AutofillHints.newUsername : AutofillHints.username]
          : email
          ? [AutofillHints.email]
          : otp
          ? [AutofillHints.oneTimeCode]
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: newPassword
            ? '至少 15 个字符，支持空格和粘贴；不要使用校邮密码。'
            : newUsername
            ? '6–24 个小写字母、数字或下划线，以字母开头。'
            : null,
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      validator: (value) {
        final input = value ?? '';
        if (otp && !_validateOtp) return null;
        if (input.isEmpty) return '请输入$label';
        if (email &&
            (RegExp(r'\s').hasMatch(input) ||
                input.startsWith('@') ||
                !input.endsWith('@hainanu.edu.cn') ||
                input.indexOf('@') != input.lastIndexOf('@'))) {
          return '请输入精确的 @hainanu.edu.cn 校园邮箱，不能有空格';
        }
        if (newUsername &&
            !RegExp(r'^[a-z][a-z0-9_]{5,23}$').hasMatch(input.toLowerCase())) {
          return '用户名须为 6–24 个字母、数字或下划线，以字母开头';
        }
        if (newPassword && input.runes.length < 15) return '新密码至少需要 15 个字符';
        if (otp && !RegExp(r'^\d{6}$').hasMatch(input)) return '请输入六位最新验证码';
        return null;
      },
    ),
  );

  Widget _button(String label, Future<void> Function()? action) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: FilledButton(
      onPressed: _busy || action == null ? null : action,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );

  Widget _secondary(String label, Future<void> Function() action) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton(
      onPressed: _busy ? null : action,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(description, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: error,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: TextStyle(
              color: error
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
