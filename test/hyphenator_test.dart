import 'dart:convert';
import 'dart:typed_data';

import 'package:hypen_dart/src/hyphenator.dart';
import 'package:hypen_dart/src/parser/dict_parser.dart';
import 'package:test/test.dart';

// No dart:io, so these also run on the web: dart test -p node
void main() {
  group('Hyphenator matches libhyphen', () {
    test('a digit starts a word', () {
      final dict = DictParser().parseLines(['.ab1cd'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, '1abcd').hyphword, '1ab=cd');
      expect(
        const Hyphenator().hyphenate(dict, 'ab2abcd').hyphword,
        'ab2ab=cd',
      );
    });

    test('a digit ends a word', () {
      final dict = DictParser().parseLines(['ab1cd.'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'abcd2').hyphword, 'ab=cd2');
      expect(
        const Hyphenator().hyphenate(dict, 'abcd2ab').hyphword,
        'ab=cd2ab',
      );
    });

    test('non-standard hyphenation at a compound boundary', () {
      // libhyphen's compound3 test
      final dict = DictParser().parseLines([
        'wat1time/tt=t,3,2',
        '.kilo1watt.',
        'NEXTLEVEL',
        '.ki1lo.',
        '.ti1me.',
      ], isUtf8: false);

      final result = const Hyphenator().hyphenate(dict, 'kilowattime');

      expect(result.hyphword, 'ki=lo=watt=ti=me');
    });

    test('a replacement before the first character', () {
      final dict = DictParser().parseLines(['1abcd/x=y,1,1'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'abcd').hyphword, 'abcd');
    });

    test('a replacement after the last character', () {
      final dict = DictParser().parseLines(['b.1/x=y,1,2'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'ab').hyphword, 'ab');
    });

    test('patterns are not merged with their suffixes', () {
      // libhyphen expects dictionaries where substrings.pl merged the digits
      // of b1cd into abcd.
      final dict = DictParser().parseLines(['abcd', 'b1cd'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'abcd').hyphword, 'abcd');
      expect(const Hyphenator().hyphenate(dict, 'xbcd').hyphword, 'xb=cd');
    });
  });

  group('DictParser', () {
    test('parseBytes reads only the bytes of the given view', () {
      final buffer = Uint8List.fromList(
        latin1.encode('x1y\nISO8859-1\nab1cd\nx1y\n'),
      );
      final view = Uint8List.sublistView(buffer, 4, 20);

      final dict = DictParser().parseBytes(view);

      expect(const Hyphenator().hyphenate(dict, 'abcd').hyphword, 'ab=cd');
      expect(const Hyphenator().hyphenate(dict, 'xxyy').hyphword, 'xxyy');
    });
  });
}
