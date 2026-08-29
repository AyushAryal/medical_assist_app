import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/design/design.dart';
import '../../../core/routing/app_router.dart';
import '../../../data/repositories/clinical_repository.dart';
import '../recall_board_controller.dart';

/// The dashboard's window onto recall: how many reviews are overdue, one tap
/// from the list. Rendered only when the module is on (caller guards with
/// `RecallModule.isVisible`).
class RecallCard extends StatefulWidget {
  const RecallCard({super.key});

  @override
  State<RecallCard> createState() => _RecallCardState();
}

class _RecallCardState extends State<RecallCard> {
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
    if (controller == null) return const SizedBox.shrink();

    return ChangeNotifierProvider<RecallBoardController>.value(
      value: controller,
      child: Consumer<RecallBoardController>(
        builder: (context, c, _) {
          final m = context.metrics;
          final count = c.dueCount;
          return SectionCard(
            title: 'Recall',
            leading: const Icon(Icons.event_repeat_outlined, size: 20),
            onTap: () => context.push(Routes.recall),
            child: c.isLoading
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: m.spaceSm),
                    child: Text('Checking overdue reviews…',
                        style: context.texts.bodySmall),
                  )
                : Row(
                    children: <Widget>[
                      StatusPill(
                        label: count == 0
                            ? 'None overdue'
                            : '$count overdue for review',
                        tone: count == 0 ? PillTone.neutral : PillTone.caution,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
