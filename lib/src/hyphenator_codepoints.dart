import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/model/result.dart';

/// A hyphenator that works entirely in Unicode codepoint space.
///
/// This is a direct Dart equivalent of [hnj_hyphen_hyphenate3] from hyphen.c,
/// with the key difference that all positions and lengths are measured in
/// Unicode codepoints (not UTF-8 bytes or UTF-16 code units).
///
/// The [HyphenDict] must have been built by [DictParser], which stores trie
/// transitions keyed by codepoint values.
///
/// The returned [HyphenResult.hyphens] contains zero-based **codepoint**
/// indices after which a soft hyphen may be inserted.
class HyphenatorCodepoints {
  const HyphenatorCodepoints();

  /// Hyphenate [word] using [dict].
  ///
  /// [lhmin]/[rhmin] override the dictionary's left/right hyphen-minimum
  /// values (counted in codepoints).  [clhmin]/[crhmin] do the same for
  /// compound-word boundaries.
  HyphenResult hyphenate(
    HyphenDict dict,
    String word, {
    int lhmin = 0,
    int rhmin = 0,
    int clhmin = 0,
    int crhmin = 0,
  }) {
    // Mirrors hnj_hyphen_hyphenate3: take the max of caller and dict values.
    lhmin = lhmin > dict.leftHyphenMin ? lhmin : dict.leftHyphenMin;
    rhmin = rhmin > dict.rightHyphenMin ? rhmin : dict.rightHyphenMin;
    clhmin = clhmin > dict.compoundLeftHyphenMin
        ? clhmin
        : dict.compoundLeftHyphenMin;
    crhmin = crhmin > dict.compoundRightHyphenMin
        ? crhmin
        : dict.compoundRightHyphenMin;

    // Convert word to a flat codepoint list – this is the analogue of the
    // UTF-8 byte array in the C code.
    final wordCps = word.runes.toList();
    final wordSize = wordCps.length;

    // hyphens[i] accumulates the digit from the pattern at codepoint i.
    final hyphens = Uint8List(wordSize + 5);

    List<String?>? rep;
    List<int>? pos;
    List<int>? cut;

    _hyphenHyph(
      dict,
      wordCps,
      wordSize,
      hyphens,
      (r) => rep = r,
      (p) => pos = p,
      (c) => cut = c,
      clhmin,
      crhmin,
      lend: true,
      rend: true,
    );

    // Enforce left/right minimum (hnj_hyphen_lhmin / hnj_hyphen_rhmin).
    _hyphenLhmin(wordCps, wordSize, hyphens, rep, pos, cut,
        lhmin > 0 ? lhmin : 2);
    _hyphenRhmin(wordCps, wordSize, hyphens, rep, pos, cut,
        rhmin > 0 ? rhmin : 2);

    // Apply NOHYPHEN sequences (hnj_hyphen_hyphenate3 nohyphen block).
    // We work in codepoints so we search by rune-level indexOf.
    if (dict.noHyphenWords.isNotEmpty) {
      _applyNoHyphen(dict, wordCps, hyphens);
    }

    // Build the hyphenated word string (hnj_hyphen_hyphword).
    final hyphword =
        _buildHyphword(wordCps, wordSize, hyphens, rep, pos, cut);

    // Collect odd-valued positions as hyphenation points.
    final hyphenPositions = <int>[];
    for (var i = 0; i < wordSize; i++) {
      if (hyphens[i].isOdd) hyphenPositions.add(i);
    }

    return HyphenResult(hyphens: hyphenPositions, hyphword: hyphword);
  }

  // ---------------------------------------------------------------------------
  // hnj_hyphen_hyph_ – the core FSM
  // ---------------------------------------------------------------------------

