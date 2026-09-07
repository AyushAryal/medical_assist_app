import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/session/session_controller.dart';
import '../../../data/repositories/clinical_repository.dart';
import 'package:provider/provider.dart';

import '../triage_board_controller.dart';

/// The dashboard's window onto triage: how many are waiting and who is top of
/// the list, one tap from the full board. Rendered only when the module is on
/// (the caller guards it with `TriageModule.isVisible`), so a clinic that does
/// not triage never sees it.
class TriageCard extends StatefulWidget {
  const TriageCard({super.key});

  @override
  State<TriageCard> createState() => _TriageCardState();
}

class _TriageCardState extends State<TriageCard> {
  TriageBoardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = TriageBoardController(context.read<ClinicalRepository>());
    _load();
  }

  Future<void> _load() async {
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
    if (controller == null) return const SizedBox.shrink();

    return ChangeNotifierProvider<TriageBoardController>.value(
      value: controller,
      child: Consumer<TriageBoardController>(
        builder: (context, c, _) {
          final m = context.metrics;
          final count = c.waitingCount;
          final top = c.attention.isNotEmpty
              ? c.attention.first
              : (c.needsObs.isNotEmpty ? c.needsObs.first : null);

          return SectionCard(
            title: 'Triage',
            leading: const Icon(Icons.emergency_outlined, size: 20),
            onTap: () => context.push(Routes.triage),
            child: c.isLoading
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: m.spaceSm),
                    child: Text('Reading the waiting room…',
                        style: context.texts.bodySmall),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          StatusPill(
                            label: count == 0
                                ? 'No one waiting'
                                : '$count waiting',
                            tone: count == 0 ? PillTone.neutral : PillTone.info,
                          ),
                        ],
                      ),
                      if (top != null) ...<Widget>[
                        SizedBox(height: m.spaceSm),
                        Text(
                          'Next: ${c.subjectFor(top.patientId)?.displayName ?? 'Patient'}'
                          ' — ${top.reasons.first}',
                          style: context.texts.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}
