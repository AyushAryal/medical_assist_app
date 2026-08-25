import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/clinics/clinic_list_screen.dart';
import '../../features/appointments/schedule_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/encounters/encounter_screen.dart';
import '../../features/notes/note_editor_screen.dart';
import '../../features/patients/patient_chart_screen.dart';
import '../../features/patients/patient_form_screen.dart';
import '../../features/patients/patient_list_screen.dart';
import '../../features/assist/ask_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/audit_log_screen.dart';
import '../../features/settings/dictation_settings_screen.dart';
import '../../features/settings/modules_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/vitals/vitals_entry_screen.dart';

/// Route names, referenced by constant everywhere so a path change is a
/// one-line edit rather than a string hunt.
abstract final class Routes {
  static const String dashboard = '/';
  static const String schedule = '/schedule';
  static const String patients = '/patients';

  /// The assistant's full page.
  ///
  /// `/ask` rather than `/reports`: it stopped being a reports page when it
  /// became the one place questions are asked, and the stale name had already
  /// caused a bug — the floating bubble hides itself on this route by matching
  /// the path, and nobody looking for "ask" would have found that check.
  static const String ask = '/ask';
  static const String patientNew = '/patients/new';
  static const String patientChart = '/patients/:patientId';
  static const String patientEdit = '/patients/:patientId/edit';
  static const String vitalsEntry = '/patients/:patientId/vitals';
  static const String encounter = '/encounters/:encounterId';
  static const String noteEditor = '/encounters/:encounterId/note';
  static const String clinics = '/clinics';
  static const String settings = '/settings';
  static const String modules = '/settings/modules';
  static const String auditLog = '/settings/audit';
  static const String dictation = '/settings/dictation';

  static String chartFor(String patientId) => '/patients/$patientId';
  static String editFor(String patientId) => '/patients/$patientId/edit';
  static String vitalsFor(String patientId) => '/patients/$patientId/vitals';
  static String encounterFor(String encounterId) => '/encounters/$encounterId';
  static String noteFor(String encounterId) => '/encounters/$encounterId/note';
}

/// Three top-level destinations only.
///
/// A clinician working through a queue should never need more than one tap to
/// get between "what's outstanding", "find a patient" and "settings". Deeper
/// structure lives inside the chart, where the context is already established.
abstract final class AppRouter {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  /// The router this app is running, once built.
  ///
  /// Exposed because the floating assistant is mounted above the router's
  /// Navigator — which is what lets it float over every screen, and also what
  /// leaves it unable to ask which screen that is. It needs to know so it can
  /// take itself out of the way on the one screen that already *is* the
  /// assistant.
  static GoRouter? instance;

  static GoRouter build() {
    return instance = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: Routes.dashboard,
      routes: <RouteBase>[
        // A stateful shell rather than a plain ShellRoute: each destination
        // is a branch with its own navigator, kept alive in an IndexedStack
        // underneath. That's what makes switching tabs an instant, silent
        // swap of already-built widgets — matching a native tab bar — instead
        // of go_router's default push/pop page transition, which briefly
        // showed the outgoing screen sliding out from under the incoming one.
        // It also means each tab remembers its own scroll position and
        // navigation stack when you switch away and back.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: Routes.dashboard,
                  builder: (context, state) => const DashboardScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: Routes.schedule,
                  builder: (context, state) => const ScheduleScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: Routes.patients,
                  builder: (context, state) => const PatientListScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: Routes.ask,
                  // `q` lets the floating assistant hand a question straight
                  // to the full screen, so the bubble never has to render an
                  // answer in a space too small to show its filters honestly.
                  builder: (context, state) => AskScreen(
                    initialQuestion: state.uri.queryParameters['q'],
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: Routes.settings,
                  builder: (context, state) => const SettingsScreen(),
                ),
              ],
            ),
          ],
        ),

        // Full-screen routes: once a chart is open the shell chrome only
        // competes for space with the record.
        GoRoute(
          path: Routes.patientNew,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const PatientFormScreen(),
        ),
        GoRoute(
          path: Routes.patientChart,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              PatientChartScreen(patientId: state.pathParameters['patientId']!),
        ),
        GoRoute(
          path: Routes.patientEdit,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              PatientFormScreen(patientId: state.pathParameters['patientId']),
        ),
        GoRoute(
          path: Routes.vitalsEntry,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => VitalsEntryScreen(
            patientId: state.pathParameters['patientId']!,
            encounterId: state.uri.queryParameters['encounterId'],
          ),
        ),
        GoRoute(
          path: Routes.encounter,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => EncounterScreen(
            encounterId: state.pathParameters['encounterId']!,
          ),
        ),
        GoRoute(
          path: Routes.noteEditor,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => NoteEditorScreen(
            encounterId: state.pathParameters['encounterId']!,
          ),
        ),
        GoRoute(
          path: Routes.clinics,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ClinicListScreen(),
        ),
        GoRoute(
          path: Routes.modules,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const ModulesScreen(),
        ),
        GoRoute(
          path: Routes.auditLog,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const AuditLogScreen(),
        ),
        GoRoute(
          path: Routes.dictation,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const DictationSettingsScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(child: Text('No screen for ${state.uri}')),
      ),
    );
  }
}
