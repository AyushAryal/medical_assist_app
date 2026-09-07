import AVFoundation
import Flutter
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AppleVisionOcr.register(with: engineBridge.pluginRegistry)
    AppleFoundationModel.register(with: engineBridge.pluginRegistry)
    AppleSpeech.register(with: engineBridge.pluginRegistry)
  }
}

/// Reads text aloud with the system speech synthesiser.
///
/// Native, offline, no dependency — "read aloud" that actually speaks. The
/// synthesiser is held statically so it is not deallocated mid-utterance.
/// Forwards synthesiser start/stop to Dart so every "read aloud" control can
/// show whether speech is playing.
final class TtsStateRelay: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  init(channel: FlutterMethodChannel) { self.channel = channel }

  private func send(_ speaking: Bool) {
    channel.invokeMethod("state", arguments: ["speaking": speaking])
  }

  /// Releases the audio session so the app is not holding the audio route once
  /// nothing is being spoken.
  private func releaseAudio() {
    try? AVAudioSession.sharedInstance().setActive(
      false, options: [.notifyOthersOnDeactivation])
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
    send(true)
  }
  func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
    send(false)
    releaseAudio()
  }
  func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
    send(false)
    releaseAudio()
  }
}

enum AppleSpeech {
  static let channelName = "app.medical/tts"
  static let synthesizer = AVSpeechSynthesizer()
  static var relay: TtsStateRelay?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AppleSpeech") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    // Held statically so the delegate is not deallocated.
    relay = TtsStateRelay(channel: channel)
    synthesizer.delegate = relay
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "speak":
        guard
          let args = call.arguments as? [String: Any],
          let text = args["text"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "text is required", details: nil))
          return
        }
        let language = (args["language"] as? String) ?? "en-US"
        let voiceId = args["voiceId"] as? String
        try? AVAudioSession.sharedInstance().setCategory(
          .playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        // An explicitly chosen voice wins; otherwise the best installed one.
        utterance.voice =
          (voiceId.flatMap { AVSpeechSynthesisVoice(identifier: $0) })
          ?? bestVoice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        result(true)
      case "voices":
        // Every installed voice for the language, quality-first, so the app can
        // show what is actually on the device and let the user pick/preview.
        let language = (call.arguments as? [String: Any])?["language"] as? String
          ?? "en"
        let base = String(language.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices()
          .filter { $0.language.hasPrefix(base) }
          .sorted {
            $0.quality.rawValue != $1.quality.rawValue
              ? $0.quality.rawValue > $1.quality.rawValue
              : $0.name < $1.name
          }
          .map {
            [
              "id": $0.identifier,
              "name": $0.name,
              "language": $0.language,
              "quality": $0.quality.rawValue,
            ] as [String: Any]
          }
        result(voices)
      case "bestVoiceQuality":
        // 1 default, 2 enhanced, 3 premium — lets the app nudge the user to
        // download a better voice when only the robotic default is installed.
        let language = (call.arguments as? [String: Any])?["language"] as? String
          ?? "en-US"
        result(bestVoice(for: language)?.quality.rawValue ?? 0)
      case "stop":
        synthesizer.stopSpeaking(at: .immediate)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The most natural installed voice for a language: premium over enhanced
  /// over the compact default (which is the robotic one shipped by default).
  /// Prefers an exact language match, then any match on the base language.
  static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
    let base = String(language.prefix(2))
    let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language == language || $0.language.hasPrefix(base)
    }
    return candidates.max { a, b in
      if a.quality.rawValue != b.quality.rawValue {
        return a.quality.rawValue < b.quality.rawValue
      }
      // Tie-break: prefer the exact locale.
      return (a.language == language ? 1 : 0) < (b.language == language ? 1 : 0)
    }
  }
}

