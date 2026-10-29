import 'dart:typed_data';

import 'package:hyphen_dart/hyphen_dart.dart';
import 'package:test/test.dart';

// No dart:io, so these also run on the web: dart test -p node
void main() {
  HyphenDict compileAndLoad(HyphenDict dict) =>
      DictParser().parseBytes(const DictCompiler().compile(dict));

  void expectSameHyphenation(
    HyphenDict expected,
    HyphenDict actual,
    List<String> words,
  ) {
    for (final word in words) {
      final want = const Hyphenator().hyphenate(expected, word);
      final got = const Hyphenator().hyphenate(actual, word);
      expect(got.hyphword, want.hyphword, reason: word);
      expect(got.hyphens, want.hyphens, reason: word);
    }
  }

  group('DictCompiler', () {
    test('compiled dictionaries hyphenate like the text', () {
      final text = DictParser().parseLines([
        'LEFTHYPHENMIN 1',
        'NOHYPHEN cd',
        '.ab1cd',
        'ab1cd.',
        'b1c',
        'é1f',
        'x1\u{1F600}',
      ], isUtf8: true);

      expectSameHyphenation(text, compileAndLoad(text), [
        'abcd',
        '1abcd',
        'xbcdx',
        'aébcd',
        'éfébcéf',
        'x\u{1F600}x',
        'zzz',
        '',
      ]);
    });

    test('dictionaries with more than 256 characters', () {
      // Edge labels take two bytes then.
      final chars = [for (var c = 0x100; c < 0x100 + 300; ++c) c];
      final text = DictParser().parseLines([
        for (final c in chars) 'a1${String.fromCharCode(c)}',
      ], isUtf8: true);

      expectSameHyphenation(text, compileAndLoad(text), [
        'xa${String.fromCharCodes(chars.take(40))}',
        String.fromCharCodes([
          for (final c in chars) ...[0x61, c],
        ]),
      ]);
    });

    test('keeps non-standard hyphenation and the next level', () {
      // libhyphen's compound3 test
      final text = DictParser().parseLines([
        'wat1time/tt=t,3,2',
        '.kilo1watt.',
        'NEXTLEVEL',
        '.ki1lo.',
        '.ti1me.',
      ], isUtf8: false);

      final compiled = compileAndLoad(text);

      expect(
        const Hyphenator().hyphenate(compiled, 'kilowattime').hyphword,
        'ki=lo=watt=ti=me',
      );
    });

    test('keeps the settings of both levels', () {
      final compiled = compileAndLoad(
        DictParser().parseLines([
          'LEFTHYPHENMIN 3',
          'RIGHTHYPHENMIN 4',
          'NOHYPHEN ab,,cd',
          'a1b',
        ], isUtf8: true),
      );

      expect(compiled.leftHyphenMin, 3);
      expect(compiled.rightHyphenMin, 4);
      expect(compiled.compoundLeftHyphenMin, 3);
      expect(compiled.compoundRightHyphenMin, 4);
      expect(compiled.noHyphenWords, ["'", '\u2013', '\u2019', '-']);
      expect(compiled.nextLevel!.noHyphenWords, ['ab', '', 'cd']);
      expect(compiled.nextLevel!.nextLevel, isNull);
    });

    test('keeps numbers of up to 32 bits', () {
      final compiled = compileAndLoad(
        DictParser().parseLines([
          'LEFTHYPHENMIN 2147483647',
          'RIGHTHYPHENMIN -2147483648',
          'a1b',
        ], isUtf8: false),
      );

      expect(compiled.leftHyphenMin, 2147483647);
      expect(compiled.rightHyphenMin, -2147483648);
    });

    test('rejects numbers beyond 32 bits', () {
      for (final line in [
        'LEFTHYPHENMIN 2147483648',
        'RIGHTHYPHENMIN -2147483649',
        'b1c/b=c,1,2147483648',
      ]) {
        final dict = DictParser().parseLines([line, 'a1b'], isUtf8: false);

        expect(
          () => const DictCompiler().compile(dict),
          throwsArgumentError,
          reason: line,
        );
      }
    });

    test('rejects levels with more than 65536 characters', () {
      // Beyond the Basic Multilingual Plane, to have enough of them
      final dict = DictParser().parseLines([
        for (var c = 0x10000; c <= 0x20000; ++c) '${String.fromCharCode(c)}1',
      ], isUtf8: true);

      expect(() => const DictCompiler().compile(dict), throwsArgumentError);
    });

    test('format version 1 stays the same', () {
      final dict = DictParser().parseLines([
        'LEFTHYPHENMIN 1',
        'NOHYPHEN xy',
        'a1b',
        'ab3c',
        'b1c/b=c,1,1',
      ], isUtf8: false);

      // Already compiled files must keep loading: a change here needs a new
      // format version.
      expect(const DictCompiler().compile(dict), [
        0x89, 0x48, 0x59, 0x42, 0x01, 0x02, 0x02, 0x00, 0x02, 0x06, 0x02, //
        0x01, 0x27, 0x01, 0x2d, 0x03, 0x02, 0x27, 0x2d, 0x03, 0x00, 0x01,
        0x01, 0x02, 0x11, 0x00, 0x01, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x01, 0x02, 0x78, 0x79, 0x06, 0x03, 0x61, 0x62, 0x63, 0xab, 0x00,
        0x00, 0x01, 0x01, 0x02, 0x02, 0x03, 0x03, 0x10, 0x00, 0x02, 0x01,
        0x02, 0x03, 0x00, 0x00, 0x00, 0x02, 0x01, 0x03, 0x01, 0x04, 0x03,
        0x62, 0x3d, 0x63, 0x00, 0x02,
      ]);
    });
  });

  group('DictParser.parseBytes', () {
    final compiled = const DictCompiler().compile(
      DictParser().parseLines(['a1b'], isUtf8: false),
    );

    test('reads compiled and libhyphen dictionaries', () {
      final text = DictParser().parseBytes(
        Uint8List.fromList('ISO8859-1\na1b\n'.codeUnits),
      );

      expectSameHyphenation(text, DictParser().parseBytes(compiled), ['abab']);
    });

    test('rejects an unsupported format version', () {
      final bytes = Uint8List.fromList(compiled)..[4] = 2;

      expect(() => DictParser().parseBytes(bytes), throwsFormatException);
    });

    test('rejects a truncated compiled dictionary', () {
      for (var length = 4; length < compiled.length; ++length) {
        expect(
          () => DictParser().parseBytes(
            Uint8List.sublistView(compiled, 0, length),
          ),
          throwsFormatException,
          reason: 'length $length',
        );
      }
    });

    test('rejects a malformed compiled dictionary', () {
      // One level with the pattern a1, part by part
      Uint8List compiled({
        List<int> minimums = const [0x04, 0x04, 0x04, 0x04], // 2, zigzag
        List<int> alphabet = const [0x02, 0x01, 0x61], // 2 states; a
        List<int> trie = const [0x01, 0x00], // root: 1 0, a: 0; a's label
        List<int> vectors = const [0x01, 0x02, 0x10], // one: 0 1
        List<int> vectorOf = const [0x00, 0x01], // per state
      }) => Uint8List.fromList([
        ...[0x89, 0x48, 0x59, 0x42, 0x01, 0x01], // magic, version, a level
        ...minimums,
        0x00, // no NOHYPHEN
        ...alphabet,
        ...trie,
        ...vectors,
        ...vectorOf,
        0x00, // no replacements
      ]);
      String hyphenate(Uint8List bytes, String word) => const Hyphenator()
          .hyphenate(DictParser().parseBytes(bytes), word)
          .hyphword;

      // The patterns a1 and b1, with the labels of the root's children
      Uint8List twoChildren(
        List<int> labels, {
        List<int> alphabet = const [0x61, 0x62], // a, b
      }) => compiled(
        alphabet: [0x03, 0x02, ...alphabet], // 3 states
        trie: [0x03, ...labels], // root: 1 1 0, a: 0, b: 0
        vectorOf: [0x00, 0x01, 0x01],
      );

      // The parts are right
      expect(hyphenate(compiled(), 'aaaa'), 'aa=aa');
      expect(hyphenate(twoChildren([0x00, 0x01]), 'abab'), 'ab=ab');

      final malformed = {
        'a character beyond Unicode': compiled(
          alphabet: [0x02, 0x01, 0x80, 0x80, 0x44],
        ),
        'a number of 2^32': compiled(
          minimums: [0x80, 0x80, 0x80, 0x80, 0x10, 0x04, 0x04, 0x04],
        ),
        'an alphabet out of order': twoChildren(
          [0x00, 0x01],
          alphabet: [0x62, 0x61],
        ),
        'a character twice in the alphabet': twoChildren(
          [0x00, 0x01],
          alphabet: [0x61, 0x61],
        ),
        'a state the root does not reach': compiled(trie: [0x02, 0x00]),
        // The next byte, 1, would pass for the label of b
        'more edges than states': compiled(
          alphabet: [0x02, 0x02, 0x61, 0x62],
          trie: [0x03, 0x00],
        ),
        'children with the same character': twoChildren([0x00, 0x00]),
        'children out of order': twoChildren([0x01, 0x00]),
        'a digit above 9': compiled(vectors: [0x01, 0x02, 0xA0]),
      };
      malformed.forEach((reason, bytes) {
        expect(
          () => DictParser().parseBytes(bytes),
          throwsFormatException,
          reason: reason,
        );
      });
    });
  });
}
