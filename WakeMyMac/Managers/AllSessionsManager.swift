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

protocol CombinedWakeManaging {
    func combinedIsActive() throws -> Bool
    func startCombined(duration: TimeInterval?) throws
}

protocol CombinedAlwaysActiveManaging {
    func combinedIsActive() throws -> Bool
    func startCombined(mode: AlwaysActiveMode, duration: TimeInterval?, inactivityInterval: TimeInterval, replacingActiveSession: Bool, force: Bool) throws
    func stopCombined(force: Bool) throws
}

extension WakeManager: CombinedWakeManaging {
    func combinedIsActive() throws -> Bool {
        try status() != nil
    }

    func startCombined(duration: TimeInterval?) throws {
        try start(duration: duration, force: true, onSuccess: {}, onFailure: {})
    }
}

extension AlwaysActiveManager: CombinedAlwaysActiveManaging {
    func combinedIsActive() throws -> Bool {
        try status() != nil
    }

    func startCombined(mode: AlwaysActiveMode, duration: TimeInterval?, inactivityInterval: TimeInterval, replacingActiveSession: Bool, force: Bool) throws {
        try start(mode: mode, duration: duration, inactivityInterval: inactivityInterval, replacingActiveSession: replacingActiveSession, force: force, onSuccess: {}, onFailure: {})
    }

    func stopCombined(force: Bool) throws {
        _ = try stop(force: force)
    }
}

final class AllSessionsManager {
    static let current = AllSessionsManager(wakeManager: WakeManager.current, alwaysActiveManager: AlwaysActiveManager.current)

    private let wakeManager: any CombinedWakeManaging
    private let alwaysActiveManager: any CombinedAlwaysActiveManaging

    init(wakeManager: any CombinedWakeManaging, alwaysActiveManager: any CombinedAlwaysActiveManaging) {
        self.wakeManager = wakeManager
        self.alwaysActiveManager = alwaysActiveManager
    }

    func hasActiveSessions() throws -> Bool {
        try wakeManager.combinedIsActive() || alwaysActiveManager.combinedIsActive()
    }

    func start(duration: TimeInterval?, mode: AlwaysActiveMode, inactivityInterval: TimeInterval, replacingActiveSessions: Bool, force: Bool = false, onSuccess: (() -> Void)? = nil) throws {
        let wakeIsActive = try wakeManager.combinedIsActive()
        let alwaysActiveIsActive = try alwaysActiveManager.combinedIsActive()
        guard replacingActiveSessions || (!wakeIsActive && !alwaysActiveIsActive) else {
            throw AllSessionsManagerError.alreadyActive
        }

        try alwaysActiveManager.startCombined(mode: mode, duration: duration, inactivityInterval: inactivityInterval, replacingActiveSession: alwaysActiveIsActive, force: force)

        do {
            try wakeManager.startCombined(duration: duration)
        } catch {
            do {
                try alwaysActiveManager.stopCombined(force: force)
            } catch let rollbackError {
                throw AllSessionsManagerError.rollbackFailed(startError: error.localizedDescription, rollbackError: rollbackError.localizedDescription)
            }
            throw error
        }
        onSuccess?()
    }
}

enum AllSessionsManagerError: LocalizedError {
    case alreadyActive
    case rollbackFailed(startError: String, rollbackError: String)

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "A Wake or Always Active session is already active."
        case .rollbackFailed(let startError, let rollbackError):
            "Wake could not start (\(startError)), and the new Always Active session could not be rolled back (\(rollbackError)). Stop it manually before retrying."
        }
    }
}
