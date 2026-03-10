import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
import 'package:hypen_dart/src/model/dict.dart';
import 'package:hypen_dart/src/model/result.dart';
import 'package:meta/meta.dart';

@immutable
class Hyphenator {
  const Hyphenator();

  /// Hyphenate [word] using [dict], returning a [HyphenResult] containing the
  /// hyphenation points and any replacement text. The [lhmin], [rhmin],
  /// [clhmin], and [crhmin] parameters specify the minimum number of code
  /// units to the left and right of a hyphenation point, and the minimum
  /// number of code units to the left and right of a compound hyphenation
  /// point.
  HyphenResult hyphenate(
    HyphenDict dict,
    String word, {
    int lhmin = 0,
    int rhmin = 0,
    int clhmin = 0,
    int crhmin = 0,
  }) {
    lhmin = lhmin > dict.leftHyphenMin ? lhmin : dict.leftHyphenMin;
    rhmin = rhmin > dict.rightHyphenMin ? rhmin : dict.rightHyphenMin;
    clhmin = clhmin > dict.compoundLeftHyphenMin
        ? clhmin
        : dict.compoundLeftHyphenMin;
    crhmin = crhmin > dict.compoundRightHyphenMin
        ? crhmin
        : dict.compoundRightHyphenMin;

    final wordUnits = word.codeUnits;
    final wordSize = wordUnits.length;

    final hyphens = Uint8List(wordSize + 5);
    List<String?>? rep;
    List<int>? pos;
    List<int>? cut;

    _hyphenHyph(
      dict,
      wordUnits,
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

    _hyphenLhmin(
      wordUnits,
      wordSize,
      hyphens,
      rep,
      pos,
      cut,
      lhmin > 0 ? lhmin : 2,
    );
    _hyphenRhmin(
      wordUnits,
      wordSize,
      hyphens,
      rep,
      pos,
      cut,
      rhmin > 0 ? rhmin : 2,
    );

    if (dict.noHyphenWords.isNotEmpty) {
      _applyNohyphen(dict, word, hyphens, zeroValue: 0);
    }

    final hyphword = _buildHyphword(wordUnits, wordSize, hyphens, rep, pos, cut);

    return HyphenResult(
      hyphens: _decodeHyphens(hyphens, wordSize),
      hyphword: hyphword,
    );
  }

  String _buildHyphword(
    List<int> word,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
  ) {
    if (wordSize <= 0) {
      return '';
    }

    final out = <int>[];
    final nonstandard = rep != null && pos != null && cut != null;
    var i = 0;

    while (i < wordSize) {
      out.add(word[i]);

      if (hyphens[i].isOdd) {
        if (nonstandard && rep[i] != null) {
          final rewind = pos[i].clamp(0, out.length);
          out.length -= rewind;
          out.addAll(rep[i]!.codeUnits);
          final skip = cut[i] - pos[i];
          if (skip > 0) {
            i += skip;
          }
        } else {
          out.add(charEquals);
        }
      }
      i++;
    }

    return String.fromCharCodes(out);
  }


  /// Returns the code-unit index of all hyphenation points in [hyphens].
  List<int> _decodeHyphens(Uint8List hyphens, int wordSize) {
    final result = <int>[];
    for (var i = 0; i < wordSize; ++i) {
      if (hyphens[i].isOdd) {
        result.add(i);
      }
    }
    return result;
  }

  void _hyphenHyph(
    HyphenDict dict,
    List<int> wordUnits,
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
    final prepWord = List<int>.filled(wordSize + 3, 0);
    prepWord[0] = charDot;
    for (var i = 0; i < wordSize; i++) {
      final ch = wordUnits[i];
      prepWord[1 + i] = _isDigitCodeUnit(ch) ? charDot : ch;
    }
    prepWord[wordSize + 1] = charDot;
    final j = wordSize + 2;

    for (var i = 0; i < j; i++) {
      hyphens[i] = 0;
    }

    final matchrepl = List<String?>.filled(wordSize + 3, null);
    final matchindex = List<int>.filled(wordSize + 3, -1);
    final matchlen = List<int>.filled(wordSize + 3, 0);
    var isrepl = false;

    var state = 0;
    outer:
    for (var i = 0; i < j; i++) {
      final ch = prepWord[i];
      for (;;) {
        if (state == -1) {
          state = 0;
          continue outer;
        }
        final hstate = dict.states[state];
        final trans = _findTransition(hstate, ch);
        if (trans != null) {
          state = trans.newState;
          break;
        }
        state = hstate.fallbackState;
      }

      final hstate = dict.states[state];
      final match = _tryGetMatch(hstate);
      if (match == null) {
        continue;
      }

      final repl = hstate.replacement;
      final replindex = hstate.replacementIndex;
      final replcut = hstate.replacementCut;
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

      for (var k = 0; k < match.length; k++) {
        final mc = match[k];
        final pos = offset + k;
        if (pos < 0 || pos >= hyphens.length) {
          continue;
        }
        if (hyphens[pos] < mc) {
          hyphens[pos] = mc;
          if (mc.isOdd) {
            matchrepl[pos] = repl;
            final replPos = offset + replindex;
            if (repl != null &&
                k >= replindex &&
                k <= replindex + replcut &&
                replPos >= 0 &&
                replPos < matchindex.length) {
              matchindex[replPos] = pos;
            }
          }
        }
      }
    }

    for (var i = 0; i < j - 3; i++) {
      hyphens[i] = hyphens[i + 1];
    }
    for (var i = j - 3; i < wordSize; i++) {
      hyphens[i] = 0;
    }
    hyphens[wordSize] = 0;

    if (isrepl) {
      final rep = List<String?>.filled(wordSize, null);
      final pos = List<int>.filled(wordSize, 0);
      final cut = List<int>.filled(wordSize, 0);

      for (var i = 0; i < wordSize; i++) {
        final mi = matchindex[i];
        if (mi >= 0 && mi < matchrepl.length && matchrepl[mi] != null) {
          rep[mi - 1] = matchrepl[mi];
          pos[mi - 1] = mi - i;
          cut[mi - 1] = matchlen[i];
          i += matchlen[i] - 1;
        }
      }
      setRep(rep);
      setPos(pos);
      setCut(cut);
    }

    if (dict.nextLevel != null) {
      final nextDict = dict.nextLevel!;
      final hyphens2 = Uint8List(wordSize + 3);

      List<String?>? outerRep;
      List<int>? outerPos;
      List<int>? outerCut;

      var begin = 0;

      for (var i = 0; i < wordSize; i++) {
        final isCompoundBoundary = hyphens[i].isOdd || (begin > 0 && i + 1 == wordSize);
        if (!isCompoundBoundary) {
          continue;
        }

        if (i - begin > 0) {
          var hyph = 0;
          final pw = List<int>.from(prepWord);
          pw[i + 2] = 0;

          if (outerRep != null &&
              outerPos != null &&
              outerCut != null &&
              i < outerRep.length &&
              outerRep[i] != null) {
            final replStr = outerRep[i]!;
            final eqIdx = replStr.indexOf('=');
            final replUnits = replStr.codeUnits;
            final offset = 2 + i - outerPos[i];
            for (
              var x = 0;
              x < replUnits.length && offset + x < pw.length - 1;
              x++
            ) {
              if (offset + x >= 0) {
                pw[offset + x] = replUnits[x];
              }
            }
            if (eqIdx >= 0) {
              hyph = eqIdx - outerPos[i];
              final truncAt = 2 + i + hyph;
              if (truncAt >= 0 && truncAt < pw.length) {
                pw[truncAt] = 0;
              }
            }
          }

          List<String?>? segRep;
          List<int>? segPos;
          List<int>? segCut;

          final segStart = begin + 1;
          final segLen = i - begin + 1 + hyph;
          if (segLen >= 0 && segStart + segLen <= pw.length) {
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
              lend: !(begin > 0) && lend,
              rend: !hyphens[i].isOdd && rend,
            );
          }

          for (var jj = 0; jj < i - begin; jj++) {
            hyphens[begin + jj] = hyphens2[jj];
            if (segRep != null && jj < segRep!.length && segRep![jj] != null) {
              outerRep ??= List<String?>.filled(wordSize, null);
              outerPos ??= List<int>.filled(wordSize, 0);
              outerCut ??= List<int>.filled(wordSize, 0);
              outerRep[begin + jj] = segRep![jj];
              outerPos[begin + jj] = segPos![jj];
              outerCut[begin + jj] = segCut![jj];
            }
          }
        }

        begin = i + 1;
      }

      if (begin == 0) {
        List<String?>? nlRep;
        List<int>? nlPos;
        List<int>? nlCut;

        _hyphenHyph(
          nextDict,
          wordUnits,
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
            wordUnits,
            wordSize,
            hyphens,
            nlRep,
            nlPos,
            nlCut,
            clhmin,
          );
        }
        if (!rend) {
          _hyphenRhmin(
            wordUnits,
            wordSize,
            hyphens,
            nlRep,
            nlPos,
            nlCut,
            crhmin,
          );
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

  void _hyphenLhmin(
    List<int> word,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
    int lhmin,
  ) {
    var charCount = 1;

    var j = 0;
    while (j < wordSize && _isDigitCodeUnit(word[j])) {
      charCount--;
      j++;
    }

    j = 0;
    while (charCount < lhmin && j < wordSize) {
      if (rep != null && pos != null && cut != null && rep[j] != null) {
        final eqIdx = rep[j]!.indexOf('=');
        if (eqIdx >= 0) {
          final lhsLen = (j - pos[j] + 1) + rep[j]!.substring(0, eqIdx).length;
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

  void _hyphenRhmin(
    List<int> word,
    int wordSize,
    Uint8List hyphens,
    List<String?>? rep,
    List<int>? pos,
    List<int>? cut,
    int rhmin,
  ) {
    var charCount = 0;

    var j = wordSize - 1;
    while (j > 0 && _isDigitCodeUnit(word[j])) {
      charCount--;
      j--;
    }

    for (j = wordSize - 1; charCount < rhmin && j > 0; j--) {
      if (rep != null && pos != null && cut != null && rep[j] != null) {
        final eqIdx = rep[j]!.indexOf('=');
        if (eqIdx >= 0) {
          final tailStart = j - pos[j] + cut[j] + 1;
          final rhsLen = (wordSize - tailStart) + rep[j]!.substring(eqIdx + 1).length;
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

  void _applyNohyphen(
    HyphenDict dict,
    String word,
    Uint8List hyphens, {
    required int zeroValue,
  }) {
    for (final nh in dict.noHyphenWords) {
      if (nh.isEmpty) {
        continue;
      }
      var idx = word.indexOf(nh);
      while (idx >= 0) {
        final end = idx + nh.length - 1;
        if (end < hyphens.length) {
          hyphens[end] = zeroValue;
        }
        if (idx > 0) {
          hyphens[idx - 1] = zeroValue;
        }
        idx = word.indexOf(nh, idx + 1);
      }
    }
  }

  HyphenTrans? _findTransition(HyphenState state, int ch) {
    for (final transition in state.transitions) {
      if (transition.ch == ch) {
        return transition;
      }
    }
    return null;
  }

  Uint8List? _tryGetMatch(HyphenState state) {
    try {
      return state.match;
    } catch (_) {
      return null;
    }
  }

  bool _isDigitCodeUnit(int value) => value >= charZero && value <= 0x39;
}