  void _hyphenHyph(
    HyphenDict dict,
    List<int> wordCps,
    int wordSize,
    Uint8List hyphens,
    void Function(List<String?>) setRep,
    void Function(List<int>) setPos,
    void Function(List<int>) setCut,
    int clhmin,
    int crhmin, {
    required bool lend,
    required bool rend,
  }) {
    // prepWord = '.' + word (digits replaced by '.') + '.'
    // Length j = wordSize + 2.
    final prepWord = List<int>.filled(wordSize + 3, 0);
    prepWord[0] = charDot;
    for (var i = 0; i < wordSize; i++) {
      final cp = wordCps[i];
      prepWord[1 + i] = _isDigitCp(cp) ? charDot : cp;
    }
    prepWord[wordSize + 1] = charDot;
    final j = wordSize + 2;

    // Zero out hyphens for the prep-word length.
    for (var i = 0; i < j; i++) {
      hyphens[i] = 0;
    }

    // Scratch arrays for non-standard (replacement) patterns.
    final matchrepl = List<String?>.filled(wordSize + 3, null);
    final matchindex = List<int>.filled(wordSize + 3, -1);
    final matchlen = List<int>.filled(wordSize + 3, 0);
    var isrepl = false;

    // Run the Aho-Corasick / trie FSM.
    var state = 0;
    outer:
    for (var i = 0; i < j; i++) {
      final ch = prepWord[i];

      // Walk transitions (with fallback) until we find a state or exhaust.
      for (;;) {
        if (state == -1) {
          state = 0;
          continue outer; // try_next_letter
        }
        final hstate = dict.states[state];
        final trans = _findTransition(hstate, ch);
        if (trans != null) {
          state = trans.newState;
          break; // found_state
        }
        state = hstate.fallbackState;
      }

      // found_state: apply the match stored at the current state.
      final hstate = dict.states[state];
      final match = _getMatch(hstate);
      if (match == null) continue;

      final repl = hstate.replacement;
      final replindex = hstate.replacementIndex;
      final replcut = hstate.replacementCut;
      // offset into hyphens/prepWord where this match's pattern starts.
      final offset = i + 1 - match.length;

      if (repl != null) {
        if (!isrepl) {
          isrepl = true;
          for (var x = 0; x < wordSize; x++) {
            matchrepl[x] = null;
            matchindex[x] = -1;
          }
        }
        final replPos = offset + replindex;
        if (replPos >= 0 && replPos < matchlen.length) {
          matchlen[replPos] = replcut;
        }
      }

      // Merge pattern digits into hyphens (take the max).
      for (var k = 0; k < match.length; k++) {
        final mc = match[k];
        final p = offset + k;
        if (p < 0 || p >= hyphens.length) continue;
        if (hyphens[p] < mc) {
          hyphens[p] = mc;
          if (mc.isOdd) {
            matchrepl[p] = repl;
            if (repl != null) {
              final replPos = offset + replindex;
              if (k >= replindex &&
                  k <= replindex + replcut &&
                  replPos >= 0 &&
                  replPos < matchindex.length) {
                matchindex[replPos] = p;
              }
            }
          }
        }
      }
    } // end outer for

    // Shift hyphens left by 1 (strip the leading '.' offset).
    // C: for (i=0; i < j-3; i++) hyphens[i] = hyphens[i+1];
    for (var i = 0; i < j - 3; i++) {
      hyphens[i] = hyphens[i + 1];
    }
    for (var i = j - 3; i < wordSize; i++) {
      hyphens[i] = 0;
    }
    hyphens[wordSize] = 0;

    // Build rep/pos/cut arrays from the match-replacement scratch data.
    // Keep a local reference so the compound block below can read them
    // (mirrors how C uses the *rep/*pos/*cut output parameters).
    List<String?>? currentRep;
    List<int>? currentPos;
    List<int>? currentCut;

    if (isrepl) {
      final repList = List<String?>.filled(wordSize, null);
      final posList = List<int>.filled(wordSize, 0);
      final cutList = List<int>.filled(wordSize, 0);

      for (var i = 0; i < wordSize; i++) {
        final mi = matchindex[i];
        if (mi >= 0 && mi < matchrepl.length && matchrepl[mi] != null) {
          repList[mi - 1] = matchrepl[mi];
          posList[mi - 1] = mi - i;
          cutList[mi - 1] = matchlen[i];
          i += matchlen[i] - 1;
        }
      }
      currentRep = repList;
      currentPos = posList;
      currentCut = cutList;
      setRep(repList);
      setPos(posList);
      setCut(cutList);
    }

    // Recursive compound-word hyphenation (mirrors the dict->nextLevel block).
    if (dict.nextLevel != null) {
      final nextDict = dict.nextLevel!;
      final hyphens2 = Uint8List(wordSize + 3);

      // Collects rep/pos/cut results from recursive segment calls so they
      // can be forwarded to the caller at the end.
      List<String?>? outerRep;
      List<int>? outerPos;
      List<int>? outerCut;

      var begin = 0;

      for (var i = 0; i < wordSize; i++) {
        final isCompound =
            hyphens[i].isOdd || (begin > 0 && i + 1 == wordSize);
        if (!isCompound) continue;

        if (i - begin > 0) {
          var hyph = 0;
          // Build a local copy of prepWord with the segment boundary zeroed.
          final pw = List<int>.from(prepWord);
          pw[i + 2] = 0;

          // Apply non-standard replacement at the compound boundary if present.
          // C reads (*rep)[i] which was set by the isrepl block above — we use
          // currentRep which holds the same data.
          if (currentRep != null &&
              currentPos != null &&
              currentCut != null &&
              i < currentRep.length &&
              currentRep[i] != null) {
            final replStr = currentRep[i]!;
            final replRunes = replStr.runes.toList();
            final offset = 2 + i - currentPos[i];
            for (var x = 0;
                x < replRunes.length && offset + x < pw.length - 1;
                x++) {
              if (offset + x >= 0) pw[offset + x] = replRunes[x];
            }
            final eqCp = replRunes.indexOf(charEquals);
            if (eqCp >= 0) {
              hyph = eqCp - currentPos[i];
              final truncAt = 2 + i + hyph;
              if (truncAt >= 0 && truncAt < pw.length) pw[truncAt] = 0;
            }
          }

          List<String?>? segRep;
          List<int>? segPos;
          List<int>? segCut;

          // C: hnj_hyphen_hyph_(dict, prep_word + begin + 1, i-begin+1+hyph, ...)
          final segStart = begin + 1;
          final segLen = i - begin + 1 + hyph;
          if (segLen > 0 && segStart + segLen <= pw.length) {
            _hyphenHyph(
              dict,
              pw.sublist(segStart, segStart + segLen),
              segLen,
              hyphens2,
              (r) => segRep = r,
              (p) => segPos = p,
              (c) => segCut = c,
              clhmin,
              crhmin,
              lend: (begin > 0) ? false : lend,
              rend: hyphens[i].isOdd ? false : rend,
            );
          }

          // Copy hyphens2 back into the main hyphens array for this segment.
          for (var jj = 0; jj < i - begin; jj++) {
            hyphens[begin + jj] = hyphens2[jj];
            if (segRep != null &&
                jj < segRep!.length &&
                segRep![jj] != null) {
              outerRep ??= List<String?>.filled(wordSize, null);
              outerPos ??= List<int>.filled(wordSize, 0);
              outerCut ??= List<int>.filled(wordSize, 0);
              outerRep[begin + jj] = segRep![jj];
              outerPos[begin + jj] = segPos![jj];
              outerCut[begin + jj] = segCut![jj];
            }
          }

          // Restore prepWord after non-standard boundary rewrite.
          // C: prep_word[i + 2] = word[i + 1]
          pw[i + 2] = (i + 1 < wordCps.length) ? wordCps[i + 1] : 0;
          if (currentRep != null &&
              currentPos != null &&
              currentCut != null &&
              i < currentRep.length &&
              currentRep[i] != null) {
            // C: strncpy(prep_word + 1, word, ...); restore full word
            for (var x = 0; x < wordSize && x + 1 < pw.length; x++) {
              pw[x + 1] = wordCps[x];
            }
          }
        }

        begin = i + 1;
      }

      // If no compound boundary was found, use the next-level dict directly.
      if (begin == 0) {
        List<String?>? nlRep;
        List<int>? nlPos;
        List<int>? nlCut;

        _hyphenHyph(
          nextDict,
          wordCps,
          wordSize,
          hyphens,
          (r) => nlRep = r,
          (p) => nlPos = p,
          (c) => nlCut = c,
          clhmin,
          crhmin,
          lend: lend,
          rend: rend,
        );

        if (!lend) {
          _hyphenLhmin(
              wordCps, wordSize, hyphens, nlRep, nlPos, nlCut, clhmin);
        }
        if (!rend) {
          _hyphenRhmin(
              wordCps, wordSize, hyphens, nlRep, nlPos, nlCut, crhmin);
        }

        if (nlRep != null) {
          setRep(nlRep!);
          setPos(nlPos!);
          setCut(nlCut!);
        }
      } else if (outerRep != null) {
        setRep(outerRep);
        setPos(outerPos!);
        setCut(outerCut!);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // hnj_hyphen_lhmin – zero out hyphens too close to the left edge
  // ---------------------------------------------------------------------------

  void _hyphenLhmin(
    List<int> wordCps,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
    int lhmin,
  ) {
    // Start character count at 1 (the character before the first hyphen slot).
    var charCount = 1;

    // Leading digit codepoints don't count toward the minimum.
    var j = 0;
    while (j < wordSize && _isDigitCp(wordCps[j])) {
      charCount--;
      j++;
    }

    // Walk forward zeroing hyphens until we've seen lhmin characters.
    j = 0;
    while (charCount < lhmin && j < wordSize) {
      if (rep != null && pos != null && cut != null && rep[j] != null) {
        final eqIdx = rep[j]!.indexOf('=');
        if (eqIdx >= 0) {
          // Count codepoints on left side of replacement.
          final lhsLen = (j - pos[j] + 1) +
              rep[j]!.runes.toList().indexOf(charEquals).clamp(0, eqIdx);
          if (lhsLen < lhmin) {
            rep[j] = null;
            hyphens[j] = 0;
          }
        }
      } else {
        hyphens[j] = 0;
      }
      j++;
      charCount++;
    }
  }

  // ---------------------------------------------------------------------------
  // hnj_hyphen_rhmin – zero out hyphens too close to the right edge
  // ---------------------------------------------------------------------------

  void _hyphenRhmin(
    List<int> wordCps,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
    int rhmin,
  ) {
    var charCount = 0;

    // Trailing digit codepoints don't count toward the minimum.
    var j = wordSize - 1;
    while (j > 0 && _isDigitCp(wordCps[j])) {
      charCount--;
      j--;
    }

    for (j = wordSize - 1; charCount < rhmin && j > 0; j--) {
      if (rep != null && pos != null && cut != null && rep[j] != null) {
        final eqIdx = rep[j]!.indexOf('=');
        if (eqIdx >= 0) {
          // Count codepoints on right side of replacement.
          final tailStart = j - pos[j] + cut[j] + 1;
          final rhsRunes = rep[j]!.runes.toList();
          final eqCp = rhsRunes.indexOf(charEquals);
          final rhsLen = (wordSize - tailStart) +
              (eqCp >= 0 ? rhsRunes.length - eqCp - 1 : 0);
          if (rhsLen < rhmin) {
            rep[j] = null;
            hyphens[j] = 0;
          }
        }
      } else {
        hyphens[j] = 0;
      }
      charCount++;
    }
  }

  // ---------------------------------------------------------------------------
  // NOHYPHEN application (hnj_hyphen_hyphenate3 nohyphen block)
  // ---------------------------------------------------------------------------

  void _applyNoHyphen(
    HyphenDict dict,
    List<int> wordCps,
    Uint8List hyphens,
  ) {
    for (final nh in dict.noHyphenWords) {
      if (nh.isEmpty) continue;
      final nhCps = nh.runes.toList();
      final nhLen = nhCps.length;
      // Find all occurrences of nhCps inside wordCps.
      for (var start = 0; start <= wordCps.length - nhLen; start++) {
        if (_cpListMatch(wordCps, start, nhCps)) {
          // Zero the slot immediately before the sequence (idx - 1).
          final before = start - 1;
          if (before >= 0) hyphens[before] = 0;
          // Zero the slot at the last character of the sequence.
          final end = start + nhLen - 1;
          if (end < hyphens.length) hyphens[end] = 0;
        }
      }
    }
  }

  bool _cpListMatch(List<int> word, int start, List<int> pattern) {
    for (var i = 0; i < pattern.length; i++) {
      if (word[start + i] != pattern[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // hnj_hyphen_hyphword – build the hyphenated output string
  // ---------------------------------------------------------------------------

  String _buildHyphword(
    List<int> wordCps,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
  ) {
    if (wordSize <= 0) return '';

    // Mirror C's fixed output buffer: hyphword_size = 2*word_size - 1.
    final maxOut = 2 * wordSize - 1;

    final out = <int>[];
    final nonstandard = rep != null && pos != null && cut != null;
    var i = 0;

    while (i < wordSize && out.length < maxOut) {
      out.add(wordCps[i]);

      if (hyphens[i].isOdd && out.length < maxOut) {
        if (nonstandard && rep[i] != null) {
          // Non-standard replacement: rewind pos[i] codepoints, write
          // replacement string, then skip cut[i]-pos[i] extra input chars.
          final rewind = pos[i].clamp(0, out.length);
          out.length -= rewind;
          for (final cp in rep[i]!.runes) {
            if (out.length >= maxOut) break;
            out.add(cp);
          }
          final skip = cut[i] - pos[i];
          if (skip > 0) i += skip;
        } else {
          out.add(charEquals);
        }
      }
      i++;
    }

    return String.fromCharCodes(out);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  HyphenTrans? _findTransition(HyphenState state, int cp) {
    for (final t in state.transitions) {
      if (t.ch == cp) return t;
    }
    return null;
  }

  /// Returns the match array for [state], or null if it has none.
  /// Uses a try/catch to handle the `late` field before it is initialised
  /// (state 0 in a freshly-built dict has no match).
  Uint8List? _getMatch(HyphenState state) {
    try {
      return state.match;
    } catch (_) {
      return null;
    }
  }

  bool _isDigitCp(int cp) => cp >= charZero && cp <= 0x39;
}

