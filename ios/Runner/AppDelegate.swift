import Flutter
import UIKit
import Vision

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
        recognize(path: path, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Always completes the Flutter result on the platform (main) thread — Vision
  /// calls back on a background queue, and a FlutterResult must not.
  private static func recognize(path: String, result: @escaping FlutterResult) {
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
      let lines = observations.compactMap {
        $0.topCandidates(1).first?.string
      }
      reply(["text": lines.joined(separator: "\n"), "blocks": lines.count])
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        fail("ocr_failed", error.localizedDescription)
      }
    }
  }
}
