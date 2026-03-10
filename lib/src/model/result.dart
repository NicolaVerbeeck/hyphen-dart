class HyphenResult {
  /// Zero-based code-unit indices after which a hyphen may be inserted.
  final List<int> hyphens;

  /// The hyphenated word using '=' for standard breaks or replacement text
  /// for nonstandard hyphenation patterns.
  final String hyphword;

  const HyphenResult({required this.hyphens, required this.hyphword});
}
