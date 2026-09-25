import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../clinical/flags/clinical_flag.dart';
import '../../../clinical/news2.dart';
import '../../../clinical/summary/handoff.dart';
import '../../../core/app_bootstrap.dart';
import '../../../core/design/design.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/encounter.dart';
import '../../../data/services/assist/language_model.dart';
import '../../../data/services/speech_out.dart';
import '../../assist/assist.dart';
import '../patient_chart_controller.dart';

/// Shows a deterministic SBAR handoff, ready to read aloud or copy.
///
/// Two layers on purpose. At the top, the kit's [OptSituationCard] — the
/// 30-second cross-cover glance, with the NEWS2 chip structurally impossible
/// to omit. Below it, the structured SBAR text remains the source of truth —
/// no editing, so what is copied is exactly what the record says. When an
/// on-device model is available, it can additionally *reword* that same
/// handoff into a natural paragraph for reading aloud; that version is marked
/// as generated and never replaces the structured one. If no model is
/// present, the feature simply is not offered — the handoff works without it.
class HandoffSheet extends StatefulWidget {
  const HandoffSheet({
    super.key,
    required this.handoff,
    this.news2,
    this.situation,
    this.background = const <String>[],
    this.recentEvents = const <(String, String)>[],
    this.recommendation,
  });

  final Handoff handoff;

  /// The latest scored NEWS2, for the situation card's risk chip.
  final News2Result? news2;

  /// One line: why this patient is being handed over (current complaint).
  final String? situation;

  /// Active problems, capped at 4 by the card itself.
  final List<String> background;

  /// (time, event) pairs — last visit, latest observations.
  final List<(String, String)> recentEvents;

  /// The contingency line — mirrors the SBAR Recommendation section.
  final String? recommendation;

  static Future<void> show(BuildContext context, Handoff handoff) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HandoffSheet(handoff: handoff),
    );
  }

  /// Opens the handoff for a loaded chart, deriving the situation-card
  /// glance from data the controller already holds — the same latest-scored
  /// NEWS2 the header chip shows, the open visit's complaint, the active
  /// problem list, and the most recent visit and observation times. One
  /// helper so the header action and the summary-card button cannot drift.
  static Future<void> showForChart(
    BuildContext context,
    PatientChartController chart,
  ) {
    final handoff = chart.handoff;
    if (handoff == null) return Future<void>.value();

    // Rebuild the result from the stored score: the total and band are what
    // the chip renders, and the stored pair is the scored record — recomputing
    // here could disagree with what was written at the time.
    final vitals = chart.latestVitals;
    final risk = vitals == null
        ? null
        : News2Risk.values.where((r) => r.name == vitals.news2Risk).firstOrNull;
    final news2 = (vitals != null && vitals.news2Score != null && risk != null)
        ? News2Result(
            total: vitals.news2Score!,
            risk: risk,
            parameterScores: const <String, int>{},
            hasSingleParameterThree: false,
            algorithmVersion:
                vitals.news2Algorithm ?? News2Calculator.algorithmVersion,
          )
        : null;

    final open = chart.openEncounter;
    final lastVisit = chart.encounters.firstOrNull;
    final situation = open?.chiefComplaint ?? lastVisit?.chiefComplaint;

    final recentEvents = <(String, String)>[
      if (lastVisit != null)
        (
          Fmt.dateShort(lastVisit.startedAt),
          'Visit: ${lastVisit.chiefComplaint ?? lastVisit.type.label}',
        ),
      if (vitals != null)
        (
          Fmt.dateShort(vitals.recordedAt),
          'Obs at ${Fmt.time(vitals.recordedAt)}'
              '${vitals.news2Score != null ? ' · NEWS2 ${vitals.news2Score}' : ''}',
        ),
    ];

    // The card's R mirrors the sheet's own Recommendation section — the
    // deterministic contingency text, never a second opinion.
    final recommendation = handoff.sections
        .where((s) => s.part == SbarPart.recommendation)
        .expand((s) => s.lines)
        .map((l) => l.text)
        .join(' · ');

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HandoffSheet(
        handoff: handoff,
        news2: news2,
        situation: situation,
        background: <String>[
          for (final problem in chart.activeProblems.take(4)) problem.display,
        ],
        recentEvents: recentEvents,
        recommendation: recommendation.isEmpty ? null : recommendation,
      ),
    );
  }

  @override
  State<HandoffSheet> createState() => _HandoffSheetState();
}

