import 'dart:typed_data';

import 'package:hypen_dart/hypen_dart.dart';
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
      expect(compiled.noHyphenWords, ["'", '–', '’', '-']);
      expect(compiled.nextLevel!.noHyphenWords, ['ab', '', 'cd']);
      expect(compiled.nextLevel!.nextLevel, isNull);
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
  });
}