/// Native on-device text recognition, exposed to Flutter over a method channel.
///
/// Uses Apple's Vision framework (`VNRecognizeTextRequest`), which runs entirely
/// on the device — no network, no bundled model, nothing leaves the phone. On
/// Apple hardware this is the "native model" path; other platforms fall back to
/// the bundled ML Kit recogniser on the Dart side.
///
/// Defined here, in the same file as the AppDelegate, so it is part of the
/// Runner target's compile sources without an Xcode project edit.
enum AppleVisionOcr {
  static let channelName = "app.medical/ocr"

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AppleVisionOcr") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "recognize":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "path is required", details: nil))
          return
        }
        // Optional region of interest, normalised top-left (x, y, width, height).
        var roi: CGRect?
        if let r = args["region"] as? [String: Any],
          let x = (r["x"] as? NSNumber)?.doubleValue,
          let y = (r["y"] as? NSNumber)?.doubleValue,
          let w = (r["width"] as? NSNumber)?.doubleValue,
          let h = (r["height"] as? NSNumber)?.doubleValue {
          // Vision's ROI is normalised with a bottom-left origin, so flip y.
          roi = CGRect(x: x, y: 1 - y - h, width: w, height: h)
        }
        recognize(path: path, region: roi, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Always completes the Flutter result on the platform (main) thread — Vision
  /// calls back on a background queue, and a FlutterResult must not.
  private static func recognize(
    path: String, region: CGRect?, result: @escaping FlutterResult
  ) {
    func reply(_ value: Any?) {
      DispatchQueue.main.async { result(value) }
    }
    func fail(_ code: String, _ message: String) {
      DispatchQueue.main.async {
        result(FlutterError(code: code, message: message, details: nil))
      }
    }

    guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage
    else {
      fail("bad_image", "Could not load the image at \(path).")
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        fail("ocr_failed", error.localizedDescription)
        return
      }
      let observations =
        (request.results as? [VNRecognizedTextObservation]) ?? []
      // Each line with its box, normalised to the full image and flipped to a
      // top-left origin, so the Dart side can keep only the lines that fall
      // inside a freeform loop rather than its bounding rectangle.
      let lines: [[String: Any]] = observations.compactMap { obs in
        guard let text = obs.topCandidates(1).first?.string else { return nil }
        let b = obs.boundingBox
        return [
          "text": text,
          "x": b.origin.x,
          "y": 1 - b.origin.y - b.height,
          "w": b.width,
          "h": b.height,
        ]
      }
      let joined = lines.compactMap { $0["text"] as? String }
        .joined(separator: "\n")
      reply(["text": joined, "blocks": lines.count, "lines": lines])
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if let region = region {
      request.regionOfInterest = region
    }

    // Pass the photo's orientation, or Vision reads the raw (often sideways)
    // pixels while Flutter shows it upright — the region and the recognised
    // text would then come from the wrong part of the page.
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: cgOrientation(image.imageOrientation),
      options: [:]
    )
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        fail("ocr_failed", error.localizedDescription)
      }
    }
  }

  private static func cgOrientation(
    _ orientation: UIImage.Orientation
  ) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

/// The system on-device language model (Apple Intelligence, iOS 26+), exposed
/// over a method channel to the Foundation Models framework.
///
/// Guarded so it compiles on any SDK: `availability` reports "unavailable"
/// wherever the framework or the OS version is not there, and the Dart side
/// falls back to a downloaded model. Nothing here authors clinical data — it
/// only reshapes the text the app already built.
enum AppleFoundationModel {
  static let channelName = "app.medical/foundation_model"

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AppleFoundationModel")
    else { return }
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "availability":
        result(availabilityString())
      case "generate":
        guard
          let args = call.arguments as? [String: Any],
          let prompt = args["prompt"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "prompt is required", details: nil))
          return
        }
        generate(prompt: prompt, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func availabilityString() -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "available"
      default:
        return "unavailable"
      }
    }
    #endif
    return "unavailable"
  }

  static func generate(prompt: String, result: @escaping FlutterResult) {
    func reply(_ value: Any?) { DispatchQueue.main.async { result(value) } }
    func fail(_ code: String, _ message: String) {
      DispatchQueue.main.async {
        result(FlutterError(code: code, message: message, details: nil))
      }
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      Task {
        do {
          let session = LanguageModelSession()
          let response = try await session.respond(to: prompt)
          reply(response.content)
        } catch {
          fail("generate_failed", error.localizedDescription)
        }
      }
      return
    }
    #endif
    fail("unavailable", "Foundation Models is not available on this device.")
  }
}
