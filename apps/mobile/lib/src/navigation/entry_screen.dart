import 'package:flutter/material.dart';

import '../auth/auth_presentation.dart';
import 'channel_directory_controller.dart';

/// Login and authoritative directory loading only. The app root presents the
/// recommended feed once the complete directory and session are available.
class EntryScreen extends StatelessWidget {
  const EntryScreen({
    super.key,
    required this.directory,
    required this.onLoginRequested,
    this.restoringSession = false,
    this.onMessagesPressed,
    this.messagesUnread = false,
  });

  final ChannelDirectoryController directory;
  final VoidCallback onLoginRequested;
  final bool restoringSession;
  final VoidCallback? onMessagesPressed;
  final bool messagesUnread;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: directory,
    builder: (context, _) =>
        restoringSession || directory.status == ChannelDirectoryStatus.signedOut
        ? AuthWelcomeScreen(onStarted: onLoginRequested)
        : Scaffold(
            appBar: AppBar(
              title: const Text('HnuHole'),
              actions: [
                if (onMessagesPressed != null)
                  IconButton(
                    tooltip: '消息',
                    onPressed: onMessagesPressed,
                    icon: Badge(
                      isLabelVisible: messagesUnread,
                      child: const Icon(Icons.forum_outlined),
                    ),
                  ),
              ],
            ),
            body: Center(
              child: switch (directory.status) {
                ChannelDirectoryStatus.signedOut => FilledButton.icon(
                  onPressed: onLoginRequested,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('登录或注册'),
                ),
                ChannelDirectoryStatus.failure => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 30),
                      const SizedBox(height: 10),
                      Text(
                        directory.error?.message ?? '暂时无法进入首页，请重试。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: directory.retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新核对会话'),
                      ),
                    ],
                  ),
                ),
                _ => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在准备首页…'),
                  ],
                ),
              },
            ),
          ),
  );
}
