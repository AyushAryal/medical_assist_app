import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/app_bootstrap.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/audit_event.dart';

/// The access log.
///
/// Making it visible to the clinician is deliberate: an audit trail nobody can
/// see is one nobody trusts, and the person most likely to notice an access
/// they did not make is the person whose device it is.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditEvent> _events = const <AuditEvent>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final audit = context.read<AppBootstrap>().audit;
    final events = await audit.recent(limit: 300);
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Access log')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No entries yet',
                )
              : ContentWidth(
                  child: ListView.separated(
                    padding: EdgeInsets.all(m.spaceLg),
                    itemCount: _events.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(_iconFor(event.action), size: 18),
                        title: Text(event.action.label),
                        subtitle: Text(
                          <String>[
                            Fmt.dateTime(event.occurredAt),
                            if (event.actor != null) event.actor!,
                            if (event.detail != null) event.detail!,
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  static IconData _iconFor(AuditAction action) => switch (action) {
        AuditAction.appUnlock ||
        AuditAction.appLock =>
          Icons.lock_open_outlined,
        AuditAction.appUnlockFailed => Icons.gpp_bad_outlined,
        AuditAction.patientView => Icons.visibility_outlined,
        AuditAction.patientCreate ||
        AuditAction.patientUpdate =>
          Icons.person_outline,
        AuditAction.patientDelete => Icons.person_off_outlined,
        AuditAction.appointmentBook ||
        AuditAction.appointmentUpdate =>
          Icons.event_available_outlined,
        AuditAction.encounterCreate ||
        AuditAction.encounterUpdate =>
          Icons.event_note_outlined,
        AuditAction.encounterSign ||
        AuditAction.noteSign =>
          Icons.draw_outlined,
        AuditAction.vitalsCreate ||
        AuditAction.vitalsUpdate =>
          Icons.monitor_heart_outlined,
        AuditAction.noteCreate ||
        AuditAction.noteUpdate =>
          Icons.description_outlined,
        AuditAction.noteAmend => Icons.playlist_add_check_outlined,
        AuditAction.attachmentAdd ||
        AuditAction.attachmentDelete =>
          Icons.attach_file_outlined,
        AuditAction.export => Icons.ios_share_outlined,
        AuditAction.databaseDestroy => Icons.delete_forever_outlined,
      };
}
