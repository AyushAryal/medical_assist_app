import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/repositories/clinical_repository.dart';
import '../ai/pipeline.dart';
import '../data/services/assist/assist_service.dart';
import '../data/fixtures/demo_data.dart';
import '../data/services/assist/apple_foundation_model.dart';
import '../data/services/assist/assist_model_catalog.dart';
import '../data/services/assist/assist_model_manager.dart';
import '../data/services/assist/language_model.dart';
import '../data/services/assist/llama_engine.dart';
import '../data/services/dictation_recorder.dart';
import '../data/services/transcription/speech_model.dart';
import '../data/services/transcription/transcription_engine.dart';
import '../data/services/transcription/whisper_engine.dart';
import '../data/services/voice_note_service.dart';
import 'audit/audit_service.dart';
import 'db/app_database.dart';
import 'db/app_meta_store.dart';
import 'modules/entitlements.dart';
import 'modules/workflow_preferences.dart';
import 'security/app_lock_service.dart';
import 'security/db_key_manager.dart';
import 'security/secure_store.dart';
import 'session/session_controller.dart';

enum BootstrapPhase { idle, opening, ready, failed }

/// Wires the data layer, and does so only *after* the user authenticates.
///
/// The database key is fetched from the keystore and the encrypted file opened
/// at unlock, not at launch. Before unlock the process holds no key and no
/// decrypted handle, so an attacker who grabs a launched-but-locked device gets
/// nothing from memory either.
class AppBootstrap extends ChangeNotifier {
  AppBootstrap({
    required this.secureStore,
    required this.lockService,
    required this.entitlements,
  });

  final SecureStore secureStore;
  final AppLockService lockService;
  final Entitlements entitlements;

  BootstrapPhase _phase = BootstrapPhase.idle;
  Object? _error;

  AppDatabase? _database;
  AuditService? _audit;
  ClinicalRepository? _repository;
  AppMetaStore? _meta;
  SessionController? _session;
  WorkflowPreferences? _workflows;
  VoiceNoteService? _voiceNotes;
  DictationRecorder? _dictation;
  AssistService? _assist;
  AssistPipeline? _pipeline;

  /// Model management is safe before unlock — it touches no patient data — so
  /// it is created once and kept, unlike everything above it.
  final SpeechModelManager speechModels = SpeechModelManager();

  /// Same rule as [speechModels]: the manager only handles files, so it lives
  /// across locks. The *engine* built on those files does not — see
  /// [refreshAssistEngine].
  final AssistModelManager assistModels = AssistModelManager();

  TranscriptionEngine _transcription = const UnconfiguredTranscriptionEngine();

  /// Where the dictation storage-quality preference lives. In `app_meta`, which
  /// is inside the encrypted database, like every other operational setting.
  static const String dictationQualityKey = 'dictation_quality';

  /// Which installed speech model to use, when more than one is present.
  static const String speechModelKey = 'speech_model_id';

  /// Which installed assistant model interprets unmatched questions.
  static const String assistModelKey = 'assist_model_id';

  /// Whether the floating assistant appears over every screen.
  static const String assistantEnabledKey = 'assistant_enabled';

  /// Whether every dictation also keeps its untrimmed recording.
  static const String keepOriginalAudioKey = 'dictation_keep_original';

  /// On by default, and switchable from Settings. A control that follows a
  /// clinician onto every screen has to be removable, or the people it does
  /// not suit spend the day working around it.
  bool get assistantEnabled => _assistantEnabled;
  bool _assistantEnabled = true;

  Future<void> setAssistantEnabled(bool enabled) async {
    _assistantEnabled = enabled;
    await meta.write(assistantEnabledKey, enabled.toString());
    notifyListeners();
  }

  /// The model currently driving [transcription], or null when none is
  /// installed. Exposed so Settings can mark which of several is live.
  SpeechModel? get activeSpeechModel => _activeSpeechModel;
  SpeechModel? _activeSpeechModel;

  /// The language model behind the assistant, or null when none is installed.
  AssistModel? get activeAssistModel => _activeAssistModel;
  AssistModel? _activeAssistModel;
  LanguageModelEngine? _assistEngine;

  /// Whether an assistant model is installed and live.
  bool get assistModelActive => _assistEngine != null;

  /// The live engine, for the features that draft with it (note sorting,
  /// patient instructions). Null when no model is installed — every caller
  /// must work without it, because on most devices it will be.
  LanguageModelEngine? get assistEngine => _assistEngine;

