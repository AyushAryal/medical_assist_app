import 'package:flutter/material.dart';

import '../../../data/services/speech_out.dart';
import '../speak_aloud.dart';

/// A drop-anywhere "read aloud" control.
///
/// One speaker button that reads [text] and turns into a stop button while
/// anything is playing (only one utterance plays at a time). Because it watches
/// the shared [SpeechOut.speaking] state, every SpeakButton across the app
/// stays in sync — press one to start, press any to stop. The first time only a
/// robotic voice is available it points the user to a better one.
class SpeakButton extends StatelessWidget {
  const SpeakButton({
    super.key,
    required this.text,
    this.tooltip = 'Read aloud',
    this.size = 20,
  });

  final String text;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SpeechOut.speaking,
      builder: (context, speaking, _) => IconButton(
        tooltip: speaking ? 'Stop' : tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
          size: size,
        ),
        onPressed: text.trim().isEmpty
            ? null
            : () {
                if (speaking) {
                  SpeechOut.stop();
                } else {
                  speakAloud(context, text);
                }
              },
      ),
    );
  }
}
