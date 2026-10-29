import 'dart:convert';
import 'dart:typed_data';

import 'package:hypen_dart/src/compiled_dict.dart';
import 'package:hypen_dart/src/model/automaton.dart';
import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/parser/automaton_builder.dart';

class DictParser {
  /// Parses a list of lines into a [HyphenDict]
  HyphenDict parseLines(List<String> lines, {required bool isUtf8}) =>
      _parse(_ListLines(lines), isUtf8: isUtf8);

  /// Parses a byte array into a [HyphenDict]: a libhyphen dictionary, or one
  /// compiled by [DictCompiler], which is recognized by its first bytes.
  ///
  /// A libhyphen dictionary names its encoding on the first line. Only UTF-8
  /// and Latin-1 encodings are supported, with latin-1 being the fallback if
  /// the first line is not recognized as UTF-8 ("UTF-8" or "UTF8").
  HyphenDict parseBytes(Uint8List bytes) {
    if (isCompiledDict(bytes)) {
      return loadCompiledDict(bytes);
    }

    // Extract the first line to get the encoding

    final firstNl = bytes.indexOf(0x0A);
    final firstLineBytes = firstNl >= 0 ? bytes.sublist(0, firstNl) : bytes;
    // latin1 is a safe "view" codec for any byte sequence.
    final firstLine = latin1.decode(firstLineBytes).trim().toLowerCase();

    final remainingBytes = Uint8List.sublistView(bytes, firstNl + 1);

    final String content;
    final isUtf8 = firstLine == 'utf-8' || firstLine == 'utf8';
    if (isUtf8) {
      content = utf8.decode(remainingBytes);
    } else {
      content = latin1.decode(remainingBytes);
    }

    return _parse(_TextLines(content), isUtf8: isUtf8);
  }

  HyphenDict _parse(_Lines lines, {required bool isUtf8}) {
    var level = 0;
    final dictionaries = <_LevelBuilder>[];

    for (var k = 0; k < 2; ++k) {
      final dict = _LevelBuilder();
      dictionaries.add(dict);

      if (k == 0 || level == 1) {
        while (lines.moveNext()) {
          final text = lines.text;
          final start = lines.start;
          final end = lines.end;
          if (start == end) {
            continue; // Skip empty lines
          }
          final first = text.codeUnitAt(start);
          if (first == 0x23 /* '#' */ || first == 0x25 /* '%' */ ) {
            continue; // Skip comments
          }

          // Keywords start with an upper case letter.
          if (first >= 0x41 /* 'A' */ && first <= 0x5A /* 'Z' */ ) {
            final line = text.substring(start, end);
            if (line.startsWith('LEFTHYPHENMIN')) {
              dict.leftHyphenMin = int.tryParse(line.substring(13).trim()) ?? 0;
              continue;
            } else if (line.startsWith('RIGHTHYPHENMIN')) {
              dict.rightHyphenMin =
                  int.tryParse(line.substring(14).trim()) ?? 0;
              continue;
            } else if (line.startsWith('COMPOUNDLEFTHYPHENMIN')) {
              dict.compoundLeftHyphenMin =
                  int.tryParse(line.substring(21).trim()) ?? 0;
              continue;
            } else if (line.startsWith('COMPOUNDRIGHTHYPHENMIN')) {
              dict.compoundRightHyphenMin =
                  int.tryParse(line.substring(22).trim()) ?? 0;
              continue;
            } else if (line.startsWith('NOHYPHEN')) {
              dict.noHyphenWords
                ..clear()
                ..addAll(line.substring(8).trimLeft().split(','));
              continue;
            } else if (line.startsWith('NEXTLEVEL')) {
              ++level;
              break;
            }
          }

          if (_contains(text, start, end, 0x2F /* '/' */)) {
            dict.loadReplacementLine(text.substring(start, end));
          } else {
            dict.loadPattern(text, start, end);
          }
        }
      } else {
        dict.noHyphenWords.addAll(
          (isUtf8 ? "',\u2013,\u2019,-" : "',-").split(','),
        );
        for (final pattern in [
          '1-1',
          "1'1",
          if (isUtf8) ...[
            '1\u20131', // en-dash
            '1\u20191', // right single quotation mark
          ],
        ]) {
          dict.loadPattern(pattern, 0, pattern.length);
        }
      }
    }
    if (level == 1) {
      return dictionaries[0].build(nextLevel: dictionaries[1].build());
    } else {
      final first = dictionaries[0].build();
      return (dictionaries[1]
            ..leftHyphenMin = first.leftHyphenMin
            ..rightHyphenMin = first.rightHyphenMin
            ..compoundLeftHyphenMin = first.compoundLeftHyphenMin != 0
                ? first.compoundLeftHyphenMin
                : (first.leftHyphenMin != 0 ? first.leftHyphenMin : 3)
            ..compoundRightHyphenMin = first.compoundRightHyphenMin != 0
                ? first.compoundRightHyphenMin
                : (first.rightHyphenMin != 0 ? first.rightHyphenMin : 3))
          .build(nextLevel: first);
    }
  }

