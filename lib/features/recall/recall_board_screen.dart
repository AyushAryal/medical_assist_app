import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../clinical/worklist/recall_worklist.dart';
import '../../clinical/worklist/worklist.dart';
import '../../core/app_bootstrap.dart';
import '../../core/design/design.dart';
import '../../core/routing/app_router.dart';
import '../../data/repositories/clinical_repository.dart';
import '../assist/assist.dart';
import 'recall_board_controller.dart';

/// Patients overdue for a review they were promised, most overdue first.
class RecallBoardScreen extends StatefulWidget {
  const RecallBoardScreen({super.key});

  @override
  State<RecallBoardScreen> createState() => _RecallBoardScreenState();
}

class _RecallBoardScreenState extends State<RecallBoardScreen> {
  RecallBoardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = RecallBoardController(context.read<ClinicalRepository>());
    _controller!.load();
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
      appBar: AppBar(title: const Text('Recall')),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : ChangeNotifierProvider<RecallBoardController>.value(
              value: controller,
              child: Consumer<RecallBoardController>(
                builder: (context, c, _) {
                  if (c.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (c.dueCount == 0) {
                    return const EmptyState(
                      icon: Icons.event_repeat_outlined,
                      title: 'No reviews overdue',
                      message: 'Patients appear here when a follow-up date '
                          'passes without a return visit.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: c.load,
                    child: ContentWidth(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(m.spaceLg, m.spaceSm,
                            m.spaceLg, m.spaceLg + context.bottomBarClearance),
                        children: <Widget>[
                          SectionCard(
                            title: '${c.dueCount} overdue',
                            child: Column(
                              children: <Widget>[
                                for (final entry in c.entries)
                                  _RecallRow(
                                    entry: entry,
                                    subject: c.subjectFor(entry.patientId),
                                    onReminder: context
                                            .watch<AppBootstrap>()
                                            .assistModelActive
                                        ? () => _reminderFor(context, entry,
                                            c.subjectFor(entry.patientId))
                                        : null,
                                  ),
                              ],
                            ),
                          ),
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

void _reminderFor(
    BuildContext context, WorklistEntry entry, RecallSubject? subject) {
  final name = subject?.displayName ?? 'the patient';
  final facts = <String>['Patient: $name', ...entry.reasons].join('. ');
  AiDraftSheet.show(
    context,
    title: 'Recall reminder',
    subtitle: name,
    generate: (engine) => engine.patientReminder(facts),
  );
}

class _RecallRow extends StatelessWidget {
  const _RecallRow({
    required this.entry,
    required this.subject,
    this.onReminder,
  });

  final WorklistEntry entry;
  final RecallSubject? subject;

  /// Drafts a patient-friendly reminder message (AI). Null when no model.
  final VoidCallback? onReminder;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final name = subject?.displayName ?? 'Patient';
    // score is the overdue-days count; the deeper it is, the louder.
    final tone = (entry.score ?? 0) >= 30 ? PillTone.caution : PillTone.info;

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
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          StatusPill(
            label: entry.reasons.length > 1 ? entry.reasons[1] : 'due',
            tone: tone,
            dense: true,
          ),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: m.spaceXs / 2),
        child: Text(entry.reasons.first, style: context.texts.bodySmall),
      ),
      trailing: onReminder == null
          ? null
          : IconButton(
              tooltip: 'Draft reminder',
              icon: const Icon(Icons.sms_outlined),
              onPressed: onReminder,
            ),
      onTap: () => context.push(Routes.chartFor(entry.patientId)),
    );
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
