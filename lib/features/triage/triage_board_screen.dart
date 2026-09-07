import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../clinical/news2.dart';
import '../../clinical/worklist/triage_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../../core/session/session_controller.dart';
import '../../data/repositories/clinical_repository.dart';
import '../assist/assist.dart';
import 'triage_board_controller.dart';

/// "Who do I see first." Ranks the waiting room by acuity and holds the
/// unmeasured patients apart so they are never read as low priority.
class TriageBoardScreen extends StatefulWidget {
  const TriageBoardScreen({super.key});

  @override
  State<TriageBoardScreen> createState() => _TriageBoardScreenState();
}

class _TriageBoardScreenState extends State<TriageBoardScreen> {
  TriageBoardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = TriageBoardController(context.read<ClinicalRepository>());
    _reload();
  }

  Future<void> _reload() async {
    final session = context.read<SessionController>();
    await _controller?.load(clinicId: session.activeClinic?.id);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Triage')),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : ChangeNotifierProvider<TriageBoardController>.value(
              value: controller,
              child: Consumer<TriageBoardController>(
                builder: (context, c, _) {
                  if (c.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (c.waitingCount == 0) {
                    return const EmptyState(
                      icon: Icons.emergency_outlined,
                      title: 'No one waiting',
                      message: 'Patients appear here once they are checked in.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ContentWidth(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceSm,
                            m.spaceLg, m.spaceLg + context.bottomBarClearance),
                        children: <Widget>[
                          if (c.attention.isNotEmpty)
                            _Section(
                              title: 'Attention',
                              entries: c.attention,
                              controller: c,
                              aiActive: context
                                  .watch<AppBootstrap>()
                                  .assistModelActive,
                            ),
                          if (c.needsObs.isNotEmpty) ...<Widget>[
                            SizedBox(height: m.spaceLg),
                            _Section(
                              title: 'Needs observations',
                              subtitle: 'Risk unknown until vitals are taken.',
                              entries: c.needsObs,
                              controller: c,
                              aiActive: context
                                  .watch<AppBootstrap>()
                                  .assistModelActive,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.entries,
    required this.controller,
    required this.aiActive,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<WorklistEntry> entries;
  final TriageBoardController controller;
  final bool aiActive;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return SectionCard(
      title: title,
      child: Column(
        children: <Widget>[
          if (subtitle != null)
            Padding(
              padding: EdgeInsets.only(bottom: m.spaceSm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(subtitle!, style: context.texts.bodySmall),
              ),
            ),
          for (final entry in entries)
            _TriageRow(
              entry: entry,
              subject: controller.subjectFor(entry.patientId),
              aiActive: aiActive,
            ),
        ],
      ),
    );
  }
}

class _TriageRow extends StatelessWidget {
  const _TriageRow({
    required this.entry,
    required this.subject,
    required this.aiActive,
  });

  final WorklistEntry entry;
  final TriageSubject? subject;
  final bool aiActive;

  void _talkingPoints(BuildContext context) {
    final name = subject?.displayName ?? 'the patient';
    final facts = <String>['Patient: $name', ...entry.reasons].join('. ');
    AiDraftSheet.show(
      context,
      title: 'Talking points',
      subtitle: name,
      caveat: 'Prompts to consider — not a diagnosis, not advice. You decide '
          'what to ask and examine.',
      notice: 'Suggestions generated from the presenting details only.',
      generate: (engine) => engine.triageTalkingPoints(facts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final name = subject?.displayName ?? 'Patient';
    final (tone, bandLabel) = _band(subject);

    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: m.spaceXs),
      leading: PatientAvatar(
        initials: _initials(name),
        seed: entry.patientId,
        radius: 20,
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          StatusPill(label: bandLabel, tone: tone, dense: true),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: m.spaceXs / 2),
        child: Text(entry.reasons.join(' · '),
            style: context.texts.bodySmall),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (aiActive)
            IconButton(
              tooltip: 'Talking points',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => _talkingPoints(context),
            ),
          InfoDot.text(
            title: 'Why this ranking',
            summary: entry.reasons.join(' · '),
            source: _provenanceText(entry),
          ),
        ],
      ),
      onTap: () => context.push(Routes.chartFor(entry.patientId)),
    );
  }

  /// The exact rows and times the rank was read from, so a clinician can check
  /// the board's reasoning rather than trust it.
  static String _provenanceText(WorklistEntry entry) => entry.provenance
      .map((p) => p.at == null ? p.label : '${p.label} · ${_time(p.at!)}')
      .join('; ');

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Maps the NEWS2 band onto a reserved clinical tone. "Needs obs" is info,
  /// never a severity colour it has not earned.
  static (PillTone, String) _band(TriageSubject? s) {
    return switch (s?.risk) {
      News2Risk.high => (PillTone.critical, 'High'),
      News2Risk.medium => (PillTone.caution, 'Medium'),
      News2Risk.lowMedium => (PillTone.caution, 'Low–med'),
      News2Risk.low => (PillTone.normal, 'Low'),
      null => (PillTone.info, 'Needs obs'),
    };
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.isEmpty ? '?' : parts.first[0].toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
