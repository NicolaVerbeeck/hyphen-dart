import 'dart:io';

import 'package:hypen_dart/hypen_dart.dart';

/// Compiles a libhyphen dictionary into the format of [DictCompiler], which
/// DictParser.parseBytes loads several times faster.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run hypen_dart:compile_dict <dictionary.dic> <output.hyb>',
    );
    exit(64);
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exit(66);
  }

  final source = input.readAsBytesSync();
  final compiled = const DictCompiler().compile(
    DictParser().parseBytes(source),
  );
  File(args[1]).writeAsBytesSync(compiled);

  stdout.writeln(
    '${args[1]}: ${compiled.length} bytes (${args[0]}: ${source.length} bytes)',
  );
}
