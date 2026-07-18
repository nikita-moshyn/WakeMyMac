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

    private func restoreSession() {
        do {
            session = try storage.loadWakeSession()
        } catch {
            session = nil
            logger.error("Failed to load session: \(error.localizedDescription)")
        }

        if session == nil {
            logger.info("Saved session is not detected.")
            dprint("Saved session is not detected")
        }
    }
    
    func sessionIsActive() -> Bool {
        let status = session != nil
        logger.info("Session status: \(status)")
        guard let daemonID = session?.deamonID else { return false }
        guard send(.isActive, daemonID) == .success else { return false }
        return status
    }
    
    func savedSessionExists() -> Bool {
        do {
            let exists = try storage.loadWakeSession() != nil
            logger.info("Saved session exists: \(exists)")
            return exists
        } catch {
            logger.error("Failed to check saved session: \(error.localizedDescription)")
            return false
        }
    }
    
    func saveSession(_ session: WakeSession) throws {
        logger.info("Attempting to save new session")

        try storage.saveWakeSession(session)
        self.session = session
    }
    
    func saveSession(_ daemonID: Int32, duration: TimeInterval?) {
        let session = WakeSession(deamonID: daemonID, duration: duration)
        try? saveSession(session)
    }
    
    private func deleteFileIfExists() {
        do {
            try storage.deleteWakeSession()
            logger.info("Session file was successfully removed")
        } catch {
            logger.error("Failed to delete session file: \(error.localizedDescription)")
        }
    }
    
    func releaseSession() {
        deleteFileIfExists()
        session = nil
    }
    
    /// Saves IOPMAssertionID to existing saved session
    /// Returns result as a bool
    @discardableResult
    func saveAssertion(id: IOPMAssertionID) -> Bool {
        guard var session else { return false }

        do {
            session.assertionID = id
            try saveSession(session)
            return true
        } catch {
            return false
        }
    }
}
