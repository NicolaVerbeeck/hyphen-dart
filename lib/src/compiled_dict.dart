import 'dart:convert';
import 'dart:typed_data';

import 'package:hyphen_dart/src/model/automaton.dart';
import 'package:hyphen_dart/src/model/dict.dart';
import 'package:hyphen_dart/src/parser/automaton_builder.dart';

// The compiled dictionary format, version 1. Numbers are unsigned LEB128
// varints below 2^32, zigzag encoded where they can be negative. Strings are a
// length and UTF-8.
//
//   magic "\x89HYB" | version | flags: 1 for a UTF-8 dictionary, else 0 |
//     level count | the levels, top level first
//
// A level:
//   leftHyphenMin, rightHyphenMin, compoundLeftHyphenMin and
//     compoundRightHyphenMin (zigzag) | NOHYPHEN count, strings
//   state count n | alphabet size a (at most 65536), its characters ascending
//   the trie breadth-first: per state a 1 bit per child and a 0 bit, 2n - 1
//     bits, least significant bit first
//   the n - 1 edge labels (alphabet indices): a byte each, two (little
//     endian) when a > 256. Children are in alphabet order, so edge t leads to
//     state t + 1
//   pattern digit vectors, most used first: count, then per vector its length
//     and its digits, two per byte, low nibble first
//   per state the number of its vector, 0 for none
//   replacements: count, then per replacement its state, text, index (zigzag)
//     and cut (zigzag)
//
// Fallbacks and dense rows are rebuilt when loading: storing the fallbacks
// would double the file for a third less loading time.

/// The first bytes of a compiled dictionary. A libhyphen dictionary starts
/// with the name of its encoding instead, which is ASCII.
const _magic = [0x89, 0x48, 0x59, 0x42]; // "\x89HYB"

const _version = 1;

/// Compiles a [HyphenDict] into a compact binary form that loads several times
/// faster than a libhyphen dictionary. DictParser.parseBytes reads both.
class DictCompiler {
  const DictCompiler();

  /// Compiles [dict].
  ///
  /// Throws an [ArgumentError] when [dict] does not fit the format: a level
  /// with more than 65536 different characters, or a hyphen minimum or a
  /// replacement's index or cut outside the 32-bit range.
  Uint8List compile(HyphenDict dict) {
    final levels = [for (HyphenDict? d = dict; d != null; d = d.nextLevel) d];
    final out = _Writer()
      ..bytes(_magic)
      ..byte(_version)
      ..byte(dict.isUtf8 ? 1 : 0)
      ..varint(levels.length);
    for (final level in levels) {
      _writeLevel(out, level);
    }
    return out.takeBytes();
  }

  void _writeLevel(_Writer out, HyphenDict dict) {
    out
      ..signed(dict.leftHyphenMin)
      ..signed(dict.rightHyphenMin)
      ..signed(dict.compoundLeftHyphenMin)
      ..signed(dict.compoundRightHyphenMin)
      ..varint(dict.noHyphenWords.length);
    dict.noHyphenWords.forEach(out.string);

    final patterns = dict.patterns;
    final count = patterns.fallback.length;
    final alphabet = {...patterns.transChar}.toList()..sort();
    if (alphabet.length > 0x10000) {
      throw ArgumentError(
        'A level has ${alphabet.length} different characters, more than the '
        '65536 of a compiled dictionary',
      );
    }
    final classOf = {for (var i = 0; i < alphabet.length; ++i) alphabet[i]: i};
    out
      ..varint(count)
      ..varint(alphabet.length);
    alphabet.forEach(out.varint);

    // The states breadth-first, as order[new state] = state
    final order = Int32List(count);
    final labels = <int>[];
    final trie = _BitWriter();
    var added = 1;
    for (var i = 0; i < count; ++i) {
      final s = order[i];
      final edges = [
        for (
          var t = patterns.transStart[s];
          t < patterns.transStart[s + 1];
          ++t
        )
          t,
      ]..sort((a, b) => patterns.transChar[a].compareTo(patterns.transChar[b]));
      for (final t in edges) {
        trie.add(1);
        labels.add(classOf[patterns.transChar[t]]!);
        order[added++] = patterns.transTarget[t];
      }
      trie.add(0);
    }
    out.bytes(trie.takeBytes());
    for (final label in labels) {
      out.byte(label & 0xFF);
      if (alphabet.length > 256) out.byte(label >> 8);
    }

    // Few distinct digit vectors, so a table of them. Digits that are all 0
    // change no hyphen: without a replacement they are left out.
    final replacementOf = patterns.replacementOf;
    final vectorOf = List<String?>.filled(count, null);
    final uses = <String, int>{};
    for (var i = 0; i < count; ++i) {
      final s = order[i];
      final start = patterns.matchStart[s];
      if (start < 0) continue;
      final digits = patterns.matchData.sublist(
        start,
        start + patterns.matchLen[s],
      );
      final replaced = replacementOf != null && replacementOf[s] >= 0;
      if (!replaced && digits.every((d) => d == 0)) continue;
      final vector = vectorOf[i] = String.fromCharCodes(digits);
      uses[vector] = (uses[vector] ?? 0) + 1;
    }
    final vectors = uses.keys.toList()
      ..sort((a, b) {
        final byUse = uses[b]!.compareTo(uses[a]!);
        return byUse != 0 ? byUse : a.compareTo(b);
      });
    final number = {for (var i = 0; i < vectors.length; ++i) vectors[i]: i + 1};
    out.varint(vectors.length);
    for (final vector in vectors) {
      final digits = vector.codeUnits;
      out.varint(digits.length);
      for (var k = 0; k < digits.length; k += 2) {
        out.byte(digits[k] | (k + 1 < digits.length ? digits[k + 1] << 4 : 0));
      }
    }
    for (var i = 0; i < count; ++i) {
      final vector = vectorOf[i];
      out.varint(vector == null ? 0 : number[vector]!);
    }

    final replaced = [
      if (replacementOf != null)
        for (var i = 0; i < count; ++i)
          if (replacementOf[order[i]] >= 0) i,
    ];
    out.varint(replaced.length);
    for (final i in replaced) {
      final replacement = patterns.replacements[replacementOf![order[i]]];
      out
        ..varint(i)
        ..string(replacement.text)
        ..signed(replacement.index)
        ..signed(replacement.cut);
    }
  }
}

