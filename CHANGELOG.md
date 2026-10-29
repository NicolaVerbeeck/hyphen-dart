## 1.0.0

- Initial version: a port of libhyphen that gives the same results, on the VM
  and the web.
- `DictParser` reads libhyphen dictionaries (`hyph_xx_XX.dic`) in UTF-8 or
  ISO-8859-1, with non-standard hyphenation, compound words,
  `LEFTHYPHENMIN`, `RIGHTHYPHENMIN` and `NOHYPHEN`.
- `DictCompiler` and `dart run hyphen_dart:compile_dict` compile a dictionary
  into a binary form that is 1.6 to 3.4 times smaller and loads 4 to 7 times
  faster. `DictParser.parseBytes` recognizes it by its first bytes.
