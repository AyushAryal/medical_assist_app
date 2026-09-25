import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/routing/app_router.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';
import 'patient_chart_screen.dart';

/// Find a patient, then work on them.
///
/// On a tablet the chart opens *beside* the list rather than on top of it. That
/// is not decoration: the actual task is "work through these six people", and
/// on the previous layout every patient cost a push, a read, and a pop that
/// lost the search text and the scroll position. Here the list keeps its state
/// and the selection moves.
class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<Patient> _results = const <Patient>[];
  bool _isLoading = true;

  /// The patient shown in the detail pane. Only consulted on a wide screen; a
  /// phone navigates instead, so there is no pane for it to fill.
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Short debounce: long enough to avoid a query per keystroke, short enough
  /// that the list feels like it is filtering as you type.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _search(value));
  }

  Future<void> _search(String value) async {
    final repository = context.read<ClinicalRepository>();
    final results = value.trim().isEmpty
        ? await repository.patients.recent(limit: 50)
        : await repository.patients.search(value);
    if (!mounted) return;
    setState(() {
      _results = results;
      _isLoading = false;
      // A selection that has fallen out of the filtered list would leave the
      // detail pane showing someone the list no longer contains.
      if (_selectedId != null &&
          !results.any((patient) => patient.id == _selectedId)) {
        _selectedId = null;
      }
    });
  }

  void _open(Patient patient) {
    if (context.breakpoint.hasDetailPane) {
      setState(() => _selectedId = patient.id);
      return;
    }
    context.push(Routes.chartFor(patient.id)).then((_) {
      if (mounted) _search(_query.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Patients'),
        actions: <Widget>[
          // Top-right, iOS-style: a FAB down there sat behind the floating
          // pill bar.
          IconButton(
            tooltip: 'New patient',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () async {
              await context.push(Routes.patientNew);
              if (mounted) _search(_query.text);
            },
          ),
        ],
      ),
      body: TwoPane(
        masterFlex: 2,
        detailFlex: 3,
        minMasterWidth: 320,
        maxMasterWidth: 400,
        master: _list(context),
        detail: (context) => _selectedId == null
            ? const DetailPanePlaceholder(
                icon: Icons.folder_shared_outlined,
                title: 'No patient selected',
                message:
                    'Choose someone from the list to open their chart '
                    'here, without losing your place.',
              )
            // Keyed so switching patients rebuilds the chart's controller
            // rather than showing the previous patient's data under a new name.
            : PatientChartScreen(
                key: ValueKey<String>(_selectedId!),
                patientId: _selectedId!,
              ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final m = context.metrics;

    return ContentWidth(
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              m.spaceLg,
              m.spaceMd,
              m.spaceLg,
              m.spaceSm,
            ),
            child: TextField(
              controller: _query,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Name, MRN or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _query.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? SkeletonList(
                    padding: EdgeInsets.fromLTRB(
                      m.spaceLg,
                      0,
                      m.spaceLg,
                      m.spaceLg + context.bottomBarClearance,
                    ),
                  )
                : _results.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: _query.text.isEmpty
                        ? 'No patients registered'
                        : 'No match for "${_query.text}"',
                    message: _query.text.isEmpty
                        ? 'Register the first patient to get started.'
                        : 'Check the spelling, or register a new patient.',
                    actionLabel: 'Register patient',
                    onAction: () async {
                      await context.push(Routes.patientNew);
                      if (mounted) _search(_query.text);
                    },
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      m.spaceLg,
                      0,
                      m.spaceLg,
                      m.spaceLg + context.bottomBarClearance,
                    ),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => SizedBox(height: m.spaceSm),
                    itemBuilder: (context, index) => _PatientTile(
                      patient: _results[index],
                      isSelected: _results[index].id == _selectedId,
                      onTap: () => _open(_results[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({
    required this.patient,
    required this.isSelected,
    required this.onTap,
  });

  final Patient patient;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = context.metrics;

    return Material(
      // Selection has to be visible in a master–detail layout: without it the
      // list gives no clue which of six patients the pane is showing.
      color: isSelected ? palette.primaryContainer : palette.surface,
      borderRadius: BorderRadius.circular(m.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: m.spaceMd),
          child: PersonRow(
            name: patient.displayName,
            subtitle: patient.identityLine,
            seed: patient.id,
            initials: patient.initials,
            badge: patient.allergyStatus == AllergyStatus.hasAllergies
                ? AvatarBadge(
                    icon: Icons.warning_amber_rounded,
                    tone: palette.critical,
                  )
                : null,
            // "Not seen yet", not a dash: a placeholder glyph in the
            // last-seen slot reads as a rendering bug on a freshly
            // registered patient.
            trailing: Text(
              patient.lastSeenAt == null
                  ? 'Not seen yet'
                  : Fmt.relative(patient.lastSeenAt),
              style: context.texts.labelSmall?.copyWith(
                color: patient.lastSeenAt == null
                    ? context.palette.onSurfaceMuted
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
