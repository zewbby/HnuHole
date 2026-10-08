import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart' as hashes;

import '../auth/auth_crypto.dart';

enum PostOperation { create, retry, cancel, deletePost, hideTask }

extension PostOperationWire on PostOperation {
  String get wire => switch (this) {
    PostOperation.create => 'CREATE',
    PostOperation.retry => 'RETRY',
    PostOperation.cancel => 'CANCEL',
    PostOperation.deletePost => 'DELETE_POST',
    PostOperation.hideTask => 'HIDE_TASK',
  };
}

/// 与 Go 共用固定二进制 framing；原文字不做 trim、换行替换或 NFC。
class PostProtocol {
  static String resourceId(String value) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(value) ||
        value == '00000000-0000-0000-0000-000000000000') {
      throw const FormatException('Invalid post resource ID');
    }
    return value;
  }

  static String commandId(String value) {
    final bytes = AuthCrypto.decode(value, bytes: 16);
    if (bytes.every((b) => b == 0)) {
      throw const FormatException('Invalid post command key');
    }
    return value;
  }

  static String digestValue(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid post request digest');
    }
    return value;
  }

  static int version(int value) {
    if (value < 1 || value > 2147483647) {
      throw const FormatException('Invalid post attempt version');
    }
    return value;
  }

  static String? cursor(String? value) {
    if (value != null &&
        (value.isEmpty ||
            value.length > 1024 ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value))) {
      throw const FormatException('Invalid post cursor');
    }
    return value;
  }

  static Uint8List create({
    required String channelId,
    required String identityId,
    required String title,
    required String body,
  }) => _frame(1, [_id(channelId), _id(identityId), _text(title), _text(body)]);
  static Uint8List retry({
    required String taskId,
    required int expectedAttemptVersion,
    required String title,
    required String body,
  }) => _frame(2, [
    _id(taskId),
    _version(expectedAttemptVersion),
    _text(title),
    _text(body),
  ]);
  static Uint8List cancel({
    required String taskId,
    required int expectedAttemptVersion,
  }) => _frame(3, [_id(taskId), _version(expectedAttemptVersion)]);
  static Uint8List delete({required String postId}) => _frame(4, [_id(postId)]);
  static Uint8List hide({
    required String taskId,
    required int expectedAttemptVersion,
  }) => _frame(5, [_id(taskId), _version(expectedAttemptVersion)]);
  static String digest(List<int> frame) =>
      hashes.sha256.convert(frame).toString();

  static Uint8List _frame(int operation, List<List<int>> fields) =>
      Uint8List.fromList([
        ...ascii.encode('HNUHOLE/POST-COMMAND/V1'),
        0,
        operation,
        for (final field in fields) ...field,
      ]);
  static List<int> _id(String value) {
    final hex = resourceId(value).replaceAll('-', '');
    return List.generate(
      16,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }

  static List<int> _version(int value) => (ByteData(
    8,
  )..setUint64(0, version(value), Endian.big)).buffer.asUint8List();
  static List<int> _text(String value) {
    PostContentRules.scalarText(value);
    final bytes = utf8.encode(value);
    if (bytes.length > 262144) {
      throw const FormatException('Post framing text too large');
    }
    return [
      ...(ByteData(
        4,
      )..setUint32(0, bytes.length, Endian.big)).buffer.asUint8List(),
      ...bytes,
    ];
  }
}

/// characters 1.4.1 固定为 Unicode 16；计数与是否有实际内容是不同检查。
class PostContentRules {
  static const unicodeVersion = '16.0.0';
  static const maxTitleClusters = 15, maxBodyClusters = 3000;
  static const maxTitleBytes = 4096, maxBodyBytes = 65536;

  static int count(String value) {
    scalarText(value);
    return value.characters.length;
  }

  static void validate(String title, String body) {
    validateTitle(title);
    validateBody(body);
  }

  static void validateTitle(String value) =>
      _field(value, maxTitleClusters, maxTitleBytes);
  static void validateBody(String value) =>
      _field(value, maxBodyClusters, maxBodyBytes);

  /// 草稿是否有实际输入；发布有效性仍须 validate，避免抹掉暂时无效的编辑内容。
  static bool hasMeaningfulText(String value) => value.runes.any(
    (scalar) => !whiteSpace(scalar) && !defaultIgnorable(scalar),
  );

  /// Dart 字符串可含未配对 UTF-16 代理项，UTF-8 编码前必须显式拒绝。
  static void scalarText(String value) {
    final units = value.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('Invalid Unicode scalar text');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid Unicode scalar text');
      }
    }
  }

  static void _field(String value, int clusterLimit, int byteLimit) {
    scalarText(value);
    if (utf8.encode(value).length > byteLimit) {
      throw const FormatException('Post text byte limit exceeded');
    }
    var hasContent = false;
    for (final scalar in value.runes) {
      if (((scalar < 0x20 || scalar >= 0x7f && scalar <= 0x9f) &&
          scalar != 9 &&
          scalar != 10 &&
          scalar != 13)) {
        throw const FormatException('Post text contains invalid control');
      }
      if (!whiteSpace(scalar) && !defaultIgnorable(scalar)) hasContent = true;
    }
    if (!hasContent || count(value) > clusterLimit) {
      throw const FormatException('Post content invalid');
    }
  }

  // Unicode 16.0 PropList / DerivedCoreProperties 摘录，与服务端冻结表一致。
  // Unicode 数据许可见服务端 testdata/LICENSE-UNICODE.txt。
  static bool whiteSpace(int s) =>
      s >= 9 && s <= 13 ||
      s == 0x20 ||
      s == 0x85 ||
      s == 0xa0 ||
      s == 0x1680 ||
      s >= 0x2000 && s <= 0x200a ||
      s == 0x2028 ||
      s == 0x2029 ||
      s == 0x202f ||
      s == 0x205f ||
      s == 0x3000;
  static bool defaultIgnorable(int s) =>
      s == 0xad ||
      s == 0x34f ||
      s == 0x61c ||
      s >= 0x115f && s <= 0x1160 ||
      s >= 0x17b4 && s <= 0x17b5 ||
      s >= 0x180b && s <= 0x180f ||
      s >= 0x200b && s <= 0x200f ||
      s >= 0x202a && s <= 0x202e ||
      s >= 0x2060 && s <= 0x206f ||
      s == 0x3164 ||
      s >= 0xfe00 && s <= 0xfe0f ||
      s == 0xfeff ||
      s == 0xffa0 ||
      s >= 0xfff0 && s <= 0xfff8 ||
      s >= 0x1bca0 && s <= 0x1bca3 ||
      s >= 0x1d173 && s <= 0x1d17a ||
      s >= 0xe0000 && s <= 0xe0fff;
}
