import 'dart:convert';
import 'dart:typed_data';

import 'package:hyphen_dart/src/hyphenator.dart';
import 'package:hyphen_dart/src/model/dict.dart';
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

    test('the right minimum counts bytes', () {
      // libhyphen counts the right minimum in bytes and stops before the
      // first one: a first letter of one byte can stay alone on a line.
      final lines = [
        'LEFTHYPHENMIN 1',
        'RIGHTHYPHENMIN 2',
        'é1b',
        'a1b',
        'é1é',
      ];
      final utf8Dict = DictParser().parseLines(lines, isUtf8: true);
      final latin1Dict = DictParser().parseLines(lines, isUtf8: false);
      String hyphword(HyphenDict dict, String word) =>
          const Hyphenator().hyphenate(dict, word).hyphword;

      expect(hyphword(utf8Dict, 'éb'), 'éb');
      expect(hyphword(utf8Dict, 'éé'), 'éé');
      expect(hyphword(utf8Dict, 'ab'), 'a=b');
      expect(hyphword(latin1Dict, 'éb'), 'é=b');
      expect(hyphword(latin1Dict, 'éé'), 'é=é');
      expect(hyphword(latin1Dict, 'ab'), 'a=b');
    });

    test('ffi and ffl count as two letters for the left minimum', () {
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 2',
        'RIGHTHYPHENMIN 1',
        'ﬃ1n',
        'ﬀ1n',
      ], isUtf8: true);

      expect(const Hyphenator().hyphenate(dict, 'ﬃn').hyphword, 'ﬃ=n');
      expect(const Hyphenator().hyphenate(dict, 'ﬀn').hyphword, 'ﬀn');
    });

    test('a replacement without = is kept whatever the minimums', () {
      // As in LibreOffice's Albanian dictionary
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 2',
        'RIGHTHYPHENMIN 2',
        'a3dh4/e',
      ], isUtf8: true);

      expect(const Hyphenator().hyphenate(dict, 'adh').hyphword, 'e');
      expect(const Hyphenator().hyphenate(dict, 'xadh').hyphword, 'xe');
      expect(const Hyphenator().hyphenate(dict, 'adhxx').hyphword, 'e');
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

    test('hyphens cannot be changed', () {
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 1',
        'RIGHTHYPHENMIN 1',
        'a1b',
      ], isUtf8: false);
      final broken = const Hyphenator().hyphenate(dict, 'abab').hyphens;
      final whole = const Hyphenator().hyphenate(dict, 'xyz').hyphens;

      expect(() => broken[0] = 1, throwsUnsupportedError);
      expect(() => broken.add(4), throwsUnsupportedError);
      expect(() => whole.add(0), throwsUnsupportedError);
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
      final [_, other] = const Hyphenator().hyphenate(dict, 'abab').breaks;

      expect(() => result.part(other, null), throwsArgumentError);
      expect(() => result.part(null, other), throwsArgumentError);
      expect(other.canFollow(result.breaks.first), isFalse);
      expect(result.breaks.last.canFollow(result.breaks.first), isTrue);
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

    test('the last NOHYPHEN word before CR LF keeps the CR', () {
      // As in LibreOffice's Catalan and Mongolian dictionaries: libhyphen
      // drops only the '\n', and the word with the '\r' never matches.
      const lines = [
        'UTF-8',
        'LEFTHYPHENMIN 1',
        'RIGHTHYPHENMIN 1',
        'NOHYPHEN x,b',
        'a1b',
        'NEXTLEVEL',
        'a1b',
      ];
      HyphenDict parse(String newline) => DictParser().parseBytes(
        Uint8List.fromList(utf8.encode('${lines.join(newline)}$newline')),
      );
      final lf = parse('\n');
      final crlf = parse('\r\n');
      final cr = parse('\r');
      // Lines of a CR LF text split at the '\n'
      final splitCrlf = DictParser().parseLines([
        for (final line in lines.skip(1)) '$line\r',
      ], isUtf8: true);

      expect(lf.noHyphenWords, ['x', 'b']);
      expect(crlf.noHyphenWords, ['x', 'b\r']);
      expect(cr.noHyphenWords, ['x', 'b']);
      expect(splitCrlf.noHyphenWords, ['x', 'b\r']);
      expect(const Hyphenator().hyphenate(lf, 'ab').hyphword, 'ab');
      expect(const Hyphenator().hyphenate(crlf, 'ab').hyphword, 'a=b');
      expect(const Hyphenator().hyphenate(cr, 'ab').hyphword, 'ab');
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
