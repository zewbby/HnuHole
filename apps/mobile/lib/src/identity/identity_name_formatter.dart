import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

import 'identity_name_ranges.dart';

enum IdentityNameFeedback { none, illegalCharacter, maximumLength }

/// Filters only the offending characters and counts extended grapheme clusters.
/// Never alters an active IME composing range. NFC/uniqueness are server checks.
class IdentityNameFormatter extends TextInputFormatter {
  IdentityNameFormatter({this.onFeedback});
  final void Function(IdentityNameFeedback)? onFeedback;

  static bool _in(int rune, List<(int, int)> ranges) {
    var low = 0, high = ranges.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2, range = ranges[middle];
      if (rune < range.$1) {
        high = middle - 1;
      } else if (rune > range.$2) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static String filterCharacters(String value) {
    final result = StringBuffer();
    var attachedToLetter = false;
    for (final rune in value.runes) {
      if (_in(rune, identityLetterRanges)) {
        result.writeCharCode(rune);
        attachedToLetter = true;
      } else if (_in(rune, identityDigitRanges) ||
          _in(rune, identityPunctuationRanges)) {
        result.writeCharCode(rune);
        attachedToLetter = false;
      } else if (attachedToLetter && _in(rune, identityMarkRanges)) {
        result.writeCharCode(rune);
      } else {
        attachedToLetter = false;
      }
    }
    return result.toString();
  }

  static String? validate(String value) {
    if (filterCharacters(value) != value) return '请移除空格、表情或不可见字符';
    if (utf8.encode(value).length > 512) return '昵称中的组合字符过多';
    final count = value.characters.length;
    if (count < 2) return '昵称至少需要 2 个字';
    if (count > 12) return '昵称最多 12 个字';
    return null;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.composing.isCollapsed) return newValue;
    final filtered = filterCharacters(newValue.text);
    final shortened = filtered.characters.take(12).toString();
    onFeedback?.call(filtered != newValue.text
        ? IdentityNameFeedback.illegalCharacter
        : shortened != filtered
        ? IdentityNameFeedback.maximumLength
        : IdentityNameFeedback.none);
    if (shortened == newValue.text) return newValue;
    final cursor = newValue.selection.extentOffset.clamp(0, newValue.text.length).toInt();
    final retainedPrefix = filterCharacters(newValue.text.substring(0, cursor))
        .characters.take(12).toString().length;
    return TextEditingValue(text: shortened,
      selection: TextSelection.collapsed(offset: retainedPrefix.clamp(0, shortened.length).toInt()));
  }
}
