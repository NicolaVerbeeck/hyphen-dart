import 'dart:convert';
import 'dart:io';

import 'package:hypen_dart/src/hyphenator_manual.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/parser/dict_parser.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final files = Directory('test/data')
      .listSync(recursive: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.pat'));
  final names = files.map((e) => basenameWithoutExtension(e.path)).toList();

  final encodings = await Future.wait(
    names.map((name) {
      final dictFile = File('test/data/$name.pat');
      return _extractEncoding(dictFile);
    }),
  );

  group('Hyphenation tests', () {
    for (var i = 0; i < names.length; ++i) {
      final encoding = encodings[i];
      final name = names[i];

      final dictFile = File('test/data/$name.pat');
      final wordFile = File('test/data/$name.word');
      final hyphFile = File('test/data/$name.hyph');

      group(name, () {
        late HyphenDict dict;
        late HyphenatorManual hyphenator;

        setUpAll(() async {
          final dictFileBytes = await dictFile.readAsBytes();
          dict = DictParser().parseBytes(dictFileBytes);
          hyphenator = const HyphenatorManual();
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
          });
        }
      });
    }
  });
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
