import 'cohort/cohort_query.dart';
import '../core/modules/entitlements.dart';
import '../core/modules/module_registry.dart';
import 'assist_request.dart';
import 'intent.dart';
import 'provenance.dart';

/// Whether an intent may proceed, and why not if it may not.
class AccessDecision {
  const AccessDecision.allowed()
      : isAllowed = true,
        reason = null;

  const AccessDecision.denied(String this.reason) : isAllowed = false;

  final bool isAllowed;

  /// Written for the person who asked, not for a log. "You cannot do that" is
  /// useless; "recording a diagnosis needs the problem list module, which is
  /// not enabled here" tells someone what to do next.
  final String? reason;
}

/// Decides what an intent is allowed to do, before anything does it.
///
/// A distinct stage rather than a check inside each handler, for the same
/// reason every mutation goes through one repository: a rule enforced in five
/// places is a rule that is missing from one of them. Reads and writes are
/// judged by different standards here, deliberately —
///
/// * **Reads are permitted broadly.** This is the clinician's own register on
///   their own device, and a search that refuses to count patients is a search
///   nobody uses. Reading is already audited where it matters: opening a chart
///   writes an access entry, and that is the control that counts.
///
/// * **Writes are permitted narrowly, and never silently.** A change arrived
///   at through language has one more layer of interpretation between the
///   person and the record than a tapped form does, and that layer can be
///   wrong in ways nobody sees. So a mutation is only ever a proposal, it
///   needs the module that owns the data to be enabled, and it needs a named
///   actor — an unattributable change to a clinical record is not a change
///   worth having.
class Authoriser {
  const Authoriser(this._entitlements);

  final Entitlements _entitlements;

  AccessDecision check(
    AssistIntent intent,
    AssistRequest request,
    Provenance provenance,
  ) {
    final decision = _decide(intent, request);
    provenance.add(
      'authorise',
      decision.isAllowed ? 'Permitted' : 'Not permitted',
      detail: decision.reason,
    );
    return decision;
  }

  AccessDecision _decide(AssistIntent intent, AssistRequest request) {
    switch (intent) {
      case UnknownIntent():
        return const AccessDecision.allowed();

      case QueryIntent():
      case ReportIntent():
      case AnalysisIntent():
      case RankIntent():
      case OverviewIntent():
      case PatientSummaryIntent():
        // Reading the register the clinician is already holding. A summary of
        // one patient is a read of a chart they can already open — an aggregate
        // is a weaker disclosure than the list it came from, not a stronger
        // one — nobody who can open a chart is being shown something new by an
        // average of it.
        return const AccessDecision.allowed();

      case MutationIntent(:final entity, :final operation):
        if (request.actor == null || request.actor!.trim().isEmpty) {
          return const AccessDecision.denied(
            'A change needs a named clinician against it. Set your name in '
            'Settings before making changes this way.',
          );
        }

        final module = _moduleFor(entity);
        if (!_entitlements.has(module)) {
          return AccessDecision.denied(
            '${ModuleRegistry.all[module]?.name ?? 'That feature'} is not '
            'enabled on this device, so it cannot be changed from here.',
          );
        }

        if (operation == MutationOperation.archive) {
          // Nothing in this app deletes a clinical record, and language is not
          // where that would start.
          return const AccessDecision.denied(
            'Records are archived from the chart itself, where the reason is '
            'recorded with the change. That is deliberate — it keeps the '
            'record defensible.',
          );
        }

        return const AccessDecision.allowed();
    }
  }

  /// The module that owns each kind of data, so a locked feature cannot be
  /// written to through a side door.
  static ModuleId _moduleFor(QueryEntity entity) => switch (entity) {
        QueryEntity.patients => ModuleId.patients,
        QueryEntity.appointments => ModuleId.appointments,
        QueryEntity.visits => ModuleId.encounters,
        QueryEntity.vitals => ModuleId.vitals,
        QueryEntity.notes => ModuleId.notes,
        QueryEntity.files => ModuleId.attachments,
      };
}
