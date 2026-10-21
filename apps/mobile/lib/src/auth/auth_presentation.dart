import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth_store.dart';

const authBrandColor = Color(0xFF00A7E9);

/// Appearance is separate from credential records and never stores form input.
class AuthPresentationController extends ChangeNotifier {
  AuthPresentationController({this.preferences});

  final AuthVault? preferences;
  ThemeMode themeMode = ThemeMode.system;
  bool english = false;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final value = await preferences?.read();
      if (value == null || _disposed || revision != _revision) return;
      final record = jsonDecode(value);
      if (record is! Map || record['version'] != 1) return;
      final theme = record['theme'];
      final language = record['language'];
      if (!['system', 'light', 'dark'].contains(theme) ||
          !['zh', 'en'].contains(language)) {
        return;
      }
      themeMode = ThemeMode.values.byName(theme as String);
      english = language == 'en';
      notifyListeners();
    } catch (_) {
      // Optional non-secret preferences must never block authentication.
    }
  }

  void toggleTheme(Brightness brightness) {
    themeMode = brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    _changed();
  }

  void toggleLanguage() {
    english = !english;
    _changed();
  }

  void _changed() {
    _revision++;
    notifyListeners();
    final value = jsonEncode({
      'version': 1,
      'theme': themeMode.name,
      'language': english ? 'en' : 'zh',
    });
    _writes = _writes.then((_) async {
      try {
        await preferences?.write(value);
      } catch (_) {
        // Appearance remains usable when preference persistence is unavailable.
      }
    });
  }

  String text(String chinese, [String? englishText]) {
    if (!english) return chinese;
    final translated = englishText ?? authEnglish[chinese];
    if (translated != null) return translated;
    final wait = RegExp(r'^(\d+) 秒后可(重新获取|核对申请)$').firstMatch(chinese);
    if (wait != null) {
      return wait.group(2) == '重新获取'
          ? 'Try again in ${wait.group(1)} seconds'
          : 'Check in ${wait.group(1)} seconds';
    }
    if (chinese.startsWith('私有用户名：')) {
      return 'Username: ${chinese.substring(6)}';
    }
    if (chinese.startsWith('预计完成时间：')) {
      return 'Expected completion: ${chinese.substring(7)}';
    }
    return chinese;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AuthPresentationScope
    extends InheritedNotifier<AuthPresentationController> {
  const AuthPresentationScope({
    super.key,
    required AuthPresentationController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthPresentationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AuthPresentationScope>()
      ?.notifier;

  static String text(BuildContext context, String chinese, [String? english]) =>
      maybeOf(context)?.text(chinese, english) ?? chinese;
}

ThemeData authPresentationTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final foreground = dark ? const Color(0xFFF2F4F7) : const Color(0xFF24272B);
  final background = dark ? const Color(0xFF14171B) : Colors.white;
  final colors = base.colorScheme.copyWith(
    primary: dark ? authBrandColor : const Color(0xFF0076A3),
    onPrimary: dark ? background : Colors.white,
    surface: background,
    onSurface: foreground,
    outline: dark ? const Color(0xFF434B56) : const Color(0xFFD9DDE2),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: authBrandColor, width: 2),
      ),
    ),
  );
}

/// Also supports isolated auth routes and widget harnesses without the app root.
class AuthPresentationHost extends StatefulWidget {
  const AuthPresentationHost({super.key, required this.child});
  final Widget child;

  @override
  State<AuthPresentationHost> createState() => _AuthPresentationHostState();
}

