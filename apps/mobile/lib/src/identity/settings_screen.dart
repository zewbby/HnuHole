import 'package:flutter/material.dart';

/// Routes to implemented account, identity and credential management.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onManageIdentity,
    required this.onManageSecurity,
    this.onManageAccount,
  });
  final VoidCallback onManageIdentity, onManageSecurity;
  final VoidCallback? onManageAccount;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              if (onManageAccount != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('账号与安全'),
                  subtitle: const Text('登录状态、退出与账号注销'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onManageAccount,
                ),
                const Divider(height: 1),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('身份管理'),
                subtitle: const Text('创建、改名与删除发言身份'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageIdentity,
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.security_outlined),
                title: const Text('设备与恢复凭据'),
                subtitle: const Text('会话、恢复码与 Passkey'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageSecurity,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
