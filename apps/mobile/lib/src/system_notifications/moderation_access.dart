import 'dart:convert';

import 'package:flutter/material.dart';

import '../auth/auth_crypto.dart';
import '../auth/auth_store.dart';
import '../posts/post_models.dart';
import 'governance_api.dart';

/// A fixed-lifetime, self-only capability. It is kept in its own native vault
/// namespace and is never installed as a normal community session.
class ModerationAccess extends ChangeNotifier {
  ModerationAccess({required this.api, required this.vault});
  final HttpGovernanceApi api;
  final AuthVault vault;
  String? token, ownerKey;
  DateTime? expiresAt;
  bool busy = false;
  String? error;
  int _epoch = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    if (busy) return false;
    final epoch = ++_epoch;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await api.send(
        null,
        'POST',
        '/api/v1/moderation-access/sessions',
        body: {'username': username, 'password': password},
      );
      final m = PostJson.record(response.value, {
        'sessionToken',
        'expiresAt',
        'scope',
        'moderationSubject',
      });
      final capability = PostJson.text(m, 'sessionToken');
      AuthCrypto.decode(capability, bytes: 32);
      if (m['scope'] != 'MODERATION_SELF') {
        throw const FormatException('Invalid restricted scope');
      }
      final deadline = PostJson.date(m, 'expiresAt'),
          owner = PostJson.text(m, 'moderationSubject', maxLength: 43);
      AuthCrypto.decode(owner, bytes: 32);
      if (_disposed || epoch != _epoch) return false;
      final encoded = jsonEncode({
        'v': 1,
        'scope': 'MODERATION_SELF',
        'token': capability,
        'moderationSubject': owner,
        'expiresAt': deadline.toIso8601String(),
      });
      await vault.write(encoded);
      if (await vault.read() != encoded) throw const AuthStorageFailure();
      if (_disposed || epoch != _epoch) return false;
      token = capability;
      ownerKey = owner;
      expiresAt = deadline;
      _notify();
      return true;
    } on Object {
      if (epoch == _epoch) {
        error = '暂时无法进入处理通知。请核对用户名、密码或稍后重试。';
        _notify();
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> clear() async {
    final oldToken = token;
    _epoch++;
    token = ownerKey = null;
    expiresAt = null;
    busy = false;
    _notify();
    await vault.write(jsonEncode({'v': 1, 'signedOut': true}));
    if (oldToken != null) {
      try {
        await api.send(
          oldToken,
          'POST',
          '/api/v1/moderation-access/session-revocations',
        );
      } on Object {
        /* Local capability is already unavailable to this UI. */
      }
    }
  }

  // Restricted access requires explicit login after restart. The stored value
  // only isolates material ownership; a stale capability is never promoted.
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

class ModerationAccessScreen extends StatefulWidget {
  const ModerationAccessScreen({super.key, required this.access});
  final ModerationAccess access;
  @override
  State<ModerationAccessScreen> createState() => _ModerationAccessScreenState();
}

class _ModerationAccessScreenState extends State<ModerationAccessScreen> {
  final _username = TextEditingController(),
      _password = TextEditingController();
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.access,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('查看处理通知与申诉')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('账号受限时，仍可用原用户名和密码查看本人的处理结果并申诉。此入口只允许处理通知与申诉。'),
          const SizedBox(height: 24),
          TextField(
            controller: _username,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '私有用户名'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.access.busy
                ? null
                : () async {
                    final password = _password.text;
                    _password.clear();
                    final ok = await widget.access.login(
                      _username.text,
                      password,
                    );
                    if (context.mounted && ok) Navigator.pop(context, true);
                  },
            child: Text(widget.access.busy ? '正在核对' : '查看处理通知'),
          ),
          if (widget.access.error != null)
            Semantics(liveRegion: true, child: Text(widget.access.error!)),
        ],
      ),
    ),
  );
}
