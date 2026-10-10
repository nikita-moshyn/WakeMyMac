// Copyright 2025 Nikita Moshyn
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

enum DataRemovalCopy {
    static let warning = "This stops all active sessions, permanently deletes the entire ~/.wake directory and legacy session data, and closes WakeMyMac. Continue?"
}

protocol DataRemovalWakeManaging {
    func stopForDataRemoval() throws
}

protocol DataRemovalAlwaysActiveManaging {
    func stopForDataRemoval() throws
}

extension WakeManager: DataRemovalWakeManaging {
    func stopForDataRemoval() throws {
        _ = try stop()
    }
}

extension AlwaysActiveManager: DataRemovalAlwaysActiveManaging {
    func stopForDataRemoval() throws {
        _ = try stop()
    }
}

final class DataRemovalManager {
    static let current = DataRemovalManager(wakeManager: WakeManager.current, alwaysActiveManager: AlwaysActiveManager.current, storage: AppServices.applicationDataStorage)

    private let wakeManager: any DataRemovalWakeManaging
    private let alwaysActiveManager: any DataRemovalAlwaysActiveManaging
    private let storage: any ApplicationDataStorage

    init(wakeManager: any DataRemovalWakeManaging, alwaysActiveManager: any DataRemovalAlwaysActiveManaging, storage: any ApplicationDataStorage) {
        self.wakeManager = wakeManager
        self.alwaysActiveManager = alwaysActiveManager
        self.storage = storage
    }

    func removeAllData() throws {
        var stopFailures = [String]()
        do {
            try wakeManager.stopForDataRemoval()
        } catch {
            stopFailures.append("Wake could not stop: \(error.localizedDescription)")
        }
        do {
            try alwaysActiveManager.stopForDataRemoval()
        } catch {
            stopFailures.append("Always Active could not stop: \(error.localizedDescription)")
        }
        guard stopFailures.isEmpty else {
            throw DataRemovalManagerError.couldNotStopSessions(stopFailures.joined(separator: " "))
        }

        do {
            try storage.removeAllData()
        } catch {
            throw DataRemovalManagerError.couldNotRemoveData(error.localizedDescription)
        }
    }
}

enum DataRemovalManagerError: LocalizedError {
    case couldNotStopSessions(String)
    case couldNotRemoveData(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStopSessions(let details):
            "Saved data was not removed because all sessions must stop first. \(details)"
        case .couldNotRemoveData(let details):
            "WakeMyMac could not remove its saved data: \(details)"
        }
    }
}
