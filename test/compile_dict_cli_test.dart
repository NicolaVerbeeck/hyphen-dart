@TestOn('vm')
library;

import 'dart:io';

import 'package:hyphen_dart/hyphen_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('compile_dict'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> compileDict(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/compile_dict.dart', ...args],
  );

  test('compiles a dictionary that parseBytes loads', () async {
    final source = File(
      '${temp.path}/hyph.dic',
    )..writeAsStringSync('ISO8859-1\nLEFTHYPHENMIN 1\nRIGHTHYPHENMIN 1\na1b\n');
    final output = File('${temp.path}/hyph.hyb');

    final result = await compileDict([source.path, output.path]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final dict = DictParser().parseBytes(output.readAsBytesSync());
    expect(const Hyphenator().hyphenate(dict, 'abab').hyphword, 'a=ba=b');
  });

  test('prints the usage without two arguments', () async {
    final result = await compileDict([]);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Usage'));
  });

  test('fails for a missing dictionary', () async {
    final result = await compileDict([
      '${temp.path}/missing.dic',
      '${temp.path}/missing.hyb',
    ]);

    expect(result.exitCode, 66);
    expect(result.stderr, contains('File not found'));
  });
}
