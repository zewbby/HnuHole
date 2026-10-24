import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_flows.dart';
import 'auth_presentation.dart';
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
  final _loginEmail = TextEditingController();
  final _loginOtp = TextEditingController();
  final _visiblePasswords = <String>{};
  bool _emailLogin = false;
  bool _registrationFinishing = false;
  String? _copyFeedback;
  double _minimumBodyHeight = 0;
  BuildContext? _presentationContext;
  _AuthMode _mode = _AuthMode.login;
  Timer? _countdown;
  bool _authenticated = false;
  bool _validateOtp = false;
  bool _explicitClosureLogin = false;
  bool _explicitRegistrationLogin = false;
  bool _explicitClosureRecovery = false;
  bool _explicitResetLogin = false;
  String? _lastFlowError;
  String? _lastSessionError;
  bool _errorDialogOpen = false;

  bool get _busy => widget.sessions.busy || widget.flows.busy;

  @override
  void initState() {
    super.initState();
    _authenticated = widget.sessions.status == AuthStatus.authenticated;
    _lastFlowError = widget.flows.errorMessage;
    _lastSessionError = widget.sessions.errorMessage;
    if (widget.flows.emailLogin != null) {
      _emailLogin = true;
      final saved = widget.flows.emailLogin!['email'] as String;
      _loginEmail.text = saved.substring(
        0,
        saved.length - '@hainanu.edu.cn'.length,
      );
    }
    widget.sessions.addListener(_changed);
    widget.flows.addListener(_changed);
    if (widget.sessions.status == AuthStatus.unavailable) {
      _queueErrorDialog('暂时无法进入');
    }
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (widget.flows.otpWaitUntil != null ||
              widget.flows.emailLoginWaitUntil != null)) {
        setState(() {});
      }
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
      _loginEmail,
      _loginOtp,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final flowError = widget.flows.errorMessage;
    final sessionError = widget.sessions.errorMessage;
    if (flowError != null && flowError != _lastFlowError) {
      // Registration already has a dedicated continuation screen for this state.
      if (_mode != _AuthMode.register || flowError != '结果未知，请保留原请求并核对。') {
        _queueErrorDialog(flowError);
      }
    } else if (sessionError != null &&
        sessionError != _lastSessionError &&
        sessionError != '本地已退出，服务器撤销待确认。') {
      _queueErrorDialog(sessionError);
    }
    _lastFlowError = flowError;
    _lastSessionError = sessionError;
    final authenticated = widget.sessions.status == AuthStatus.authenticated;
    final registrationEmail = widget.flows.registrationEmail;
    if (_mode == _AuthMode.register &&
        registrationEmail != null &&
        _email.text.isEmpty) {
      _email.text = registrationEmail.endsWith('@hainanu.edu.cn')
          ? registrationEmail.substring(
              0,
              registrationEmail.length - '@hainanu.edu.cn'.length,
            )
          : registrationEmail;
    }
    if (authenticated && !_authenticated) {
      _visiblePasswords.clear();
      _loginEmail.clear();
      _loginOtp.clear();
      _password.clear();
      _newPassword.clear();
      _recoveryCode.clear();
      _confirmation.clear();
      _otp.clear();
      _email.clear();
      if (!_registrationFinishing &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
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
    _loginEmail.clear();
    _loginOtp.clear();
    _emailLogin = false;
    _visiblePasswords.clear();
    _validateOtp = false;
    _email.clear();
    _otp.clear();
    _registrationFinishing = false;
    _copyFeedback = null;
    setState(() => _mode = mode);
    widget.flows.restorePending();
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await action();
  }

  void _queueErrorDialog(String message) {
    if (_errorDialogOpen) return;
    _errorDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        _errorDialogOpen = false;
        return;
      }
      try {
        await _showErrorDialog(message);
      } finally {
        _errorDialogOpen = false;
      }
    });
  }

  Future<void> _showErrorDialog(String message) {
    if (widget.sessions.status == AuthStatus.unavailable) {
      return showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('暂时无法进入'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('重试'),
            ),
          ],
        ),
      ).then((retry) async {
        if (mounted && retry == true) await widget.sessions.retry();
      });
    }
    final friendlyMessage = switch (message) {
      '结果未知，请保留原请求并核对。' =>
        _emailLogin ? '验证码发送或验证结果暂时无法确认，请检查网络后重试。' : '暂时无法确认操作结果，请检查网络后重试。',
      '安全存储或响应验证失败，操作已停止；请重试核对。' => '暂时无法完成操作，请稍后重试。',
      '请先核对原操作，不能创建新的请求。' => '请先完成当前操作，再重试。',
      _ => message,
    };
    final source = _presentationContext ?? context;
    final themes = InheritedTheme.capture(
      from: source,
      to: Navigator.of(source, rootNavigator: true).context,
    );
    return showGeneralDialog<void>(
      context: source,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(source).modalBarrierDismissLabel,
      transitionDuration: MediaQuery.disableAnimationsOf(source)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      transitionBuilder: (_, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              key: const ValueKey('auth-error-dialog-scale'),
              alignment: Alignment.center,
              scale: animation
                  .drive(CurveTween(curve: Curves.easeOutCubic))
                  .drive(Tween<double>(begin: 0.88, end: 1)),
              child: child,
            ),
          ),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          themes.wrap(
            AlertDialog(
              key: const ValueKey('login-error-dialog'),
              backgroundColor: _theme.colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                _text(
                  message == '用户名或密码不正确。' ? '登录失败' : '提示',
                  message == '用户名或密码不正确。' ? 'Sign-in failed' : 'Notice',
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Text(_text(friendlyMessage)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_text('确定', 'OK')),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      AuthPresentationHost(child: Builder(builder: _buildPage));

  String _text(String value, [String? english]) => AuthPresentationScope.text(
    _presentationContext ?? context,
    value,
    english,
  );

  ThemeData get _theme => Theme.of(_presentationContext ?? context);

  Widget _buildPage(BuildContext context) {
    _presentationContext = context;
    final sessionStatus = widget.sessions.status;
    final flowStatus = widget.flows.status;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title:
            sessionStatus == AuthStatus.authenticated && !_registrationFinishing
            ? Text(_text('账号与安全'))
            : null,
        leading: IconButton(
          tooltip: _text('返回登录'),
          onPressed: _busy
              ? null
              : () {
                  if (_registrationFinishing &&
                      widget.sessions.isAuthenticated) {
                    _finishRegistration();
                  } else if (_mode == _AuthMode.register &&
                      {
                        AuthFlowStatus.registrationCodeShown,
                        AuthFlowStatus.registrationCodeConfirmation,
                      }.contains(widget.flows.status)) {
                    _copyFeedback = null;
                    _confirmation.clear();
                    widget.flows.resetFlow();
                    widget.flows.restorePending();
                  } else if (_mode != _AuthMode.login) {
                    _selectMode(_AuthMode.login);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: const [AuthThemeButton(), SizedBox(width: 12)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _minimumBodyHeight = (constraints.maxHeight - 48).clamp(
              0,
              double.infinity,
            );
            final content = _content(sessionStatus, flowStatus);
            return Align(
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
                        if (_mode == _AuthMode.register) ...[
                          _registrationProgress(flowStatus),
                          const SizedBox(height: 42),
                        ],
                        ...content,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _content(AuthStatus session, AuthFlowStatus flow) {
    if (session == AuthStatus.starting || session == AuthStatus.restoring) {
      return const [_Title('正在加载', '请稍候。')];
    }
    if (session == AuthStatus.storageFailure) {
      return [
        const _Title('暂时无法加载', '请稍后重试。'),
        _button('重试', widget.sessions.retry),
      ];
    }
    if (session == AuthStatus.authenticated) {
      return _registrationFinishing ? _registrationComplete() : _account();
    }
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
      ...switch (_mode) {
        _AuthMode.login => _login(),
        _AuthMode.register => _registration(flow),
        _AuthMode.recover => _recovery(),
      },
      if (_mode == _AuthMode.recover)
        _secondary('返回登录', () async => _selectMode(_AuthMode.login)),
    ];
  }

  int get _emailWaitSeconds =>
      widget.flows.emailLoginWaitUntil
          ?.difference(DateTime.now())
          .inSeconds
          .clamp(0, 3600) ??
      0;

  bool get _emailMatchesRequest =>
      widget.flows.emailLogin?['email'] == _campusEmail(_loginEmail.text);

  List<Widget> _login() {
    final normal =
        !_explicitClosureLogin &&
        !_explicitResetLogin &&
        !_explicitRegistrationLogin;
    final email = normal && _emailLogin;
    final controls = <Widget>[
      const SizedBox(height: 56),
      const _Title('欢迎回来', ''),
      if (_explicitClosureLogin) const _Notice('注销缓冲期内主动登录将撤销注销申请。'),
      if (email) ...[
        _field(
          '邮箱',
          _loginEmail,
          key: 'email-login-address',
          email: true,
          pending: !widget.flows.supportsEmailLogin,
          onChanged: (_) {
            _loginOtp.clear();
            _validateOtp = false;
          },
          placeholder: '输入邮箱',
        ),
        _field(
          '验证码',
          _loginOtp,
          key: 'email-login-code',
          otp: true,
          pending: !widget.flows.supportsEmailLogin,
          placeholder: '输入验证码',
          suffix: SizedBox(
            width: 126,
            child: TextButton(
              key: const ValueKey('email-login-request'),
              onPressed:
                  !widget.flows.supportsEmailLogin ||
                      _busy ||
                      _emailWaitSeconds > 0 ||
                      widget.flows.emailLogin?['proof'] != null ||
                      (_emailMatchesRequest &&
                          widget.flows.emailLogin?['confirmKey'] != null)
                  ? null
                  : () {
                      _validateOtp = false;
                      _submit(
                        () => widget.flows.requestEmailLogin(
                          _campusEmail(_loginEmail.text),
                        ),
                      );
                    },
              child: Text(
                widget.flows.supportsEmailLogin
                    ? _text(
                        _emailWaitSeconds > 0
                            ? '$_emailWaitSeconds 秒后可重新获取'
                            : '发送验证码',
                      )
                    : _text('待接入', 'Coming soon'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
        if (_emailMatchesRequest &&
            widget.flows.emailLogin?['sendState'] == 'ACCEPTED')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _text(
                  '若邮箱存在，将会收到验证码。',
                  'If the email exists, it will receive a verification code.',
                ),
                key: const ValueKey('email-login-sent-notice'),
                style: TextStyle(color: _theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        if (_emailMatchesRequest && widget.flows.emailUnregistered)
          const _Notice('该邮箱尚未注册，请创建账号。'),
        if (!_emailMatchesRequest && widget.flows.emailLogin?['proof'] != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    final saved = widget.flows.emailLogin!['email'] as String;
                    _loginEmail.text = saved.substring(
                      0,
                      saved.length - '@hainanu.edu.cn'.length,
                    );
                    _loginOtp.clear();
                    _validateOtp = false;
                  }),
            child: Text(_text('继续上次登录', 'Continue previous sign-in')),
          ),
      ] else ...[
        _field(
          '用户名',
          _username,
          key: 'login-username',
          username: true,
          placeholder: '输入用户名',
        ),
        _field(
          '密码',
          _password,
          key: 'login-password',
          password: true,
          placeholder: '输入密码',
        ),
      ],
      if (normal)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: TextButton(
                key: const ValueKey('login-method-toggle'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _password.clear();
                        _loginOtp.clear();
                        _visiblePasswords.clear();
                        _emailLogin = !_emailLogin;
                        if (_emailLogin &&
                            _loginEmail.text.isEmpty &&
                            widget.flows.emailLogin != null) {
                          final saved =
                              widget.flows.emailLogin!['email'] as String;
                          _loginEmail.text = saved.substring(
                            0,
                            saved.length - '@hainanu.edu.cn'.length,
                          );
                        }
                      }),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text(
                  _text(
                    email
                        ? '切换用户名登录'
                        : widget.flows.supportsEmailLogin
                        ? '切换邮箱登录'
                        : '切换邮箱登录（待接入）',
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _selectMode(_AuthMode.recover),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(_text('找回账号'), style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: _text(
              email && !widget.flows.supportsEmailLogin ? '邮箱登录待接入' : '登录并进入',
            ),
            child: FilledButton(
              key: const ValueKey('login-submit'),
              onPressed:
                  _busy ||
                      (email &&
                          (!widget.flows.supportsEmailLogin ||
                              !_emailMatchesRequest ||
                              widget.flows.emailLogin?['flowId'] == null ||
                              widget.flows.emailUnregistered))
                  ? null
                  : email
                  ? () async {
                      _validateOtp =
                          widget.flows.emailLogin?['confirmKey'] == null;
                      await _submit(
                        () => widget.flows.completeEmailLogin(_loginOtp.text),
                      );
                    }
                  : () => _submit(
                      () =>
                          widget.sessions.login(_username.text, _password.text),
                    ),
              style: FilledButton.styleFrom(
                fixedSize: const Size(64, 64),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.arrow_forward_rounded, size: 32),
            ),
          ),
        ),
      ),
    ];
    return [
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: normal ? _minimumBodyHeight : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: controls,
            ),
            if (normal)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _text('第一次来？'),
                      style: TextStyle(
                        color: _theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (widget.flows.emailUnregistered) {
                                await widget.flows.clearEmailLogin();
                              }
                              if (mounted) _selectMode(_AuthMode.register);
                            },
                      child: Text(
                        _text('创建账号'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _registrationProgress(AuthFlowStatus flow) {
    final step =
        _registrationFinishing ||
            {
              AuthFlowStatus.registrationCodeShown,
              AuthFlowStatus.registrationCodeConfirmation,
              AuthFlowStatus.registrationUnknown,
              AuthFlowStatus.registrationComplete,
            }.contains(flow)
        ? 3
        : flow == AuthFlowStatus.eligibilityReady
        ? 2
        : 1;
    final labels = [
      _text('邮箱验证', 'Email verification'),
      _text('账号设置', 'Account setup'),
      _text('账号安全', 'Account security'),
    ];
    return Column(
      key: const ValueKey('registration-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: _text('注册进度', 'Registration progress'),
          value: '$step / 3',
          child: LinearProgressIndicator(
            value: step / 3,
            minHeight: 10,
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF0088CC),
            backgroundColor: _theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  '${i + 1} ${labels[i]}',
                  textAlign: i == 0
                      ? TextAlign.start
                      : i == 2
                      ? TextAlign.end
                      : TextAlign.center,
                  style: TextStyle(
                    fontSize: MediaQuery.sizeOf(context).width <= 340 ? 11 : 12,
                    fontWeight: step == i + 1
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: step == i + 1
                        ? _theme.colorScheme.primary
                        : _theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _registrationNext(
    String label,
    Future<void> Function()? action, {
    String key = 'registration-next',
  }) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: _text(label),
        child: FilledButton(
          key: ValueKey(key),
          onPressed: _busy || action == null ? null : action,
          style: FilledButton.styleFrom(
            backgroundColor: _theme.brightness == Brightness.dark
                ? const Color(0xFF32B7F3)
                : const Color(0xFF0088CC),
            foregroundColor: _theme.brightness == Brightness.dark
                ? const Color(0xFF10212C)
                : Colors.white,
            fixedSize: const Size(64, 64),
            padding: EdgeInsets.zero,
            shape: const CircleBorder(),
          ),
          child: const Icon(Icons.arrow_forward_rounded, size: 32),
        ),
      ),
    ),
  );

  List<Widget> _registration(AuthFlowStatus flow) {
    if (flow == AuthFlowStatus.eligibilityReady) {
      return [
        const _Title('设置你的账号', ''),
        const SizedBox(height: 18),
        _field(
          '用户名',
          _username,
          key: 'registration-username',
          username: true,
          newUsername: true,
          placeholder: '输入用户名',
        ),
        _field(
          '密码',
          _password,
          key: 'registration-password',
          password: true,
          newPassword: true,
          placeholder: '输入密码',
        ),
        _registrationNext(
          '生成并保存恢复码',
          () => _submit(() async {
            _copyFeedback = null;
            await widget.flows.createRegistration(
              _username.text,
              _password.text,
            );
          }),
        ),
      ];
    }
    final wait = widget.flows.otpWaitUntil;
    final seconds = wait == null
        ? 0
        : wait.difference(DateTime.now()).inSeconds.clamp(0, 3600);
    final unknown = flow == AuthFlowStatus.otpRequestUnknown;
    final confirming = flow == AuthFlowStatus.otpConfirmationPending;
    final requestLabel = unknown
        ? seconds > 20
              ? '${seconds - 20} 秒后可核对申请'
              : '发送验证码'
        : seconds > 0
        ? '$seconds 秒后可重新获取'
        : '发送验证码';
    Future<void> request() async {
      if (unknown) {
        await widget.flows.requestOtp(widget.flows.registrationEmail!);
        return;
      }
      _validateOtp = false;
      await _submit(() => widget.flows.requestOtp(_campusEmail(_email.text)));
    }

    return [
      const _Title('你的校园邮箱', ''),
      const SizedBox(height: 18),
      _field(
        '校园邮箱',
        _email,
        key: 'registration-email',
        email: true,
        locked:
            confirming ||
            unknown ||
            (flow == AuthFlowStatus.otpRequested && seconds > 0),
      ),
      _field(
        '验证码',
        _otp,
        key: 'registration-otp',
        otp: true,
        placeholder: '输入验证码',
        suffix: SizedBox(
          width: 126,
          child: TextButton(
            key: const ValueKey('registration-request-otp'),
            onPressed:
                _busy || confirming || (unknown ? seconds > 20 : seconds > 0)
                ? null
                : request,
            child: Text(
              _text(requestLabel),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      ),
      _registrationNext(
        confirming ? '核对校邮确认结果' : '确认验证码',
        confirming
            ? widget.flows.reconcileOtpConfirmation
            : flow == AuthFlowStatus.otpRequested &&
                  _campusEmail(_email.text) == widget.flows.registrationEmail
            ? () {
                _validateOtp = true;
                return _submit(() => widget.flows.confirmOtp(_otp.text));
              }
            : null,
      ),
      if (confirming && !widget.flows.canRestartOtpVerification)
        _secondary('使用原验证码继续确认', () {
          _validateOtp = true;
          return _submit(() => widget.flows.confirmOtp(_otp.text));
        }),
      if (widget.flows.canRestartOtpVerification)
        _secondary('结束过期操作，重新收码', widget.flows.abandonExpiredOtpOperation),
    ];
  }

  Widget _passkeySetup({required bool enabled}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 30),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _theme.colorScheme.primaryContainer,
            foregroundColor: _theme.colorScheme.primary,
            child: const Icon(Icons.key_outlined),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _text('通行密钥', 'Passkey'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _text('可选', 'Optional'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _text(
                    '使用指纹或面容，方便以后找回账号。',
                    'Use a fingerprint or face to recover your account later.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: _theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('registration-passkey'),
                    onPressed: enabled && !_busy
                        ? widget.onManageSecurity
                        : null,
                    child: Text(
                      _text(
                        enabled ? '设置通行密钥' : '确认恢复码后设置',
                        enabled
                            ? 'Set up passkey'
                            : 'Confirm recovery code first',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  List<Widget> _registrationSecurity({bool confirm = false}) => [
    const _Title('保护你的账号', ''),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: Text(
            _text(
              confirm ? '确认恢复码' : '保存恢复码',
              confirm ? 'Confirm recovery code' : 'Save recovery code',
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          _text('必需', 'Required'),
          style: TextStyle(
            fontSize: 12,
            color: _theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    if (confirm) ...[
      Text(
        _text(
          '原码已隐藏，请完整输入刚才保存的恢复码。',
          'The code is hidden. Enter the complete code you saved.',
        ),
        style: TextStyle(
          fontSize: 13,
          color: _theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      _field('恢复码', _confirmation, key: 'recovery-confirmation'),
      _button(
        '确认恢复码并创建账号',
        () => _submit(() async {
          _registrationFinishing = true;
          await widget.flows.commitRegistration(_confirmation.text);
          if (mounted && !widget.sessions.isAuthenticated) {
            setState(() => _registrationFinishing = false);
          }
        }),
      ),
    ] else ...[
      _registrationRecoveryBox(),
      const SizedBox(height: 14),
      Semantics(
        liveRegion: true,
        child: Text(
          _copyFeedback ??
              _text(
                '恢复码只展示一次。请记下或存入你信任的密码管理器。',
                'Shown once. Write it down or store it in your password manager.',
              ),
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: _theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      _button('我已保存，继续确认', () async {
        _copyFeedback = null;
        _password.clear();
        _recoveryCode.clear();
        _confirmation.clear();
        widget.flows.hideRecoveryCode();
      }),
    ],
    _passkeySetup(enabled: false),
  ];

  Widget _registrationRecoveryBox() {
    final code = widget.flows.recoveryCode ?? '';
    final midpoint = (code.length / 2).ceil();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _theme.brightness == Brightness.dark
            ? const Color(0xFF20303B)
            : const Color(0xFFEDF7FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 22),
            child: Center(
              child: Semantics(
                label: code,
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${code.substring(0, midpoint)}\n${code.substring(midpoint)}',
                      key: const ValueKey('displayed-recovery-code'),
                      textAlign: TextAlign.center,
                      style: _theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                        height: 1.7,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              key: const ValueKey('copy-registration-recovery-code'),
              tooltip: _text('复制恢复码', 'Copy recovery code'),
              onPressed: _busy || code.isEmpty
                  ? null
                  : () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!mounted ||
                            widget.flows.status !=
                                AuthFlowStatus.registrationCodeShown ||
                            widget.flows.recoveryCode != code) {
                          return;
                        }
                        setState(
                          () => _copyFeedback = _text(
                            '恢复码已复制，请妥善保存。原码只展示一次。',
                            'Recovery code copied. Store it safely. It is shown only once.',
                          ),
                        );
                      } catch (_) {
                        if (!mounted ||
                            widget.flows.status !=
                                AuthFlowStatus.registrationCodeShown ||
                            widget.flows.recoveryCode != code) {
                          return;
                        }
                        setState(
                          () => _copyFeedback = _text(
                            '复制未成功，请手动记下恢复码并妥善保存。',
                            'Copy failed. Write down the code and keep it safe.',
                          ),
                        );
                      }
                    },
              color: _theme.colorScheme.primary,
              icon: Icon(
                _copyFeedback?.startsWith(
                          _text('恢复码已复制', 'Recovery code copied'),
                        ) ==
                        true
                    ? Icons.check_rounded
                    : Icons.copy_outlined,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _registrationComplete() => [
    ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: (_minimumBodyHeight - 100).clamp(0, double.infinity),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Title('保护你的账号', ''),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: _theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _text('恢复码已保存并确认', 'Recovery code saved and confirmed'),
                      style: TextStyle(color: _theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
              _passkeySetup(enabled: true),
            ],
          ),
          _registrationNext(
            '完成注册',
            () async => _finishRegistration(),
            key: 'registration-finish',
          ),
        ],
      ),
    ),
  ];

  void _finishRegistration() {
    if (_busy || !widget.sessions.isAuthenticated) return;
    setState(() {
      _registrationFinishing = false;
      _mode = _AuthMode.login;
    });
    widget.onAuthenticated?.call();
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
    const _AuthText('密码、恢复码和全部备用 Passkey 都丢失后，旧号无法找回。不会按邮箱人工重置。'),
  ];

  List<Widget> _showRecoveryCode({required bool isReset}) => !isReset
      ? _registrationSecurity()
      : [
          _Title(
            isReset ? '保存新的恢复码' : '保存你的恢复码',
            '只在这次画面展示。请写下或存入你选择的安全管理器，下一页隐藏原码后需要完整重输。',
          ),
          if (isReset && widget.flows.resetUsername != null)
            _AuthText('私有用户名：${widget.flows.resetUsername}'),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                widget.flows.recoveryCode ?? '',
                key: const ValueKey('displayed-recovery-code'),
                style: _theme.textTheme.titleLarge?.copyWith(
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Notice(
            '恢复码是单次使用的账号控制凭据，拿到的人可能重设密码。系统截图可能同步到云端；应用不会替你自动保存或复制原码。',
          ),
          if (!isReset)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: _AuthText(
                '密码、恢复码和所有备用 Passkey 均丢失时，旧号不能找回；再次收校邮验证码也不会释放旧号配额。',
              ),
            ),
          _button('我已保存，隐藏原码并确认', () async {
            _recoveryCode.clear();
            _confirmation.clear();
            widget.flows.hideRecoveryCode();
          }),
        ];

  List<Widget> _confirmRecoveryCode({required bool isReset}) => !isReset
      ? _registrationSecurity(confirm: true)
      : [
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
                  ? widget.flows.commitReset(
                      _newPassword.text,
                      _confirmation.text,
                    )
                  : widget.flows.commitRegistration(_confirmation.text),
            ),
          ),
        ];

  List<Widget> _account() => [
    const _Title('账号已登录', '本账号只保持一个有效移动会话。恢复码原文不能再次查看。'),
    if (widget.sessions.username != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _AuthText('私有用户名：${widget.sessions.username}'),
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
          title: const _AuthText('申请七天后注销'),
          content: const _AuthText(
            '预计完成时间由服务端受理时确定。期间登录会撤销申请；尚未公开的发送任务将取消，公开内容仍保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const _AuthText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const _AuthText('申请注销'),
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
      if (dueAt != null) _AuthText('预计完成时间：${_deadline(dueAt)}'),
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
      if (status == AuthFlowStatus.closureCancelled)
        _secondary('结束已取消的注销操作', () async {
          await widget.flows.forgetClosureStatus();
          if (!mounted) return;
          _explicitClosureLogin = false;
          _explicitClosureRecovery = false;
          _selectMode(_AuthMode.login);
          await widget.sessions.retry();
        }),
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
    bool pending = false,
    bool locked = false,
    ValueChanged<String>? onChanged,
    String? placeholder,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      onChanged: email || onChanged != null
          ? (value) {
              onChanged?.call(value);
              setState(() {});
            }
          : null,
      inputFormatters: email ? [_CampusEmailPrefixFormatter()] : null,
      enabled: !_busy && !pending && !locked,
      obscureText: password && !_visiblePasswords.contains(key),
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
        labelText: _text(label),
        hintText: placeholder == null ? null : _text(placeholder),
        suffixText: email ? '@hainanu.edu.cn' : null,
        suffixStyle: const TextStyle(fontSize: 13),
        suffixIcon:
            suffix ??
            (password
                ? IconButton(
                    tooltip: _text(
                      _visiblePasswords.contains(key) ? '隐藏密码' : '显示密码',
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            if (!_visiblePasswords.add(key)) {
                              _visiblePasswords.remove(key);
                            }
                          }),
                    icon: Icon(
                      _visiblePasswords.contains(key)
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  )
                : null),
        helperText: newPassword
            ? _text('至少 10 位，支持字母、数字和英文标点')
            : newUsername
            ? _text('6–24 个小写字母、数字或下划线，以字母开头。')
            : null,
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      validator: (value) {
        final input = value ?? '';
        if (otp && !_validateOtp) return null;
        if (input.isEmpty) return '${_text('请输入', 'Enter ')}${_text(label)}';
        if (email &&
            (RegExp(r'\s').hasMatch(input) ||
                input.startsWith('@') ||
                !_campusEmail(input).endsWith('@hainanu.edu.cn') ||
                _campusEmail(input).indexOf('@') !=
                    _campusEmail(input).lastIndexOf('@'))) {
          return _text('请输入精确的 @hainanu.edu.cn 校园邮箱，不能有空格');
        }
        if (newUsername &&
            !RegExp(r'^[a-z][a-z0-9_]{5,23}$').hasMatch(input.toLowerCase())) {
          return _text('用户名须为 6–24 个字母、数字或下划线，以字母开头');
        }
        if (newPassword && !RegExp(r'^[!-~]{10,128}$').hasMatch(input)) {
          return _text('密码需为 10–128 位字母、数字或英文标点，不能有空格');
        }
        if (otp && !RegExp(r'^\d{6}$').hasMatch(input)) {
          return _text('请输入六位最新验证码');
        }
        return null;
      },
    ),
  );

  Widget _button(String label, Future<void> Function()? action) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: FilledButton(
      onPressed: _busy || action == null ? null : action,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: _mode != _AuthMode.register
            ? null
            : _theme.brightness == Brightness.dark
            ? const Color(0xFF32B7F3)
            : const Color(0xFF0088CC),
        foregroundColor: _mode != _AuthMode.register
            ? null
            : _theme.brightness == Brightness.dark
            ? const Color(0xFF10212C)
            : Colors.white,
        textStyle: _mode == _AuthMode.register
            ? _theme.textTheme.labelLarge?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
              )
            : null,
      ),
      child: Text(_text(label), textAlign: TextAlign.center),
    ),
  );

  Widget _secondary(String label, Future<void> Function() action) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextButton(
      onPressed: _busy ? null : action,
      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
      child: Text(_text(label), textAlign: TextAlign.center),
    ),
  );

  String _campusEmail(String value) =>
      value.contains('@') ? value : '$value@hainanu.edu.cn';
}

/// Only a valid, exact campus suffix is split from a pasted address. Invalid
/// domains, whitespace and case are preserved for the existing validator.
class _CampusEmailPrefixFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    const suffix = '@hainanu.edu.cn';
    final text = newValue.text;
    if (!text.endsWith(suffix) ||
        text.indexOf('@') != text.lastIndexOf('@') ||
        RegExp(r'\s').hasMatch(text)) {
      return newValue;
    }
    final prefix = text.substring(0, text.length - suffix.length);
    return TextEditingValue(
      text: prefix,
      selection: TextSelection.collapsed(offset: prefix.length),
    );
  }
}

class _AuthText extends StatelessWidget {
  const _AuthText(this.value);
  final String value;

  @override
  Widget build(BuildContext context) =>
      Text(AuthPresentationScope.text(context, value));
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AuthPresentationScope.text(context, title),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            AuthPresentationScope.text(context, description),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            AuthPresentationScope.text(context, message),
            style: TextStyle(
              color: colors.onSecondaryContainer,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
