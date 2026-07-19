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

final class AlwaysActiveManager {
    static let current = AlwaysActiveManager(storage: AppServices.sessionStorage)

    private let storage: any SessionStorage

    init(storage: any SessionStorage) {
        self.storage = storage
    }

    func status() throws -> AlwaysActiveSession? {
        switch try statusResult() {
        case .active(let session):
            session
        case .inactive, .staleStateRemoved:
            nil
        }
    }

    func statusResult() throws -> AlwaysActiveStatusResult {
        guard let session = try storage.loadAlwaysActiveSession() else { return .inactive }
        guard processIsRunning(session.daemonID) else {
            try storage.deleteAlwaysActiveSession()
            return .staleStateRemoved
        }
        return .active(session)
    }

    func start(mode: AlwaysActiveMode, replacingActiveSession: Bool = false, force: Bool = false, debug: Bool = false, onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) throws {
        guard A11yService.isAccessibilityEnabled() else {
            throw AlwaysActiveManagerError.accessibilityPermissionRequired
        }

        if let session = try status() {
            guard replacingActiveSession else {
                throw AlwaysActiveManagerError.alreadyActive
            }

            let signal: Signal = force ? .kill : .terminate
            guard send(signal, session.daemonID) == .success else {
                throw AlwaysActiveManagerError.couldNotStopExistingSession
            }
            try storage.deleteAlwaysActiveSession()
        }

        let daemon = DmnService.createBackgroundDaemon()
        daemon.arguments = ["always-active-daemon", "--start", "--mode", mode.rawValue]

        do {
            let result = try SigService.waitForDaemonStartup {
                try daemon.run()
                dprint("Started daemon (PID \(daemon.processIdentifier)).", debug)

                let session = AlwaysActiveSession(daemonID: daemon.processIdentifier, mode: mode)
                try storage.saveAlwaysActiveSession(session)
            }
            guard result == .success else {
                throw AlwaysActiveManagerError.couldNotStart
            }
            onSuccess()
        } catch {
            if daemon.isRunning {
                daemon.terminate()
            }
            try? storage.deleteAlwaysActiveSession()
            onFailure()
            throw error
        }
    }

    func stop(force: Bool = false) throws -> AlwaysActiveStopResult {
        let session: AlwaysActiveSession
        switch try statusResult() {
        case .active(let activeSession):
            session = activeSession
        case .inactive:
            return .notRunning
        case .staleStateRemoved:
            return .staleStateRemoved
        }

        let signal: Signal = force ? .kill : .terminate
        guard send(signal, session.daemonID) == .success else {
            throw AlwaysActiveManagerError.couldNotStop
        }

        try storage.deleteAlwaysActiveSession()
        return .stopped
    }

}

enum AlwaysActiveStopResult {
    case stopped
    case notRunning
    case staleStateRemoved
}

enum AlwaysActiveStatusResult {
    case active(AlwaysActiveSession)
    case inactive
    case staleStateRemoved
}

enum AlwaysActiveManagerError: LocalizedError {
    case accessibilityPermissionRequired
    case alreadyActive
    case couldNotStart
    case couldNotStopExistingSession
    case couldNotStop

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Always Active requires Accessibility access for Terminal."
        case .alreadyActive:
            "An Always Active session is already active."
        case .couldNotStart:
            "Failed to start the Always Active daemon."
        case .couldNotStopExistingSession:
            "Failed to terminate the existing Always Active daemon."
        case .couldNotStop:
            "Failed to terminate the Always Active daemon."
        }
    }
}
