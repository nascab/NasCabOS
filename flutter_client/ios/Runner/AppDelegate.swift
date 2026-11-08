import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioSessionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Flutter 3.35+ 的 UIScene 生命周期下，storyboard 里的 FlutterViewController 使用隐式引擎，
  // 插件与 App 级 MethodChannel 必须在这里注册，否则 Dart 侧调用会抛 MissingPluginException。
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "nascab.music.audio_session",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleAudioSession(call: call, result: result)
    }
    audioSessionChannel = channel
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
