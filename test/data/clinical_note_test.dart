import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/models/clinical_note.dart';

/// The medico-legal properties of a note: it hashes deterministically, the
/// hash detects tampering, and signing is a one-way door.
void main() {
  ClinicalNote noteWith({
    String? assessment,
    NoteStatus status = NoteStatus.draft,
    String? contentHash,
  }) {
    return ClinicalNote(
      id: 'note-1',
      patientId: 'patient-1',
      encounterId: 'encounter-1',
      subjective: 'Cough for three days.',
      objective: 'Chest clear.',
      assessment: assessment ?? 'Viral URTI.',
      plan: 'Fluids, review if worse.',
      status: status,
      contentHash: contentHash,
      createdAt: DateTime(2026, 6, 15, 9),
      updatedAt: DateTime(2026, 6, 15, 9),
    );
  }

  group('hashing', () {
    test('is deterministic for identical content', () {
      expect(noteWith().computeHash(), noteWith().computeHash());
    });

    test('changes when any section changes', () {
      expect(
        noteWith().computeHash(),
        isNot(noteWith(assessment: 'Bacterial pneumonia.').computeHash()),
      );
    });
  });

  group('integrity', () {
    test('passes when the stored text still matches the signature', () {
      final signed = noteWith(status: NoteStatus.signed);
      final withHash = signed.copyWith(contentHash: signed.computeHash());
      expect(withHash.verifyIntegrity(), isTrue);
    });

    test('fails when the text was altered after signing', () {
      final signed = noteWith(status: NoteStatus.signed);
      final hash = signed.computeHash();
      final tampered = noteWith(
        assessment: 'Something else entirely.',
        status: NoteStatus.signed,
        contentHash: hash,
      );
      expect(tampered.verifyIntegrity(), isFalse);
    });

    test('an unsigned note with no hash is not reported as tampered', () {
      expect(noteWith().verifyIntegrity(), isTrue);
    });
  });

  group('status', () {
    test('draft is editable, signed and amended are locked', () {
      expect(noteWith().isLocked, isFalse);
      expect(noteWith(status: NoteStatus.signed).isLocked, isTrue);
      expect(noteWith(status: NoteStatus.amended).isLocked, isTrue);
    });
  });

  group('completeness', () {
    test('counts only sections with real content', () {
      expect(noteWith().filledSectionCount, 4);

      final partial = ClinicalNote(
        id: 'n',
        patientId: 'p',
        encounterId: 'e',
        subjective: 'Headache.',
        objective: '   ',
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 15),
      );
      expect(partial.filledSectionCount, 1);
      expect(partial.isEmpty, isFalse);
    });

    test('whitespace-only content counts as empty', () {
      final blank = ClinicalNote(
        id: 'n',
        patientId: 'p',
        encounterId: 'e',
        subjective: '   ',
        plan: '\n\n',
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 15),
      );
      expect(blank.isEmpty, isTrue);
      expect(blank.filledSectionCount, 0);
    });
  });

  test('copyWith bumps the revision and re-queues for sync', () {
    final original = noteWith();
    final updated = original.copyWith(plan: 'Add antibiotics.');
    expect(updated.revision, original.revision + 1);
    expect(updated.syncStatus, 'pending');
    expect(updated.createdAt, original.createdAt);
  });
}