class _AuthPresentationHostState extends State<AuthPresentationHost> {
  final _fallback = AuthPresentationController();

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AuthPresentationScope.maybeOf(context) ?? _fallback;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final base = Theme.of(context);
        final dark = controller.themeMode == ThemeMode.system
            ? base.brightness == Brightness.dark
            : controller.themeMode == ThemeMode.dark;
        final themed =
            base.brightness == (dark ? Brightness.dark : Brightness.light)
            ? base
            // The host can update before the root theme animation finishes.
            // Keep component text styles and font fallback consistent while
            // changing brightness; a bare ThemeData breaks TextStyle.lerp.
            : base.copyWith(
                brightness: dark ? Brightness.dark : Brightness.light,
              );
        return AuthPresentationScope(
          controller: controller,
          child: Semantics(
            localeForSubtree: controller.english
                ? const Locale('en', 'US')
                : const Locale('zh', 'CN'),
            child: Theme(
              data: authPresentationTheme(themed),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class AuthThemeButton extends StatelessWidget {
  const AuthThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final controller = AuthPresentationScope.maybeOf(context)!;
    return IconButton(
      key: const ValueKey('auth-theme-toggle'),
      tooltip: controller.text(dark ? '切换浅色主题' : '切换深色主题'),
      onPressed: () => controller.toggleTheme(Theme.of(context).brightness),
      icon: Icon(
        dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
        color: authBrandColor,
        size: 26,
      ),
    );
  }
}

class AuthWelcomeScreen extends StatelessWidget {
  const AuthWelcomeScreen({super.key, required this.onStarted});
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context) => AuthPresentationHost(
    child: Builder(
      builder: (context) {
        final controller = AuthPresentationScope.maybeOf(context)!;
        return Scaffold(
          key: const ValueKey('auth-welcome'),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                        child: Column(
                          children: [
                            const Align(
                              alignment: Alignment.centerRight,
                              child: AuthThemeButton(),
                            ),
                            Expanded(
                              child: Align(
                                alignment: const Alignment(0, -0.45),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 48,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        label: 'HnuHole',
                                        image: true,
                                        child: ExcludeSemantics(
                                          child: Container(
                                            width: 150,
                                            height: 150,
                                            alignment: Alignment.center,
                                            decoration: const BoxDecoration(
                                              color: authBrandColor,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Text(
                                              'h',
                                              style: TextStyle(
                                                fontSize: 112,
                                                height: 1,
                                                fontFamily: 'serif',
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      const Text(
                                        'HnuHole',
                                        style: TextStyle(
                                          fontSize: 31,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        controller.text(
                                          '你的校园，你的树洞。\n在这里，说说心里话。',
                                          'Your campus, your stories.\nA space to speak your mind.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('auth-language-toggle'),
                              onPressed: controller.toggleLanguage,
                              child: Text(
                                controller.english
                                    ? '切换为简体中文'
                                    : 'Continue in English',
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton(
                                key: const ValueKey('auth-start'),
                                onPressed: onStarted,
                                style: FilledButton.styleFrom(
                                  shape: const StadiumBorder(),
                                ),
                                child: Text(
                                  controller.text('开始使用', 'Get started'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

const authEnglish = <String, String>{
  '正在核对账号状态': 'Checking account status',
  '新密码': 'New password',
  '设置新密码并激活新恢复码': 'Set new password and activate recovery code',
  '确认恢复码并创建账号': 'Confirm recovery code and create account',
  '本机已退出，服务端撤销仍待完成。联网后会继续定向撤销旧会话，不恢复旧登录。': 'Signed out locally. Server revocation will resume when online without restoring the old session.',
  '正在核对登录状态': 'Checking your session',
  '恢复现有会话，不会主动登录或撤销注销申请。': 'Restoring an existing session will not sign you in again or cancel an account closure request.',
  '安全存储暂不可用': 'Secure storage unavailable',
  '恢复安全存储后再继续。账号凭据不会写入普通文件。': 'Restore secure storage to continue. Credentials are never saved to ordinary files.',
  '重试安全存储': 'Retry secure storage',
  '暂时无法核对会话': 'Unable to check your session',
  '已保留安全存储中的会话。服务恢复后重试，不需要重新注册。': 'Your session remains in secure storage. Retry when the service is available; no new account is needed.',
  '重新核对会话': 'Check session again',
  '退出本机': 'Sign out on this device',
  '正在核对密码重设结果': 'Checking password reset',
  '请求结果尚未确定。请核对原结果，不要重新使用旧恢复码。': 'The outcome is unknown. Check the original request instead of reusing the old recovery code.',
  '若账号在注销缓冲期，主动登录会撤销注销申请；这里的结果核对不会登录。': 'Signing in during the closure grace period cancels closure. Checking this result does not sign you in.',
  '核对重设结果': 'Check reset result',
  '主动登录，缓冲期将撤销注销': 'Sign in and cancel pending closure',
  '密码已重设': 'Password reset',
  '新恢复码已生效，全部旧恢复码、Passkey 和会话已失效。': 'Your new recovery code is active. All old recovery codes, passkeys and sessions are invalid.',
  '密码重设不会自动登录，也不会撤销注销申请。缓冲期内使用新密码登录会撤销注销。': 'Resetting a password does not sign you in or cancel closure. Signing in during the grace period cancels closure.',
  '前往登录': 'Go to sign in',
  '本次重设未提交': 'Reset was not committed',
  '受限意图已失效，可以重新用有效恢复凭据开始。': 'The reset intent has expired. Start again with a valid recovery credential.',
  '重新开始恢复': 'Restart recovery',
  '开户结果待核对': 'Account creation needs checking',
  '开户响应不会重发会话。请明确使用刚设置的用户名和密码登录；未建成账号时登录会失败。': 'Use the username and password you just set to sign in explicitly. Sign-in will fail if account creation did not complete.',
  '前往用户名密码登录': 'Sign in with username and password',
  '有待核对的账号操作': 'Pending account operation',
  '先核对已保存的原请求结果，再继续账号操作。':
      'Check the saved original request before continuing.',
  '核对原结果': 'Check original result',
  '返回注销状态，不重设': 'Back to closure status without resetting',
  '返回注销状态，不登录': 'Back to closure status without signing in',
  '注销缓冲期内主动登录将撤销注销申请。':
      'Signing in during the grace period cancels the closure request.',
  '设置新账号': 'Set up your account',
  '校邮只给新账号准入。私有用户名不是公开昵称，请使用独立密码。': 'Campus email verifies eligibility for a new account. Your username is private. Choose a separate password.',
  '新账号用户名': 'New username',
  '新账号密码': 'New password',
  '密码、恢复码和全部备用 Passkey 都丢失后，旧号不能找回，也不能仅凭重新收码用同一精确邮箱创建第二个账号。': 'If your password and all recovery credentials are lost, the old account cannot be recovered. Another email code cannot create a second account for the same exact address.',
  '生成并保存恢复码': 'Generate and save recovery code',
  '校邮注册': 'Verify campus email',
  '校园邮箱只用于新注册，不能登录或找回旧账号。邮箱只交给独立校邮验证方。': 'Campus email is used for new registration. It cannot sign in to or recover an existing account. Only the independent verifier receives your email.',
  '校园邮箱': 'Campus email',
  '最新验证码': 'Latest verification code',
  '请使用最新验证码。': 'Use the latest verification code.',
  '核对验证码申请': 'Check code request',
  '确认验证码': 'Verify code',
  '核对校邮确认结果': 'Check email verification',
  '使用原验证码继续确认': 'Continue with the original code',
  '结束过期操作，重新收码': 'End expired operation and request a new code',
  '如果可以发送，验证码将到达邮箱。投递结果未知时先核对原申请。': 'If delivery is possible, a code will arrive in your inbox. Check the original request when delivery is uncertain.',
  '用恢复码找回旧号': 'Recover with your recovery code',
  '忘记用户名也可以恢复。校邮验证码不能找回已有账号。': 'You can recover even if you forgot your username. Campus email cannot recover an existing account.',
  '已保存的恢复码': 'Saved recovery code',
  '验证恢复码': 'Verify recovery code',
  '使用 Passkey 恢复': 'Recover with a passkey',
  'Passkey 只用于找回旧号。验证后仍需设置新密码、保存并完整确认新恢复码，不会自动登录。': 'Passkeys are for recovery only. Set a new password and save and confirm the new recovery code. Recovery does not sign you in automatically.',
  '密码、恢复码和全部备用 Passkey 都丢失后，旧号无法找回。不会按邮箱人工重置。': 'If your password and all recovery credentials are lost, your account cannot be recovered. Email cannot be used for a manual reset.',
  '保存新的恢复码': 'Save your new recovery code',
  '保存你的恢复码': 'Save your recovery code',
  '只在这次画面展示。请写下或存入你选择的安全管理器，下一页隐藏原码后需要完整重输。': 'This code is shown once. Store it safely. On the next screen, re-enter it in full after it is hidden.',
  '恢复码是单次使用的账号控制凭据，拿到的人可能重设密码。系统截图可能同步到云端；应用不会替你自动保存或复制原码。': 'A recovery code can reset your password. Screenshots may sync to the cloud. The app does not automatically save or copy this code.',
  '密码、恢复码和所有备用 Passkey 均丢失时，旧号不能找回；再次收校邮验证码也不会释放旧号配额。': 'Losing your password and all recovery credentials makes recovery impossible. Another email code does not release the old account allocation.',
  '我已保存，隐藏原码并确认': 'I saved it; hide and confirm the code',
  '完整重输已保存的恢复码': 'Re-enter the full recovery code',
  '原码已经隐藏。服务端会核对完整确认值。': 'The original code is hidden. The server will verify the full confirmation.',
  '新的独立密码': 'New independent password',
  '恢复码确认': 'Confirm recovery code',
  '重设将废止全部旧恢复凭据与会话，不会自动登录或撤销注销申请。': 'Resetting invalidates all old recovery credentials and sessions. It does not sign you in or cancel closure.',
  '确认并提交密码重设': 'Confirm password reset',
  '确认并创建账号': 'Confirm and create account',
  '账号已登录': 'Account signed in',
  '本账号只保持一个有效移动会话。恢复码原文不能再次查看。': 'One mobile session is active at a time. The recovery code cannot be shown again.',
  '核对上次注销申请': 'Check previous closure request',
  '已确认取消，清除上次状态': 'Clear confirmed cancelled request',
  '设备与恢复凭据': 'Devices and recovery credentials',
  '申请注销账号': 'Close account',
  '七天缓冲期内主动登录会撤销申请。申请后退出全部设备，尚未公开的发送任务将取消，已公开内容仍保留。': 'Signing in during the seven-day grace period cancels closure. All devices sign out; unpublished tasks are cancelled, while published content remains.',
  '重新输入密码': 'Re-enter password',
  '查看并确认注销申请': 'Review account closure',
  '申请七天后注销': 'Request closure after seven days',
  '预计完成时间由服务端受理时确定。期间登录会撤销申请；尚未公开的发送任务将取消，公开内容仍保留。': 'The server determines the completion time. Signing in cancels closure. Unpublished tasks are cancelled; published content remains.',
  '取消': 'Cancel',
  '申请注销': 'Request closure',
  '注销缓冲期': 'Closure grace period',
  '申请已受理，七天内主动登录会撤销申请。查看本页不会恢复登录。': 'Closure is pending. Signing in within seven days cancels it. Viewing this screen does not restore a session.',
  '注销申请已取消': 'Closure cancelled',
  '可以主动登录继续使用。': 'Sign in explicitly to continue.',
  '正式关闭处理中': 'Closing your account',
  '已经到达注销截止，不能再登录或恢复旧号。': 'The closure deadline has passed. This account can no longer be signed in to or recovered.',
  '账号已关闭，资格释放处理中': 'Account closed; releasing eligibility',
  '等待验证方持久确认释放后，再用同一精确邮箱注册新号。': 'Wait for confirmed eligibility release before registering a new account with the same exact email.',
  '账号已关闭，资格已释放': 'Account closed; eligibility released',
  '可以重新校邮注册全新账号。新号不会继承旧身份或内容。': 'You may register a new account. It does not inherit old identities or content.',
  '注销申请结果待核对': 'Check account closure result',
  '尚不能确定请求结果。未查到状态也不能证明原申请未提交；请继续核对。': 'The outcome is uncertain. A missing result does not prove the request was not committed. Keep checking.',
  '核对注销状态': 'Check closure status',
  '原申请密码': 'Original request password',
  '以原申请重新确认': 'Confirm the original request again',
  '登录并撤销注销': 'Sign in and cancel closure',
  '结束已取消的注销操作': 'Finish the cancelled closure operation',
  '重设密码，继续保留注销': 'Reset password and keep closure pending',
  '创建全新账号': 'Create a new account',
  '至少 15 个字符，支持空格和粘贴；不要使用校邮密码。': 'At least 15 characters. Spaces and paste are supported. Do not use your campus email password.',
  '6–24 个小写字母、数字或下划线，以字母开头。':
      '6–24 lowercase letters, digits or underscores, starting with a letter.',
  '请输入精确的 @hainanu.edu.cn 校园邮箱，不能有空格':
      'Enter an exact @hainanu.edu.cn address without spaces',
  '用户名须为 6–24 个字母、数字或下划线，以字母开头':
      'Use 6–24 letters, digits or underscores, starting with a letter',
  '新密码至少需要 15 个字符': 'Your new password needs at least 15 characters',
  '请输入六位最新验证码': 'Enter the latest six-digit code',
  '用户名或密码不正确。': 'Incorrect username or password.',
  '登录暂时不可用，请重试。': 'Sign-in is temporarily unavailable. Try again.',
  '登录结果暂时无法确认，请主动重试。':
      'The sign-in result is uncertain. Please retry explicitly.',
  '上次登录已建立会话，请主动重新登录。': 'The previous attempt established a session. Please sign in again explicitly.',
  '安全存储写入失败，不能确认本机登录。': 'Secure storage could not confirm this sign-in.',
  '系统安全存储不可用，请恢复后重试。':
      'System secure storage is unavailable. Restore it and retry.',
  '系统安全存储不可用，不能恢复社区会话。': 'System secure storage is unavailable. The community session cannot be restored.',
  '暂时无法核对会话，请恢复服务后重试。':
      'Unable to check the session. Retry when service is restored.',
  '暂时无法确认会话，请重试。': 'Unable to confirm the session. Please retry.',
  '此设备的会话已被新设备接替，请重新登录。':
      'Another device replaced this session. Please sign in again.',
  '会话已失效，请重新登录。': 'Your session is no longer valid. Please sign in again.',
  '暂时无法确认会话，已保留安全存储中的令牌。':
      'Unable to confirm the session. Its token remains in secure storage.',
  '续期结果待确认，请重试恢复会话。': 'Renewal needs checking. Retry session restoration.',
  '安全存储不可用，请恢复后核对会话。': 'Restore secure storage, then check your session.',
  '本地已退出，服务器撤销待确认。': 'Signed out locally. Server revocation is pending.',
  '退出待办未能完成持久写入，不能确认退出成功。':
      'The pending sign-out could not be saved. Sign-out is not confirmed.',
  '退出状态需要安全核对，请重试。': 'Sign-out requires a secure check. Please retry.',
  '已取消 Passkey 验证。你仍可使用恢复码。':
      'Passkey verification was cancelled. You can still use a recovery code.',
  '系统 Passkey 暂不可用，请重试或使用恢复码。':
      'System passkeys are unavailable. Retry or use a recovery code.',
  '核对记录已过保留期，无法据此确认是否提交。请主动选择后续操作。': 'The result record expired. Its outcome cannot be determined; choose the next action explicitly.',
  '结果未知，请保留原请求并核对。':
      'The outcome is unknown. Keep and check the original request.',
  '先隐藏原恢复码，再完整重输确认。':
      'Hide the original recovery code, then enter the full code to confirm.',
  '请先核对原操作，不能创建新的请求。':
      'Check the original operation before creating a new request.',
  '请等待倒计时结束。': 'Wait for the countdown to finish.',
  '操作未完成，请检查输入或核对原操作。': 'The operation did not complete. Check your input or the original request.',
  '安全存储或响应验证失败，操作已停止；请重试核对。': 'Secure storage or response validation failed. The operation stopped; retry the check.',
  '欢迎回来': 'Welcome back',
  '用户名': 'Username',
  '私有用户名': 'Username',
  '密码': 'Password',
  '邮箱': 'Email',
  '验证码': 'Verification code',
  '获取验证码': 'Get code',
  '找回账号': 'Recover account',
  '创建账号': 'Create an account',
  '第一次来？': 'New here?',
  '返回登录': 'Back to sign in',
  '登录并进入': 'Sign in and continue',
  '切换邮箱登录（待接入）': 'Use email (coming soon)',
  '切换用户名登录': 'Use username instead',
  '邮箱登录待接入': 'Email sign-in is coming soon',
  '切换浅色主题': 'Switch to light theme',
  '切换深色主题': 'Switch to dark theme',
  '显示密码': 'Show password',
  '隐藏密码': 'Hide password',
  '账号与安全': 'Account and security',
  '输入用户名': 'Your username',
  '输入密码': 'Your password',
  '输入邮箱': 'Your email',
  '输入验证码': 'Email code',
};
