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
import ArgumentParser

final class WakeManager: WakeSessionManager {
    
    static let current = WakeManager(storage: AppServices.sessionStorage)
    
    override init(storage: any SessionStorage) {
        super.init(storage: storage)
    }
    
    func start(duration: TimeInterval? = nil, force: Bool = false, onSuccess: (() -> Void)? = nil, onFailure: (() -> Void)? = nil) throws {
        let active = try sessionIsActive()
        if active, !force {
            logger.info("Attempting to start a new session while another session is active")
            cprint("A wake session is already active.", .warning)
            guard askForConfirmation("Do you want to overwrite the current session?") else {
                logger.info("User chose not to overwrite the active session.")
                cprint("Operation canceled. Existing wake session remains active.")
                return
            }
        }

        if active {
            _ = try stop()
        } else if getCurrentSession() != nil {
            try releaseSession()
        }

        try startDaemon(duration: duration, onSuccess: onSuccess, onFailure: onFailure)
    }

    private func startDaemon(duration: TimeInterval?, onSuccess: (() -> Void)?, onFailure: (() -> Void)?) throws {
        logger.info("Setting up daemon process.")

        let daemon = DmnService.createBackgroundDaemon()
        daemon.arguments = ["wake-daemon", "--start"]

        if let duration = duration {
            daemon.arguments?.append(contentsOf: ["--duration", "\(duration)"])
        }

        switch try SigService.waitForDaemonStartup(starting: daemon.run) {
        case .success:
            if let onSuccess {
                onSuccess()
            } else if let duration {
                cprint("Wake session started successfully. Duration: \(formatDuration(duration)).", .success)
            } else {
                cprint("Wake session started successfully. Duration: indefinite.", .success)
            }
        case .failure:
            try? releaseSession()
            onFailure?()
            throw WakeManagerError.couldNotStart
        }
    }
    func stop(force: Bool = false) throws -> WakeStopResult {
        try requireReadableSessionState()
        guard let session = getCurrentSession() else {
            logger.info("No active session to stop.")
            return .notRunning
        }

        guard processIsRunning(session.daemonID) else {
            try releaseSession()
            return .notRunning
        }

        let signal: Signal = force ? .kill : .terminate
        guard send(signal, session.daemonID) == .success else {
            throw WakeManagerError.couldNotStop
        }

        try releaseSession()
        return .stopped
    }

    func status() throws -> (startTime: Date, remainingTime: TimeInterval?)? {
        try requireReadableSessionState()
        guard let sessionData = getCurrentSession() else { return nil }
        guard processIsRunning(sessionData.daemonID) else {
            try releaseSession()
            return nil
        }
        if let duration = sessionData.duration {
            let elapsed = Date().timeIntervalSince(sessionData.startTime)
            return (sessionData.startTime, max(duration - elapsed, 0))
        }
        return (sessionData.startTime, nil)
    }
}

enum WakeStopResult {
    case stopped
    case notRunning
}

enum WakeManagerError: LocalizedError {
    case couldNotStart
    case couldNotStop

    var errorDescription: String? {
        switch self {
        case .couldNotStart:
            "Failed to start the wake session daemon."
        case .couldNotStop:
            "Failed to terminate the wake session daemon."
        }
    }
}
