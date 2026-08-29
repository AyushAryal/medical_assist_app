import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../../data/services/assist/ai_engine_preference.dart';
import '../../data/services/assist/apple_foundation_model.dart';

/// One place to choose which model powers the assistant and to see, per
/// feature, what works now.
///
/// The design principle made visible: the deterministic features are the
/// product and always work; a model only *adds* — rewording, widening the
/// wording understood — and every feature keeps working when the model is
/// swapped or absent. So this screen lets the user pick an engine (system
/// model, a download, or none) and honestly reports what each feature does
/// with and without one.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  bool _appleReady = false;
  bool _hasDownloaded = false;
  bool _probing = true;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final bootstrap = context.read<AppBootstrap>();
    final apple = await AppleFoundationLanguageModel().isReady();
    final downloaded = await bootstrap.assistModels.firstInstalled() != null;
    if (mounted) {
      setState(() {
        _appleReady = apple;
        _hasDownloaded = downloaded;
        _probing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final bootstrap = context.watch<AppBootstrap>();
    final pref = bootstrap.aiEnginePreference;
    final active = bootstrap.assistModelActive;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('AI assistant')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.all(m.spaceLg),
          children: <Widget>[
            SectionCard(
              title: 'Engine',
              subtitle: 'What powers rewording and generation',
              leading: const Icon(Icons.smart_toy_outlined, size: 20),
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Active now: ${bootstrap.activeAiEngineLabel}',
                        style: context.texts.bodySmall),
                  ),
                  SizedBox(height: m.spaceSm),
                  for (final option in AiEnginePreference.values)
                    _EngineOption(
                      option: option,
                      selected: pref == option,
                      status: _statusFor(option),
                      onSelect: () =>
                          context.read<AppBootstrap>().setAiEnginePreference(option),
                    ),
                  if (!_hasDownloaded && !_probing) ...<Widget>[
                    SizedBox(height: m.spaceSm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push(Routes.dictation),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Download a model'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),
            SectionCard(
              title: 'Where AI is used',
              subtitle: active
                  ? 'A model is active — these are enhanced.'
                  : 'No model active — these run from the app\'s own rules.',
              leading: const Icon(Icons.auto_awesome_outlined, size: 20),
              child: Column(
                children: <Widget>[
                  for (final f in _features) _FeatureRow(feature: f, modelActive: active),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _statusFor(AiEnginePreference option) => switch (option) {
        AiEnginePreference.appleIntelligence =>
          _probing ? null : (_appleReady ? 'Available' : 'Unavailable here'),
        AiEnginePreference.downloaded =>
          _probing ? null : (_hasDownloaded ? 'Installed' : 'Not installed'),
        _ => null,
      };
}

class _EngineOption extends StatelessWidget {
  const _EngineOption({
    required this.option,
    required this.selected,
    required this.onSelect,
    this.status,
  });

  final AiEnginePreference option;
  final bool selected;
  final String? status;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? palette.primary : palette.onSurfaceMuted,
      ),
      title: Row(
        children: <Widget>[
          Expanded(child: Text(option.label)),
          if (status != null)
            StatusPill(
              label: status!,
              tone: status == 'Available' || status == 'Installed'
                  ? PillTone.normal
                  : PillTone.neutral,
              dense: true,
            ),
        ],
      ),
      subtitle: Text(option.blurb, style: context.texts.bodySmall),
      onTap: onSelect,
    );
  }
}

/// A feature and how it behaves with / without a model.
typedef _Feature = ({String name, String instruction, _Need need});
enum _Need { model, native, deterministic }

const List<_Feature> _features = <_Feature>[
  (
    name: 'Ask about your register',
    instruction: 'Ask a question in plain words; it is matched to a known '
        'query and answered from your data.',
    need: _Need.deterministic,
  ),
  (
    name: 'Working notes → SOAP',
    instruction: 'Dictate a consultation into one box and sort it into '
        'sections before you sign.',
    need: _Need.deterministic,
  ),
  (
    name: 'Guided dictation (vitals/forms)',
    instruction: 'Speak values into a form; every number is checked against '
        'its bounds before it fills.',
    need: _Need.deterministic,
  ),
  (
    name: 'Patient instructions',
    instruction: 'Rewrite a plan into plain-language instructions for the '
        'patient.',
    need: _Need.model,
  ),
  (
    name: 'Pre-read brief & SBAR handoff',
    instruction: 'Reword the record into a spoken brief or handoff. The '
        'structured version is always the source of truth.',
    need: _Need.model,
  ),
  (
    name: 'Recall reminders & triage prompts',
    instruction: 'Draft a reminder message, or suggest questions to consider '
        '— never a diagnosis.',
    need: _Need.model,
  ),
  (
    name: 'Scan text from a photo',
    instruction: 'Read text off a page, circling just the part you want. Uses '
        'the device\'s native text recognition.',
    need: _Need.native,
  ),
  (
    name: 'Read aloud',
    instruction: 'Speak generated or record text with a system voice.',
    need: _Need.native,
  ),
];

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.modelActive});

  final _Feature feature;
  final bool modelActive;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (feature.need) {
      _Need.native => ('Native', PillTone.info),
      _Need.deterministic =>
        modelActive ? ('Enhanced', PillTone.normal) : ('Works now', PillTone.normal),
      _Need.model =>
        modelActive ? ('Ready', PillTone.normal) : ('Needs a model', PillTone.caution),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.metrics.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(feature.name, style: context.texts.labelLarge),
                Text(feature.instruction, style: context.texts.bodySmall),
              ],
            ),
          ),
          SizedBox(width: context.metrics.spaceSm),
          StatusPill(label: label, tone: tone, dense: true),
        ],
      ),
    );
  }
}
