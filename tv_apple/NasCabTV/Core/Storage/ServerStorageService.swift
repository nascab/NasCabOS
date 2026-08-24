import Foundation

final class ServerStorageService {
    static let shared = ServerStorageService()

    private let defaults = UserDefaults.standard
    private let serversKey = "saved_servers"
    private let lastSelectedKey = "last_selected_server"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Public API

    func loadServers() -> [ServerInfo] {
        guard let data = defaults.data(forKey: serversKey),
              var list = try? decoder.decode([ServerInfo].self, from: data) else {
            return []
        }
        for i in list.indices {
            list[i].isAutoScanned = false
        }
        return dedupeByUniqueKey(list)
    }

    @discardableResult
    func saveServers(_ servers: [ServerInfo]) -> Bool {
        let normalized = dedupeByUniqueKey(servers)
        guard let data = try? encoder.encode(normalized) else { return false }
        defaults.set(data, forKey: serversKey)
        return true
    }

    @discardableResult
    func addServer(_ server: ServerInfo) -> Bool {
        var current = loadServers()
        let key = server.uniqueKey
        if let idx = current.firstIndex(where: { $0.uniqueKey == key }) {
            current[idx] = ServerInfo.merged(current[idx], with: server)
        } else {
            current.append(server)
        }
        return saveServers(current)
    }

    @discardableResult
    func removeServer(_ server: ServerInfo) -> Bool {
        var current = loadServers()
        let key = server.uniqueKey
        current.removeAll { $0.uniqueKey == key }
        return saveServers(current)
    }

    @discardableResult
    func updateServer(_ server: ServerInfo) -> Bool {
        var current = loadServers()
        let key = server.uniqueKey
        guard let idx = current.firstIndex(where: { $0.uniqueKey == key }) else { return false }
        current[idx] = ServerInfo.merged(current[idx], with: server)
        return saveServers(current)
    }

    func serverExists(url: String) -> Bool {
        loadServers().contains { $0.serverUrl == url }
    }

    func getServerCount() -> Int {
        loadServers().count
    }

    @discardableResult
    func saveLastSelected(_ server: ServerInfo) -> Bool {
        guard let data = try? encoder.encode(server) else { return false }
        defaults.set(data, forKey: lastSelectedKey)
        return true
    }

    func getLastSelected() -> ServerInfo? {
        guard let data = defaults.data(forKey: lastSelectedKey) else { return nil }
        return try? decoder.decode(ServerInfo.self, from: data)
    }

    func clearAll() {
        defaults.removeObject(forKey: serversKey)
        defaults.removeObject(forKey: lastSelectedKey)
    }

    // MARK: - Private

    private func dedupeByUniqueKey(_ list: [ServerInfo]) -> [ServerInfo] {
        var byKey: [String: ServerInfo] = [:]
        var order: [String] = []
        for s in list {
            let key = s.uniqueKey
            if let existing = byKey[key] {
                byKey[key] = ServerInfo.merged(existing, with: s)
            } else {
                byKey[key] = s
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }
}
