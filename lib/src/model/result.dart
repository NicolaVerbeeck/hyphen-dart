import 'dart:typed_data';

import 'package:hyphen_dart/src/model/consts.dart';
import 'package:meta/meta.dart';

class HyphenResult {
  @internal
  HyphenResult(
    this.hyphens,
    this._word,
    this._marks,
    this._rep,
    this._pos,
    this._cut,
  );

  /// Zero-based indices after which a hyphen may be inserted, counted in code
  /// points of the word. They are code-unit indices too when the word has no
  /// characters outside the Basic Multilingual Plane.
  final List<int> hyphens;

  /// The hyphenated word using '=' for standard breaks or replacement text
  /// for nonstandard hyphenation patterns. Built on first use.
  late final String hyphword = _hyphWord();

  /// The breaks at [hyphens], in the same order: the two parts the word
  /// becomes at each of them. Built on first use.
  ///
  /// Most breaks only split the word, but with non-standard hyphenation the
  /// letters around the break change too: the Hungarian "hosszúság" breaks
  /// into "hosz" and "szúság".
  late final List<HyphenBreak> breaks = List.unmodifiable([
    for (final index in hyphens) _breakAt(index),
  ]);

  /// The part of the word between two of its [breaks], without hyphens: from
  /// [from], or the start of the word when it is null, up to [to], or the end
  /// of the word. A word broken over three lines is `part(null, first)`,
  /// `part(first, second)` and `part(second, null)`.
  ///
  /// Throws an [ArgumentError] when a break is not one of [breaks], or when
  /// [to] cannot follow [from] (see [HyphenBreak.canFollow]).
  String part(HyphenBreak? from, HyphenBreak? to) {
    if (from != null && !identical(from._word, _word)) {
      throw ArgumentError('from is not a break of this word');
    }
    if (to != null && !identical(to._word, _word)) {
      throw ArgumentError('to is not a break of this word');
    }
    if (from != null && to != null && !to.canFollow(from)) {
      throw ArgumentError(
        'The break after ${to.index} cannot follow the break after '
        '${from.index}',
      );
    }
    final start = from?.end ?? 0;
    final end = to?.start ?? _word.length;
    return (from?.after ?? '') +
        String.fromCharCodes(_word, start, end) +
        (to?.before ?? '');
  }

  final Int32List _word;

  /// Hyphenation values per code point, odd where a break is allowed.
  final Uint8List _marks;

  final List<String?>? _rep;
  final Int32List? _pos;
  final Int32List? _cut;

  // Equivalent to the hnj_hyphen_hyphword method
  String _hyphWord() {
    final word = _word;
    final hyphens = _marks;
    if (word.isEmpty) {
      return '';
    }

    // Define a maximum limit to provide c equivalence
    final maxLength = word.length * 2 - 1;

    final rep = _rep;
    final pos = _pos;
    final cut = _cut;
    if (rep == null || pos == null || cut == null) {
      // String.fromCharCodes is only fast for List<int>, Uint8List and
      // Uint16List, not for an Int32List.
      var maxChar = 0;
      for (var i = 0; i < word.length; ++i) {
        if (word[i] > maxChar) maxChar = word[i];
      }
      final List<int> result = maxChar < 0x100
          ? Uint8List(maxLength)
          : maxChar < 0x10000
          ? Uint16List(maxLength)
          : List<int>.filled(maxLength, 0);
      var length = 0;
      for (var i = 0; i < word.length && length < maxLength; ++i) {
        result[length++] = word[i];
        if (hyphens[i].isOdd && length < maxLength) {
          result[length++] = charEquals;
        }
      }
      return String.fromCharCodes(result, 0, length);
    }

    // Dynamic buffer to build the result
    final result = <int>[];
    for (var i = 0; i < word.length && result.length < maxLength; ++i) {
      // Always add the current character first
      result.add(word[i]);

      // If there is a hyphenation point here (odd value)
      if (hyphens[i].isOdd && result.length < maxLength) {
        final replacement = rep[i];
        if (replacement == null) {
          // --- Standard Hyphenation ---
          result.add(charEquals);
          continue;
        }
        // --- Non-standard Hyphenation ---
        final position = pos[i];
        final cutLength = cut[i];

        // 1. Backtrack: Remove 'position' characters from the end of the output buffer.
        //    This corresponds to 'j -= (*pos)[i]' in C.
        if (position > 0) {
          if (position <= result.length) {
            result.length -= position;
          } else {
            result.clear(); // Safety check
          }
        }

        // 2. Append replacement string (e.g., "k-k") without going over
        //    maxLength.
        for (final rune in replacement.runes) {
          if (result.length >= maxLength) break;
          result.add(rune);
        }

        // 3. Skip the characters of the word that the replacement replaced:
        //    i (current) + cut (consumed) - position (backtracked).
        i += cutLength - position;
      }
    }

    return String.fromCharCodes(result);
  }

  HyphenBreak _breakAt(int index) {
    final word = _word;
    final rep = _rep;
    final replacement = rep != null && index < rep.length ? rep[index] : null;
    if (replacement == null) {
      final at = index < word.length ? index + 1 : word.length;
      return HyphenBreak._(word, index, at, at, '', '');
    }
    // As in hnj_hyphen_hyphword: the replacement starts pos code points before
    // the break and takes the place of cut code points. The range stays inside
    // the word, wherever a malformed dictionary points.
    final start = (index + 1 - _pos![index]).clamp(0, word.length);
    final end = (start + _cut![index]).clamp(start, word.length);
    final hyphen = replacement.indexOf('=');
    return HyphenBreak._(
      word,
      index,
      start,
      end,
      hyphen < 0 ? replacement : replacement.substring(0, hyphen),
      hyphen < 0 ? '' : replacement.substring(hyphen + 1),
    );
  }
}

/// A place where a word may be broken, and the two parts it becomes there:
/// [firstPart] ends a line, followed by a hyphen, and [secondPart] starts the
/// next one. [HyphenResult.part] gives the parts of a word broken at more
/// than one place.
///
/// Positions are counted in code points of the word, like
/// [HyphenResult.hyphens].
final class HyphenBreak {
  HyphenBreak._(
    this._word,
    this.index,
    this.start,
    this.end,
    this.before,
    this.after,
  );

  final Int32List _word;

  /// The code point the break follows, as in [HyphenResult.hyphens].
  final int index;

  /// Where the code points that the break replaces start. The same as [end],
  /// right after [index], when the break only splits the word.
  final int start;

  /// Where the code points that the break replaces end, exclusive.
  final int end;

  /// What [firstPart] ends with in place of the replaced code points. Empty
  /// when the break only splits the word.
  final String before;

  /// What [secondPart] starts with in place of the replaced code points.
  /// Empty when the break only splits the word.
  final String after;

  /// The word up to the break, without a hyphen: "hosz" for the first break
  /// of "hosszúság". The same as `part(null, this)`.
  String get firstPart => String.fromCharCodes(_word, 0, start) + before;

  /// The word from the break on: "szúság" for the first break of
  /// "hosszúság". The same as `part(this, null)`.
  String get secondPart => after + String.fromCharCodes(_word, end);

  /// Whether the word can be broken at [previous], one of its breaks, and
  /// then at this break: this break has to come after the code points that
  /// [previous] replaces, and not replace any of them itself.
  bool canFollow(HyphenBreak previous) =>
      index >= previous.end && start >= previous.end;
}
