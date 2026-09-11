import 'package:flutter_test/flutter_test.dart';
import 'package:medical_app/data/services/speech_out.dart';

/// What it guards: read-aloud must not let a value glue itself onto the next
/// line's label. "waiting now: 0\nAppointments remaining: 1" was heard as
/// "zero appointments remaining" — the text was right and the voice was wrong.
void main() {
  test('every line becomes its own sentence', () {
    final spoken = SpeechOut.speakable(
      'Patients waiting now: 0\nAppointments remaining today: 1',
    );
    expect(
      spoken,
      'Patients waiting now: 0. Appointments remaining today: 1.',
    );
  });

  test('existing terminal punctuation is kept, markdown is dropped', () {
    final spoken = SpeechOut.speakable(
      '## Summary\n- **BP** 120/80\nAll stable!',
    );
    expect(spoken, 'Summary. BP 120/80. All stable!');
  });

  test('blank lines vanish rather than becoming stray full stops', () {
    expect(SpeechOut.speakable('One\n\n\nTwo'), 'One. Two.');
  });
}
