## 2.0.0

- Faster: dictionaries parse about 6x faster and words hyphenate 2-4x faster,
  the patterns are compiled into flat arrays.
- Digits end a word, like in libhyphen (before, patterns with a `.` did not
  match next to a digit).
- Fixed: non-standard hyphenation at a compound boundary threw
  `Bad state: Too few elements` on the web.
- Fixed: `DictParser.parseBytes` read bytes outside the given `Uint8List` view.
- `HyphenResult.hyphword` is built on first use.
- Breaking: removed `HyphenState`, `HyphenTrans` and `HyphenDict.states`.
  `HyphenDict` and `HyphenResult` are created by the package only.

## 1.0.0

- Initial version.