  static bool _contains(String text, int start, int end, int char) {
    for (var i = start; i < end; ++i) {
      if (text.codeUnitAt(i) == char) return true;
    }
    return false;
  }
}

/// Builds the trie of one level while its lines are read.
class _LevelBuilder {
  _LevelBuilder() {
    _addState(-1, 0); // The root
  }

  int leftHyphenMin = 0;
  int rightHyphenMin = 0;
  int compoundLeftHyphenMin = 0;
  int compoundRightHyphenMin = 0;
  final noHyphenWords = <String>[];

  // Per state: the parent, the character from the parent and the pattern.
  final _parent = _IntBuffer();
  final _char = _IntBuffer();
  final _matchStart = _IntBuffer();
  final _matchLen = _IntBuffer();
  final _matchData = _ByteBuffer();
  _IntBuffer? _replacementOf;
  final _replacements = <Replacement>[];
  final _children = _ChildMap();

  // The word and the digits (one more than characters) of a pattern line.
  var _word = Int32List(64);
  var _digits = Uint8List(65);

  int _addState(int parent, int char) {
    _parent.add(parent);
    _char.add(char);
    _matchStart.add(-1);
    _matchLen.add(0);
    _replacementOf?.add(-1);
    return _parent.length - 1;
  }

  int _child(int state, int char) {
    final child = _children.get(state, char);
    if (child >= 0) return child;
    final added = _addState(state, char);
    _children.put(state, char, added);
    return added;
  }

  void _setPattern(
    int state,
    List<int> digits,
    int from,
    int to,
    Replacement? replacement,
  ) {
    _matchStart[state] = _matchData.length;
    _matchLen[state] = to - from;
    for (var i = from; i < to; ++i) {
      _matchData.add(digits[i]);
    }
    if (replacement != null) {
      _replacementOf ??= _IntBuffer(_parent.length, -1);
      _replacements.add(replacement);
      _replacementOf![state] = _replacements.length - 1;
    } else {
      _replacementOf?[state] = -1;
    }
  }

