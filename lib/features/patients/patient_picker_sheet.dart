import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';
import '../../data/models/patient.dart';
import '../../data/repositories/clinical_repository.dart';

/// Pick one patient by name, for the `\pat` smart phrase.
///
/// The reason it exists: a doctor rarely knows the exact spelling on file, and
/// three registers hold more than one "Ramesh". Searching and *tapping* the
/// right person resolves the ambiguity at the source, so whatever is asked next
/// carries an exact patient id rather than a name the assistant must re-guess.
class PatientPickerSheet extends StatefulWidget {
  const PatientPickerSheet({super.key});

  static Future<Patient?> show(BuildContext context) {
    return showModalBottomSheet<Patient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (_) => Provider<ClinicalRepository>.value(
        value: context.read<ClinicalRepository>(),
        child: const PatientPickerSheet(),
      ),
    );
  }

  @override
  State<PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<PatientPickerSheet> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<Patient> _results = const <Patient>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load('');
      _focus.requestFocus();
    });
    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), () {
        _load(_search.text.trim());
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final repository = context.read<ClinicalRepository>();
    setState(() => _loading = true);
    // Empty query shows the recently seen — the common case is the patient in
    // front of you, who was just opened.
    final patients = query.isEmpty
        ? await repository.patients.recent(limit: 30)
        : await repository.patients.search(query, limit: 30);
    if (!mounted) return;
    setState(() {
      _results = patients;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(m.spaceLg, 0, m.spaceLg, m.spaceMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.person_search_outlined,
                    size: 20, color: palette.accent),
                SizedBox(width: m.spaceSm),
                Text('Insert a patient', style: context.texts.titleMedium),
              ],
            ),
            SizedBox(height: m.spaceMd),
            TextField(
              controller: _search,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Search by name, MRN or phone…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: palette.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(m.radiusLg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: m.spaceSm),
            Flexible(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _results.isEmpty
                      ? EmptyState(
                          icon: Icons.person_off_outlined,
                          title: 'No one found',
                          message: _search.text.trim().isEmpty
                              ? 'No patients on the register yet.'
                              : 'No patient matches "${_search.text.trim()}".',
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final patient = _results[i];
                            return PersonRow(
                              name: patient.displayName,
                              subtitle: patient.identityLine,
                              seed: patient.id,
                              initials: patient.initials,
                              onTap: () =>
                                  Navigator.of(context).pop(patient),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
