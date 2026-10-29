import 'dart:convert';
import 'dart:typed_data';

import 'package:hyphen_dart/src/hyphenator.dart';
import 'package:hyphen_dart/src/model/result.dart';
import 'package:hyphen_dart/src/parser/dict_parser.dart';
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

    test('a replacement without index and cut replaces the pattern', () {
      final dict = DictParser().parseLines(['ab1c/b=c'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'xabcx').hyphword, 'xb=c');
    });

    test('a replacement with only an index ignores it', () {
      final dict = DictParser().parseLines(['ab1c/b=c,1'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'xabcx').hyphword, 'xb=cx');
    });

    test('a replacement ignores what follows the cut', () {
      final dict = DictParser().parseLines(['ab1c/b=c,2,1,9'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'xabcx').hyphword, 'xab=ccx');
    });

    test('a state with many transitions falls back to one with few', () {
      final dict = DictParser().parseLines([
        for (final c in 'abcdefgh'.split('')) 'x1$c',
      ], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'axbx').hyphword, 'ax=bx');
      expect(const Hyphenator().hyphenate(dict, 'xxa').hyphword, 'xxa');
    });
  });

  group('HyphenResult.breaks', () {
    List<(int, int, int, String, String, String, String)> breaksOf(
      HyphenResult result,
    ) => [
      for (final b in result.breaks)
        (b.index, b.start, b.end, b.before, b.after, b.firstPart, b.secondPart),
    ];

    test('breaks that only split the word', () {
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 1',
        'RIGHTHYPHENMIN 1',
        'a1b',
      ], isUtf8: false);

      final result = const Hyphenator().hyphenate(dict, 'abab');

      expect(result.hyphens, [0, 2]);
      expect(breaksOf(result), [
        (0, 1, 1, '', '', 'a', 'bab'),
        (2, 3, 3, '', '', 'aba', 'b'),
      ]);
    });

    test('a break that changes letters', () {
      // Hungarian: a double ssz breaks as sz-sz
      final dict = DictParser().parseLines([
        's1sz/sz=sz,1,3',
        'ú1s',
      ], isUtf8: true);

      final result = const Hyphenator().hyphenate(dict, 'hosszúság');

      expect(result.hyphword, 'hosz=szú=ság');
      expect(breaksOf(result), [
        (2, 2, 5, 'sz', 'sz', 'hosz', 'szúság'),
        (5, 6, 6, '', '', 'hosszú', 'ság'),
      ]);
    });

    test('a break that adds a letter at a compound boundary', () {
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
      expect(breaksOf(result), [
        (1, 2, 2, '', '', 'ki', 'lowattime'),
        (3, 4, 4, '', '', 'kilo', 'wattime'),
        (6, 6, 8, 'tt', 't', 'kilowatt', 'time'),
        (8, 9, 9, '', '', 'kilowatti', 'me'),
      ]);
    });

    test('a word without breaks', () {
      final dict = DictParser().parseLines(['a1b'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, 'xyz').breaks, isEmpty);
    });

    test('the parts of a word broken at two places', () {
      final dict = DictParser().parseLines([
        's1sz/sz=sz,1,3',
        'ú1s',
      ], isUtf8: true);
      final result = const Hyphenator().hyphenate(dict, 'hosszúság');
      final [first, second] = result.breaks;

      expect(second.canFollow(first), isTrue);
      expect(first.canFollow(second), isFalse);
      expect(first.canFollow(first), isFalse);
      expect(
        [
          result.part(null, first),
          result.part(first, second),
          result.part(second, null),
        ],
        ['hosz', 'szú', 'ság'],
      );
      expect(result.part(null, first), first.firstPart);
      expect(result.part(second, null), second.secondPart);
      expect(result.part(null, null), 'hosszúság');
    });

    test('a break in the letters that an earlier break replaces', () {
      final dict = DictParser().parseLines([
        's1sz/sz=sz,1,3',
        'z1ú',
        'ú1s',
      ], isUtf8: true);
      final result = const Hyphenator().hyphenate(dict, 'hosszúság');
      final [first, inside, last] = result.breaks;

      // libhyphen leaves the break after the z out
      expect(result.hyphword, 'hosz=szú=ság');
      expect(inside.canFollow(first), isFalse);
      expect(last.canFollow(first), isTrue);
      expect(() => result.part(first, inside), throwsArgumentError);
      expect(result.part(first, last), 'szú');
    });

    test('parts only between breaks of the same word', () {
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 1',
        'RIGHTHYPHENMIN 1',
        'a1b',
      ], isUtf8: false);
      final result = const Hyphenator().hyphenate(dict, 'abab');
      final other = const Hyphenator().hyphenate(dict, 'abab').breaks.first;

      expect(() => result.part(other, null), throwsArgumentError);
      expect(() => result.part(null, other), throwsArgumentError);
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

    test('compound minimums without NEXTLEVEL', () {
      final dict = DictParser().parseLines([
        'COMPOUNDLEFTHYPHENMIN 4',
        'COMPOUNDRIGHTHYPHENMIN 5',
        'a1b',
      ], isUtf8: false);

      expect(dict.compoundLeftHyphenMin, 4);
      expect(dict.compoundRightHyphenMin, 5);
    });

    test('long pattern lines', () {
      final x = 'x' * 70;
      final dict = DictParser().parseLines(['${x}1y'], isUtf8: false);

      expect(const Hyphenator().hyphenate(dict, '${x}yz').hyphword, '$x=yz');
    });

    test('lines ending in CR LF', () {
      final lines = ['LEFTHYPHENMIN 1', 'RIGHTHYPHENMIN 1', 'a1b', 'c1d'];

      final fromLines = DictParser().parseLines([
        for (final line in lines) '$line\r\n',
      ], isUtf8: false);
      final fromBytes = DictParser().parseBytes(
        Uint8List.fromList(
          latin1.encode('ISO8859-1\r\n${lines.join('\r\n')}\r\n'),
        ),
      );

      for (final dict in [fromLines, fromBytes]) {
        expect(const Hyphenator().hyphenate(dict, 'abcd').hyphword, 'a=bc=d');
      }
    });
  });
}
