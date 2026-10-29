@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:hyphen_dart/src/compiled_dict.dart';
import 'package:hyphen_dart/src/hyphenator.dart';
import 'package:hyphen_dart/src/model/dict.dart';
import 'package:hyphen_dart/src/model/result.dart';
import 'package:hyphen_dart/src/parser/dict_parser.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final root = 'third_party/hyphen/tests';

  final files = Directory(root)
      .listSync(recursive: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.pat'));
  final names = files.map((e) => basenameWithoutExtension(e.path)).toList();

  final encodings = await Future.wait(
    names.map((name) {
      final dictFile = File(join(root, '$name.pat'));
      return _extractEncoding(dictFile);
    }),
  );

  group('Hyphenation tests', () {
    for (var i = 0; i < names.length; ++i) {
      final encoding = encodings[i];
      final name = names[i];

      final dictFile = File(join(root, '$name.pat'));
      final wordFile = File(join(root, '$name.word'));
      final hyphFile = File(join(root, '$name.hyph'));

      for (final compiled in [false, true]) {
        group(compiled ? '$name (compiled)' : name, () {
          late HyphenDict dict;
          late Hyphenator hyphenator;

          setUpAll(() async {
            final dictFileBytes = await dictFile.readAsBytes();
            dict = DictParser().parseBytes(dictFileBytes);
            if (compiled) {
              dict = DictParser().parseBytes(
                const DictCompiler().compile(dict),
              );
            }
            hyphenator = const Hyphenator();
          });

          final input = const LineSplitter().convert(
            wordFile.readAsStringSync(encoding: encoding),
          );
          final expected = const LineSplitter().convert(
            hyphFile.readAsStringSync(encoding: encoding),
          );

          for (var index = 0; index < input.length; ++index) {
            final inputWord = input[index];
            test('Hyphenating $inputWord', () {
              final actual = hyphenator.hyphenate(dict, inputWord);
              final expectedWord = expected[index];
              expect(actual.hyphword, expectedWord);
              expect(_hyphwordFromBreaks(inputWord, actual), expectedWord);
            });
          }
        });
      }
    }
  });
}

/// [HyphenResult.hyphword] built from the [HyphenResult.part]s between the
/// breaks the way libhyphen applies them: in order, leaving out the breaks
/// that cannot follow the one before, and cut at libhyphen's length limit.
String _hyphwordFromBreaks(String word, HyphenResult result) {
  final used = <HyphenBreak>[];
  for (final b in result.breaks) {
    if (used.isEmpty || b.canFollow(used.last)) used.add(b);
  }
  final parts = [
    for (var i = 0; i <= used.length; ++i)
      result.part(i > 0 ? used[i - 1] : null, i < used.length ? used[i] : null),
  ];
  return String.fromCharCodes(
    parts.join('=').runes.take(2 * word.runes.length - 1),
  );
}

/// The encoding is in the first line of the dict file
/// It is either "UTF-8" or "UTF8" for UTF-8, else it is Latin-1
Future<Encoding> _extractEncoding(File dictFile) async {
  // Efficiently read only the first line, cap at 20 bytes to avoid reading too much
  final line = await dictFile
      .openRead(0, 20)
      .transform(latin1.decoder)
      .transform(const LineSplitter())
      .first;

  final encoding = line.trim().toLowerCase();
  if (encoding == 'utf-8' || encoding == 'utf8') {
    return utf8;
  } else {
    return latin1;
  }
}
