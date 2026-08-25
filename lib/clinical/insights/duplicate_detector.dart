import 'dart:math' as math;

import '../explanations.dart';
import '../../core/utils/text_similarity.dart';

/// The fields a duplicate check compares. Kept free of the `Patient` model so
/// this stays pure logic that can be tested without a database.
class PatientIdentity {
  const PatientIdentity({
    required this.id,
    required this.givenName,
    required this.familyName,
    this.dateOfBirth,
    this.dobIsEstimated = false,
    this.phone,
    this.altPhone,
    this.nationalId,
    this.mrn,
    this.sexAtBirth,
  });

  final String id;
  final String givenName;
  final String familyName;
  final DateTime? dateOfBirth;
  final bool dobIsEstimated;
  final String? phone;
  final String? altPhone;
  final String? nationalId;
  final String? mrn;
  final String? sexAtBirth;

  String get displayName => '$givenName $familyName';
}

/// One possible duplicate, with the evidence that produced it.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.existing,
    required this.score,
    required this.reasons,
    required this.isNearCertain,
  });

  final PatientIdentity existing;

  /// 0–1. Above [DuplicateDetector.reviewThreshold] is worth showing a human.
  final double score;

  /// Why this record was raised, in the order that carries the most weight.
  final List<String> reasons;

  /// A hard identifier matched. Registering over one of these is almost always
  /// a mistake rather than a coincidence.
  final bool isNearCertain;
}

/// Finds patients who may already be registered.
///
/// Duplicate records are the most common and most damaging data-quality
/// failure in a clinic register, and the damage is clinical rather than
/// cosmetic: the allergy recorded on Tuesday is not on the chart opened on
/// Friday, and the second record shows no history at all for someone who has
/// been treated for years.
///
/// The design constraint that shapes everything here is that **this must never
/// block registration**. A patient standing at the desk gets registered. The
/// check offers "is this the same person?" with the evidence, and the
/// front-desk worker — who can see the patient — decides. A matcher that
/// refuses to create a record is worked around within a week, usually by
/// misspelling the name on purpose.
abstract final class DuplicateDetector {
  /// Below this, a candidate is not worth a clinician's attention. Set by what
  /// two unrelated people in the same district actually score.
  static const double reviewThreshold = 0.62;

  /// Above this the match is strong enough to interrupt with.
  static const double strongThreshold = 0.80;

  /// Both halves of a name must reach this before the pair counts as a name
  /// match. Jaro similarity between two unrelated names sits around 0.5–0.6
  /// rather than near zero, so a threshold that looks generous is not.
  static const double _bothHalvesThreshold = 0.72;

