import 'dart:typed_data';

/// Characters below this have their alphabet class in
/// [PatternAutomaton.classLow].
const classLowLimit = 0x800;

/// The patterns of one dictionary level, compiled into flat arrays.
///
/// The states are the prefixes of the pattern words (a trie). Each state has a
/// fallback state: the longest proper suffix of its string that is also a
/// state. Together this is the Aho-Corasick automaton libhyphen builds.
final class PatternAutomaton {
  PatternAutomaton({
    required this.transStart,
    required this.transChar,
    required this.transTarget,
    required this.fallback,
    required this.classLow,
    required this.classHigh,
    required this.alphabetSize,
    required this.rowOf,
    required this.rows,
    required this.matchStart,
    required this.matchLen,
    required this.matchData,
    required this.replacementOf,
    required this.replacements,
  });

  /// The transitions of state `s` are at `transStart[s]` up to
  /// `transStart[s + 1]` in [transChar] and [transTarget].
  final Int32List transStart;
  final Int32List transChar;
  final Int32List transTarget;

  /// The fallback state of each state, -1 for the root.
  final Int32List fallback;

  /// Alphabet class of the characters below [classLowLimit], -1 when no
  /// transition uses the character.
  final Int32List classLow;

  /// Alphabet class of the other characters that a transition uses.
  final Map<int, int> classHigh;

  final int alphabetSize;

  /// Row in [rows] of the states with many transitions, -1 for the others.
  final Int32List rowOf;

  /// `rows[row * alphabetSize + class]` is the state reached from the row's
  /// state, following fallbacks where needed, or -1 when they run out.
  final Int32List rows;

  /// The pattern digits of state `s` are the `matchLen[s]` values of
  /// [matchData] from `matchStart[s]`, which is -1 when no pattern ends in `s`.
  final Int32List matchStart;
  final Int32List matchLen;
  final Uint8List matchData;

  /// Index in [replacements] of the non-standard hyphenation of each state,
  /// -1 for none. Null when no pattern of the level has one.
  final Int32List? replacementOf;
  final List<Replacement> replacements;
}

/// The non-standard hyphenation of a pattern, e.g. `tt=t,3,2` of
/// `wat1time/tt=t,3,2`.
final class Replacement {
  const Replacement(this.text, this.index, this.cut);

  final String text;

  /// First character of the pattern that the replacement replaces.
  final int index;

  /// Number of characters it replaces.
  final int cut;
}
