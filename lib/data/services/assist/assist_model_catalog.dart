/// Small open-weight language models suitable for this assistant, on-device.
///
/// The task is narrow — rewrite a free-form request as one of a few dozen
/// known question forms — which is exactly what the smallest instruction-tuned
/// models do well and the only thing this app will ask one to do. Knowledge,
/// diagnosis and generation are all out of contract (see
/// `language_model.dart`), so the selection criteria are: instruction
/// following at tiny scale, a licence a clinic can actually accept, GGUF
/// availability for llama.cpp-style runtimes, and a size a mid-range Android
/// tablet holds in memory beside SQLCipher and Whisper.
///
/// Catalogued like the speech models: exact artefact, exact size, so the
/// download shows real progress and refuses to start without room.
/// How much memory a device has to spare, in the coarse bands that actually
/// change the recommendation.
///
/// Deliberately three bands the operator picks, not a number the app measures.
/// Total RAM is not readable without a platform plugin, "free" RAM swings
/// minute to minute, and a wrong guess here would either push a heavy model
/// onto a device that will kill it under load or hide a good one from a device
/// that could run it. The operator knows their fleet; the app states what each
/// model needs and lets them match it — the same "an operator explicitly
/// accepts it" stance the rest of the app takes with anything it cannot verify.
enum DeviceClass {
  /// Budget tablets, ~2–3 GB total RAM, sharing memory with SQLCipher and
  /// Whisper. Only the smallest models leave room to work.
  entry,

  /// The common mid-range clinic tablet, ~4–6 GB. Any model here is fine.
  standard,

  /// ~8 GB or more. Runs the most accurate model without thinking about it.
  ample,
}

extension DeviceClassX on DeviceClass {
  String get label => switch (this) {
        DeviceClass.entry => 'Entry',
        DeviceClass.standard => 'Standard',
        DeviceClass.ample => 'Ample',
      };

  /// The rough total-RAM band this stands for, for the picker to show.
  String get memoryHint => switch (this) {
        DeviceClass.entry => '2–3 GB RAM',
        DeviceClass.standard => '4–6 GB RAM',
        DeviceClass.ample => '8 GB+ RAM',
      };

  int get _rank => switch (this) {
        DeviceClass.entry => 0,
        DeviceClass.standard => 1,
        DeviceClass.ample => 2,
      };

  /// Whether a device of this class comfortably runs something needing [need].
  bool meets(DeviceClass need) => _rank >= need._rank;
}

class AssistModel {
  const AssistModel({
    required this.id,
    required this.name,
    required this.description,
    required this.repository,
    required this.file,
    required this.bytes,
    required this.licence,
    required this.parameters,
    required this.minDeviceClass,
    required this.runtimeMemoryLabel,
  });

  final String id;
  final String name;
  final String description;

  /// Hugging Face repository holding the quantised GGUF.
  final String repository;
  final String file;
  final int bytes;

  /// Stated because it is a deployment decision, not a footnote: a clinic
  /// installing a model is accepting its licence.
  final String licence;

  final String parameters;

  /// The smallest device class that runs this comfortably alongside everything
  /// else resident. A device below it can still install the model — nothing is
  /// blocked — but is warned it may be heavy.
  final DeviceClass minDeviceClass;

  /// Roughly the working memory the model needs while answering — the download
  /// size plus the runtime the weights and a small context cost. Stated so the
  /// size on disk is not mistaken for the cost of running it.
  final String runtimeMemoryLabel;

  String get sizeLabel => '${(bytes / (1024 * 1024)).round()} MB';

  String get url => 'https://huggingface.co/$repository/resolve/main/$file';
}

abstract final class AssistModelCatalog {
  static AssistModel? byId(String? id) =>
      models.where((model) => model.id == id).firstOrNull;

  /// The model to steer a device of [deviceClass] toward: the most accurate one
  /// (models are in quality order) that class runs comfortably. Falls back to
  /// the smallest if nothing fits, so there is always a recommendation.
  static AssistModel recommendedFor(DeviceClass deviceClass) =>
      models.firstWhere(
        (model) => deviceClass.meets(model.minDeviceClass),
        orElse: () => models.last,
      );

