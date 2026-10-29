import 'dart:typed_data';

import 'package:hyphen_dart/src/model/automaton.dart';
import 'package:meta/meta.dart';

/// A parsed hyphenation dictionary.
///
/// As in libhyphen, a dictionary has two pattern levels: this one and
/// [nextLevel]. The breaks this level finds are compound boundaries; the word,
/// or each part of it between boundaries, is then hyphenated with [nextLevel].
final class HyphenDict {
  @internal
  HyphenDict({
    required this.patterns,
    required this.leftHyphenMin,
    required this.rightHyphenMin,
    required this.compoundLeftHyphenMin,
    required this.compoundRightHyphenMin,
    required List<String> noHyphenWords,
    required this.nextLevel,
  }) : noHyphenWords = List.unmodifiable(noHyphenWords),
       noHyphenRunes = List.unmodifiable([
         for (final word in noHyphenWords)
           if (word.isNotEmpty) Int32List.fromList(word.runes.toList()),
       ]);

  final int leftHyphenMin;

  final int rightHyphenMin;

  final int compoundLeftHyphenMin;

  final int compoundRightHyphenMin;

  /// Forbidden hyphenation sequences.
  final List<String> noHyphenWords;

  final HyphenDict? nextLevel;

  /// The patterns of this level.
  @internal
  final PatternAutomaton patterns;

  /// [noHyphenWords] as code points, without the empty ones.
  @internal
  final List<Int32List> noHyphenRunes;
}
