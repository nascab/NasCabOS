import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "nascab.music.audio_session",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] (call, result) in
        self?.handleAudioSession(call: call, result: result)
      }
    }
    return result
  }

  private func handleAudioSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "activatePlayback":
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true, options: [])
        result(nil)
      } catch {
        result(FlutterError(code: "AUDIO_SESSION", message: error.localizedDescription, details: nil))
      }
    case "deactivatePlayback":
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        result(nil)
      } catch {
        result(FlutterError(code: "AUDIO_SESSION", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

}
