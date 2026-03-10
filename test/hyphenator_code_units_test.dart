import 'dart:io';

import 'package:hypen_dart/src/hyphenator_manual.dart';
import 'package:hypen_dart/src/parser/dict_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Hyphenator with code-unit dictionaries', () {
    test('uses numeric pattern digits from DictParser', () {
      final dict = DictParser().parseLines(['ab1cd'], isUtf8: false);

      // final result = const HyphenatorCodepoints().hyphenate(dict, 'abcd');
      final result = const HyphenatorManual().hyphenate(dict, 'abcd');

      expect(result.hyphens, [1]);
      expect(result.hyphword, 'ab=cd');
    });

    test('returns code-unit offsets for non-ASCII BMP characters', () {
      final dict = DictParser().parseLines(['éb1cd'], isUtf8: false);

      final result = const HyphenatorManual().hyphenate(dict, 'ébcd');

      expect(result.hyphens, [1]);
      expect(result.hyphword, 'éb=cd');
    });

    test('blocks hyphenation immediately before a nohyphen sequence', () {
      final dict = DictParser().parseLines([
        'NOHYPHEN éb',
        'a1ébcd',
        'NEXTLEVEL',
      ], isUtf8: false);

      final result = const HyphenatorManual().hyphenate(dict, 'aébcd');

      expect(result.hyphens, isEmpty);
      expect(result.hyphword, 'aébcd');
    });

    test('handles foobar', (){
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 4',
        'RIGHTHYPHENMIN 4',
        'foo1',
        'NEXTLEVEL',
        'bar1',
      ], isUtf8: true);

      final result = const HyphenatorManual().hyphenate(dict, '123foobarfoobar');

      expect(result.hyphword, '123foobar=foobar');
    });
  });
}