  /// In recommendation order.
  ///
  /// Qwen2.5 first: at this size class it follows rewrite instructions most
  /// reliably and its Apache-2.0 licence is the least encumbered. Gemma is
  /// the strongest per parameter but carries Google's use policy; Llama
  /// carries Meta's. SmolLM2 is the floor that still works, for devices where
  /// every hundred megabytes matters.
  ///
  /// MedGemma 4B is last and apart: the one entry trained on medical text, kept
  /// as an option for a clinic that wants the assistant's rewrites to share the
  /// vocabulary of the notes they sit beside. It changes nothing about the
  /// contract — it still only reshapes text and still never diagnoses (see
  /// `language_model.dart`); its medical training buys wording, not opinion. It
  /// is deliberately never the automatic recommendation, because the rewrite
  /// tasks were verified against Qwen and MedGemma costs several times the
  /// memory. At 4B it needs a high-memory device, which the device-class
  /// marking makes plain rather than discovering at first run.
  static const List<AssistModel> models = <AssistModel>[
    AssistModel(
      id: 'qwen2.5-1.5b-instruct-q4',
      name: 'Qwen2.5 1.5B Instruct',
      description: 'Best rewrite accuracy of the small models tried; '
          'unencumbered licence.',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      file: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      bytes: 1117320736,
      licence: 'Apache 2.0',
      parameters: '1.5B',
      minDeviceClass: DeviceClass.standard,
      runtimeMemoryLabel: '~1.8 GB RAM',
    ),
    AssistModel(
      id: 'qwen2.5-0.5b-instruct-q4',
      name: 'Qwen2.5 0.5B Instruct',
      description: 'Half a gigabyte and answers in about a second on a '
          'tablet. The one the rewrite contract was verified against.',
      repository: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
      file: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
      bytes: 491400032,
      licence: 'Apache 2.0',
      parameters: '0.5B',
      minDeviceClass: DeviceClass.entry,
      runtimeMemoryLabel: '~0.9 GB RAM',
    ),
    AssistModel(
      id: 'gemma-3-1b-it-q4',
      name: 'Gemma 3 1B Instruct',
      description: 'Strongest per parameter; Google Gemma terms of use.',
      repository: 'ggml-org/gemma-3-1b-it-GGUF',
      file: 'gemma-3-1b-it-Q4_K_M.gguf',
      bytes: 806058240,
      licence: 'Gemma Terms of Use',
      parameters: '1B',
      minDeviceClass: DeviceClass.standard,
      runtimeMemoryLabel: '~1.3 GB RAM',
    ),
    AssistModel(
      id: 'llama-3.2-1b-instruct-q4',
      name: 'Llama 3.2 1B Instruct',
      description: 'Widely deployed on-device; Meta community licence.',
      repository: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
      file: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      bytes: 807694464,
      licence: 'Llama 3.2 Community License',
      parameters: '1B',
      minDeviceClass: DeviceClass.standard,
      runtimeMemoryLabel: '~1.3 GB RAM',
    ),
    AssistModel(
      id: 'smollm2-360m-instruct-q8',
      name: 'SmolLM2 360M Instruct',
      description: 'The smallest that still follows the rewrite task; for '
          'low-storage devices.',
      repository: 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
      file: 'smollm2-360m-instruct-q8_0.gguf',
      bytes: 386404992,
      licence: 'Apache 2.0',
      parameters: '360M',
      minDeviceClass: DeviceClass.entry,
      runtimeMemoryLabel: '~0.7 GB RAM',
    ),
    AssistModel(
      id: 'medgemma-4b-it-q4',
      name: 'MedGemma 4B Instruct',
      description: 'Trained on medical text, so its rewrites share the '
          'vocabulary of a clinical note. Reshaping only — it does not '
          'diagnose or answer questions. Large: needs a high-memory device.',
      repository: 'unsloth/medgemma-4b-it-GGUF',
      file: 'medgemma-4b-it-Q4_K_M.gguf',
      bytes: 2489894720,
      licence: 'Health AI Developer Foundations Terms',
      parameters: '4B',
      minDeviceClass: DeviceClass.ample,
      runtimeMemoryLabel: '~3 GB RAM',
    ),
  ];
}