  /// Re-reads which assistant model is installed and rebuilds the engine.
  ///
  /// Called at unlock and after every install, switch or removal in Settings.
  /// The pipeline reads the engine through a provider, so a swap here takes
  /// effect on the next question without rebuilding the pipeline — which is
  /// what preserves the conversation across a model change. The stored
  /// preference wins when its model is actually installed; otherwise the
  /// first installed model serves, so removing one falls back rather than
  /// silently switching the feature off.
  Future<void> refreshAssistEngine() async {
    // Prefer the system model (Apple Intelligence) when the OS offers it: no
    // download, no bundled weights, and it is already on the device. A
    // downloaded model only serves where the native one is unavailable.
    final apple = AppleFoundationLanguageModel();
    if (await apple.isReady()) {
      await _assistEngine?.dispose();
      _assistEngine = apple;
      _activeAssistModel = null; // no downloaded file backs this one
      notifyListeners();
      return;
    }

    final preferredId =
        _meta == null ? null : await meta.read(assistModelKey);
    final preferred = AssistModelCatalog.byId(preferredId);

    final model = preferred != null &&
            await assistModels.installed(preferred) != null
        ? preferred
        : await assistModels.firstInstalled();

    final installed =
        model == null ? null : await assistModels.installed(model);

    await _assistEngine?.dispose();
    _activeAssistModel = installed?.model;
    _assistEngine = installed == null
        ? null
        : LlamaEngine(
            modelPath: installed.path,
            modelName: installed.model.name,
          );
    notifyListeners();
  }

  /// Chooses which installed assistant model answers from now on.
  Future<void> setAssistModel(AssistModel model) async {
    await meta.write(assistModelKey, model.id);
    await refreshAssistEngine();
  }

  /// Debug convenience provisioning runs on debug builds but never under
  /// `flutter test`, so a bootstrap test cannot trigger a slow seed or a
  /// network model download.
  bool get _debugProvisioningEnabled =>
      kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Debug only: fills an empty database with the realistic demo dataset, so a
  /// fresh debug install lands on populated triage/recall/charts. Idempotent —
  /// it seeds only when nothing is there — and swallows its own failures rather
  /// than ever blocking startup.
  Future<void> _seedDemoDataIfEmpty(ClinicalRepository repository) async {
    try {
      final seeder = DemoDataSeeder(repository);
      if (await seeder.count() == 0) {
        await seeder.seed();
      }
    } on Object catch (error) {
      debugPrint('Debug demo seed skipped: $error');
    }
  }

  /// Debug only: downloads and activates the smallest assistant model when none
  /// is installed, so the AI features are visible without a manual install.
  Future<void> _installLightestAssistModelIfNone() async {
    try {
      // Nothing to download if the OS already provides a system model.
      if (await AppleFoundationLanguageModel().isReady()) return;
      if (await assistModels.firstInstalled() != null) return;
      final lightest = AssistModelCatalog.models
          .reduce((a, b) => a.bytes <= b.bytes ? a : b);
      await assistModels.download(lightest);
      await setAssistModel(lightest);
    } on Object catch (error) {
      debugPrint('Debug assist-model auto-install skipped: $error');
    }
  }

  BootstrapPhase get phase => _phase;
  Object? get error => _error;
  bool get isReady => _phase == BootstrapPhase.ready;

  AppDatabase get database => _require(_database, 'database');
  AuditService get audit => _require(_audit, 'audit');
  ClinicalRepository get repository => _require(_repository, 'repository');
  AppMetaStore get meta => _require(_meta, 'meta');
  SessionController get session => _require(_session, 'session');
  WorkflowPreferences get workflows => _require(_workflows, 'workflows');
  VoiceNoteService get voiceNotes => _require(_voiceNotes, 'voiceNotes');
  DictationRecorder get dictation => _require(_dictation, 'dictation');
  AssistService get assist => _require(_assist, 'assist');

  /// The one path from a question to an answer.
  ///
  /// Single instance on purpose: the bubble and the full search screen used to
  /// each carry their own copy of the middle of this and drifted apart twice.
  AssistPipeline get pipeline => _require(_pipeline, 'pipeline');

  /// The configured transcriber, or an [UnconfiguredTranscriptionEngine] that
  /// explains how to set one up. Never null, so no call site has to branch on
  /// whether the feature exists.
  TranscriptionEngine get transcription => _transcription;

  bool get canTranscribe =>
      _transcription is! UnconfiguredTranscriptionEngine;

