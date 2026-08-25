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

  String get sizeLabel => '${(bytes / (1024 * 1024)).round()} MB';
}

abstract final class AssistModelCatalog {
  /// In recommendation order.
  ///
  /// Qwen2.5 first: at this size class it follows rewrite instructions most
  /// reliably and its Apache-2.0 licence is the least encumbered. Gemma is
  /// the strongest per parameter but carries Google's use policy; Llama
  /// carries Meta's. SmolLM2 is the floor that still works, for devices where
  /// every hundred megabytes matters.
  static const List<AssistModel> models = <AssistModel>[
    AssistModel(
      id: 'qwen2.5-1.5b-instruct-q4',
      name: 'Qwen2.5 1.5B Instruct',
      description: 'Best rewrite accuracy of the small models tried; '
          'unencumbered licence.',
      repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      file: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      bytes: 1120000000,
      licence: 'Apache 2.0',
      parameters: '1.5B',
    ),
    AssistModel(
      id: 'gemma-3-1b-it-q4',
      name: 'Gemma 3 1B Instruct',
      description: 'Strongest per parameter; Google Gemma terms of use.',
      repository: 'ggml-org/gemma-3-1b-it-GGUF',
      file: 'gemma-3-1b-it-Q4_K_M.gguf',
      bytes: 806000000,
      licence: 'Gemma Terms of Use',
      parameters: '1B',
    ),
    AssistModel(
      id: 'llama-3.2-1b-instruct-q4',
      name: 'Llama 3.2 1B Instruct',
      description: 'Widely deployed on-device; Meta community licence.',
      repository: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
      file: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      bytes: 808000000,
      licence: 'Llama 3.2 Community License',
      parameters: '1B',
    ),
    AssistModel(
      id: 'smollm2-360m-instruct-q8',
      name: 'SmolLM2 360M Instruct',
      description: 'The smallest that still follows the rewrite task; for '
          'low-storage devices.',
      repository: 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
      file: 'smollm2-360m-instruct-q8_0.gguf',
      bytes: 386000000,
      licence: 'Apache 2.0',
      parameters: '360M',
    ),
  ];
}