  /// A pattern line without a replacement, read from [text] in place.
  void loadPattern(String text, int start, int end) {
    if (_word.length < end - start) {
      _word = Int32List(2 * (end - start));
      _digits = Uint8List(2 * (end - start) + 1);
    }
    final word = _word;
    final digits = _digits;
    var length = 0;
    digits[0] = 0;
    for (var i = start; i < end; ++i) {
      var cp = text.codeUnitAt(i);
      // Iterate by codepoints, like String.runes
      if ((cp & 0xFC00) == 0xD800 &&
          i + 1 < end &&
          (text.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
        cp = 0x10000 + ((cp & 0x3FF) << 10) + (text.codeUnitAt(++i) & 0x3FF);
      }
      if (cp <= 0x20) {
        break; // Break on control/whitespace characters
      }
      if (cp >= charZero && cp <= 0x39) {
        // Digit: store as pattern value at current word-codepoint position
        digits[length] = cp - charZero;
      } else {
        word[length++] = cp;
        digits[length] = 0;
      }
    }
    // Remove leading 0s from pattern
    var from = 0;
    while (from <= length && digits[from] == 0) {
      from++;
    }
    var state = 0;
    for (var i = 0; i < length; ++i) {
      state = _child(state, word[i]);
    }
    _setPattern(state, digits, from, length + 1, null);
  }

  /// A pattern line with a replacement after a '/' (non-standard
  /// hyphenation).
  void loadReplacementLine(String line) {
    final slashIdx = line.indexOf('/');
    var replacement = line.substring(slashIdx + 1).trim();
    line = line.substring(0, slashIdx).trim();

    // Build word as a list of codepoints and pattern as digit values.
    // We iterate by codepoints so that supplementary characters (surrogate
    // pairs in UTF-16) are treated as a single unit, matching what the
    // codepoint-based hyphenator expects.
    final wordCps = <int>[]; // codepoints of the word
    final pattern = <int>[0]; // one slot per codepoint position in word
    for (final cp in line.runes) {
      if (cp <= 0x20) {
        break; // Break on control/whitespace characters
      }
      if (cp >= charZero && cp <= 0x39) {
        // Digit: store as pattern value at current word-codepoint position
        pattern[wordCps.length] = cp - charZero;
      } else {
        wordCps.add(cp);
        pattern.add(0);
      }
    }

    // As in libhyphen: "text" replaces the whole pattern, "text,index" ignores
    // the index and "text,index,cut" ignores anything after the cut.
    var replIndex = 0;
    var replCut = 0;
    final parts = replacement.split(',');
    if (parts.length == 1) {
      replCut = line.length;
    } else {
      replacement = parts[0].trim();
      if (parts.length >= 3) {
        replIndex = (int.tryParse(parts[1].trim()) ?? 1) - 1;
        replCut = int.tryParse(parts[2].trim()) ?? 0;
      }
    }

    // When the pattern word starts with '.', skip one pattern slot (the
    // leading dot is not part of the hyphenation target, so the pattern
    // array is offset by 1).  Do NOT adjust replIndex: the 1-based values
    // from the file already count codepoints relative to the word-without-
    // dot, so replIndex (= file_value - 1) is already correct.
    final patternStart = wordCps.isNotEmpty && wordCps.first == charDot ? 1 : 0;

    var state = 0;
    for (final cp in wordCps) {
      state = _child(state, cp);
    }
    _setPattern(
      state,
      pattern,
      patternStart,
      pattern.length,
      Replacement(
        replacement,
        replIndex,
        // replacementCut is in codepoints
        replCut != 0 ? replCut : wordCps.length,
      ),
    );
  }

  HyphenDict build({HyphenDict? nextLevel}) {
    final count = _parent.length;
    final parent = _parent.toList();
    final chars = _char.toList();

    // Transitions, grouped by state
    final transStart = Int32List(count + 1);
    for (var s = 1; s < count; ++s) {
      ++transStart[parent[s] + 1];
    }
    for (var s = 0; s < count; ++s) {
      transStart[s + 1] += transStart[s];
    }
    final transChar = Int32List(count - 1);
    final transTarget = Int32List(count - 1);
    final next = Int32List.fromList(transStart);
    for (var s = 1; s < count; ++s) {
      final t = next[parent[s]]++;
      transChar[t] = chars[s];
      transTarget[t] = s;
    }

    // The states by depth
    final depth = Int32List(count);
    var maxDepth = 0;
    for (var s = 1; s < count; ++s) {
      depth[s] = depth[parent[s]] + 1;
      if (depth[s] > maxDepth) maxDepth = depth[s];
    }
    final depthStart = Int32List(maxDepth + 2);
    for (var s = 0; s < count; ++s) {
      ++depthStart[depth[s] + 1];
    }
    for (var d = 0; d <= maxDepth; ++d) {
      depthStart[d + 1] += depthStart[d];
    }
    final byDepth = Int32List(count);
    for (var s = 0; s < count; ++s) {
      byDepth[depthStart[depth[s]]++] = s;
    }

    return HyphenDict(
      patterns: completeAutomaton(
        transStart: transStart,
        transChar: transChar,
        transTarget: transTarget,
        byDepth: byDepth,
        matchStart: _matchStart.toList(),
        matchLen: _matchLen.toList(),
        matchData: _matchData.toList(),
        replacementOf: _replacementOf?.toList(),
        replacements: List.unmodifiable(_replacements),
      ),
      leftHyphenMin: leftHyphenMin,
      rightHyphenMin: rightHyphenMin,
      compoundLeftHyphenMin: compoundLeftHyphenMin,
      compoundRightHyphenMin: compoundRightHyphenMin,
      noHyphenWords: noHyphenWords,
      nextLevel: nextLevel,
    );
  }
}

/// The lines of a dictionary: [text] from [start] up to [end].
abstract interface class _Lines {
  String get text;

