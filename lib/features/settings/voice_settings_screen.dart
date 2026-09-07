import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../data/services/speech_out.dart';

/// Chooses the voice used for read-aloud, and previews what is installed.
///
/// The natural voices (Enhanced / Premium) are a separate iOS download; the
/// literal Siri voice is not available to apps. This screen shows exactly what
/// is on the device so the robotic default is not a mystery, lets the user hear
/// each one, and pins their choice.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  static const String _sample =
      'Blood pressure 120 over 80, heart rate 72, oxygen 98 percent. '
      'Review in two weeks.';

  List<TtsVoice> _voices = const <TtsVoice>[];
  bool _loading = true;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = SpeechOut.preferredVoiceId;
    _load();
  }

  Future<void> _load() async {
    final voices = await SpeechOut.voices();
    if (mounted) {
      setState(() {
        _voices = voices;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    SpeechOut.stop();
    super.dispose();
  }

  Future<void> _select(String? id) async {
    setState(() => _selectedId = id);
    await context.read<AppBootstrap>().setTtsVoice(id);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final hasNatural = _voices.any((v) => v.isNatural);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Read-aloud voice')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(m.spaceLg),
          children: <Widget>[
            SectionCard(
              title: 'About the voices',
              leading: const Icon(Icons.record_voice_over_outlined, size: 20),
              child: Text(
                hasNatural
                    ? 'Pick a voice below and preview it. "Enhanced" and '
                        '"Premium" voices sound natural; "Default" is the basic '
                        'system voice.'
                    : 'Only the basic system voice is installed, which is why '
                        'read-aloud sounds robotic. Add a natural one in '
                        'Settings → Accessibility → Spoken Content → Voices → '
                        'English (choose an Enhanced or Premium voice). Apple '
                        'does not make the Siri voice itself available to apps.',
                style: context.texts.bodySmall,
              ),
            ),
            SizedBox(height: m.spaceMd),
            SectionCard(
              title: 'Voice',
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: <Widget>[
                        _VoiceTile(
                          title: 'Automatic',
                          subtitle: 'Use the best voice installed',
                          selected: _selectedId == null,
                          onSelect: () => _select(null),
                        ),
                        for (final voice in _voices)
                          _VoiceTile(
                            title: voice.name,
                            subtitle: voice.language,
                            qualityLabel: voice.qualityLabel,
                            natural: voice.isNatural,
                            selected: _selectedId == voice.id,
                            onSelect: () => _select(voice.id),
                            onPreview: () => SpeechOut.preview(_sample, voice.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onSelect,
    this.qualityLabel,
    this.natural = false,
    this.onPreview,
  });

  final String title;
  final String subtitle;
  final String? qualityLabel;
  final bool natural;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? palette.primary : palette.onSurfaceMuted,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: context.texts.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (qualityLabel != null)
            StatusPill(
              label: qualityLabel!,
              tone: natural ? PillTone.normal : PillTone.neutral,
              dense: true,
            ),
          if (onPreview != null)
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: onPreview,
            ),
        ],
      ),
      onTap: onSelect,
    );
  }
}
