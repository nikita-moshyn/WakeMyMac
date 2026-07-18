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
import IOKit.pwr_mgt

final class WakeManager: WakeSessionManager {
    
    static let current = WakeManager(storage: AppServices.sessionStorage)
    
    override init(storage: any SessionStorage) {
        super.init(storage: storage)
    }
    
    /// Start function will override any existing
    func start(duration: TimeInterval? = nil, force: Bool = false) {
        // Stop any active sestion
        if sessionIsActive(), !force {
            logger.info("Attempting to start a new session while another session is active")
            cprint("A wake session is already active", .warning)
            if askForConfirmation("Do you want to overwrite the current session?") {
                logger.info("User chose to overwrite the active session.")
                dprint("Overwriting the current session")
                stop()
            } else {
                logger.info("User chose not to overwrite the active session.")
                dprint("Operation canceled by user.")
                return
            }
        } else if sessionIsActive(), force {
            stop()
        }
        
        startDeamon(duration: duration)
    }
    
    private func startDeamon(duration: TimeInterval?) {
        logger.info("Setting up daemon process.")
        
        setupSignalHandler()
        let daemon = Process()
        let executablePath: String
        if let bundlePath = Bundle.main.executablePath {
            executablePath = bundlePath
        } else {
            let rawPath = CommandLine.arguments[0]
            executablePath = URL(fileURLWithPath: rawPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardized.path
        }
        daemon.executableURL = URL(fileURLWithPath: executablePath)
        daemon.arguments = ["wake-daemon", "--start"]
        
        if let duration = duration {
            daemon.arguments?.append(contentsOf: ["--duration", "\(duration)"])
        }
        
        let pipe = Pipe()
        daemon.standardOutput = pipe
        
        do {
            try daemon.run()
#if DEBUG
            cprint("Daemon successfully started with PID: \(daemon.processIdentifier)", .success)
#endif
            saveSession(daemon.processIdentifier, duration: duration)
            
            RunLoop.main.run()
        } catch {
            cprint("Failed to start wake session: \(error)", .error )
        }
    }
    
    private func setupSignalHandler() {
        // Create signals
        let successSignal = DispatchSource.makeSignalSource(signal: Signal.success.rawValue, queue: .main)
        let failureSignal = DispatchSource.makeSignalSource(signal: Signal.failure.rawValue, queue: .main)
        
        // Ignore detault system behaviuor for signals
        signal(Signal.success.rawValue, SIG_IGN)
        signal(Signal.failure.rawValue, SIG_IGN)
        
        successSignal.setEventHandler {
            
            cprint("Wake session started successfully!", .success)
            
            successSignal.cancel()
            exit(0)
        }
        
        failureSignal.setEventHandler { [weak self] in
            guard let self else { return }
            
            cprint("Failed to start wake session.", .error)
            dprint("Killing deamon")
            
            failureSignal.cancel()
            releaseSession()
            exit(0)
        }

        successSignal.resume()
        failureSignal.resume()
    }
    
    
    func stop(force: Bool = false) {
        guard let session = getCurrentSession() else {
            logger.info("No active session to stop.")
            print("No active session to stop.")
            return
        }
        
        dprint("Daemon exists: \(kill(session.deamonID, 0) == 0)")
        
        if force {
            send(.kill, session.deamonID)
        } else {
            send(.terminate, session.deamonID)
        }
        releaseSession()
    }
    
    private func isDeamonRunning() -> Bool {
        guard let pid = getCurrentSession()?.deamonID else { return false }
        return kill(pid, 0) == 0
    }
    
    func status() -> (startTime: Date, remainingTime: TimeInterval?)? {
        guard let sessionData = getCurrentSession(), isDeamonRunning() else { return nil }
        if let duration = sessionData.duration {
            let elapsed = Date().timeIntervalSince(sessionData.startTime)
            return (sessionData.startTime, max(duration - elapsed, 0))
        }
        return (sessionData.startTime, nil)
    }
}