  int get start;

  int get end;

  bool moveNext();
}

/// Lines given as strings.
class _ListLines implements _Lines {
  _ListLines(this._lines);

  final List<String> _lines;
  var _index = -1;

  @override
  var text = '';

  @override
  int get start => 0;

  @override
  var end = 0;

  @override
  bool moveNext() {
    if (++_index >= _lines.length) return false;
    text = _lines[_index];
    // Remove trailing newlines and carriage returns
    end = text.length;
    while (end > 0 &&
        (text.codeUnitAt(end - 1) == 0x0A ||
            text.codeUnitAt(end - 1) == 0x0D)) {
      --end;
    }
    return true;
  }
}

/// The lines of a text, split where LineSplitter splits: at "\n", "\r\n" and
/// "\r".
class _TextLines implements _Lines {
  _TextLines(this.text);

  @override
  final String text;

  var _next = 0;

  @override
  var start = 0;

  @override
  var end = 0;

  @override
  bool moveNext() {
    if (_next >= text.length) return false;
    start = _next;
    end = start;
    while (end < text.length &&
        text.codeUnitAt(end) != 0x0A &&
        text.codeUnitAt(end) != 0x0D) {
      ++end;
    }
    _next = end + 1;
    if (_next < text.length &&
        text.codeUnitAt(end) == 0x0D &&
        text.codeUnitAt(_next) == 0x0A) {
      ++_next;
    }
    return true;
  }
}

/// A growable list of ints in an [Int32List].
class _IntBuffer {
  /// A buffer of [length] times [value].
  _IntBuffer([this.length = 0, int value = 0])
    : _data = Int32List(length < 256 ? 256 : length)
        ..fillRange(0, length, value);

  Int32List _data;
  int length;

  void operator []=(int index, int value) => _data[index] = value;

  void add(int value) {
    if (length == _data.length) {
      _data = Int32List(2 * length)..setRange(0, length, _data);
    }
    _data[length++] = value;
  }

  Int32List toList() => _data.sublist(0, length);
}

/// A growable list of bytes in a [Uint8List].
class _ByteBuffer {
  var _data = Uint8List(1024);
  var length = 0;

  void add(int value) {
    if (length == _data.length) {
      _data = Uint8List(2 * length)..setRange(0, length, _data);
    }
    _data[length++] = value;
  }

  Uint8List toList() => _data.sublist(0, length);
}

/// The children of the trie states while it is built: (state, character) to
/// child state, by open addressing.
class _ChildMap {
  var _states = Int32List(1024);
  var _chars = Int32List(1024);
  var _children = Int32List(1024); // 0: free, the root is nobody's child
  var _size = 0;

  /// The child of [state] for [char], or -1.
  int get(int state, int char) {
    final mask = _children.length - 1;
    for (var i = _hash(state, char) & mask; ; i = (i + 1) & mask) {
      final child = _children[i];
      if (child == 0) return -1;
      if (_states[i] == state && _chars[i] == char) return child;
    }
  }

  void put(int state, int char, int child) {
    if (2 * (_size + 1) > _children.length) _grow();
    final mask = _children.length - 1;
    var i = _hash(state, char) & mask;
    while (_children[i] != 0) {
      i = (i + 1) & mask;
    }
    _states[i] = state;
    _chars[i] = char;
    _children[i] = child;
    ++_size;
  }

  void _grow() {
    final states = _states;
    final chars = _chars;
    final children = _children;
    _states = Int32List(2 * children.length);
    _chars = Int32List(2 * children.length);
    _children = Int32List(2 * children.length);
    _size = 0;
    for (var i = 0; i < children.length; ++i) {
      if (children[i] != 0) put(states[i], chars[i], children[i]);
    }
  }

  static int _hash(int state, int char) {
    final h = state * 0x45d9f3b ^ char * 0x119de1f3;
    return h ^ (h >> 15);
  }
}
