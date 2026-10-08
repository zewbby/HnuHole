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
  Future<String?> read() =>
      _channel.invokeMethod<String>('read', {'namespace': namespace});
  Future<void> write(String value) => _channel.invokeMethod<void>('write', {
    'namespace': namespace,
    'value': value,
  });
}

/// 业务密钥与数据库使用独立原生命名空间，不读写认证状态。
class DurableBusinessVault {
  DurableBusinessVault(this.scope) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(scope)) {
      throw ArgumentError('Invalid business storage scope');
    }
  }
  final String scope;
  static const _channel = MethodChannel('hnuhole/auth_vault');
  Future<String?> read() =>
      _channel.invokeMethod<String>('businessRead', {'namespace': scope});
  Future<void> write(String value) => _channel.invokeMethod<void>(
    'businessWrite',
    {'namespace': scope, 'value': value},
  );
  Future<void> purgeClosedAccount() => _channel.invokeMethod<void>(
    'businessPurgeClosedAccount',
    {'namespace': scope},
  );

  /// 原生层建立并确认不参加备份的目录，Dart 不自行选择普通文档目录。
  Future<String> databasePath() async {
    final path = await _channel.invokeMethod<String>('businessDatabasePath', {
      'namespace': scope,
    });
    if (path == null || path.isEmpty) {
      throw PlatformException(code: 'BUSINESS_STORAGE_UNAVAILABLE');
    }
    return path;
  }
}
