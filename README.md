# hyphen_dart

[![Version](https://img.shields.io/pub/v/hyphen_dart.svg)](https://pub.dev/packages/hyphen_dart)
[![test](https://github.com/NicolaVerbeeck/hyphen-dart/actions/workflows/pr-cicd.yml/badge.svg)](https://github.com/NicolaVerbeeck/hyphen-dart/actions/workflows/pr-cicd.yml)
[![codecov](https://codecov.io/gh/NicolaVerbeeck/hyphen-dart/graph/badge.svg)](https://codecov.io/gh/NicolaVerbeeck/hyphen-dart)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/NicolaVerbeeck/hyphen-dart/badge)](https://securityscorecards.dev/viewer/?uri=github.com/NicolaVerbeeck/hyphen-dart)

**LibreOffice's hyphenation, in pure Dart.** hyphen_dart is a port of
[libhyphen](https://github.com/hunspell/hyphen), the hyphenation engine of
LibreOffice and Hunspell, that finds exactly the same breaks: on the Dart VM,
in Flutter and on the web.

```dart
const hyphenator = Hyphenator();
hyphenator.hyphenate(english, 'hyphenation').hyphword;   // 'hy=phen=ation'
hyphenator.hyphenate(german, 'silbentrennung').hyphword; // 'sil=ben=tren=nung'
hyphenator.hyphenate(hungarian, 'hosszúság').hyphword;   // 'hosz=szú=ság'
```

That last word gained a letter. Hungarian writes some double consonants out in
full when a word breaks inside them, and hyphen_dart hands a text layout the
exact text to put on each line.

## Why hyphen_dart

- **The same breaks as libhyphen.** Checked word by word against the C
  library on 2.8 million words from all 50 LibreOffice dictionaries and TeX's
  81 pattern sets: the results only differ for 7 Albanian words, where
  libhyphen cuts a letter in half.
- **Breaks that change the word.** Non-standard hyphenation, like Hungarian's
  `hosz-szú`, with the parts of the word at every break, also for a word broken
  over several lines.
- **Fast enough for live text layout.** About 0.3 µs a word on the VM and under
  0.4 µs on the web: hyphenating a whole page takes a fraction of a
  millisecond.
- **Compiled dictionaries.** 1.6 to 3.4 times smaller and 4 to 7 times faster
  to load: Hungarian, one of the largest, loads in about 4 ms.
- **50 ready-made dictionaries.** Every LibreOffice hyphenation dictionary
  loads as it is, and so do all 81 of TeX's pattern sets after a conversion.
- **Pure Dart.** No `dart:io` and no native code: the VM, Flutter, dart2js and
  dart2wasm, all tested in CI.

## Getting started

```yaml
dependencies:
  hyphen_dart: ^1.0.0
```

Load a dictionary once, then hyphenate with it as often as you like:

```dart
import 'package:hyphen_dart/hyphen_dart.dart';

final dict = DictParser().parseBytes(bytes); // the bytes of hyph_en_US.dic

final result = const Hyphenator().hyphenate(dict, 'hyphenation');
result.hyphens;  // [1, 5]: a break may follow these characters
result.hyphword; // 'hy=phen=ation'
```

Like libhyphen, the hyphenator takes the word as it is: pass it in lower case,
without the punctuation around it, as LibreOffice does.

`DictParser.parseLines` parses a dictionary given as lines instead. A
`HyphenDict` is immutable, so one instance per language can be shared.

## Dictionaries

### Where to find them

hyphen_dart doesn't ship dictionaries. These are good places to get them:

| Source | What you get |
|---|---|
| [LibreOffice dictionaries](https://github.com/LibreOffice/dictionaries) | 50 libhyphen dictionaries (`hyph_*.dic`) for 45 languages, ready to use |
| Linux distributions | The same files, packaged: Debian's `hyphen-*` packages install them in `/usr/share/hyphen` |
| [hyph-utf8](https://github.com/hyphenation/tex-hyphen) (also on [CTAN](https://ctan.org/pkg/hyph-utf8)) | TeX's 81 pattern sets, which [need converting](#converting-tex-patterns) first |

> **Check the licenses yourself.** Every dictionary has its own license, and
> some ask you to keep their notice. Before you ship a dictionary, read its
> license: the README or license file next to it in LibreOffice's repository,
> or the header of a TeX pattern file.

### The format

The first line of a dictionary names its encoding; the patterns follow, with
optional settings:

```
UTF-8
LEFTHYPHENMIN 2
RIGHTHYPHENMIN 3
.a2b
as5szon2y/sz=,2,1
```

The last pattern is a non-standard one, which changes letters at the break;
libhyphen's
[README.nonstandard](https://github.com/hunspell/hyphen/blob/master/README.nonstandard)
describes them.

A dictionary has two pattern levels: the first one finds compound boundaries
and the second one hyphenates the parts. Without a `NEXTLEVEL` line, the first
level breaks words at hyphens and apostrophes only, as in libhyphen.

Like libhyphen, the hyphenator expects the patterns to be preprocessed by
libhyphen's `substrings.pl`, as the published dictionaries are: a pattern
does not pick up the digits of the shorter patterns inside it.

### Converting TeX patterns

libhyphen's
[`substrings.pl`](https://github.com/hunspell/hyphen/blob/master/substrings.pl)
turns TeX patterns into a dictionary. Put the patterns of the `\patterns{...}`
group in a file, one per line, after a comment line and an empty line, and
pass the encoding and the minimums from the TeX file's header:

```bash
perl substrings.pl hyph-de-1996.pat hyph_de_DE.dic UTF-8 2 2
```

The comment and the empty line matter: `substrings.pl` copies the comments at
the top of the file and drops the line that ends them. libhyphen has no
exception lists, so a `\hyphenation{...}` group is left out.

## Results

`HyphenResult.hyphens` lists the positions after which a break is allowed,
counted in code points of the word. They are UTF-16 indices too unless the
word has characters outside the Basic Multilingual Plane, such as emoji.

`HyphenResult.hyphword` is the word with `=` at every break, built on first
use. Non-standard hyphenation changes the word around a break, which is why it
is there:

```dart
final result = const Hyphenator().hyphenate(hungarian, 'hosszúság');
result.hyphens;  // [2, 5]
result.hyphword; // 'hosz=szú=ság'
```

### Breaking a line

To break a line at one of these places, `HyphenResult.breaks` gives each break
with the two parts the word becomes, and the code points that the break
replaces. A text layout measures and paints the parts, and maps the replaced
code points back to the word for the caret and selection:

```dart
final first = result.breaks.first;
first.firstPart;             // 'hosz', followed by a hyphen
first.secondPart;            // 'szúság', on the next line
(first.start, first.end);    // (2, 3): the first 's' is replaced
(first.before, first.after); // ('sz', ''): by 'sz' in the first part
```

How much a break replaces depends on the dictionary, but the parts do not:
with a dictionary that replaces 'ssz' by 'sz' and 'sz', this break is (2, 5)
and ('sz', 'sz').

A word broken over more than two lines takes its parts from
`HyphenResult.part`, between two of its breaks. `HyphenBreak.canFollow` tells
whether a break can come after the one on the line before: not when it lies in
the letters that one replaces.

```dart
final [first, second] = result.breaks;
result.part(null, first);   // 'hosz'
result.part(first, second); // 'szú'
result.part(second, null);  // 'ság'
second.canFollow(first);    // true
```

## Compiled dictionaries

Compile a dictionary once to make it smaller and faster to load:

```bash
dart run hyphen_dart:compile_dict hyph_de_DE.dic hyph_de_DE.hyb
```

`DictParser.parseBytes` recognizes a compiled dictionary by its first bytes, so
the same call loads both kinds. `DictCompiler` compiles from code. A compiled
dictionary of a format version that the package does not read throws a
`FormatException`: compile it again.

| Dictionary | libhyphen file | Compiled | Brotli, libhyphen → compiled |
|---|---|---|---|
| en_US | 36 KB | 19 KB | 16.4 → 12.0 KB |
| nl_NL | 84 KB | 43 KB | 34.5 → 23.9 KB |
| hu_HU | 876 KB | 310 KB | 254 → 153 KB |

## Performance

Loading a dictionary, libhyphen file → compiled:

| Dictionary | VM (AOT) | dart2wasm | dart2js |
|---|---|---|---|
| en_US | 0.69 → 0.13 ms | 0.64 → 0.15 ms | 1.00 → 0.16 ms |
| hu_HU | 20.0 → 3.9 ms | 17.1 → 4.0 ms | 23.0 → 4.8 ms |

Hyphenating a word, on average over 235,976 English words with the German
dictionary:

| | VM (AOT) | dart2wasm | dart2js |
|---|---|---|---|
| Positions | 0.29 µs | 0.33 µs | 0.39 µs |
| Positions and `hyphword` | 0.35 µs | 0.39 µs | 0.65 µs |

Measured on an Apple Silicon Mac, with Node 26 for the web builds.

## hyphen_dart and the hyphenation package

[hyphenation](https://pub.dev/packages/hyphenation) is another pure Dart
hyphenation package. It implements TeX's algorithm for TeX pattern files, and
[flutter_hyphenation](https://pub.dev/packages/flutter_hyphenation) adds a
hyphenating `Text` widget for Flutter.

With the same patterns, both packages mostly find the same breaks: all of
801,257 words in English, German and Hungarian, for example. Across all 81
pattern sets of hyph-utf8, checked against TeX's own algorithm, words with
combining marks or zero-width joiners (Indic scripts, Coptic, Church Slavonic,
accented Latin) break as in TeX with hyphen_dart, while hyphenation 1.0.2
shifts or loses those breaks. In languages that allow a break after the first
letter, hyphen_dart, like libhyphen, breaks some two-letter words that TeX
leaves whole.

Where they differ:

| | hyphen_dart | hyphenation |
|---|---|---|
| Letters that change at a break (Hungarian `hosz-szú`) | ✓ | ✗ TeX patterns can't express it |
| Combining marks and zero-width joiners | ✓ as in TeX | ✗ breaks shifted or missing |
| Dictionaries | libhyphen's (LibreOffice has 50), compiled ones, TeX's after a conversion | TeX's (hyph-utf8 has 81) |
| Compound word levels (`NEXTLEVEL`) and `NOHYPHEN` | ✓ | ✗ |
| Exception lists (`\hyphenation`) | ✗ written as patterns | ✓ |
| Minimum characters around a break | read from the dictionary | set in code |
| Case and punctuation around a word | up to the caller | handled |
| Cache for repeated words | none: a `Map` in front costs 16 ns a word | built in: 9 ns a word |
| Line breaking and a Flutter widget | ✗ made for your own text layout | ✓ |
| License | MPL 1.1 | MIT |

Speed, with the same TeX patterns and without caches:

| | English | German | Hungarian |
|---|---|---|---|
| Hyphenating a word: hyphen_dart | 301 ns | 396 ns | 383 ns |
| Hyphenating a word: hyphenation | 346 ns | 559 ns | 577 ns |
| Loading: hyphen_dart, compiled | 0.15 ms | 1.67 ms | 3.47 ms |
| Loading: hyphenation | 0.36 ms | 3.69 ms | 6.93 ms |
| Loading: hyphen_dart, libhyphen file | 0.83 ms | 9.04 ms | 15.5 ms |

Measured with hyphenation 1.0.2, AOT on an Apple Silicon Mac, with the en-us,
de-1996 and hu patterns of hyph-utf8.

In short: pick hyphenation for hyphenated Flutter `Text` with TeX patterns out
of the box. Pick hyphen_dart for LibreOffice's results, for text whose letters
change at a break or that has combining marks, or for a text layout of your
own.

## Development

libhyphen is a git submodule in `third_party/hyphen`: its test files are the
expected results of the tests. Without it, `dart pub publish --dry-run`
reports its empty folder as a gitignored file.

```bash
git clone --recurse-submodules https://github.com/NicolaVerbeeck/hyphen-dart.git
```

```bash
dart test
```

The tests without `dart:io` also run compiled for the web, which needs Node:

```bash
dart test --platform node --compiler dart2js --compiler dart2wasm
```

Coverage ends up in `coverage/lcov.info`:

```bash
dart run coverage:test_with_coverage
```

## CI/CD

| Workflow | Runs on | Does |
|---|---|---|
| `pr-cicd.yml` | pull requests, pushes to `main` | formatting, `dart analyze --fatal-infos` and `dart pub publish --dry-run`; the tests with coverage to Codecov and a test report; the tests compiled with dart2js and dart2wasm on Node |
| `publish.yml` | tags `vX.Y.Z` | publishes to pub.dev |
| `scorecard.yml` | pushes to `main`, weekly | the OpenSSF Scorecard |
| `dependency-review.yml` | pull requests | flags vulnerable dependencies |

Dependabot updates the dependencies weekly and the GitHub Actions daily.

To release, update the version in `pubspec.yaml` and `CHANGELOG.md`, merge, and
push a tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Publishing uses pub.dev's automated publishing with GitHub Actions, enabled on
pub.dev for this repository with the tag pattern `v{{version}}` and the
`pub.dev` environment. Codecov needs the `CODECOV_TOKEN` secret.

## License

MPL 1.1, see [LICENSE](LICENSE). libhyphen, which this package is ported
from, is available under the GPL 2.0, the LGPL 2.1 or the MPL 1.1, or any
later version of them.

## Additional information

For more information, visit the
[GitHub repository](https://github.com/NicolaVerbeeck/hyphen-dart).

If you encounter any issues or have feature requests, please file them on the
[issue tracker](https://github.com/NicolaVerbeeck/hyphen-dart/issues).