  static List<DuplicateCandidate> search(
    PatientIdentity candidate,
    Iterable<PatientIdentity> register, {
    int limit = 5,
  }) {
    final results = <DuplicateCandidate>[];

    for (final existing in register) {
      if (existing.id == candidate.id) continue;
      final assessment = compare(candidate, existing);
      if (assessment.score >= reviewThreshold) results.add(assessment);
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList(growable: false);
  }

  /// Scores one pair.
  ///
  /// Name similarity sets the baseline and the other fields adjust it, rather
  /// than everything being averaged. Averaging lets a matching district and a
  /// matching sex drag two completely different names up to a middling score,
  /// and in a register where most patients share a district and half share a
  /// sex, that produces a list of false matches long enough that people stop
  /// reading it.
  static DuplicateCandidate compare(
    PatientIdentity candidate,
    PatientIdentity existing,
  ) {
    final reasons = <String>[];
    var nearCertain = false;

    // --- Hard identifiers -----------------------------------------------
    // A national ID or an MRN typed twice is not a coincidence.
    final candidateId = _digits(candidate.nationalId);
    final existingId = _digits(existing.nationalId);
    if (candidateId != null && candidateId == existingId) {
      reasons.add('Same national ID');
      nearCertain = true;
    }

    final phones = _sharedPhone(candidate, existing);
    if (phones != null) {
      reasons.add('Same phone number ($phones)');
    }

    // --- Name -------------------------------------------------------------
    final familyScore = TextSimilarity.jaroWinkler(
      TextSimilarity.normaliseName(candidate.familyName),
      TextSimilarity.normaliseName(existing.familyName),
    );
    final givenScore = TextSimilarity.jaroWinkler(
      TextSimilarity.normaliseName(candidate.givenName),
      TextSimilarity.normaliseName(existing.givenName),
    );

    // Names swapped between the two fields is a routine data-entry error and
    // must not be missed — the person is the same person.
    final swappedScore = math.min(
      TextSimilarity.jaroWinkler(
        TextSimilarity.normaliseName(candidate.familyName),
        TextSimilarity.normaliseName(existing.givenName),
      ),
      TextSimilarity.jaroWinkler(
        TextSimilarity.normaliseName(candidate.givenName),
        TextSimilarity.normaliseName(existing.familyName),
      ),
    );

    var nameScore = (familyScore * 0.55) + (givenScore * 0.45);
    // `swappedScore` is already the weaker of the two crossed comparisons, so
    // it needs no separate both-halves check below.
    var weakerHalf = math.min(familyScore, givenScore);
    if (swappedScore > nameScore) {
      nameScore = swappedScore * 0.95;
      weakerHalf = swappedScore;
      reasons.add('Given and family names appear swapped');
    }

    // A weighted sum lets one matching half carry a name that plainly differs
    // in the other half. On a register where a surname is shared by a whole
    // district, that alone puts hundreds of unrelated people over the
    // threshold — and a duplicate warning that is usually wrong is a warning
    // nobody reads. So a name only counts as similar when *both* halves are.
    if (weakerHalf < _bothHalvesThreshold) {
      nameScore = weakerHalf * 0.7;
    }

    // Transliteration: two spellings that share a consonant skeleton are one
    // name written twice. Checked against the normalised spellings rather than
    // the score, so the reason is given whenever it is the reason — a match
    // explained as "name is very similar" when it was actually a spelling
    // variant tells the reader less than it could.
    final spellingDiffers = TextSimilarity.normaliseName(candidate.familyName) !=
            TextSimilarity.normaliseName(existing.familyName) ||
        TextSimilarity.normaliseName(candidate.givenName) !=
            TextSimilarity.normaliseName(existing.givenName);
    if (spellingDiffers) {
      final skeletonMatch = TextSimilarity.consonantSkeleton(
                candidate.familyName,
              ) ==
              TextSimilarity.consonantSkeleton(existing.familyName) &&
          TextSimilarity.consonantSkeleton(candidate.givenName) ==
              TextSimilarity.consonantSkeleton(existing.givenName);
      if (skeletonMatch) {
        nameScore = math.max(nameScore, 0.88);
        reasons.add('Same name, spelled differently');
      }
    }

    if (nameScore >= 0.94) {
      reasons.insert(0, 'Name matches');
    } else if (nameScore >= 0.80) {
      reasons.insert(0, 'Name is very similar');
    }

    var score = nameScore;

    // --- Date of birth ----------------------------------------------------
    final dobAgreement = _dobAgreement(candidate, existing);
    switch (dobAgreement) {
      case _DobAgreement.exact:
        score = math.min(1, score + 0.18);
        reasons.add('Same date of birth');
      case _DobAgreement.approximate:
        score = math.min(1, score + 0.08);
        reasons.add('Birth year is within a year');
      case _DobAgreement.conflict:
        // Two different, *confirmed* birth dates is the strongest evidence
        // available that these are different people — strong enough to
        // override an identical name, because families reuse names.
        score -= 0.42;
        reasons.add('Dates of birth differ');
      case _DobAgreement.unknown:
        break;
    }

    if (phones != null) score = math.min(1, score + 0.16);
    if (nearCertain) score = math.max(score, 0.95);

    // Different recorded sex, with both known, is a weak negative: it is
    // sometimes a data-entry error, so it nudges rather than excludes.
    if (candidate.sexAtBirth != null &&
        existing.sexAtBirth != null &&
        candidate.sexAtBirth != existing.sexAtBirth) {
      score -= 0.10;
      reasons.add('Recorded sex differs');
    }

    return DuplicateCandidate(
      existing: existing,
      score: score.clamp(0.0, 1.0),
      reasons: reasons,
      isNearCertain: nearCertain,
    );
  }

  static String? _digits(String? value) {
    if (value == null) return null;
    final digits = value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    return digits.length < 4 ? null : digits;
  }

  static String? _sharedPhone(PatientIdentity a, PatientIdentity b) {
    final left = <String>{
      ?TextSimilarity.normalisePhone(a.phone),
      ?TextSimilarity.normalisePhone(a.altPhone),
    };
    final right = <String>{
      ?TextSimilarity.normalisePhone(b.phone),
      ?TextSimilarity.normalisePhone(b.altPhone),
    };
    final shared = left.intersection(right);
    return shared.isEmpty ? null : shared.first;
  }

  static _DobAgreement _dobAgreement(
    PatientIdentity a,
    PatientIdentity b,
  ) {
    final left = a.dateOfBirth;
    final right = b.dateOfBirth;
    if (left == null || right == null) return _DobAgreement.unknown;

    final sameDay = left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;

    // An estimated date of birth is a derived 1 January, so comparing the day
    // is meaningless — only the year carries information.
    if (a.dobIsEstimated || b.dobIsEstimated) {
      final yearGap = (left.year - right.year).abs();
      if (yearGap == 0) return _DobAgreement.exact;
      if (yearGap <= 1) return _DobAgreement.approximate;
      return _DobAgreement.unknown;
    }

    if (sameDay) return _DobAgreement.exact;
    return _DobAgreement.conflict;
  }

  /// The explanation shown behind the duplicate warning's info button.
  static MetricExplanation explain(DuplicateCandidate candidate) {
    return MetricExplanation(
      title: 'Possible duplicate — ${candidate.existing.displayName}',
      summary: 'This existing record resembles the one being registered. '
          'Nothing has been merged or blocked: this is a prompt to check, '
          'and registration continues either way.',
      method: const <String>[
        'Family and given names are compared with a measure that treats a '
            'transposition as one slip rather than two, and rewards agreement '
            'at the start of a name.',
        'The names are also compared with each other swapped, because typing '
            'them into the wrong fields is a routine error.',
        'Vowels are then stripped from both, so two transliterations of one '
            'name still match.',
        'A matching date of birth or phone number raises the score; two '
            'different confirmed dates of birth lower it sharply, because '
            'families reuse names.',
        'A matching national ID is treated as near-certain on its own.',
      ],
      derivation: <ExplainRow>[
        for (final reason in candidate.reasons)
          ExplainRow(label: reason, value: ''),
        ExplainRow(
          label: 'Overall similarity',
          value: '${(candidate.score * 100).round()}%',
          note: candidate.score >= strongThreshold
              ? 'Above the threshold for a strong match'
              : 'Worth a look',
        ),
      ],
      confidence: candidate.isNearCertain
          ? ExplainConfidence.measured
          : ExplainConfidence.heuristic,
      source: 'Jaro–Winkler string similarity with clinical field weighting',
      caveat: 'Names repeat, especially within a family and within a village. '
          'The person in front of you is the evidence that settles this — not '
          'the percentage.',
    );
  }
}

enum _DobAgreement { exact, approximate, conflict, unknown }
