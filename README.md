# hyphen-dart

[![Version](https://img.shields.io/pub/v/hyphen_dart.svg)](https://pub.dev/packages/hyphen_dart)
[![test](https://github.com/NicolaVerbeeck/hyphen-dart/actions/workflows/pr-cicd.yml/badge.svg)](https://github.com/NicolaVerbeeck/hyphen-dart/actions/workflows/pr-cicd.yml)
[![codecov](https://codecov.io/gh/NicolaVerbeeck/hyphen-dart/graph/badge.svg)](https://codecov.io/gh/NicolaVerbeeck/hyphen-dart)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/NicolaVerbeeck/hyphen-dart/badge)](https://securityscorecards.dev/viewer/?uri=github.com/NicolaVerbeeck/hyphen-dart)

Hyphenation for Dart with the TeX based patterns of
[libhyphen](https://github.com/hunspell/hyphen), the hyphenation library of
LibreOffice and hunspell. A port of libhyphen that gives the same results, on
the Dart VM, in Flutter and on the web (dart2js and dart2wasm).

## Features

- **libhyphen dictionaries as they are**: the `hyph_xx_XX.dic` files of
  LibreOffice and hunspell, in UTF-8 or ISO-8859-1.
- **The same results as libhyphen**, checked word by word against the C library
  on millions of words, including non-standard hyphenation (`ssz` becomes
  `sz=sz` in Hungarian), compound words, `LEFTHYPHENMIN` and
  `RIGHTHYPHENMIN`, and `NOHYPHEN`.
- **Fast**: a word hyphenates in about 0.3 µs, and the English dictionary
  loads in 0.7 ms (0.13 ms compiled).
- **Compiled dictionaries** that are 1.6 to 3.4 times smaller and load 4 to 7
  times faster.
- **Pure Dart** without `dart:io`: the same code on every platform.

## Getting started

```yaml
dependencies:
  hyphen_dart: ^2.1.0
```

Parse a dictionary once and hyphenate with it:

```dart
import 'package:hyphen_dart/hyphen_dart.dart';

final dict = DictParser().parseBytes(bytes); // the bytes of hyph_en_US.dic

final result = const Hyphenator().hyphenate(dict, 'hyphenation');
result.hyphens;  // [1, 5]: a break may follow these characters
result.hyphword; // 'hy=phen=ation'
```

`DictParser.parseLines` parses a dictionary given as lines instead. A
`HyphenDict` is immutable, so one instance per language can be shared.

## Dictionaries

The [LibreOffice dictionaries](https://github.com/LibreOffice/dictionaries)
have libhyphen dictionaries for many languages, each with its own license.
The first line of a dictionary names its encoding; the patterns follow, with
optional settings:

```
UTF-8
LEFTHYPHENMIN 2
RIGHTHYPHENMIN 3
.a2b
as5szon2y/sz=,2,1
```

A dictionary has two pattern levels: the first one finds compound boundaries
and the second one hyphenates the parts. Without a `NEXTLEVEL` line, the first
level breaks words at hyphens and apostrophes only, as in libhyphen.

Like libhyphen, the hyphenator expects the patterns to be preprocessed by
libhyphen's `substrings.pl`, as the published dictionaries are: a pattern
does not pick up the digits of the shorter patterns inside it.

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
git tag v2.1.0 && git push origin v2.1.0
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
