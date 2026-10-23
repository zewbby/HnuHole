import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_store.dart';
import 'dm_controller.dart';

class DmNotificationTarget {
  const DmNotificationTarget(this.scope, this.identity, this.conversation);
  final String scope, identity, conversation;
  static DmNotificationTarget? parse(Object? value) {
    if (value is! Map || value.length != 3) return null;
    final scope = value['scope'],
        identity = value['identityId'],
        conversation = value['conversationId'];
    final uuid = RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
    if (scope is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        identity is! String ||
        !uuid.hasMatch(identity) ||
        conversation is! String ||
        !uuid.hasMatch(conversation)) {
      return null;
    }
    return DmNotificationTarget(scope, identity, conversation);
  }
}

/// Notification clicks are hints. Navigation revalidates ownership against the
/// current authenticated directory; neither clicks nor notification delivery ACK
/// or mark any messages read.
class DmNotifications {
  DmNotifications({
    required this.environment,
    required this.preferences,
    this.channel = const MethodChannel('hnuhole/dm_notifications'),
  });
  final String environment;
  final AuthVault preferences;
  final MethodChannel channel;
  final Map<String, bool> _previews = {};
  String? _scope;
  bool _loaded = false;
  bool _bound = false;
  final _started = Completer<void>();
  DmNotificationTarget? pending;
  VoidCallback? onTap;
  String scopeFor(String account) => sha256
      .convert(
        utf8.encode(
          jsonEncode(['hnuhole.dm.notifications.v1', environment, account]),
        ),
      )
      .toString();

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'tap') {
        pending = DmNotificationTarget.parse(call.arguments);
        onTap?.call();
      }
    });
    try {
      pending = DmNotificationTarget.parse(
        await channel.invokeMethod('takeTap'),
      );
      final raw = await preferences.read();
      if (raw != null) {
        final saved = jsonDecode(raw);
        if (saved is Map && saved.length <= 100) {
          for (final entry in saved.entries) {
            if (entry.key is String &&
                RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) &&
                entry.value is bool) {
              _previews[entry.key] = entry.value;
            }
          }
        }
      }
    } catch (_) {
      /* No permission/storage/platform support: stay private. */
    }
    _loaded = true;
    if (!_started.isCompleted) _started.complete();
    onTap?.call();
  }

  Future<void> bind(String? account) async {
    await _started.future;
    final next = account == null ? null : scopeFor(account);
    if (_bound && _scope == next) return;
    _bound = true;
    _scope = next;
    if (next != null && pending != null && pending!.scope != next) {
      pending = null;
    }
    try {
      await channel.invokeMethod('bind', {'scope': next});
    } catch (_) {}
  }

  bool preview(String account) =>
      _loaded && _previews[scopeFor(account)] == true;
  Future<void> setPreview(String account, bool value) async {
    final next = {..._previews, scopeFor(account): value};
    await preferences.write(jsonEncode(next));
    _previews
      ..clear()
      ..addAll(next);
    // Withdraw older expanded notifications when opting back into privacy.
    if (!value) await clear();
  }

  Future<void> purge(String account) async {
    _previews.remove(scopeFor(account));
    await preferences.write(jsonEncode(_previews));
    if (pending?.scope == scopeFor(account)) pending = null;
    await clear();
  }

  Future<void> clear() async {
    try {
      await channel.invokeMethod('clear');
    } catch (_) {}
  }

  Future<void> reconcile(DmController controller) async {
    final account = controller.accountId;
    if (!controller.available ||
        account == null ||
        _scope != scopeFor(account)) {
      return;
    }
    final owner = _scope!;
    try {
      await channel.invokeMethod('retain', {
        'scope': owner,
        'targets': [
          for (final row in controller.conversations)
            if (row['muted'] != true &&
                row['deleted'] != true &&
                (row['unread'] as int? ?? 0) > 0)
              '$owner:${row['identityId']}:${row['id']}',
        ],
      });
    } catch (_) {}
  }

  Future<bool> permission({bool request = false}) async {
    try {
      return await channel.invokeMethod<bool>(
            request ? 'requestPermission' : 'permission',
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }

  Future<void> incoming(
    List<Map<String, dynamic>> items,
    String account,
    DmController controller,
  ) async {
    final owner = scopeFor(account), window = controller.scope;
    if (!_loaded || _scope != owner || !controller.available) return;
    for (final item in items) {
      if (_scope != owner ||
          !controller.available ||
          controller.scope != window) {
        return;
      }
      final row = controller.conversations
          .where(
            (r) =>
                r['identityId'] == item['identityId'] &&
                r['id'] == item['conversationId'],
          )
          .firstOrNull;
      if (row == null || row['muted'] == true || row['deleted'] == true) {
        continue;
      }
      try {
        await channel.invokeMethod('show', {
          'scope': owner,
          'identityId': item['identityId'],
          'conversationId': item['conversationId'],
          'preview': preview(account),
          // Public sender name only; no recipient name or private note.
          'sender': preview(account) ? row['peerName'] : '',
          'text': preview(account)
              ? (item['kind'] == 'IMAGE' ? '[图片]' : item['text'])
              : '',
        });
      } catch (_) {
        /* Notification failure never rolls back durable delivery. */
      }
    }
  }

  void dispose() {
    channel.setMethodCallHandler(null);
    onTap = null;
  }
}

class DmNotificationSettings extends StatefulWidget {
  const DmNotificationSettings({
    super.key,
    required this.notifications,
    required this.account,
    required this.current,
  });
  final DmNotifications notifications;
  final String account;
  final bool Function() current;
  @override
  State<DmNotificationSettings> createState() => _DmNotificationSettingsState();
}

class _DmNotificationSettingsState extends State<DmNotificationSettings> {
  bool _saving = false;
  String? _status;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('私信通知')),
    body: ListView(
      children: [
        const ListTile(
          title: Text('默认隐藏内容与身份'),
          subtitle: Text('通知只显示“你有一条新私信”。免打扰会话不提醒。'),
        ),
        SwitchListTile(
          title: const Text('显示发件昵称和消息预览'),
          value: widget.notifications.preview(widget.account),
          onChanged: _saving || !widget.current()
              ? null
              : (value) async {
                  setState(() => _saving = true);
                  try {
                    await widget.notifications.setPreview(
                      widget.account,
                      value,
                    );
                  } catch (_) {
                    if (mounted) _status = '设置未保存，请重试';
                  }
                  if (mounted) setState(() => _saving = false);
                },
        ),
        ListTile(
          title: const Text('允许系统通知'),
          subtitle: Text(_status ?? '由 Android 系统控制通知权限'),
          onTap: !widget.current()
              ? null
              : () async {
                  final allowed = await widget.notifications.permission(
                    request: true,
                  );
                  if (mounted) {
                    setState(
                      () =>
                          _status = allowed ? '系统通知已允许' : '请在系统授权面板或应用通知设置中开启',
                    );
                  }
                },
        ),
      ],
    ),
  );
}
