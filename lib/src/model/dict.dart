import 'dart:typed_data';

abstract class HyphenDict {
  int get leftHyphenMin;

  int get rightHyphenMin;

  int get compoundLeftHyphenMin;

  int get compoundRightHyphenMin;

  /// Forbidden hyphenation sequences.
  List<String> get noHyphenWords;

  List<HyphenState> get states;

  HyphenDict? get nextLevel;
}

abstract class HyphenState {
  /// The digit-pattern string stored as numeric values 0-9.
  Uint8List? get match;

  String? get replacement;

  int get replacementIndex;

  int get replacementCut;

  int get fallbackState;

  List<HyphenTrans> get transitions;
}

class HyphenTrans {
  final int ch; // transition character code unit
  final int newState;

  const HyphenTrans(this.ch, this.newState);
}
