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
import OSLog

class WakeSessionManager {

    private let storage: any SessionStorage
    private var session: WakeSession?
    private var restorationError: Error?

    init() {
        self.storage = AppServices.sessionStorage
        restoreSession()
    }

    init(storage: any SessionStorage) {
        self.storage = storage
        restoreSession()
    }
    
    func getCurrentSession() -> WakeSession? {
        session
    }
    
    func refreshSession() {
        restoreSession()
    }

    func requireReadableSessionState() throws {
        guard let restorationError else { return }
        throw WakeSessionManagerError.couldNotReadState(restorationError)
    }

    private func restoreSession() {
        do {
            session = try storage.loadWakeSession()
            restorationError = nil
        } catch {
            session = nil
            restorationError = error
            logger.error("Failed to load session: \(error.localizedDescription)")
        }

        if session == nil {
            logger.info("Saved session is not detected.")
        }
    }
    
    func sessionIsActive() throws -> Bool {
        try requireReadableSessionState()
        guard let daemonID = session?.deamonID else { return false }
        return processIsRunning(daemonID)
    }
    
    func saveSession(_ session: WakeSession) throws {
        logger.info("Attempting to save new session")

        try storage.saveWakeSession(session)
        self.session = session
    }
    
    func releaseSession() throws {
        do {
            try storage.deleteWakeSession()
            logger.info("Session file was successfully removed")
        } catch {
            logger.error("Failed to delete session file: \(error.localizedDescription)")
            throw WakeSessionManagerError.couldNotUpdateState(error)
        }
        session = nil
    }
}

enum WakeSessionManagerError: LocalizedError {
    case couldNotReadState(Error)
    case couldNotUpdateState(Error)

    var errorDescription: String? {
        switch self {
        case .couldNotReadState(let error):
            "Failed to read saved session state: \(error.localizedDescription)"
        case .couldNotUpdateState(let error):
            "Failed to update saved session state: \(error.localizedDescription)"
        }
    }
}