class _HandoffSheetState extends State<HandoffSheet> {
  LanguageModelDraft? _spoken;
  bool _busy = false;

  @override
  void dispose() {
    SpeechOut.stop();
    super.dispose();
  }

  Future<void> _generate() async {
    final bootstrap = context.read<AppBootstrap>();
    var engine = bootstrap.assistEngine;
    if (engine == null || _busy) return;

    setState(() => _busy = true);
    try {
      // Rebuild a not-yet-ready engine (fresh download / stuck load) instead
      // of dead-ending — see AiDraftSheet for the same handling.
      if (!await engine.isReady()) {
        await bootstrap.refreshAssistEngine();
        engine = bootstrap.assistEngine;
        if (engine == null) return;
      }
      final draft = await engine.spokenHandoff(widget.handoff.plainText);
      if (mounted) setState(() => _spoken = draft);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final handoff = widget.handoff;
    final engineAvailable = context.read<AppBootstrap>().assistEngine != null;

    return SheetScaffold(
      title: 'SBAR handoff',
      subtitle: handoff.identityLine,
      footer: FilledButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: handoff.plainText));
          if (context.mounted) {
            OptToast.success(context, 'Handoff copied');
            Navigator.of(context).pop();
          }
        },
        icon: const Icon(Icons.copy_all_outlined),
        label: const Text('Copy handoff'),
      ),
      children: <Widget>[
        // The 30-second glance. The card collapses to nothing when every slot
        // is empty, so a sparse record costs no dead space; the deterministic
        // SBAR text below stays the read-aloud, copyable artifact.
        OptSituationCard(
          news2: widget.news2,
          situation: widget.situation,
          background: widget.background,
          recentEvents: widget.recentEvents,
          recommendation: widget.recommendation,
          margin: EdgeInsets.only(bottom: m.spaceLg),
        ),
        for (final section in handoff.sections) ...<Widget>[
          _PartHeader(part: section.part),
          for (final line in section.lines) _LineRow(line: line),
          SizedBox(height: m.spaceMd),
        ],
        if (engineAvailable) _SpokenSection(
          draft: _spoken,
          busy: _busy,
          onGenerate: _generate,
        ),
      ],
    );
  }
}

/// The AI convenience: a reworded, read-aloud version of the same handoff.
class _SpokenSection extends StatelessWidget {
  const _SpokenSection({
    required this.draft,
    required this.busy,
    required this.onGenerate,
  });

  final LanguageModelDraft? draft;
  final bool busy;
  final Future<void> Function() onGenerate;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final d = draft;

    if (d == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: busy ? null : () => onGenerate(),
          icon: busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(busy ? 'Rewording…' : 'Read-aloud version'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const AiBadge(),
            const Spacer(),
            SpeakButton(text: d.text),
            IconButton(
              tooltip: 'Copy spoken version',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: d.text));
                if (context.mounted) {
                  OptToast.success(context, 'Spoken version copied');
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
        SizedBox(height: m.spaceXs),
        GeneratedText(text: d.text, typeIn: true),
        SizedBox(height: m.spaceSm),
        Text(
          'Generated from the record. Read it before you rely on it — the '
          'structured SBAR above is the source.',
          style: context.texts.bodySmall
              ?.copyWith(color: context.palette.onSurfaceMuted),
        ),
      ],
    );
  }
}

class _PartHeader extends StatelessWidget {
  const _PartHeader({required this.part});

  final SbarPart part;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.spaceXs),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              part.letter,
              style: context.texts.labelSmall
                  ?.copyWith(color: context.palette.onPrimary),
            ),
          ),
          SizedBox(width: m.spaceSm),
          Text(part.title, style: context.texts.titleSmall),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final HandoffLine line;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;
    final color = switch (line.severity) {
      FlagSeverity.critical => palette.critical,
      FlagSeverity.caution => palette.caution,
      FlagSeverity.info => palette.info,
      null => line.isRecorded ? palette.onSurface : palette.onSurfaceMuted,
    };

    return Padding(
      padding: EdgeInsets.only(left: m.spaceLg, bottom: m.spaceXs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('•  ', style: context.texts.bodySmall?.copyWith(color: color)),
          Expanded(
            child: Text(
              line.text,
              style: context.texts.bodySmall?.copyWith(
                color: color,
                fontStyle:
                    line.isRecorded ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
