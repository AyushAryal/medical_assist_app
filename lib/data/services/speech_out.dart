import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One installed system voice.
class TtsVoice {
  const TtsVoice({
    required this.id,
    required this.name,
    required this.language,
    required this.quality,
  });

  final String id;
  final String name;
  final String language;

  /// 1 default (compact, robotic), 2 enhanced, 3 premium.
  final int quality;

  String get qualityLabel => switch (quality) {
        3 => 'Premium',
        2 => 'Enhanced',
        _ => 'Default',
      };

  bool get isNatural => quality >= 2;
}

/// Reads text aloud through the platform speech synthesiser.
///
/// A thin channel to the system voice (iOS `AVSpeechSynthesizer`). Best-effort:
/// where no synthesiser is wired the calls are no-ops. [preferredVoiceId] lets
/// the user pin a specific installed voice; without it the platform picks the
/// best available. Note the literal Siri voice is not exposed to apps — only
/// the downloadable Enhanced/Premium voices are.
abstract final class SpeechOut {
  static const MethodChannel _channel = MethodChannel('app.medical/tts');

  /// The user's chosen voice, applied to every [speak]. Loaded at startup and
  /// updated by the voice picker.
  static String? preferredVoiceId;

  /// Whether speech is currently playing — driven by the platform so every
  /// read-aloud control reflects the same state (one utterance plays at a time).
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && call.arguments is Map) {
        speaking.value = (call.arguments as Map)['speaking'] == true;
      }
      return null;
    });
  }

  static Future<void> speak(String text) => _speak(text, preferredVoiceId);

  /// Speaks [text], or stops if something is already playing.
  static Future<void> toggle(String text) async {
    if (speaking.value) {
      await stop();
    } else {
      await speak(text);
    }
  }

  /// Speaks with an explicit voice — used to preview a voice before choosing it.
  static Future<void> preview(String text, String voiceId) =>
      _speak(text, voiceId);

  /// Rewrites display text into speakable text.
  ///
  /// A synthesiser only pauses at punctuation, so a line break between
  /// "waiting now: 0" and "Appointments remaining: 1" is heard as
  /// "zero appointments remaining" — the number attaches itself to the next
  /// label and correct text *sounds* wrong. Every line becomes a sentence,
  /// and markdown marks that mean nothing aloud are dropped.
  static String speakable(String text) {
    final lines = text
        .split('\n')
        .map((line) => line
            .replaceAll(RegExp(r'[*_#|`>]+'), ' ')
            .replaceAll(RegExp(r'^\s*[-•]\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim())
        .where((line) => line.isNotEmpty);
    return lines
        .map((line) =>
            RegExp(r'[.!?:;]$').hasMatch(line) ? line : '$line.')
        .join(' ');
  }

  static Future<void> _speak(String text, String? voiceId) async {
    if (text.trim().isEmpty) return;
    _ensureHandler();
    final args = <String, Object?>{'text': speakable(text)};
    if (voiceId != null) args['voiceId'] = voiceId;
    try {
      await _channel.invokeMethod<bool>('speak', args);
      speaking.value = true; // platform confirms via the state callback
    } on Object {
      // No synthesiser on this platform — silence is an acceptable outcome.
    }
  }

  static Future<void> stop() async {
    speaking.value = false;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on Object {
      // Nothing playing / no channel.
    }
  }

  /// Every installed voice for [language], quality-first.
  static Future<List<TtsVoice>> voices({String language = 'en'}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'voices',
        <String, Object?>{'language': language},
      );
      return <TtsVoice>[
        for (final entry in raw ?? const <Object?>[])
          if (entry is Map)
            TtsVoice(
              id: entry['id'] as String,
              name: entry['name'] as String,
              language: entry['language'] as String,
              quality: (entry['quality'] as num).toInt(),
            ),
      ];
    } on Object {
      return const <TtsVoice>[];
    }
  }

  /// Quality of the best installed voice: 0 none, 1 default, 2 enhanced,
  /// 3 premium.
  static Future<int> bestVoiceQuality() async {
    try {
      return await _channel.invokeMethod<int>('bestVoiceQuality') ?? 0;
    } on Object {
      return 0;
    }
  }
}
