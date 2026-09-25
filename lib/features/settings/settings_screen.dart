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
import '../lock/lock.dart';
import 'smart_phrases_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _providerName = TextEditingController();
  String? _providerNameOnFocus;
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
    final demo = demoDataAllowed ? await DemoDataSeeder(repository).count() : 0;

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

    final seeder = DemoDataSeeder(context.read<ClinicalRepository>());

    try {
      final affected = await action(seeder);
      if (!mounted) return;
      OptToast.success(context, describe(affected));
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      OptToast.error(context, 'Demo data failed: $error');
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) =>
      confirmDialog(
        context,
        title: title,
        message: message,
        confirmLabel: action,
      );

  // ── App lock helpers ──────────────────────────────────────────────────
  // The lock is "on" once a PIN exists. Enrolment and change both run through
  // PinSetupScreen; turning it off clears the PIN (and biometrics with it).

  Future<void> _enableAppLock(AppLockService lock) async {
    await Navigator.of(
      context,
    ).push(FadeThroughRoute<void>(builder: (_) => const _EnableAppLockPage()));
    if (mounted) await _load();
  }

  Future<void> _changePin() async {
    await Navigator.of(
      context,
    ).push(FadeThroughRoute<void>(builder: (_) => const PinSetupScreen()));
    if (mounted) await _load();
  }

  Future<void> _disableAppLock(AppLockService lock) async {
    final ok = await _confirm(
      'Turn off app lock?',
      'The PIN and any biometric unlock will be removed. Anyone with the '
          'device will be able to open the patient records without a PIN.',
      'Turn off',
    );
    if (!ok) return;
    await lock.clearPin();
    if (mounted) {
      setState(() => _biometricEnabled = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final lock = context.watch<AppLockService>();
    final theme = context.watch<ThemeController>();
    final palette = context.palette;
    final m = context.metrics;

    final bootstrap = context.watch<AppBootstrap>();
    final pinSet = lock.state != AppLockState.uninitialised;
    final biometricUsable = _biometricAvailable && pinSet;

    // The kit's family-canonical settings shape: header card, grouped
    // sections, and the standard "About OptDAI" footer row. No sign-out row —
    // this is an offline, single-device app with no account to sign out of.
    return OptSettingsScaffold(
      appName: 'OptDAI',
      onAbout: () => context.push(Routes.about),
      footerNote: 'Clinical Records · Encrypted on-device chart',
      // ── Clinician (header card) ──────────────────────────────────────
      header: SectionCard(
        title: 'Clinician',
        subtitle: 'Attributed to your signatures and audit entries',
        leading: _SectionGlyph(
          icon: Icons.badge_outlined,
          tone: palette.primary,
        ),
        child: Column(
          children: <Widget>[
            // Persisted on every keystroke; the toast waits for the
            // field to lose focus so "saved" is said once, not per key.
            Focus(
              onFocusChange: (focused) {
                if (focused) {
                  _providerNameOnFocus = _providerName.text;
                } else if (_providerName.text.trim() !=
                    (_providerNameOnFocus ?? '').trim()) {
                  OptToast.success(context, 'Provider name saved');
                }
              },
              child: LabeledField(
                label: 'Name shown on signatures',
                controller: _providerName,
                hint: 'e.g. Dr A. Sharma',
                textCapitalization: TextCapitalization.words,
                onChanged: session.setProviderName,
              ),
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
      sections: <OptSettingsSection>[
        // ── Workspace (clinic + smart phrases) ─────────────────────────
        OptSettingsSection(
          title: 'Workspace',
          tiles: <Widget>[
            _SettingsTile(
              icon: Icons.location_on_outlined,
              tone: palette.accent,
              title: 'Active clinic',
              subtitle: session.activeClinic?.name ?? 'None selected',
              chevron: true,
              onTap: () => context.push(Routes.clinics),
            ),
            _SettingsTile(
              icon: Icons.bolt_outlined,
              tone: palette.primary,
              title: 'Smart phrases',
              subtitle:
                  'Expansions like \\ros and \\normal, plus the '
                  'built-in \\pat, \\me, \\today, \\clinic',
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SmartPhrasesScreen(),
                ),
              ),
            ),
          ],
        ),

        // ── Security ─────────────────────────────────────────────────────
        OptSettingsSection(
          title: 'Security',
          tiles: <Widget>[
            _SettingsTile(
              icon: Icons.shield_outlined,
              tone: palette.primary,
              title: 'App lock',
              subtitle: pinSet
                  ? 'On · a PIN is required to open the app'
                  : 'Off · anyone can open the app',
              trailing: _StateChip(on: pinSet),
              onTap: pinSet
                  ? () => _disableAppLock(lock)
                  : () => _enableAppLock(lock),
            ),
            if (pinSet)
              _SettingsTile(
                icon: Icons.pin_outlined,
                tone: palette.accent,
                title: 'Change PIN',
                subtitle: 'Choose a new six-digit PIN',
                chevron: true,
                onTap: _changePin,
              ),
            _SettingsTile(
              icon: Icons.fingerprint,
              tone: palette.accent,
              title: _biometricLabel,
              subtitle: !_biometricAvailable
                  ? 'Not available on this device'
                  : pinSet
                  ? 'Unlock with a face or fingerprint instead of '
                        'the PIN'
                  : 'Turn on app lock first',
              trailing: Switch.adaptive(
                value: _biometricEnabled && biometricUsable,
                onChanged: biometricUsable
                    ? (value) async {
                        await lock.setBiometricEnabled(value);
                        setState(() => _biometricEnabled = value);
                      }
                    : null,
              ),
            ),
            if (pinSet)
              _SettingsTile(
                icon: Icons.lock_clock_outlined,
                tone: palette.primary,
                title: 'Lock now',
                subtitle: 'Require unlock the next time the app opens',
                onTap: lock.lock,
              ),
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              tone: palette.accent,
              title: 'Access log',
              subtitle: 'Who opened which record, and when',
              chevron: true,
              onTap: () => context.push(Routes.auditLog),
            ),
          ],
        ),

        // ── Assistant & dictation ────────────────────────────────────────
        OptSettingsSection(
          title: 'Assistant and dictation',
          footnote: 'Recording, speech recognition and the assistant bubble.',
          tiles: <Widget>[
            _SettingsTile(
              icon: Icons.smart_toy_outlined,
              tone: palette.accent,
              title: 'Assistant bubble',
              subtitle:
                  'A floating button on every screen for asking '
                  'about the register',
              trailing: Switch.adaptive(
                value: bootstrap.assistantEnabled,
                onChanged: (value) =>
                    context.read<AppBootstrap>().setAssistantEnabled(value),
              ),
            ),
            _SettingsTile(
              icon: Icons.record_voice_over_outlined,
              tone: palette.primary,
              title: 'Speech recognition',
              subtitle: bootstrap.canTranscribe
                  ? 'On device — '
                        '${context.read<AppBootstrap>().transcription.name}'
                  : 'Not set up — dictation is saved as audio only',
              chevron: true,
              onTap: () => context.push(Routes.dictation),
            ),
            _SettingsTile(
              icon: Icons.auto_awesome_outlined,
              tone: palette.accent,
              title: 'AI assistant',
              subtitle: 'Engine: ${bootstrap.activeAiEngineLabel}',
              chevron: true,
              onTap: () => context.push(Routes.ai),
            ),
            _SettingsTile(
              icon: Icons.graphic_eq_outlined,
              tone: palette.primary,
              title: 'Read-aloud voice',
              subtitle: 'The voice used to speak generated text',
              chevron: true,
              onTap: () => context.push(Routes.voice),
            ),
          ],
        ),

        // ── Appearance ───────────────────────────────────────────────────
        OptSettingsSection(
          title: 'Appearance',
          footnote: 'Colours and spacing come from assets/theme/clinical.json.',
          tiles: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: m.spaceLg,
                vertical: m.spaceMd,
              ),
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
          ],
        ),

        // ── Data ─────────────────────────────────────────────────────────
        OptSettingsSection(
          title: 'Data',
          tiles: <Widget>[
            _SettingsTile(
              icon: Icons.shield_outlined,
              tone: palette.primary,
              title: 'Storage',
              subtitle: 'All records are held encrypted on this device only',
              trailing: const StatusPill(
                label: 'Encrypted',
                tone: PillTone.normal,
                icon: Icons.shield_outlined,
                dense: true,
              ),
            ),
            _SettingsTile(
              icon: Icons.sync_outlined,
              tone: palette.accent,
              title: 'Pending sync',
              subtitle: 'Queued for upload when a backend is configured',
              trailing: StatusPill(
                label: '$_pendingSync',
                tone: PillTone.neutral,
                dense: true,
              ),
            ),
            _SettingsTile(
              icon: Icons.tune_outlined,
              tone: palette.primary,
              title: 'Modules & subscription',
              chevron: true,
              onTap: () => context.push(Routes.modules),
            ),
          ],
        ),

        // Opt-in builds only. Fabricated patients must never be reachable
        // in a shipped clinical app, so this whole section is compiled out
        // unless the build asked for it — every debug build, or a release
        // built with --dart-define=ALLOW_DEMO_DATA=true. A store build
        // passes neither and the section, like the seeder, does not exist.
        if (demoDataAllowed)
          OptSettingsSection(
            title: 'Demo data',
            footnote: 'Review builds only — never in a shipped app.',
            tiles: <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: m.spaceLg,
                  vertical: m.spaceMd,
                ),
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
                    SizedBox(height: m.spaceSm),
                    // Transparent Material for the same reason as
                    // _SettingsTile: the row sits on the kit section's
                    // decorated surface.
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Load demo data'),
                        subtitle: Text(
                          _demoBusy
                              ? 'Working…'
                              : _demoPatients > 0
                              ? 'Fictional "(DEMO)" records are loaded'
                              : 'Off — no demo records',
                          style: context.texts.bodySmall,
                        ),
                        value: _demoPatients > 0,
                        onChanged: _demoBusy
                            ? null
                            : (on) async {
                                if (on) {
                                  await _runDemoAction(
                                    (s) => s.seed(),
                                    (n) => 'Added $n demo patients.',
                                  );
                                } else {
                                  final ok = await _confirm(
                                    'Remove demo data?',
                                    'This removes only the fictional "(DEMO)" '
                                        'records. Real patient records are not '
                                        'affected.',
                                    'Remove',
                                  );
                                  if (ok) {
                                    await _runDemoAction(
                                      (s) => s.clear(),
                                      (n) => 'Removed $n demo patients.',
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A tinted leading glyph for a section header — a rounded square holding the
/// section icon in its tone, matching the per-row [_SettingsTile] treatment.
class _SectionGlyph extends StatelessWidget {
  const _SectionGlyph({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: context.iconTintAlpha),
        borderRadius: BorderRadius.circular(m.radiusSm),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 19, color: tone),
    );
  }
}

/// One row in a grouped settings section: a tinted leading icon, a title with
/// an optional subtitle, and either a trailing control, a chevron, or nothing.
///
/// Mirrors the grouped-list style used by the other apps in the family, but
/// built entirely from OptDAI tokens so the design guardrails hold.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metrics;
    final palette = context.palette;

    // Transparent Material so the tile's ink renders on the kit OptSection's
    // grouped surface (a DecoratedBox) instead of being painted beneath it —
    // the same trick the kit's own OptTile uses.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: m.spaceLg),
        onTap: onTap,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: context.iconTintAlpha),
            borderRadius: BorderRadius.circular(m.radiusSm),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: tone),
        ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing:
            trailing ??
            (chevron
                ? Icon(Icons.chevron_right, color: palette.onSurfaceMuted)
                : null),
      ),
    );
  }
}