/// Whether [bytes] start like a dictionary compiled by [DictCompiler].
bool isCompiledDict(Uint8List bytes) {
  if (bytes.length < _magic.length) return false;
  for (var i = 0; i < _magic.length; ++i) {
    if (bytes[i] != _magic[i]) return false;
  }
  return true;
}

/// Loads a dictionary compiled by [DictCompiler].
///
/// Throws a [FormatException] when [bytes] are not a compiled dictionary of a
/// version this package reads.
HyphenDict loadCompiledDict(Uint8List bytes) {
  if (!isCompiledDict(bytes)) {
    throw const FormatException('Not a compiled hyphenation dictionary');
  }
  // A copy: reading a JS typed array or a view is much slower on the web.
  final reader = _Reader(Uint8List.fromList(bytes))..pos = _magic.length;
  final version = reader.byte();
  if (version != _version) {
    throw FormatException(
      'Unsupported compiled hyphenation dictionary version $version',
    );
  }
  final flags = reader.byte();
  if (flags > 1) throw _malformed;
  final levels = [
    for (var i = reader.varint(); i > 0; --i)
      _readLevel(reader, isUtf8: flags == 1),
  ];
  if (levels.isEmpty || reader.pos != bytes.length) {
    throw const FormatException('Malformed compiled hyphenation dictionary');
  }
  HyphenDict? dict;
  for (final level in levels.reversed) {
    dict = level(dict);
  }
  return dict!;
}

