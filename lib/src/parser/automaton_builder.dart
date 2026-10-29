import 'dart:typed_data';

import 'package:hyphen_dart/src/model/automaton.dart';

/// States with at least this many transitions get a row in
/// [PatternAutomaton.rows].
const _denseRowMinTransitions = 8;

/// Completes a trie into a [PatternAutomaton]: adds the fallback states, the
/// alphabet classes and the dense rows.
///
/// The trie is given as the transitions of each state ([transStart],
/// [transChar] and [transTarget]) and its states by depth: [byDepth], or null
/// when the states are numbered by depth already.
PatternAutomaton completeAutomaton({
  required Int32List transStart,
  required Int32List transChar,
  required Int32List transTarget,
  required Int32List? byDepth,
  required Int32List matchStart,
  required Int32List matchLen,
  required Uint8List matchData,
  required Int32List? replacementOf,
  required List<Replacement> replacements,
}) {
  final count = transStart.length - 1;

  // Alphabet classes
  final classLow = Int32List(classLowLimit)..fillRange(0, classLowLimit, -1);
  final classHigh = <int, int>{};
  var alphabetSize = 0;
  final transClass = Int32List(transChar.length);
  for (var t = 0; t < transChar.length; ++t) {
    final char = transChar[t];
    if (char < classLowLimit) {
      if (classLow[char] < 0) classLow[char] = alphabetSize++;
      transClass[t] = classLow[char];
    } else {
      transClass[t] = classHigh.putIfAbsent(char, () => alphabetSize++);
    }
  }

  // Rows with the transitions of the states with many of them
  final rowOf = Int32List(count)..fillRange(0, count, -1);
  var rowCount = 0;
  for (var s = 0; s < count; ++s) {
    if (transStart[s + 1] - transStart[s] >= _denseRowMinTransitions) {
      rowOf[s] = rowCount++;
    }
  }
  final rows = Int32List(rowCount * alphabetSize)
    ..fillRange(0, rowCount * alphabetSize, -1);
  for (var s = 0; s < count; ++s) {
    final row = rowOf[s];
    if (row < 0) continue;
    for (var t = transStart[s]; t < transStart[s + 1]; ++t) {
      rows[row * alphabetSize + transClass[t]] = transTarget[t];
    }
  }

  // Fallback states: the longest proper suffix that is a state. Visiting the
  // states by depth makes every shorter suffix ready when it is needed.
  final fallback = Int32List(count);
  fallback[0] = -1; // The root; the states below it fall back to it (0)
  for (var i = 1; i < count; ++i) {
    final parent = byDepth == null ? i : byDepth[i];
    for (var t = transStart[parent]; t < transStart[parent + 1]; ++t) {
      final cls = transClass[t];
      for (var f = fallback[parent]; ; f = fallback[f]) {
        var next = -1;
        final row = rowOf[f];
        if (row >= 0) {
          next = rows[row * alphabetSize + cls];
        } else {
          for (var u = transStart[f]; u < transStart[f + 1]; ++u) {
            if (transClass[u] == cls) {
              next = transTarget[u];
              break;
            }
          }
        }
        if (next >= 0) {
          fallback[transTarget[t]] = next;
          break;
        }
        if (f == 0) break;
      }
    }
  }

  // Follow the fallbacks for the classes a row has no transition for. By
  // depth, so that the rows of the (shorter) fallback states are complete.
  for (var i = 1; i < count; ++i) {
    final s = byDepth == null ? i : byDepth[i];
    final row = rowOf[s];
    if (row < 0) continue;
    for (var cls = 0; cls < alphabetSize; ++cls) {
      if (rows[row * alphabetSize + cls] >= 0) continue;
      var next = -1;
      for (var f = fallback[s]; f >= 0; f = fallback[f]) {
        final fallbackRow = rowOf[f];
        if (fallbackRow >= 0) {
          next = rows[fallbackRow * alphabetSize + cls];
          break;
        }
        for (var u = transStart[f]; u < transStart[f + 1]; ++u) {
          if (transClass[u] == cls) {
            next = transTarget[u];
            break;
          }
        }
        if (next >= 0) break;
      }
      rows[row * alphabetSize + cls] = next;
    }
  }

  return PatternAutomaton(
    transStart: transStart,
    transChar: transChar,
    transTarget: transTarget,
    fallback: fallback,
    classLow: classLow,
    classHigh: classHigh,
    alphabetSize: alphabetSize,
    rowOf: rowOf,
    rows: rows,
    matchStart: matchStart,
    matchLen: matchLen,
    matchData: matchData,
    replacementOf: replacementOf,
    replacements: replacements,
  );
}
