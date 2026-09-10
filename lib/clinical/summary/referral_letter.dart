import 'package:intl/intl.dart';

import '../../data/models/allergy.dart';
import '../../data/models/medication.dart';
import '../../data/models/patient.dart';
import '../../data/models/problem.dart';
import '../../data/models/vitals_record.dart';

/// Composes a referral letter the way a clinician writes one — flowing,
/// formal paragraphs — from the structured record.
///
/// Pure and deterministic: this is the letter's floor. The language model is
/// invited to *polish* this text (vary the phrasing, tighten a sentence), but
/// when no model is installed, or it fails, or it hallucinates, this is what
/// stands — so the sheet never again shows a raw field dump as "the letter".
abstract final class ReferralLetterComposer {
  static String compose({
    required Patient patient,
    String? reason,
    List<Problem> problems = const <Problem>[],
    List<Medication> medications = const <Medication>[],
    List<Allergy> allergies = const <Allergy>[],
    VitalsRecord? latestVitals,
  }) {
    final p = _Pronouns.of(patient.sexAtBirth);
    final paragraphs = <String>[];

    // Opening: who, and why they are being sent.
    final ageSex = _ageSex(patient);
    final opening = StringBuffer()
      ..write('Thank you for seeing ${patient.displayName}, ')
      ..write('a $ageSex under my care');
    if (reason != null && reason.trim().isNotEmpty) {
      opening.write(
          '. I would be grateful for your review of ${p.possessive} '
          '${_lowerFirst(reason.trim())}.');
    } else {
      opening.write(
          ', whom I would be grateful for your opinion on regarding the '
          'concerns summarised below.');
    }
    paragraphs.add(opening.toString());

    // History.
    final active = problems
        .where((problem) => problem.status == ProblemStatus.active)
        .map((problem) => problem.display)
        .toList();
    if (active.isNotEmpty) {
      paragraphs.add(
          '${_capitalise(p.possessive)} relevant history includes '
          '${_prose(active)}.');
    }

    // Medications and allergies, together — the paragraph a colleague reads
    // before prescribing anything.
    final medLines = medications
        .map((med) => <String?>[med.name, med.dose, med.frequency]
            .whereType<String>()
            .where((part) => part.isNotEmpty)
            .join(' '))
        .where((line) => line.isNotEmpty)
        .toList();
    final medsSentence = medLines.isEmpty
        ? '${_capitalise(p.subject)} ${p.isPlural ? 'take' : 'takes'} no '
            'regular medications.'
        : 'Current medications are ${_prose(medLines)}.';
    final allergySentence = allergies.isEmpty
        ? ' There are no known drug allergies.'
        : ' Please note ${p.possessive} documented '
            '${_prose(allergies.map(_allergyPhrase).toList())}.';
    paragraphs.add('$medsSentence$allergySentence');

    // Latest observations, only what was measured.
    if (latestVitals != null) {
      final observed = _observations(latestVitals);
      if (observed.isNotEmpty) {
        final when =
            DateFormat('d MMMM yyyy').format(latestVitals.recordedAt);
        var sentence =
            'When last reviewed on $when, ${p.possessive} observations '
            'were ${_prose(observed)}';
        final news2 = latestVitals.news2Score;
        if (news2 != null) {
          final risk = latestVitals.news2Risk;
          sentence += ', giving a NEWS2 score of $news2'
              '${risk != null ? ' ($risk risk)' : ''}';
        }
        paragraphs.add('$sentence.');
      }
    }

    // Close.
    paragraphs.add(
        'I would value your assessment and any advice on further management. '
        'Please contact me if any further information would be helpful.');

    return paragraphs.join('\n\n');
  }

  static String _ageSex(Patient patient) {
    final age = patient.age;
    final years = age == null
        ? null
        : age.years >= 1
            ? '${age.years}-year-old'
            : '${age.months}-month-old';
    final sex = switch (patient.sexAtBirth) {
      SexAtBirth.male => 'man',
      SexAtBirth.female => 'woman',
      _ => 'patient',
    };
    final child = age != null && age.years < 13;
    final noun = child
        ? switch (patient.sexAtBirth) {
            SexAtBirth.male => 'boy',
            SexAtBirth.female => 'girl',
            _ => 'child',
          }
        : sex;
    return years == null ? noun : '$years $noun';
  }

  static String _allergyPhrase(Allergy allergy) {
    final reaction = allergy.reaction;
    return reaction == null || reaction.trim().isEmpty
        ? '${allergy.substance} allergy'
        : '${allergy.substance} allergy (${_lowerFirst(reaction.trim())})';
  }

  static List<String> _observations(VitalsRecord vitals) => <String>[
        if (vitals.systolicBp != null && vitals.diastolicBp != null)
          'blood pressure ${vitals.systolicBp}/${vitals.diastolicBp}',
        if (vitals.heartRate != null) 'pulse ${vitals.heartRate}',
        if (vitals.respiratoryRate != null)
          'respiratory rate ${vitals.respiratoryRate}',
        if (vitals.temperatureC != null)
          'temperature ${vitals.temperatureC}°C',
        if (vitals.spo2 != null) 'oxygen saturation ${vitals.spo2}%',
      ];

  /// "a, b and c" — the connective a letter uses, not the comma list a
  /// database prints.
  static String _prose(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and '
        '${items.last}';
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _lowerFirst(String s) =>
      s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

class _Pronouns {
  const _Pronouns(this.subject, this.possessive, {this.isPlural = false});

  final String subject;
  final String possessive;
  final bool isPlural;

  static _Pronouns of(SexAtBirth sex) => switch (sex) {
        SexAtBirth.male => const _Pronouns('he', 'his'),
        SexAtBirth.female => const _Pronouns('she', 'her'),
        _ => const _Pronouns('they', 'their', isPlural: true),
      };
}
