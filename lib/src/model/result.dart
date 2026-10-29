import 'dart:typed_data';

import 'package:hypen_dart/src/model/consts.dart';
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
}
