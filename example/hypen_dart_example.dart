import 'package:hypen_dart/hypen_dart.dart';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    print('Usage: dart hypen_dart_example.dart <hyphen dict file> <word>');
    exit(-1);
  }
  final dictFile = File(args[0]);
  if (!dictFile.existsSync()) {
    print('File not found: ${args[0]}');
    exit(-1);
  }

  final dictBytes = dictFile.readAsBytesSync();
  final dict = DictParser().parseBytes(dictBytes);

  const hyphenator = Hyphenator();
  final word = args[1];
  final res = hyphenator.hyphenate(dict, word);

  print(res.hyphword);
}
