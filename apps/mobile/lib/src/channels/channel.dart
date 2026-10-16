import 'package:flutter/foundation.dart';

/// A channel returned by the server directory.
///
/// `code` is an immutable machine identifier. Display text is deliberately
/// supplied by the API so that the client does not become a second source of
/// business channel data.
@immutable
class Channel {
  const Channel({
    required this.id,
    required this.code,
    required this.name,
    required this.initiallyVisible,
    required this.displayOrder,
  });

  final String id;
  final String code;
  final String name;
  final bool initiallyVisible;
  final int displayOrder;

  /// Local UI aliases; wire fields remain exactly the OpenAPI names above.
  String get displayName => name;
  int get sortOrder => displayOrder;

  factory Channel.fromJson(Map<String, dynamic> json) {
    final id = _readString(json, const ['id']);
    final code = _readString(json, const ['code']);
    final displayName = _readString(
      json,
      const ['display_name', 'displayName', 'name'],
    );
    final sortOrder = _readInt(
      json,
      const ['displayOrder', 'display_order', 'sort_order', 'sortOrder'],
    );
    final initiallyVisible = _readBool(
      json,
      const ['initial_visible', 'initially_visible', 'initiallyVisible'],
    );

    if (id.isEmpty || code.isEmpty || displayName.isEmpty) {
      throw const FormatException('A channel must have id, code and display name');
    }

    return Channel(
      id: id,
      code: code,
      name: displayName,
      initiallyVisible: initiallyVisible,
      displayOrder: sortOrder,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'initiallyVisible': initiallyVisible,
        'displayOrder': displayOrder,
      };

  @override
  bool operator ==(Object other) {
    return other is Channel &&
        other.id == id &&
        other.code == code &&
        other.name == name &&
        other.initiallyVisible == initiallyVisible &&
        other.displayOrder == displayOrder;
  }

  @override
  int get hashCode => Object.hash(
        id,
        code,
        name,
        initiallyVisible,
        displayOrder,
      );

  static String _readString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key];
      if (value is String) {
        return value.trim();
      }
    }
    throw FormatException('Missing string field: ${keys.join(', ')}');
  }

  static int _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException('Missing integer field: ${keys.join(', ')}');
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is String) {
        if (value.toLowerCase() == 'true') {
          return true;
        }
        if (value.toLowerCase() == 'false') {
          return false;
        }
      }
      if (value is num) {
        return value != 0;
      }
    }
    throw FormatException('Missing boolean field: ${keys.join(', ')}');
  }
}

/// Validates the complete server directory before the UI is allowed to show
/// even one node.
class ChannelDirectory {
  const ChannelDirectory._();

  /// The contract's stable order. These are protocol identifiers, not a
  /// client-owned display list.
  static const List<String> requiredCodes = <String>[
    'vent',
    'warning',
    'recommendation',
    'buddy',
    'emotion',
    'mutual_help',
    'technology',
  ];

  static const Set<String> initiallyVisibleCodes = <String>{
    'vent',
    'warning',
    'recommendation',
    'buddy',
    'emotion',
  };

  static List<Channel> validate(Iterable<Channel> input) {
    final channels = input.toList(growable: false);
    if (channels.length != requiredCodes.length) {
      throw const FormatException('The channel directory is incomplete');
    }

    final ids = <String>{};
    final codes = <String>{};
    for (final channel in channels) {
      if (!ids.add(channel.id)) {
        throw const FormatException('The channel directory contains duplicate ids');
      }
      if (!codes.add(channel.code)) {
        throw const FormatException('The channel directory contains duplicate codes');
      }
    }

    if (!codes.containsAll(requiredCodes) || codes.length != requiredCodes.length) {
      throw const FormatException('The channel directory contains unknown codes');
    }

    final visibleCodes = channels
        .where((channel) => channel.initiallyVisible)
        .map((channel) => channel.code)
        .toSet();
    if (visibleCodes.length != initiallyVisibleCodes.length ||
        !visibleCodes.containsAll(initiallyVisibleCodes)) {
      throw const FormatException('The channel directory has invalid initial visibility');
    }

    final ordered = channels.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var index = 0; index < requiredCodes.length; index++) {
      if (ordered[index].code != requiredCodes[index]) {
        throw const FormatException('The channel directory order is invalid');
      }
    }

    return List<Channel>.unmodifiable(ordered);
  }
}
