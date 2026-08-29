/// Which language-model engine the app should use, chosen by the user.
///
/// The app runs on devices that may have a system model (Apple Intelligence on
/// recent iPhones), a model the user downloaded, or neither (older iOS,
/// Android, low-storage devices). This is the single knob that decides which of
/// those backs the assistant — and every AI feature degrades gracefully when
/// the choice resolves to nothing, because the deterministic engines are always
/// the product and the model only ever adds to them.
enum AiEnginePreference {
  /// Prefer the system model, fall back to a downloaded one — the sensible
  /// default that "just works" on any device.
  auto,

  /// Only the system model (Apple Intelligence). Off where it is unavailable.
  appleIntelligence,

  /// Only a model the user downloaded.
  downloaded,

  /// No model — deterministic features only.
  off,
}

extension AiEnginePreferenceX on AiEnginePreference {
  String get label => switch (this) {
        AiEnginePreference.auto => 'Automatic',
        AiEnginePreference.appleIntelligence => 'Apple Intelligence',
        AiEnginePreference.downloaded => 'Downloaded model',
        AiEnginePreference.off => 'Off',
      };

  String get blurb => switch (this) {
        AiEnginePreference.auto =>
          'Use the system model when the device has one, otherwise a model you '
              'downloaded.',
        AiEnginePreference.appleIntelligence =>
          'Use only the on-device system model. No effect where the device or '
              'OS does not provide one.',
        AiEnginePreference.downloaded =>
          'Use only a model you downloaded in this app.',
        AiEnginePreference.off =>
          'Turn the assistant off. Every feature still works from the app\'s '
              'own rules; nothing is reworded or generated.',
      };

  static AiEnginePreference parse(String? value) =>
      AiEnginePreference.values.where((v) => v.name == value).firstOrNull ??
      AiEnginePreference.auto;
}
