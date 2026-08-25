import 'dart:math' as math;

/// String comparison for matching names people typed by hand.
///
/// This is not general-purpose fuzzy matching. It is tuned for one job —
/// deciding whether two patient records are the same person — and the errors
/// it has to survive are the ones front-desk staff actually make: a
/// transposition, a dropped vowel, a nickname, a name written as one word here
/// and two words there, and the same name transliterated differently by two
/// people on two days.
abstract final class TextSimilarity {
  /// Jaro similarity, 0–1.
  ///
  /// Chosen over edit distance because it weights *transpositions* as a single
  /// error rather than two. `Aryal` versus `Aryla` is one slip of the fingers
  /// and should score close to 1; Levenshtein charges it as two substitutions
  /// and drops it below a name that shares no letters in the same order.
  static double jaro(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    // Characters count as matching if they appear within this distance of each
    // other, which is what makes the measure tolerant of an inserted letter.
    final window = math.max(0, (math.max(a.length, b.length) / 2).floor() - 1);

    final aMatched = List<bool>.filled(a.length, false);
    final bMatched = List<bool>.filled(b.length, false);

    var matches = 0;
    for (var i = 0; i < a.length; i++) {
      final from = math.max(0, i - window);
      final to = math.min(b.length - 1, i + window);
      for (var j = from; j <= to; j++) {
        if (bMatched[j] || a[i] != b[j]) continue;
        aMatched[i] = true;
        bMatched[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0;

    // Count matched pairs that appear in a different order in each string.
    var transpositions = 0;
    var k = 0;
    for (var i = 0; i < a.length; i++) {
      if (!aMatched[i]) continue;
      while (!bMatched[k]) {
        k++;
      }
      if (a[i] != b[k]) transpositions++;
      k++;
    }

    final m = matches.toDouble();
    return (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
  }

  /// Jaro–Winkler: Jaro, with a bonus for a shared prefix.
  ///
  /// The prefix bonus is right for names specifically. People mistype and
  /// abbreviate the *ends* of names far more than the beginnings, so agreement
  /// at the start is stronger evidence of identity than agreement anywhere
  /// else.
  static double jaroWinkler(String a, String b, {double scale = 0.1}) {
    final base = jaro(a, b);
    // Applying the bonus to weak matches inflates unrelated names that happen
    // to share a first letter, which on a large register is most of them.
    if (base < 0.7) return base;

    var prefix = 0;
    final limit = math.min(4, math.min(a.length, b.length));
    while (prefix < limit && a[prefix] == b[prefix]) {
      prefix++;
    }
    return base + prefix * scale * (1 - base);
  }

  /// Strips everything that varies between two spellings of the same name:
  /// case, accents, punctuation and spacing.
  static String normaliseName(String value) {
    final lower = value.toLowerCase().trim();
    final builder = StringBuffer();
    for (final char in lower.split('')) {
      final folded = _diacritics[char];
      if (folded != null) {
        builder.write(folded);
      } else if (RegExp(r'[a-z0-9]').hasMatch(char)) {
        builder.write(char);
      }
      // Everything else — hyphens, apostrophes, spaces — is dropped, so
      // `O'Brien`, `OBrien` and `o brien` collapse to one form.
    }
    return builder.toString();
  }

  /// Digits only, so `+977 98-1234567` and `09812 34567` compare equal.
  ///
  /// Compared on the last nine digits: the same number is written with and
  /// without a country code and with and without a trunk zero, and the tail is
  /// the part that is actually stable.
  static String? normalisePhone(String? value) {
    if (value == null) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    return digits.length <= 9
        ? digits
        : digits.substring(digits.length - 9);
  }

  /// A crude but effective transliteration fold, plus the vowel-dropping that
  /// makes `Muhammad`/`Mohammed` and `Krishna`/`Krsna` comparable.
  ///
  /// Keeps the first letter and all consonants. Names transliterated from
  /// scripts without written vowels vary almost entirely in their vowels, and
  /// two spellings of one name usually share their consonant skeleton exactly.
  static String consonantSkeleton(String value) {
    final normalised = normaliseName(value);
    if (normalised.isEmpty) return '';
    final builder = StringBuffer(normalised[0]);
    for (var i = 1; i < normalised.length; i++) {
      if (!_vowels.contains(normalised[i])) builder.write(normalised[i]);
    }
    return builder.toString();
  }

  static const Set<String> _vowels = <String>{'a', 'e', 'i', 'o', 'u'};

  static const Map<String, String> _diacritics = <String, String>{
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ō': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ç': 'c', 'ñ': 'n', 'ß': 'ss', 'ø': 'o', 'æ': 'ae', 'œ': 'oe',
    'š': 's', 'ž': 'z', 'ý': 'y', 'ÿ': 'y', 'ð': 'd', 'þ': 'th',
  };
}
