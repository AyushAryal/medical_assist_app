import 'package:flutter/material.dart';

import '../../data/services/speech_out.dart';

/// Reads [text] aloud and, the first time it finds only the basic system voice,
/// nudges the user toward a natural one.
///
/// The good iOS voices (Enhanced / Premium — essentially Siri quality) are a
/// separate download; the app picks the best installed one automatically, but
/// can only sound natural if a natural voice exists on the device. Rather than
/// ship a robotic voice silently, it says how to get a better one.
Future<void> speakAloud(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  await SpeechOut.speak(text);
  final quality = await SpeechOut.bestVoiceQuality();
  if (quality > 1) return; // enhanced or premium — already natural
  messenger.showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 7),
      content: Text(
        'Using the basic system voice. For a natural one, add an Enhanced or '
        'Premium English voice in Settings → Accessibility → Spoken Content → '
        'Voices.',
      ),
    ),
  );
}
