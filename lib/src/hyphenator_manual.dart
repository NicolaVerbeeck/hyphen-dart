import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/model/result.dart';

class HyphenatorManual {
  const HyphenatorManual();

  // Equivalent to the hnj_hyphen_hyphenate2 method
  HyphenResult hyphenate(HyphenDict dict, String word) {
    final runes = word.runes.toList();
    final hyphens = Uint8List(runes.length + 5);
    final rep = _Ref<List<String?>>();
    final pos = _Ref<List<int>>();
    final cut = _Ref<List<int>>();

    _hyphenate(
      dict,
      runes,
      hyphens,
      rep,
      pos,
      cut,
      dict.compoundLeftHyphenMin,
      dict.compoundRightHyphenMin,
      lend: true,
      rend: true,
    );
    _hypenLeftMin(
      runes,
      hyphens,
      rep,
      pos,
      cut,
      dict.leftHyphenMin > 0 ? dict.leftHyphenMin : 2,
    );
    _hypenRightMin(
      runes,
      hyphens,
      rep,
      pos,
      cut,
      dict.rightHyphenMin > 0 ? dict.rightHyphenMin : 2,
    );

    for (final noHyphen in dict.noHyphenWords) {
      if (noHyphen.isEmpty) continue;

      final noHyphenRunes = noHyphen.runes.toList();
      final noHyphenLength = noHyphenRunes.length;
      for (var start = 0; start <= runes.length - noHyphenLength; ++start) {
        if (_cpListMatch(runes, start, noHyphenRunes)) {
          // Zero the slot immediately before the sequence (idx-1)
          final before = start - 1;
          if (before >= 0) hyphens[before] = 0;
          final end = start + noHyphenLength - 1;
          if (end < hyphens.length) hyphens[end] = 0;
        }
      }
    }

    final hyphenated = _hyphWord(runes, hyphens, rep, pos, cut);

    final hyphenPositions = <int>[];
    for (var i = 0; i < hyphens.length; ++i) {
      if (hyphens[i].isOdd) {
        hyphenPositions.add(i);
      }
    }
    return HyphenResult(hyphens: hyphenPositions, hyphword: hyphenated);
  }

  void _hypenLeftMin(
    List<int> word,
    Uint8List hyphens,
    _Ref<List<String?>> rep,
    _Ref<List<int>> pos,
    _Ref<List<int>> cut,
    int lhmin,
  ) {
    var i = 1;
    var j = 0;

    // Skip numbers at the start of the word
    // j tracks index in 'word', i tracks legitimate character count
    for (; j < word.length; ++j) {
      final char = word[j];
      if (char <= 57 /* '9' */ && char >= 48 /* '0' */ ) {
        --i;
      } else {
        break;
      }
    }

    // Iterate through the "forbidden zone" (lhmin)
    for (j = 0; i < lhmin && j < word.length; ++i, ++j) {
      if (word[j] == 0) break; // Honor null-terminator if present

      bool isAllowed = false;

      // Check if a non-standard replacement exists at this position
      if (rep.value != null && rep.value![j] != null && pos.value != null) {
        final replacement = rep.value![j]!;
        final rhIndex = replacement.indexOf('=');

        if (rhIndex >= 0) {
          // Calculate effective length of the left part
          // 1. Length of word stem before the replacement
          final prefixLen = word.stringLength(n: j - pos.value![j] + 1);
          // 2. Length of the replacement string before the hyphen (using runes)
          final replLen = replacement.substring(0, rhIndex).runes.length;

          if ((prefixLen + replLen) >= lhmin) {
            isAllowed = true;
          }
        }
      } else {
        hyphens[j] = 0;
      }

      if (!isAllowed) {
        hyphens[j] = 0;
        // If we invalidate the hyphen, we must also clear the replacement
        if (rep.value != null) {
          rep.value![j] = null;
        }
      }
    }
  }

  void _hypenRightMin(
    List<int> word,
    Uint8List hyphens,
    _Ref<List<String?>> rep,
    _Ref<List<int>> pos,
    _Ref<List<int>> cut,
    int rhmin,
  ) {
    var i = 0;
    var j = 0;

    // Skip numbers at the start of the word to align with indexing logic
    for (j = word.length - 1; j > 0; --j) {
      final char = word[j];
      if (char <= 57 /* '9' */ && char >= 48 /* '0' */ ) {
        --i; // Compensate for the increment that happens in the main loop logic if we were to unify
      } else {
        break;
      }
    }

    // Iterate through the rest of the word
    for (j = word.length - 1; i < rhmin && j > 0; --j, ++i) {
      if (word[j] == 0) break; // Honor null-terminator if present

      bool isAllowed = false;

      // Check if a non-standard replacement exists at this position
      if (rep.value != null && rep.value![j] != null && pos.value != null) {
        final replacement = rep.value![j]!;
        final rhIndex = replacement.indexOf('=');

        if (rhIndex >= 0) {
          final prefixLen = word.stringLength(
            n: 100,
            start: j - pos.value![j] + cut.value![j] + 1,
          );
          final replacementRunes = replacement.runes.toList();
          final replLen =
              replacementRunes.length -
              rhIndex -
              1; // Length of the replacement string after the hyphen

          if ((prefixLen + replLen) >= rhmin) {
            isAllowed = true;
          }
        }
      } else {
        hyphens[j] = 0;
      }
      if (!isAllowed) {
        hyphens[j] = 0;
        // If we invalidate the hyphen, we must also clear the replacement
        if (rep.value != null) {
          rep.value![j] = null;
        }
      }
    }
  }

