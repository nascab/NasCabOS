import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // 设置最小窗口尺寸
    self.minSize = NSSize(width: 800, height: 600)

    let binaryMessenger = flutterViewController.engine.binaryMessenger

    let macosFileAccessChannel = FlutterMethodChannel(
      name: "nascab/macos_file_access",
      binaryMessenger: binaryMessenger
    )
    let fileAccess = MacOSFileAccessManager()
    macosFileAccessChannel.setMethodCallHandler { call, result in
      fileAccess.handle(call: call, result: result)
    }

    let audioOutputChannel = FlutterMethodChannel(
      name: "nascab.macos.audio_output",
      binaryMessenger: binaryMessenger
    )
    audioOutputChannel.setMethodCallHandler { call, result in
      MacOSAudioOutputManager.handle(call: call, result: result)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// macOS 无 AVAudioSession；休眠蓝牙音箱需 Core Audio 有活跃输出流才会连接。
/// 播放期间保持极低音量循环静音，与 mdk 实际音频并行，避免仅短脉冲无法维持连接。
enum MacOSAudioOutputManager {
  private static let queue = DispatchQueue(
    label: "nascab.macos.audio_output",
    qos: .userInitiated
  )
  private static var wakeEngine: AVAudioEngine?
  private static var wakePlayer: AVAudioPlayerNode?

  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "activatePlayback":
      queue.async {
        let errorMessage = startKeepingOutputAlive()
        DispatchQueue.main.async {
          if let errorMessage {
            result(FlutterError(code: "AUDIO_OUTPUT", message: errorMessage, details: nil))
          } else {
            result(nil)
          }
        }
      }
    case "deactivatePlayback":
      queue.async {
        stopKeepingOutputAlive()
        DispatchQueue.main.async {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func startKeepingOutputAlive() -> String? {
    if let engine = wakeEngine, engine.isRunning {
      return nil
    }
    stopKeepingOutputAlive()

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)

    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
      return "Unable to create audio format"
    }
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 0.001

    do {
      engine.prepare()
      try engine.start()
    } catch {
      return error.localizedDescription
    }

    let frameCount = AVAudioFrameCount(format.sampleRate * 0.25)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      engine.stop()
      return "Unable to create audio buffer"
    }
    buffer.frameLength = frameCount
    player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
    player.play()

    wakeEngine = engine
    wakePlayer = player
    return nil
  }

  private static func stopKeepingOutputAlive() {
    wakePlayer?.stop()
    wakeEngine?.stop()
    wakePlayer = nil
    wakeEngine = nil
  }
}

final class MacOSFileAccessManager {
  private var nextHandle: Int = 1
  private var sessions: [Int: URL] = [:]

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(nil)
        return
      }

      let url = URL(fileURLWithPath: path)
      do {
        let data = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        result(data.base64EncodedString())
      } catch {
        result(nil)
      }
      return

    case "startAccessing":
      guard
        let args = call.arguments as? [String: Any],
        let bookmark = args["bookmark"] as? String,
        let bookmarkData = Data(base64Encoded: bookmark),
        !bookmarkData.isEmpty
      else {
        result(nil)
        return
      }

      var isStale = false
      do {
        let url = try URL(
          resolvingBookmarkData: bookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )

        guard url.startAccessingSecurityScopedResource() else {
          result(nil)
          return
        }

        let handle = nextHandle
        nextHandle += 1
        sessions[handle] = url

        var refreshedBookmark: String? = nil
        if isStale {
          if let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          ) {
            refreshedBookmark = refreshed.base64EncodedString()
          }
        }

        result([
          "handle": handle,
          "path": url.path,
          "bookmark": refreshedBookmark ?? "",
        ])
      } catch {
        result(nil)
      }
      return

    case "stopAccessing":
      guard
        let args = call.arguments as? [String: Any],
        let handleAny = args["handle"]
      else {
        result(nil)
        return
      }

      let handle: Int
      if let h = handleAny as? Int {
        handle = h
      } else if let s = handleAny as? String, let h = Int(s) {
        handle = h
      } else {
        result(nil)
        return
      }

      if let url = sessions.removeValue(forKey: handle) {
        url.stopAccessingSecurityScopedResource()
      }
      result(nil)
      return

    default:
      result(FlutterMethodNotImplemented)
      return
    }
  }
}