/// A compact On / Off state chip for a toggleable setting reached by tapping
/// the row (rather than a switch) — used by App lock.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: on ? 'On' : 'Off',
      tone: on ? PillTone.normal : PillTone.neutral,
      dense: true,
    );
  }
}

/// First-time PIN enrolment pushed from Settings. PinSetupScreen in first-run
/// mode does not pop itself, so this wrapper listens to the lock service and
/// pops once a PIN lands, and adds a close button so the user can back out
/// without enrolling.
class _EnableAppLockPage extends StatefulWidget {
  const _EnableAppLockPage();

  @override
  State<_EnableAppLockPage> createState() => _EnableAppLockPageState();
}

class _EnableAppLockPageState extends State<_EnableAppLockPage> {
  AppLockService? _lock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lock != null) return;
    _lock = context.read<AppLockService>();
    _lock!.addListener(_maybePop);
  }

  @override
  void dispose() {
    _lock?.removeListener(_maybePop);
    super.dispose();
  }

  void _maybePop() {
    if (!mounted) return;
    if (_lock!.state == AppLockState.uninitialised) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      children: <Widget>[
        const PinSetupScreen(isFirstRun: true),
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close, color: palette.onSurfaceMuted),
            ),
          ),
        ),
      ],
    );
  }
}
