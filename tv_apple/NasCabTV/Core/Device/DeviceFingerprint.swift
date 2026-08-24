import Foundation

/// 设备指纹：用于登录时传给服务端，使已信任设备可免 2FA 验证。
/// 与服务端 auth 的 device_fingerprint 格式一致（storage_id 必填，用于识别同一设备）。
enum DeviceFingerprint {
    private static let storageIdKey = "nascab_device_fingerprint_storage_id"
    private static let videoDeviceIdKey = "nascab_video_player_device_id"

    /// 获取或生成持久化 storage_id（同一设备保持不变）
    static func getOrCreateStorageId() -> String {
        if let existing = UserDefaults.standard.string(forKey: storageIdKey),
           !existing.trimmingCharacters(in: .whitespaces).isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: storageIdKey)
        return newId
    }

    static func getOrCreateVideoPlayerDeviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: videoDeviceIdKey),
           !existing.trimmingCharacters(in: .whitespaces).isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: videoDeviceIdKey)
        return newId
    }

    /// 构建登录 / 2FA 验证时需传的 device_fingerprint 字典（与 Flutter/服务端 _normalizeDeviceFingerprint 对齐）
    static func getDeviceFingerprintPayload() -> [String: Any] {
        let locale = Locale.current
        let language = locale.language.languageCode?.identifier ?? ""
        let now = Date()
        let tz = TimeZone.current
        let timezoneOffset = tz.secondsFromGMT(for: now) / 60
        let timezoneName = tz.identifier

        #if os(tvOS)
        let platform = "tvOS"
        let deviceName = "Apple TV"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = "Apple TV"
        #else
        let platform = "iOS"
        let deviceName = UIDevice.current.name
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        #endif

        return [
            "user_agent": "NasCabOS TV/\(platform)",
            "platform": platform,
            "os_version": osVersion,
            "device_model": deviceModel,
            "device_name": deviceName,
            "language": language,
            "timezone_offset": timezoneOffset,
            "timezone_name": timezoneName,
            "storage_id": getOrCreateStorageId(),
            "storage_type": "UserDefaults",
        ]
    }
}
