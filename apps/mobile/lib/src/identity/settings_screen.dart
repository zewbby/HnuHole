import 'package:flutter/material.dart';

/// B02 entry only. Personal posts/favorites and other settings have their own
/// business slices; this screen advertises only implemented management routes.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.onManageIdentity,
    required this.onManageSecurity,
    required this.onManageAccount,
  });
  final VoidCallback onManageIdentity, onManageSecurity, onManageAccount;
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
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('账号与注销'),
                subtitle: const Text('退出本机与申请注销账号'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageAccount,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