  void _hyphenate(
    HyphenDict dict,
    List<int> word,
    Uint8List hyphens,
    _Ref<List<String?>> rep,
    _Ref<List<int>> pos,
    _Ref<List<int>> cut,
    int clhmin,
    int crhmin, {
    required bool lend,
    required bool rend,
  }) {
    final wordSize = word.length;

    final prepWord = _prepWord(word);
    final matchRepl = List<String?>.filled(wordSize + 2, null);
    final matchIndex = List<int>.filled(wordSize + 2, 0);
    final matchLength = List<int>.filled(wordSize + 2, 0);

    for (var i = 0; i < prepWord.length; ++i) {
      hyphens[i] = 0;
    }

    var state = 0;
    var isrepl = false;

    outer:
    for (var i = 0; i < prepWord.length; ++i) {
      final ch = prepWord[i];

      while (true) {
        if (state == -1) {
          state = 0;
          continue outer;
        }
        final hstate = dict.states[state];
        final trans = _findTransition(hstate, ch);
        if (trans != null) {
          state = trans.newState;
          break; // Breaks the infinite while
        }
        state = hstate.fallbackState;
      }

      final match = dict.states[state].match;
      final repl = dict.states[state].replacement;
      final replIndex = dict.states[state].replacementIndex;
      final replCut = dict.states[state].replacementCut;

      if (match != null) {
        final offset = i + 1 - match.length;
        if (repl != null) {
          if (!isrepl) {
            isrepl = true;
            for (var x = 0; x < wordSize; ++x) {
              matchRepl[x] = null;
              matchIndex[x] = -1;
            }
          }
          matchLength[offset + replIndex] = replCut;
        }
        for (var k = 0; k < match.length; ++k) {
          final mc = match[k];
          if (hyphens[offset + k] < mc) {
            hyphens[offset + k] = mc;
            if (mc.isOdd) {
              matchRepl[offset + k] = repl;
              if (repl != null &&
                  (k >= replIndex) &&
                  (k <= replIndex + replCut)) {
                matchIndex[offset + replIndex] = offset + k;
              }
            }
          }
        }
      }
    }
    assert(wordSize + 3 == prepWord.length);
    assert(hyphens.length > wordSize);

    for (var i = 0; i < wordSize; ++i) {
      hyphens[i] = hyphens[i + 1];
    }
    if (word.isNotEmpty) {
      // Avoid -1 index if word is empty
      hyphens[wordSize - 1] = 0;
    }
    hyphens[wordSize] = 0;

    if (isrepl) {
      rep.value ??= List.filled(wordSize, null);
      pos.value ??= List.filled(wordSize, 0);
      cut.value ??= List.filled(wordSize, 0);

      for (var i = 0; i < wordSize; i++) {
        final mi = matchIndex[i];
        if (mi >= 0 && mi < matchRepl.length && matchRepl[mi] != null) {
          rep.value![mi - 1] = matchRepl[mi];
          pos.value![mi - 1] = mi - i;
          cut.value![mi - 1] = matchLength[i];
          i += matchLength[i] - 1;
        }
      }
    }

    if (dict.nextLevel == null) {
      return;
    }
    final rep2 = _Ref<List<String?>>()..value = List.filled(wordSize, null);
    final pos2 = _Ref<List<int>>()..value = List.filled(wordSize, 0);
    final cut2 = _Ref<List<int>>()..value = List.filled(wordSize, 0);
    final hyphens2 = Uint8List(wordSize + 3);
    var begin = 0;

    for (var i = 0; i < wordSize; ++i) {
      final isCompoundBoundary =
          hyphens[i].isOdd || (begin > 0 && i + 1 == wordSize);
      if (!isCompoundBoundary) {
        continue;
      }
      if (i - begin > 0) {
        var hyph = 0;
        prepWord[i + 2] = 0;

        if (rep.value != null &&
            pos.value != null &&
            cut.value != null &&
            rep.value![i] != null) {
          final lIndex = rep.value![i]!.indexOf('=');
          final offset = 2 + i - pos.value![i];
          final count = prepWord.length - offset - 1;
          prepWord.setRange(offset, offset + count, rep.value![i]!.runes);
          if (lIndex >= 0) {
            hyph = lIndex - pos.value![i];
            prepWord[2 + i + hyph] = 0;
          }
        }
        final subStart = begin + 1;
        final subCount = i - begin + 1 + hyph;
        _hyphenate(
          dict,
          prepWord.sublist(subStart, subStart + subCount),
          hyphens2,
          rep2,
          pos2,
          cut2,
          clhmin,
          crhmin,
          lend: begin > 0 ? false : lend,
          rend: hyphens[i].isOdd ? false : rend,
        );
        for (var j = 0; j < i - begin; ++j) {
          hyphens[begin + j] = hyphens2[j];
          if (rep2.value != null && rep2.value![j] != null) {
            if (rep.value == null && pos.value == null && cut.value == null) {
              rep.value = List.filled(wordSize, null);
              pos.value = List.filled(wordSize, 0);
              cut.value = List.filled(wordSize, 0);
            }
            rep.value![begin + j] = rep2.value![j];
            pos.value![begin + j] = pos2.value![j];
            cut.value![begin + j] = cut2.value![j];
          }
        }
        prepWord[i + 2] = (i + 1 < wordSize) ? word[i + 1] : 0;
        if (rep.value != null &&
            pos.value != null &&
            cut.value != null &&
            rep.value![i] != null) {
          final offset = 1;
          final copyLen = word.length;
          prepWord.setRange(offset, offset + copyLen, word);
          prepWord.fillRange(offset + copyLen, prepWord.length, 0);
        }
      }
      begin = i + 1;
      for (var j = 0; j < wordSize; ++j) {
        rep2.value![j] = null;
      }
    }
    if (begin == 0) {
      _hyphenate(
        dict.nextLevel!,
        word,
        hyphens,
        rep,
        pos,
        cut,
        clhmin,
        crhmin,
        lend: lend,
        rend: rend,
      );
      if (!lend) _hypenLeftMin(word, hyphens, rep, pos, cut, clhmin);
      if (!rend) _hypenRightMin(word, hyphens, rep, pos, cut, crhmin);
    }
  }