  /// Re-reads which speech model is installed and rebuilds the engine.
  ///
  /// Called at unlock and again whenever Settings finishes an install, so
  /// turning the feature on does not require restarting the app mid-clinic.
  ///
  /// The stored preference wins when the model it names is actually installed.
  /// Falling back to "whatever is installed first" is only for the case where
  /// no choice has been made, or where the chosen model has since been
  /// removed — otherwise removing a model would silently leave transcription
  /// off rather than moving to the other one.
  Future<void> refreshTranscriptionEngine() async {
    final preferredId = _meta == null ? null : await meta.read(speechModelKey);
    final preferred = SpeechModel.byId(preferredId);

    final model = preferred != null &&
            await speechModels.installed(preferred) != null
        ? preferred
        : await speechModels.firstInstalled();

    _activeSpeechModel = model;
    _transcription = model == null
        ? const UnconfiguredTranscriptionEngine()
        : WhisperTranscriptionEngine(models: speechModels, model: model);
    notifyListeners();
  }

  /// Chooses which installed model transcribes from now on.
  Future<void> setSpeechModel(SpeechModel model) async {
    await meta.write(speechModelKey, model.id);
    await refreshTranscriptionEngine();
  }

  T _require<T>(T? value, String name) {
    if (value == null) {
      throw StateError('$name is unavailable until the app is unlocked');
    }
    return value;
  }

  Future<void> openAfterUnlock() async {
    if (_phase == BootstrapPhase.opening || _phase == BootstrapPhase.ready) {
      return;
    }
    _phase = BootstrapPhase.opening;
    _error = null;
    notifyListeners();

    try {
      final database = AppDatabase(DbKeyManager(secureStore));
      await database.open();

      final audit = AuditService(database);
      final repository = ClinicalRepository.wire(
        database: database,
        audit: audit,
      );
      final meta = AppMetaStore(database);
      _meta = meta;
      final session = SessionController(repository, meta);
      await session.load();

      final workflows = WorkflowPreferences(meta);
      await workflows.load();

      audit.configure(
        actor: session.signatureName,
        deviceId: session.deviceId,
      );
      // Keep the audit actor in step when the clinician changes their name.
      session.addListener(() {
        audit.configure(
          actor: session.signatureName,
          deviceId: session.deviceId,
        );
      });

      _database = database;
      _audit = audit;
      _repository = repository;
      _meta = meta;
      _session = session;
      _workflows = workflows;
      _voiceNotes = VoiceNoteService();
      _dictation = DictationRecorder(
        quality:
            await meta.read(dictationQualityKey) == DictationQuality.compact.name
                ? DictationQuality.compact
                : DictationQuality.full,
        keepOriginal: await meta.read(keepOriginalAudioKey) == 'true',
      );
      _assist = AssistService();
      _pipeline = AssistPipeline(
        repository: repository,
        entitlements: entitlements,
        // A provider, not an instance: Settings can install or switch models
        // mid-session, and the conversation must survive the swap.
        languageModel: () => _assistEngine,
      );
      _assistantEnabled =
          (await meta.read(assistantEnabledKey) ?? 'true') != 'false';

      // Debug builds arrive populated: a realistic dataset so triage, recall
      // and the charts have something to show, seeded before the dashboard
      // first loads. Never runs in a shipped build (guarded by demoDataAllowed).
      if (_debugProvisioningEnabled) {
        await _seedDemoDataIfEmpty(repository);
      }

      _phase = BootstrapPhase.ready;
      // Not awaited: they only read file sizes, and an unlock must not wait
      // on the filesystem to show the dashboard.
      unawaited(refreshTranscriptionEngine());
      unawaited(refreshAssistEngine());

      // Debug convenience: pull the smallest assistant model in the background
      // so the AI features are visible without a manual install. Non-blocking
      // and best-effort — the app is fully usable while it downloads, and the
      // deterministic features never depend on it.
      if (_debugProvisioningEnabled) {
        unawaited(_installLightestAssistModelIfNone());
      }
    } on Object catch (error) {
      _error = error;
      _phase = BootstrapPhase.failed;
    }
    notifyListeners();
  }

  /// Tears down decrypted state on lock. The handle is closed rather than
  /// merely hidden so no cached pages of PHI stay resident.
  Future<void> closeOnLock() async {
    await _dictation?.cancel();
    _dictation?.dispose();
    _dictation = null;
    _assist = null;
    // Holds a repository handle, so it must go with the database — and the
    // conversation thread inside it is PHI, gone with the lock.
    _pipeline = null;
    // The engine holds no PHI, but a worker isolate with a gigabyte of
    // weights should not sit resident behind a lock screen.
    unawaited(_assistEngine?.dispose());
    _assistEngine = null;
    _activeAssistModel = null;
    await _voiceNotes?.dispose();
    await _database?.close();
    _database = null;
    _audit = null;
    _repository = null;
    _meta = null;
    _session = null;
    _workflows = null;
    _voiceNotes = null;
    _phase = BootstrapPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _database?.close();
    _voiceNotes?.dispose();
    _dictation?.dispose();
    unawaited(_transcription.dispose());
    super.dispose();
  }
}
