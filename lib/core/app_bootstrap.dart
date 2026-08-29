import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/clinical_repository.dart';
import '../ai/pipeline.dart';
import '../data/services/assist/assist_service.dart';
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

      _phase = BootstrapPhase.ready;
      // Not awaited: they only read file sizes, and an unlock must not wait
      // on the filesystem to show the dashboard.
      unawaited(refreshTranscriptionEngine());
      unawaited(refreshAssistEngine());
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
