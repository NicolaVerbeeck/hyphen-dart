import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/model/result.dart';

class Hyphenator {
  const Hyphenator();

  // Equivalent to the hnj_hyphen_hyphenate2 method
  HyphenResult hyphenate(HyphenDict dict, String word) {
    final runes = _runes(word);
    final hyphens = Uint8List(runes.length + 5);
    final rep = _Replacements();

    _hyphenate(
      dict,
      runes,
      hyphens,
      rep,
      dict.compoundLeftHyphenMin,
      dict.compoundRightHyphenMin,
      lend: true,
      rend: true,
    );
    _hyphenLeftMin(
      runes,
      hyphens,
      rep,
      dict.leftHyphenMin > 0 ? dict.leftHyphenMin : 2,
    );
    _hyphenRightMin(
      runes,
      hyphens,
      rep,
      dict.rightHyphenMin > 0 ? dict.rightHyphenMin : 2,
    );

    final noHyphen = dict.noHyphenRunes;
    for (var n = 0; n < noHyphen.length; ++n) {
      final noHyphenRunes = noHyphen[n];
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

    final hyphenPositions = <int>[];
    for (var i = 0; i < hyphens.length; ++i) {
      if (hyphens[i].isOdd) {
        hyphenPositions.add(i);
      }
    }
    return HyphenResult(
      hyphenPositions,
      runes,
      hyphens,
      rep.rep,
      rep.pos,
      rep.cut,
    );
  }

  void _hyphenLeftMin(
    Int32List word,
    Uint8List hyphens,
    _Replacements rep,
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
      final replacements = rep.rep;
      final pos = rep.pos;
      if (replacements != null && replacements[j] != null && pos != null) {
        final replacement = replacements[j]!;
        final rhIndex = replacement.indexOf('=');

        if (rhIndex >= 0) {
          // Calculate effective length of the left part
          // 1. Length of word stem before the replacement
          final prefixLen = _stringLength(word, n: j - pos[j] + 1);
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
        if (replacements != null) {
          replacements[j] = null;
        }
      }
    }
  }

  void _hyphenRightMin(
    Int32List word,
    Uint8List hyphens,
    _Replacements rep,
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
      final replacements = rep.rep;
      final pos = rep.pos;
      if (replacements != null && replacements[j] != null && pos != null) {
        final replacement = replacements[j]!;
        final rhIndex = replacement.indexOf('=');

        if (rhIndex >= 0) {
          final prefixLen = _stringLength(
            word,
            n: 100,
            start: j - pos[j] + rep.cut![j] + 1,
          );
          final replLen =
              replacement.runes.length -
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
        if (replacements != null) {
          replacements[j] = null;
        }
      }
    }
  }

  // Equivalent to the hnj_hyphen_hyph_ method. [prepWord] is the prepared
  // word when the caller already has it.
  void _hyphenate(
    HyphenDict dict,
    Int32List word,
    Uint8List hyphens,
    _Replacements rep,
    int clhmin,
    int crhmin, {
    required bool lend,
    required bool rend,
    Int32List? prepWord,
  }) {
    final wordSize = word.length;
    final prep = prepWord ?? _prepWord(word);
    for (var i = 0; i < prep.length; ++i) {
      hyphens[i] = 0;
    }

    final patterns = dict.patterns;
    final transStart = patterns.transStart;
    final transChar = patterns.transChar;
    final transTarget = patterns.transTarget;
    final fallback = patterns.fallback;
    final classLow = patterns.classLow;
    final classLowLength = classLow.length;
    final classHigh = patterns.classHigh;
    final alphabetSize = patterns.alphabetSize;
    final rowOf = patterns.rowOf;
    final rows = patterns.rows;
    final matchStart = patterns.matchStart;
    final matchLen = patterns.matchLen;
    final matchData = patterns.matchData;
    final replacementOf = patterns.replacementOf;

    // Allocated when the first pattern with a replacement matches.
    List<String?>? matchRepl;
    Int32List? matchIndex;
    Int32List? matchLength;

    var matched = false;
    var state = 0;
    for (var i = 0; i < prep.length; ++i) {
      final ch = prep[i];
      final cls = ch < classLowLength ? classLow[ch] : classHigh[ch] ?? -1;
      if (cls < 0) {
        // No transition uses ch, so following the fallbacks would end at -1.
        state = 0;
        continue;
      }

      var next = -1;
      for (var s = state; s >= 0; s = fallback[s]) {
        final row = rowOf[s];
        if (row >= 0) {
          // Rows already include the fallbacks.
          next = rows[row * alphabetSize + cls];
          break;
        }
        final end = transStart[s + 1];
        for (var t = transStart[s]; t < end; ++t) {
          if (transChar[t] == ch) {
            next = transTarget[t];
            break;
          }
        }
        if (next >= 0) break;
      }
      if (next < 0) {
        state = 0;
        continue;
      }
      state = next;

      final ms = matchStart[state];
      if (ms < 0) continue;
      matched = true;
      final ml = matchLen[state];
      final offset = i + 1 - ml;
      final replacement = replacementOf == null || replacementOf[state] < 0
          ? null
          : patterns.replacements[replacementOf[state]];
      if (replacement != null) {
        if (matchRepl == null) {
          matchRepl = List<String?>.filled(wordSize + 2, null);
          matchIndex = Int32List(wordSize + 2)..fillRange(0, wordSize, -1);
          matchLength = Int32List(wordSize + 2);
        }
        matchLength![offset + replacement.index] = replacement.cut;
      }
      if (matchRepl == null) {
        for (var k = 0; k < ml; ++k) {
          final mc = matchData[ms + k];
          if (hyphens[offset + k] < mc) hyphens[offset + k] = mc;
        }
        continue;
      }
      for (var k = 0; k < ml; ++k) {
        final mc = matchData[ms + k];
        if (hyphens[offset + k] < mc) {
          hyphens[offset + k] = mc;
          if (mc.isOdd) {
            matchRepl[offset + k] = replacement?.text;
            if (replacement != null &&
                (k >= replacement.index) &&
                (k <= replacement.index + replacement.cut)) {
              matchIndex![offset + replacement.index] = offset + k;
            }
          }
        }
      }
    }

    final nextLevel = dict.nextLevel;
    if (!matched) {
      // The hyphens stay 0, so there are no replacements and no compound
      // boundaries.
      if (nextLevel != null) {
        _hyphenateNonCompound(
          nextLevel,
          word,
          hyphens,
          rep,
          clhmin,
          crhmin,
          lend: lend,
          rend: rend,
          prepWord: prep,
        );
      }
      return;
    }

    for (var i = 0; i < wordSize; ++i) {
      hyphens[i] = hyphens[i + 1];
    }
    if (word.isNotEmpty) {
      // Avoid -1 index if word is empty
      hyphens[wordSize - 1] = 0;
    }
    hyphens[wordSize] = 0;

    if (matchRepl != null) {
      final repl = rep.rep ??= List.filled(wordSize, null);
      final pos = rep.pos ??= Int32List(wordSize);
      final cut = rep.cut ??= Int32List(wordSize);

      for (var i = 0; i < wordSize; i++) {
        final mi = matchIndex![i];
        if (mi >= 0 && mi < matchRepl.length && matchRepl[mi] != null) {
          repl[mi - 1] = matchRepl[mi];
          pos[mi - 1] = mi - i;
          cut[mi - 1] = matchLength![i];
          i += matchLength[i] - 1;
        }
      }
    }

    if (nextLevel == null) {
      return;
    }
    // Allocated at the first compound boundary.
    _Replacements? rep2;
    Uint8List? hyphens2;
    var begin = 0;

    for (var i = 0; i < wordSize; ++i) {
      final isCompoundBoundary =
          hyphens[i].isOdd || (begin > 0 && i + 1 == wordSize);
      if (!isCompoundBoundary) {
        continue;
      }
      if (i - begin > 0) {
        rep2 ??= _Replacements.filled(wordSize);
        hyphens2 ??= Uint8List(wordSize + 3);
        var hyph = 0;
        prep[i + 2] = 0;

        // Non-standard hyphenation at compound boundary (Schiffahrt)
        final replacement = rep.rep?[i];
        if (replacement != null && rep.pos != null && rep.cut != null) {
          final lIndex = replacement.indexOf('=');
          final offset = 2 + i - rep.pos![i];
          _strncpy(prep, offset, prep.length - offset - 1, replacement.runes);
          if (lIndex >= 0) {
            hyph = lIndex - rep.pos![i];
            prep[2 + i + hyph] = 0;
          }
        }
        final subStart = begin + 1;
        final subCount = i - begin + 1 + hyph;
        _hyphenate(
          dict,
          prep.sublist(subStart, subStart + subCount),
          hyphens2,
          rep2,
          clhmin,
          crhmin,
          lend: begin > 0 ? false : lend,
          rend: hyphens[i].isOdd ? false : rend,
        );
        for (var j = 0; j < i - begin; ++j) {
          hyphens[begin + j] = hyphens2[j];
          if (rep2.rep![j] != null) {
            if (rep.rep == null && rep.pos == null && rep.cut == null) {
              rep
                ..rep = List.filled(wordSize, null)
                ..pos = Int32List(wordSize)
                ..cut = Int32List(wordSize);
            }
            rep.rep![begin + j] = rep2.rep![j];
            rep.pos![begin + j] = rep2.pos![j];
            rep.cut![begin + j] = rep2.cut![j];
          }
        }
        prep[i + 2] = (i + 1 < wordSize) ? word[i + 1] : 0;
        if (rep.rep?[i] != null && rep.pos != null && rep.cut != null) {
          _strncpy(prep, 1, prep.length - 2, word);
        }
      }
      begin = i + 1;
      rep2?.rep!.fillRange(0, wordSize, null);
    }
    if (begin == 0) {
      _hyphenateNonCompound(
        nextLevel,
        word,
        hyphens,
        rep,
        clhmin,
        crhmin,
        lend: lend,
        rend: rend,
        prepWord: prep,
      );
    }
  }

  // Hyphenates a word without compound boundaries with the next level.
  void _hyphenateNonCompound(
    HyphenDict nextLevel,
    Int32List word,
    Uint8List hyphens,
    _Replacements rep,
    int clhmin,
    int crhmin, {
    required bool lend,
    required bool rend,
    required Int32List prepWord,
  }) {
    _hyphenate(
      nextLevel,
      word,
      hyphens,
      rep,
      clhmin,
      crhmin,
      lend: lend,
      rend: rend,
      prepWord: prepWord,
    );
    if (!lend) _hyphenLeftMin(word, hyphens, rep, clhmin);
    if (!rend) _hyphenRightMin(word, hyphens, rep, crhmin);
  }

  static Int32List _runes(String word) {
    var count = 0;
    for (var i = 0; i < word.length; ++i) {
      if (_isSurrogatePair(word, i)) ++i;
      ++count;
    }
    final runes = Int32List(count);
    if (count == word.length) {
      for (var i = 0; i < count; ++i) {
        runes[i] = word.codeUnitAt(i);
      }
      return runes;
    }
    var j = 0;
    for (var i = 0; i < word.length; ++i) {
      if (_isSurrogatePair(word, i)) {
        runes[j++] =
            0x10000 +
            ((word.codeUnitAt(i) & 0x3FF) << 10) +
            (word.codeUnitAt(i + 1) & 0x3FF);
        ++i;
      } else {
        runes[j++] = word.codeUnitAt(i);
      }
    }
    return runes;
  }

  static bool _isSurrogatePair(String s, int i) =>
      (s.codeUnitAt(i) & 0xFC00) == 0xD800 &&
      i + 1 < s.length &&
      (s.codeUnitAt(i + 1) & 0xFC00) == 0xDC00;

  /// The word between dots and with a null terminator, as libhyphen matches
  /// it. Digits become dots: they end words.
  static Int32List _prepWord(Int32List word) {
    final prepWord = Int32List(word.length + 3);
    var j = 0;
    prepWord[j++] = charDot;
    for (var i = 0; i < word.length; ++i) {
      final char = word[i];
      if (char <= 57 /* '9' */ && char >= 48 /* '0' */ ) {
        prepWord[j++] = charDot;
      } else {
        prepWord[j++] = char;
      }
    }
    prepWord[prepWord.length - 2] = charDot;
    // The last element stays 0: the null terminator of the C code.
    return prepWord;
  }

  /// C's strncpy: copies [source] to [count] elements of [target] from
  /// [offset], filling the rest of them with zeros.
  static void _strncpy(
    Int32List target,
    int offset,
    int count,
    Iterable<int> source,
  ) {
    final end = offset + count;
    var i = offset;
    for (final char in source) {
      if (i >= end) return;
      target[i++] = char;
    }
    target.fillRange(i, end, 0);
  }

  static bool _cpListMatch(Int32List word, int start, Int32List pattern) {
    for (var i = 0; i < pattern.length; i++) {
      if (word[start + i] != pattern[i]) return false;
    }
    return true;
  }

  static int _stringLength(Int32List word, {required int n, int start = 0}) {
    var j = start;
    var i = 0;
    while (j < n && j < word.length && word[j] != 0) {
      ++i;
      ++j;
    }
    return i;
  }
}

/// The non-standard hyphenation after each character (rep, pos and cut in
/// libhyphen), allocated when a pattern with a replacement matches.
class _Replacements {
  _Replacements();

  _Replacements.filled(int size)
    : rep = List.filled(size, null),
      pos = Int32List(size),
      cut = Int32List(size);

  List<String?>? rep;
  Int32List? pos;
  Int32List? cut;
}
