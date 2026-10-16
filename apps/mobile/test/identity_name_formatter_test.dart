import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

void main() {
  test('preserves legal characters while rejecting spaces emoji and invisibles', () {
    IdentityNameFeedback? feedback;
    final formatter = IdentityNameFormatter(onFeedback: (value) => feedback = value);
    final value = formatter.formatEditUpdate(TextEditingValue.empty,
      const TextEditingValue(text: '春 风😀Aéかな한글！', selection: TextSelection.collapsed(offset: 14)));
    expect(value.text, '春风Aéかな한글！');
    expect(feedback, IdentityNameFeedback.illegalCharacter);
    for (final invalid in ['\u034f', '\u17b4', '\u17b5', '\u180b', '\u180c',
      '\u180d', '\u180f', '\ufe0f', '\u200b', '\u2060', '\u115f', '\u1160',
      '\u3164', '\uffa0', '\u203c', '\u2049', '\u3030', '\u303d']) {
      expect(IdentityNameFormatter.filterCharacters('ab$invalid'), 'ab');
    }
  });

  test('IME composition is left untouched then counts visible clusters after commit', () {
    final formatter = IdentityNameFormatter();
    const composing = TextEditingValue(text: 'a\u0301い',
      selection: TextSelection.collapsed(offset: 3), composing: TextRange(start: 0, end: 3));
    expect(formatter.formatEditUpdate(TextEditingValue.empty, composing), composing);
    expect(IdentityNameFormatter.validate('a\u0301い'), isNull);
    expect(IdentityNameFormatter.validate('\u1100\u1161好'), isNull);
    expect(IdentityNameFormatter.validate('か\u3099好'), isNull);
    expect(IdentityNameFormatter.validate('1\u0301好'), isNotNull);
    expect(IdentityNameFormatter.validate('\u0301好'), isNotNull);
  });

  test('maximum uses characters and ignores only the excess suffix', () {
    IdentityNameFeedback? feedback;
    final formatter = IdentityNameFormatter(onFeedback: (value) => feedback = value);
    final input = '${List.filled(12, 'e\u0301').join()}Z';
    final result = formatter.formatEditUpdate(TextEditingValue.empty,
      TextEditingValue(text: input, selection: TextSelection.collapsed(offset: input.length)));
    expect(result.text.characters.length, 12);
    expect(result.text, List.filled(12, 'e\u0301').join());
    expect(feedback, IdentityNameFeedback.maximumLength);
    expect(result.selection.extentOffset, result.text.length);
    expect(IdentityNameFormatter.validate('春'), isNotNull);
  });

  test('local byte cap explains excessive attached marks without storage failure', () {
    final nickname = 'a${List.filled(260, '\u0301').join()}b';
    expect(nickname.characters.length, 2);
    expect(utf8.encode(nickname).length, greaterThan(512));
    expect(IdentityNameFormatter.validate(nickname), '昵称中的组合字符过多');
  });

  test('allowed Latin/kana/Hangul diacritics match backend supported boundaries', () {
    expect(IdentityNameFormatter.validate('ＡＢ'), isNull);
    expect(IdentityNameFormatter.validate('Àé'), isNull);
    expect(IdentityNameFormatter.validate('汉。'), isNull);
    expect(IdentityNameFormatter.validate('コー'), isNull);
    expect(IdentityNameFormatter.validate('ｶﾞｷﾞ'), isNull);
    expect(IdentityNameFormatter.validate('ｶﾞ'), isNotNull);
    expect(IdentityNameFormatter.validate('ﾞ好'), isNotNull);
    expect(IdentityNameFormatter.validate('ab\u2c2e'), isNotNull);
    expect(IdentityNameFormatter.validate('ab\u2c5e'), isNotNull);
    expect(IdentityNameFormatter.validate('ab\u0483'), isNotNull);
    expect(IdentityNameFormatter.validate('اب'), isNotNull);
    expect(IdentityNameFormatter.validate('αβ'), isNotNull);
  });
}
