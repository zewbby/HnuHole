import 'package:flutter/services.dart';

/// One serialized native keychain/Keystore record per deployment namespace.
class DurableAuthVault {
  DurableAuthVault(this.namespace) {
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(namespace)) {
      throw ArgumentError('Invalid vault namespace');
    }
  }
  final String namespace;
  static const _channel = MethodChannel('hnuhole/auth_vault');
  Future<String?> read() => _channel.invokeMethod<String>('read', {'namespace': namespace});
  Future<void> write(String value) => _channel.invokeMethod<void>('write', {'namespace': namespace,'value': value});
}