/// Reads a level; the result makes its [HyphenDict] with the next level.
HyphenDict Function(HyphenDict? nextLevel) _readLevel(
  _Reader reader, {
  required bool isUtf8,
}) {
  final leftHyphenMin = reader.signed();
  final rightHyphenMin = reader.signed();
  final compoundLeftHyphenMin = reader.signed();
  final compoundRightHyphenMin = reader.signed();
  final noHyphenWords = [
    for (var i = reader.varint(); i > 0; --i) reader.string(),
  ];

  final bytes = reader.bytes;
  final count = reader.varint();
  final alphabetSize = reader.varint();
  if (alphabetSize > bytes.length - reader.pos) throw _malformed;
  final alphabet = Int32List(alphabetSize);
  for (var i = 0; i < alphabetSize; ++i) {
    final char = reader.varint();
    // Code points, ascending
    if (char > 0x10FFFF || i > 0 && char <= alphabet[i - 1]) throw _malformed;
    alphabet[i] = char;
  }
  if (count < 1) throw _malformed;

  // The trie and its labels; edge t leads to state t + 1
  final trieBits = reader.take((2 * count + 6) ~/ 8) * 8;
  final trieEnd = trieBits + 2 * count - 1;
  final wide = alphabetSize > 256;
  final labels = reader.take(wide ? 2 * (count - 1) : count - 1);
  final transStart = Int32List(count + 1);
  final transChar = Int32List(count - 1);
  final transTarget = Int32List(count - 1);
  var bit = trieBits;
  var edges = 0;
  for (var s = 0; s < count; ++s) {
    // The parent of every state comes before it, so the root reaches it
    if (edges < s) throw _malformed;
    transStart[s] = edges;
    var previous = -1;
    while (bit < trieEnd && (bytes[bit >> 3] >> (bit & 7)) & 1 == 1) {
      if (edges == count - 1) throw _malformed;
      final label = wide
          ? bytes[labels + 2 * edges] | bytes[labels + 2 * edges + 1] << 8
          : bytes[labels + edges];
      // Children in alphabet order, each character once
      if (label <= previous || label >= alphabetSize) throw _malformed;
      previous = label;
      transChar[edges] = alphabet[label];
      transTarget[edges] = edges + 1;
      ++edges;
      ++bit;
    }
    ++bit;
  }
  transStart[count] = edges;
  if (edges != count - 1 || bit != trieEnd) throw _malformed;

  // Pattern digits
  final vectorCount = reader.varint();
  if (vectorCount > bytes.length - reader.pos) throw _malformed;
  final vectorStart = Int32List(vectorCount);
  final vectorLength = Int32List(vectorCount);
  final digits = <int>[];
  for (var v = 0; v < vectorCount; ++v) {
    final length = reader.varint();
    final packed = reader.take((length + 1) >> 1);
    vectorStart[v] = digits.length;
    vectorLength[v] = length;
    for (var k = 0; k < length; ++k) {
      final pair = bytes[packed + (k >> 1)];
      final digit = k.isEven ? pair & 0xF : pair >> 4;
      if (digit > 9) throw _malformed;
      digits.add(digit);
    }
  }
  final matchStart = Int32List(count);
  final matchLen = Int32List(count);
  for (var s = 0; s < count; ++s) {
    final vector = reader.varint();
    if (vector > vectorCount) throw _malformed;
    if (vector == 0) {
      matchStart[s] = -1;
    } else {
      matchStart[s] = vectorStart[vector - 1];
      matchLen[s] = vectorLength[vector - 1];
    }
  }

  Int32List? replacementOf;
  final replacements = <Replacement>[];
  for (var i = reader.varint(); i > 0; --i) {
    final state = reader.varint();
    if (state >= count) throw _malformed;
    replacementOf ??= Int32List(count)..fillRange(0, count, -1);
    replacementOf[state] = replacements.length;
    replacements.add(
      Replacement(reader.string(), reader.signed(), reader.signed()),
    );
  }

  final patterns = completeAutomaton(
    transStart: transStart,
    transChar: transChar,
    transTarget: transTarget,
    byDepth: null,
    matchStart: matchStart,
    matchLen: matchLen,
    matchData: Uint8List.fromList(digits),
    replacementOf: replacementOf,
    replacements: List.unmodifiable(replacements),
  );
  return (nextLevel) => HyphenDict(
    patterns: patterns,
    leftHyphenMin: leftHyphenMin,
    rightHyphenMin: rightHyphenMin,
    compoundLeftHyphenMin: compoundLeftHyphenMin,
    compoundRightHyphenMin: compoundRightHyphenMin,
    noHyphenWords: noHyphenWords,
    isUtf8: isUtf8,
    nextLevel: nextLevel,
  );
}

const _malformed = FormatException('Malformed compiled hyphenation dictionary');

final class _Writer {
  final _bytes = BytesBuilder();

  void byte(int value) => _bytes.addByte(value);

  void bytes(List<int> values) => _bytes.add(values);

  void varint(int value) {
    assert(value >= 0 && value <= 0xFFFFFFFF);
    while (value >= 0x80) {
      _bytes.addByte(value & 0x7F | 0x80);
      value >>= 7;
    }
    _bytes.addByte(value);
  }

  void signed(int value) {
    if (value < -0x80000000 || value > 0x7FFFFFFF) {
      throw ArgumentError.value(value, null, 'Does not fit in 32 bits');
    }
    // Multiplications, as shifts are 32-bit on the web
    varint(value >= 0 ? value * 2 : -value * 2 - 1);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    varint(encoded.length);
    _bytes.add(encoded);
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class _BitWriter {
  final _bytes = BytesBuilder();
  var _byte = 0;
  var _bits = 0;

  void add(int bit) {
    _byte |= bit << _bits;
    if (++_bits == 8) {
      _bytes.addByte(_byte);
      _byte = 0;
      _bits = 0;
    }
  }

  Uint8List takeBytes() {
    if (_bits > 0) _bytes.addByte(_byte);
    return _bytes.takeBytes();
  }
}

final class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  var pos = 0;

  int byte() {
    if (pos >= bytes.length) throw _malformed;
    return bytes[pos++];
  }

  /// Reads a varint, which is below 2^32 in this format.
  int varint() {
    final first = byte();
    return first < 0x80 ? first : _longVarint(first);
  }

  int _longVarint(int first) {
    var value = first & 0x7F;
    for (var shift = 7; shift < 28; shift += 7) {
      final b = byte();
      value |= (b & 0x7F) << shift;
      if (b < 0x80) return value;
    }
    final last = byte();
    if (last > 0xF) throw _malformed;
    return value | last << 28;
  }

  int signed() {
    final value = varint();
    // Divisions, as shifts are 32-bit on the web
    return value.isEven ? value ~/ 2 : -(value ~/ 2) - 1;
  }

  /// Skips [length] bytes and returns where they start.
  int take(int length) {
    if (pos + length > bytes.length) throw _malformed;
    final start = pos;
    pos += length;
    return start;
  }

  String string() {
    final start = take(varint());
    return utf8.decode(Uint8List.sublistView(bytes, start, pos));
  }
}
