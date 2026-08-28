import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/session/session_controller.dart';
import '../../data/repositories/clinical_repository.dart';
import '../appointments/book_appointment_sheet.dart';
import '../clinics/clinic_picker_sheet.dart';
import 'dashboard_controller.dart';
import 'widgets/at_a_glance.dart';
import 'widgets/header.dart';
import 'widgets/needs_attention.dart';
import 'widgets/next_up_card.dart';
import 'widgets/open_work.dart';
import 'widgets/quick_actions.dart';
import 'widgets/recent_patients.dart';
import 'widgets/today_schedule.dart';

/// The screen a clinician opens the app onto.
///
/// Ordered by what is actually pending: who is here now, what is booked, what
/// is unfinished, and who needs a second look. Reference numbers come last —
/// "registered patients" is context, not a task.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = DashboardController(context.read<ClinicalRepository>());
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

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _bookForPatient() async {
    final patientId = await _pickPatient();
    if (patientId == null || !mounted) return;
    final patient = await context.read<ClinicalRepository>().patients.byId(
      patientId,
    );
    if (patient == null || !mounted) return;
    await BookAppointmentSheet.show(context, patient: patient);
    await _reload();
  }

  /// Lightweight patient picker so booking does not require leaving the
  /// dashboard and navigating the full patient list.
  Future<String?> _pickPatient() async {
    final repository = context.read<ClinicalRepository>();
    final recent = await repository.patients.recent(limit: 30);
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(context.metrics.spaceLg),
              child: Text('Choose patient', style: context.texts.titleMedium),
            ),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No patients registered yet.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: recent.length,
                  itemBuilder: (context, index) {
                    final patient = recent[index];
                    return ListTile(
                      leading: PatientAvatar(
                        initials: patient.initials,
                        seed: patient.id,
                        radius: 18,
                      ),
                      title: Text(patient.displayName),
                      subtitle: Text(patient.identityLine),
                      onTap: () => Navigator.of(context).pop(patient.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = context.watch<SessionController>();
    final m = context.metrics;

    return ChangeNotifierProvider<DashboardController>.value(
      value: controller,
      child: Consumer<DashboardController>(
        builder: (context, dashboard, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: <Widget>[
                RefreshIndicator(
                  onRefresh: _reload,
                  child: ContentWidth.columns(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        m.spaceLg,
                        0,
                        m.spaceLg,
                        m.spaceLg + context.bottomBarClearance,
                      ),
                      children: <Widget>[
                        SafeArea(
                          bottom: false,
                          child: SizedBox(height: m.spaceSm),
                        ),
                        Header(
                          greeting: _greeting(DateTime.now()),
                          name: session.providerName,
                          clinicName: session.activeClinic?.name,
                          onSwitchClinic: () async {
                            await ClinicPickerSheet.show(context);
                            if (context.mounted) await _reload();
                          },
                        ),
                        SizedBox(height: m.spaceLg),
                        // Who is next, and anything abnormal, always come
                        // first and always full width — they are the two
                        // things that must not be missed, and putting them in
                        // a column would let the layout decide their
                        // prominence.
                        NextUpCard(dashboard: dashboard, onChanged: _reload),
                        SizedBox(height: m.spaceLg),
                        NeedsAttention(dashboard: dashboard),
                        QuickActions(
                          dashboard: dashboard,
                          onBook: _bookForPatient,
                          onChanged: _reload,
                        ),
                        SizedBox(height: m.spaceLg),
                        // Below the fold the panels are independent, so a wide
                        // screen runs them in two columns rather than a single
                        // strip between two empty margins.
                        SplitColumns(
                          primary: <Widget>[
                            TodaySchedule(dashboard: dashboard),
                            OpenWork(dashboard: dashboard, onChanged: _reload),
                          ],
                          secondary: <Widget>[
                            AtAGlance(dashboard: dashboard),
                            RecentPatients(dashboard: dashboard),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Sits above the scrolling list so content passing beneath the
                // status bar stays legible.
                const StatusBarScrim(),
              ],
            ),
          );
        },
      ),
    );
  }
}
