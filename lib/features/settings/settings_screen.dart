import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/design/design.dart';

import '../../core/app_bootstrap.dart';
import '../../core/routing/app_router.dart';
import '../../core/routing/fade_through_route.dart';
import '../../core/security/app_lock_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/fixtures/demo_data.dart';
import '../../data/repositories/clinical_repository.dart';
import '../lock/pin_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _providerName = TextEditingController();
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _biometricLabel = 'Biometric unlock';
  int _pendingSync = 0;
  int _demoPatients = 0;
  bool _demoBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _providerName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lock = context.read<AppLockService>();
    final session = context.read<SessionController>();
    final repository = context.read<ClinicalRepository>();

    final available = await lock.canUseBiometrics();
    final enabled = await lock.isBiometricEnabled();
    final types = await lock.availableBiometrics();
    final pending = await repository.pendingSyncCount();
    final demo = kDebugMode ? await DemoDataSeeder(repository).count() : 0;

    if (!mounted) return;
    setState(() {
      _providerName.text = session.providerName;
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLabel = _describeBiometrics(types);
      _pendingSync = pending;
      _demoPatients = demo;
    });
  }

  static String _describeBiometrics(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) return 'Face unlock';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint unlock';
    if (types.contains(BiometricType.iris)) return 'Iris unlock';
    return 'Biometric unlock';
  }

  Future<void> _runDemoAction(
    Future<int> Function(DemoDataSeeder) action,
    String Function(int) describe,
  ) async {
    if (_demoBusy) return;
    setState(() => _demoBusy = true);

    final messenger = ScaffoldMessenger.of(context);
    final seeder = DemoDataSeeder(context.read<ClinicalRepository>());

    try {
      final affected = await action(seeder);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describe(affected))));
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Demo data failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final lock = context.watch<AppLockService>();
    final theme = context.watch<ThemeController>();
    final m = context.metrics;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings')),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            m.spaceLg,
            m.spaceLg,
            m.spaceLg,
            m.spaceLg + context.bottomBarClearance,
          ),
          children: <Widget>[
            SectionCard(
              title: 'Clinician',
              subtitle: 'Used to attribute signatures and audit entries',
              leading: const Icon(Icons.badge_outlined, size: 20),
              child: Column(
                children: <Widget>[
                  LabeledField(
                    label: 'Name shown on signatures',
                    controller: _providerName,
                    hint: 'e.g. Dr A. Sharma',
                    textCapitalization: TextCapitalization.words,
                    onChanged: session.setProviderName,
                  ),
                  SizedBox(height: m.spaceMd),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Device ${session.deviceId}',
                      style: context.texts.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Clinics',
              leading: const Icon(Icons.local_hospital_outlined, size: 20),
              child: Column(
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active clinic'),
                    subtitle: Text(session.activeClinic?.name ?? 'None'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.clinics),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Security',
              leading: const Icon(Icons.lock_outline, size: 20),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _biometricEnabled && _biometricAvailable,
                    onChanged: _biometricAvailable
                        ? (value) async {
                            await lock.setBiometricEnabled(value);
                            setState(() => _biometricEnabled = value);
                          }
                        : null,
                    title: Text(_biometricLabel),
                    subtitle: Text(
                      _biometricAvailable
                          ? 'A PIN is always kept as a fallback'
                          : 'Not available on this device',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      FadeThroughRoute<void>(
                        builder: (_) => const PinSetupScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lock now'),
                    trailing: const Icon(Icons.lock_outline),
                    onTap: lock.lock,
                  ),
                  SectionCard.divider(context),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Access log'),
                    subtitle: const Text('Who opened which record, and when'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.auditLog),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Assistant and dictation',
              subtitle:
                  'Recording, silence trimming, speech recognition and '
                  'the assistant bubble',
              leading: const Icon(Icons.mic_none_outlined, size: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: context.watch<AppBootstrap>().assistantEnabled,
                    onChanged: (value) =>
                        context.read<AppBootstrap>().setAssistantEnabled(value),
                    title: const Text('Assistant bubble'),
                    subtitle: const Text(
                      'A floating button on every screen for asking about the '
                      'register',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Speech recognition'),
                    subtitle: Text(
                      context.watch<AppBootstrap>().canTranscribe
                          ? 'On device — '
                                '${context.read<AppBootstrap>().transcription.name}'
                          : 'Not set up — dictation is saved as audio only',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.dictation),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Assistant language model'),
                    subtitle: Text(
                      context.watch<AppBootstrap>().activeAssistModel?.name ??
                          'Optional — translates wording the built-in '
                              'matching misses',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.dictation),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Appearance',
              subtitle:
                  'Colours and spacing come from '
                  'assets/theme/clinical.json',
              leading: const Icon(Icons.palette_outlined, size: 20),
              child: ChoiceChipRow<ThemeMode>(
                values: ThemeMode.values,
                labelOf: (mode) => switch (mode) {
                  ThemeMode.system => 'System',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                },
                selected: theme.mode,
                onSelected: (mode) {
                  if (mode == null) return;
                  theme.setMode(mode);
                  session.setThemeMode(mode);
                },
              ),
            ),
            SizedBox(height: m.spaceMd),

            SectionCard(
              title: 'Data',
              leading: const Icon(Icons.storage_outlined, size: 20),
              child: Column(
                children: <Widget>[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Storage'),
                    subtitle: const Text(
                      'All records are held encrypted on this device only.',
                    ),
                    trailing: const StatusPill(
                      label: 'Encrypted',
                      tone: PillTone.normal,
                      icon: Icons.shield_outlined,
                      dense: true,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pending sync'),
                    subtitle: const Text(
                      'Queued for upload when a backend is configured',
                    ),
                    trailing: StatusPill(
                      label: '$_pendingSync',
                      tone: PillTone.neutral,
                      dense: true,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Modules & subscription'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.modules),
                  ),
                ],
              ),
            ),

            // Debug builds only. Fabricated patients must never be reachable
            // in a shipped clinical app, so this whole section is compiled
            // out of release builds rather than merely hidden.
            if (kDebugMode) ...<Widget>[
              SizedBox(height: m.spaceMd),
              SectionCard(
                title: 'Demo data',
                subtitle: 'Debug builds only — never shipped',
                leading: const Icon(Icons.science_outlined, size: 20),
                child: Column(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Adds six fictional patients marked "(DEMO)" so the '
                        'dashboard, reference-range flagging and note '
                        'signing can be reviewed with realistic content. '
                        'Removing them leaves real records untouched.',
                        style: context.texts.bodySmall,
                      ),
                    ),
                    SizedBox(height: m.spaceMd),
                    Row(
                      children: <Widget>[
                        StatusPill(
                          label: '$_demoPatients loaded',
                          tone: _demoPatients > 0
                              ? PillTone.info
                              : PillTone.neutral,
                          dense: true,
                        ),
                      ],
                    ),
                    SizedBox(height: m.spaceMd),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _demoBusy
                                ? null
                                : () => _runDemoAction(
                                    (s) => s.seed(),
                                    (n) => 'Added $n demo patients.',
                                  ),
                            icon: const Icon(Icons.add_chart),
                            label: const Text('Load'),
                          ),
                        ),
                        SizedBox(width: m.spaceSm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _demoBusy || _demoPatients == 0
                                ? null
                                : () async {
                                    final ok = await _confirm(
                                      'Remove demo data?',
                                      'This removes only the fictional '
                                          '"(DEMO)" records. Real patient '
                                          'records are not affected.',
                                      'Remove',
                                    );
                                    if (ok) {
                                      await _runDemoAction(
                                        (s) => s.clear(),
                                        (n) => 'Removed $n demo patients.',
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
