import 'dart:convert';
import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';

class DictParser {
  /// Parses a list of lines into a [HyphenDict]
  HyphenDict parseLines(List<String> lines, {required bool isUtf8}) {
    var level = 0;
    final dictionaries = <_MutableDict>[];

    final linesLength = lines.length;
    var lineIndex = 0;

    for (var k = 0; k < 2; ++k) {
      _MutableDict dict = _MutableDict();
      dictionaries.add(dict);
      final stateMap = <String, int>{'': 0};

      if (k == 0 || level == 1) {
        lines:
        for (; lineIndex < linesLength; ++lineIndex) {
          // Remove trailing newlines and carriage returns
          final line = lines[lineIndex].replaceAll(RegExp(r'[\r\n]+$'), '');
          if (line.isEmpty || line.startsWith('#') || line.startsWith('%')) {
            continue; // Skip empty lines and comments
          }

          if (line.startsWith('LEFTHYPHENMIN')) {
            dict.leftHyphenMin = int.tryParse(line.substring(13).trim()) ?? 0;
          } else if (line.startsWith('RIGHTHYPHENMIN')) {
            dict.rightHyphenMin = int.tryParse(line.substring(14).trim()) ?? 0;
          } else if (line.startsWith('COMPOUNDLEFTHYPHENMIN')) {
            dict.compoundLeftHyphenMin =
                int.tryParse(line.substring(21).trim()) ?? 0;
          } else if (line.startsWith('COMPOUNDRIGHTHYPHENMIN')) {
            dict.compoundRightHyphenMin =
                int.tryParse(line.substring(22).trim()) ?? 0;
          } else if (line.startsWith('NOHYPHEN')) {
            dict.noHyphenWords
              ..clear()
              ..addAll(line.substring(8).trimLeft().split(','));
          } else if (line.startsWith('NEXTLEVEL')) {
            ++lineIndex;
            ++level;
            break lines;
          } else {
            _loadLine(line, dict, stateMap, isUtf8: isUtf8);
          }
        }
      } else {
        dict.noHyphenWords
          ..clear()
          ..addAll((isUtf8 ? "',\u2013,\u2019,-" : "',-").split(','));
        _loadLine('1-1', dict, stateMap, isUtf8: isUtf8);
        _loadLine("1'1", dict, stateMap, isUtf8: isUtf8);
        if (isUtf8) {
          _loadLine('1\u20131', dict, stateMap, isUtf8: isUtf8); // en-dash
          _loadLine('1\u20191', dict, stateMap, isUtf8: isUtf8); // right single quotation mark
        }
      }

      _buildFallbacks(dict, stateMap);
    }
    if (level == 1) {
      return dictionaries[0]..nextLevel = dictionaries[1];
    } else {
      final second = dictionaries[1];
      final first = dictionaries[0];
      second
        ..nextLevel = first
        ..leftHyphenMin = first.leftHyphenMin
        ..rightHyphenMin = first.rightHyphenMin
        ..compoundLeftHyphenMin = first.compoundLeftHyphenMin != 0
            ? first.compoundLeftHyphenMin
            : (first.leftHyphenMin != 0 ? first.leftHyphenMin : 3)
        ..compoundRightHyphenMin = first.compoundRightHyphenMin != 0
            ? first.compoundRightHyphenMin
            : (first.rightHyphenMin != 0 ? first.rightHyphenMin : 3);

      return second;
    }
  }

  /// Parses a byte array into a [HyphenDict], determining the encoding from the first line.
  /// Only UTF-8 and Latin-1 encodings are supported, with latin-1 being the fallback
  /// if the first line is not recognized as UTF-8 ("UTF-8" or "UTF8").
  HyphenDict parseBytes(Uint8List bytes) {
    // Extract the first line to get the encoding

    final firstNl = bytes.indexOf(0x0A);
    final firstLineBytes = firstNl >= 0 ? bytes.sublist(0, firstNl) : bytes;
    // latin1 is a safe "view" codec for any byte sequence.
    final firstLine = latin1.decode(firstLineBytes).trim().toLowerCase();

    final remainingBytes = Uint8List.view(bytes.buffer, firstNl + 1);

    final String content;
    final isUtf8 = firstLine == 'utf-8' || firstLine == 'utf8';
    if (isUtf8) {
      content = utf8.decode(remainingBytes);
    } else {
      content = latin1.decode(remainingBytes);
    }

    return parseLines(const LineSplitter().convert(content), isUtf8: isUtf8);
  }