  String _hyphWord(
    List<int> word,
    Uint8List hyphens,
    _Ref<List<String?>> rep,
    _Ref<List<int>> pos,
    _Ref<List<int>> cut,
  ) {
    if (word.isEmpty) {
      return '';
    }

    // Dynamic buffer to build the result
    final result = <int>[];

    // Check if replacement arrays have been allocated
    final hasReplacements =
        rep.value != null && pos.value != null && cut.value != null;

    // Define a maximum limit to provide c equivalence
    final maxLength = word.length * 2 - 1;

    for (var i = 0; i < word.length && result.length < maxLength; ++i) {
      // Always add the current character first
      result.add(word[i]);

      // If there is a hyphenation point here (odd value)
      if (hyphens[i].isOdd && result.length < maxLength) {
        if (hasReplacements && rep.value![i] != null) {
          // --- Non-standard Hyphenation ---
          final replacement = rep.value![i]!;
          final position = pos.value![i];
          final cutLength = cut.value![i];

          // 1. Backtrack: Remove 'position' characters from the end of the output buffer.
          //    This corresponds to 'j -= (*pos)[i]' in C.
          if (position > 0) {
            if (position <= result.length) {
              result.length -= position;
            } else {
              result.clear(); // Safety check
            }
          }

          // 2. Append replacement string (e.g., "k-k")
          // Check if we are not going over maxLength
          final replacementRunes = replacement.runes.toList();
          for (final rune in replacementRunes) {
            if (result.length < maxLength) {
              result.add(rune);
            } else {
              break; // Stop adding if we reach the maximum length
            }
          }

          // 3. Skip characters in the source input.
          //    We need to advance 'i' to skip the characters in the original word
          //    that are being replaced.
          //    Calculation: i (current) + cut (consumed) - position (backtracked)
          //    Since the loop does ++i, we add the difference.
          i += cutLength - position;
        } else {
          // --- Standard Hyphenation ---
          // Just append the hyphen character (using '=' as per C implementation)
          result.add(61 /* '=' */);
        }
      }
    }

    return String.fromCharCodes(result);
  }

  HyphenTrans? _findTransition(HyphenState state, int ch) {
    for (final transition in state.transitions) {
      if (transition.ch == ch) {
        return transition;
      }
    }
    return null;
  }

  static List<int> _prepWord(List<int> runes) {
    final prepWord = List<int>.filled(runes.length + 3, 0);
    var j = 0;
    prepWord[j++] = charDot;
    for (final char in runes) {
      if (char <= 57 /* '9' */ && char >= 48 /* '0' */ ) {
        prepWord[j++] = charZero;
      } else {
        prepWord[j++] = char;
      }
    }
    prepWord[prepWord.length - 2] = charDot;
    prepWord[prepWord.length - 1] = 0; // null terminator to align with c code
    return prepWord;
  }

  static bool _cpListMatch(List<int> word, int start, List<int> pattern) {
    for (var i = 0; i < pattern.length; i++) {
      if (word[start + i] != pattern[i]) return false;
    }
    return true;
  }
}

extension _RunesExt on List<int> {
  int stringLength({required int n, int start = 0}) {
    var j = start;
    var i = 0;
    while (j < n && j < length && this[j] != 0) {
      ++i;
      ++j;
    }
    return i;
  }
}

class _Ref<T> {
  T? value;
}
