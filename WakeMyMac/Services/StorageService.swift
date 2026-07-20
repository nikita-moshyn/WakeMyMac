// Copyright 2025 Nikita Moshyn
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

final class FileSessionStorage: SessionStorage, SettingsStorage, ApplicationDataStorage {
    static let shared = FileSessionStorage()

    private let folderName = ".wake"
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let queue = DispatchQueue(label: "com.wakeCLI.fileSessionStorage", attributes: .concurrent)

    private var storageDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(folderName)
    }

    private var legacyWakeSessionURL: URL {
        homeDirectoryURL.appendingPathComponent(Constants.wakeSession.rawValue)
    }

    init(fileManager: FileManager = .default, homeDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
    }

    func loadWakeSession() throws -> WakeSession? {
        if let session = try loadFile(.wakeSession, as: WakeSession.self) {
            return session
        }

        return try migrateLegacyWakeSession()
    }

    func saveWakeSession(_ session: WakeSession) throws {
        try saveFile(session, to: .wakeSession)
    }

    func deleteWakeSession() throws {
        try deleteFile(.wakeSession)
    }

    func loadAlwaysActiveSession() throws -> AlwaysActiveSession? {
        try loadFile(.alwaysActiveSession, as: AlwaysActiveSession.self)
    }

    func saveAlwaysActiveSession(_ session: AlwaysActiveSession) throws {
        try saveFile(session, to: .alwaysActiveSession)
    }

    func deleteAlwaysActiveSession() throws {
        try deleteFile(.alwaysActiveSession)
    }

    func loadSettings() throws -> WakeSettings? {
        try loadFile(.settings, as: WakeSettings.self)
    }

    func saveSettings(_ settings: WakeSettings) throws {
        try saveFile(settings, to: .settings)
    }

    func deleteSettings() throws {
        try deleteFile(.settings)
    }

    func removeAllData() throws {
        try queue.sync(flags: .barrier) {
            if fileManager.fileExists(atPath: storageDirectoryURL.path) {
                try fileManager.removeItem(at: storageDirectoryURL)
            }
            if fileManager.fileExists(atPath: legacyWakeSessionURL.path) {
                try fileManager.removeItem(at: legacyWakeSessionURL)
            }
        }
    }

    private func saveFile<Value: Encodable>(_ value: Value, to file: SessionFile) throws {
        try queue.sync(flags: .barrier) {
            try ensureStorageDirectoryExists()
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL(for: file), options: .atomic)
        }
    }

    private func loadFile<Value: Decodable>(_ file: SessionFile, as type: Value.Type) throws -> Value? {
        try queue.sync {
            let url = fileURL(for: file)
            guard fileManager.fileExists(atPath: url.path) else { return nil }

            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        }
    }

    private func deleteFile(_ file: SessionFile) throws {
        try queue.sync(flags: .barrier) {
            let url = fileURL(for: file)
            guard fileManager.fileExists(atPath: url.path) else { return }

            try fileManager.removeItem(at: url)
            try removeStorageDirectoryIfEmpty()
        }
    }

    private func fileURL(for file: SessionFile) -> URL {
        storageDirectoryURL.appendingPathComponent(file.fileName)
    }

    private func ensureStorageDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: storageDirectoryURL.path) else { return }

        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
    }

    private func removeStorageDirectoryIfEmpty() throws {
        let files = try fileManager.contentsOfDirectory(atPath: storageDirectoryURL.path)
        guard files.isEmpty else { return }
        try fileManager.removeItem(at: storageDirectoryURL)
    }

    private func migrateLegacyWakeSession() throws -> WakeSession? {
        guard fileManager.fileExists(atPath: legacyWakeSessionURL.path) else { return nil }

        let data = try Data(contentsOf: legacyWakeSessionURL)
        let session = try JSONDecoder().decode(WakeSession.self, from: data)
        try saveWakeSession(session)
        try? fileManager.removeItem(at: legacyWakeSessionURL)
        return session
    }
}

private enum SessionFile {
    case wakeSession
    case alwaysActiveSession
    case settings

    var fileName: String {
        switch self {
        case .wakeSession:
            Constants.wakeSession.rawValue
        case .alwaysActiveSession:
            Constants.alwaysActiveSession.rawValue
        case .settings:
            Constants.wakeConfig.rawValue
        }
    }
}
