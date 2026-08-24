import Foundation

enum NetworkConfig {
    static let signalApiBaseUrl = "https://nas.cab"
    static let p2pBaseUrl = "http://p2p.local"
    static let localhostBaseUrl = "http://127.0.0.1:9000"
    static let defaultTimeout: TimeInterval = 10
    static let defaultMaxRetries = 2
    static let defaultRetryDelay: TimeInterval = 0.5
    static let tokenRefreshInterval: TimeInterval = 60
    static let tokenExpiryThreshold: TimeInterval = 300
}