  void _loadLine(
    String line,
    _MutableDict dict,
    Map<String, int> stateMap, {
    required bool isUtf8,
  }) {
    String? replacement;
    int replIndex = 0;
    int replCut = 0;

    final slashIdx = line.indexOf('/');
    if (slashIdx >= 0) {
      replacement = line.substring(slashIdx + 1).trim();
      line = line.substring(0, slashIdx).trim();
    }

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
    // Rebuild word string from codepoints so the state-map key is consistent.
    final word = String.fromCharCodes(wordCps);

    if (replacement != null) {
      final parts = replacement.split(',');
      if (parts.length == 1) {
        replIndex = 0;
        replCut = line.length;
      } else if (parts.length == 3) {
        replacement = parts[0].trim();
        replIndex = (int.tryParse(parts[1].trim()) ?? 1) - 1;
        replCut = int.tryParse(parts[2].trim()) ?? 0;
      } else {
        replacement = null; // Invalid replacement format, ignore it
      }
    }

    var patternStart = 0;
    if (replacement == null) {
      // Remove leading 0s from pattern
      while (patternStart < pattern.length && pattern[patternStart] == 0) {
        patternStart++;
      }
    } else {
      // When the pattern word starts with '.', skip one pattern slot (the
      // leading dot is not part of the hyphenation target, so the pattern
      // array is offset by 1).  Do NOT adjust replIndex: the 1-based values
      // from the file already count codepoints relative to the word-without-
      // dot, so replIndex (= file_value - 1) is already correct.
      if (word.startsWith('.')) {
        ++patternStart;
      }
    }

    final rawPattern = Uint8List(pattern.length - patternStart);
    rawPattern.setAll(0, pattern.skip(patternStart));

    final foundBefore = stateMap.containsKey(word);
    final stateNum = _getState(dict, stateMap, word);

    final state = dict._states[stateNum];

    state.match = rawPattern;
    state.replacement = replacement;
    state.replacementIndex = replIndex;
    // replacementCut is in codepoints
    state.replacementCut = replCut != 0 ? replCut : wordCps.length;

    // --- add prefix transitions for any newly created prefix states ---
    if (!foundBefore) {
      // The word was just inserted; walk back adding transitions keyed by
      // codepoint (not code unit), so that the hyphenator can step through
      // the trie one codepoint at a time.
      var lastState = stateNum;
      var wcps = List<int>.from(wordCps);
      while (wcps.isNotEmpty) {
        final ch = wcps.removeLast(); // last codepoint
        final prefixStr = String.fromCharCodes(wcps);
        final existedBefore = stateMap.containsKey(prefixStr);
        final prefixState = _getState(dict, stateMap, prefixStr);
        dict._states[prefixState].transitions.add(HyphenTrans(ch, lastState));
        if (existedBefore) {
          break; // prefix already existed
        }
        lastState = prefixState;
      }
    }
  }

  int _getState(_MutableDict dict, Map<String, int> stateMap, String key) {
    return stateMap.putIfAbsent(key, () {
      final index = dict._states.length;
      dict._states.add(_HypenState());
      return index;
    });
  }

  /// Build fallback (suffix) states for every entry in [hashtab].
  /// Keys in [hashtab] are built from codepoints, so we strip one codepoint
  /// at a time (not one code unit) when searching for the fallback state.
  void _buildFallbacks(_MutableDict dict, Map<String, int> hashtab) {
    for (final entry in hashtab.entries) {
      if (entry.key.isEmpty) {
        continue; // state 0 keeps fallback = -1
      }
      // Strip codepoints one at a time from the front until we find a match.
      final runes = entry.key.runes.toList();
      for (var j = 1; j <= runes.length; j++) {
        final suffix = String.fromCharCodes(runes.skip(j));
        final sn = hashtab[suffix];
        if (sn != null) {
          dict._states[entry.value].fallbackState = sn;
          break;
        }
      }
    }
  }
}

class _HypenState implements HyphenState {
  @override
   Uint8List? match;
  @override
  String? replacement;
  @override
  int replacementIndex = 0;
  @override
  int replacementCut = 0;
  @override
  int fallbackState = -1;

  @override
  final transitions = <HyphenTrans>[];
}

class _MutableDict implements HyphenDict {
  final _states = <_HypenState>[_HypenState()];
  @override
  final noHyphenWords = [];
  @override
  var leftHyphenMin = 0;
  @override
  var rightHyphenMin = 0;
  @override
  var compoundLeftHyphenMin = 0;
  @override
  var compoundRightHyphenMin = 0;

  @override
  _MutableDict? nextLevel;

  @override
  List<HyphenState> get states => _states;
}
