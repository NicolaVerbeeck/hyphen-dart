# hyphen-dart

A Dart implementation of hyphenation using converted TeX hyphenation patterns.

## Features

- Hyphenate text using TeX-based hyphenation patterns
- Support for multiple languages
- Efficient pattern matching and word breaking
- Zero external dependencies

## Getting started

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  hyphen: ^1.0.0
```

## Compiled dictionaries

`DictParser.parseBytes` loads libhyphen `.dic` files as they are. Compiled once,
a dictionary is 1.6 to 3.4 times smaller and loads 4 to 7 times faster:

```bash
dart run hypen_dart:compile_dict hyph_de_DE.dic hyph_de_DE.hyb
```

`parseBytes` recognizes a compiled dictionary by its first bytes, so the same
call loads both. A compiled dictionary of a format version that the package
does not read throws a `FormatException`: compile it again.
