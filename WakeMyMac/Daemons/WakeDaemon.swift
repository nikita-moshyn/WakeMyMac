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
import Cocoa

final class WakeDaemon: WakeSessionManager, ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "wake-daemon",
                                                    abstract: "Daemon process to manage macOS sleep prevention session.", shouldDisplay: false)
    
    @Flag(help: "Start the wake session.")
    var start: Bool = false
    
    @Option(name: .shortAndLong, help: "Duration in seconds.")
    var duration: TimeInterval?
    
    private var assertionID: IOPMAssertionID = 0

    func run() throws {
        guard start else {
            cprint("Wake daemon was started without the required '--start' option.", .error)
            send(.failure)
            throw ExitCode.failure
        }
        try startWakeSession(duration: duration)
    }

    private func startWakeSession(duration: TimeInterval?) throws {
        let reason = Constants.assertionName.value as CFString
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason,
                                                 &assertionID)
        
        guard result == kIOReturnSuccess else {
            cprint("Failed to create the display-sleep assertion (IOKit error \(result)).", .error)
            send(.failure)
            throw ExitCode.failure
        }

        let session = WakeSession(daemonID: getpid(), assertionID: assertionID, duration: duration)
        do {
            try saveSession(session)
        } catch {
            IOPMAssertionRelease(assertionID)
            cprint("Failed to save wake session state: \(error.localizedDescription)", .error)
            send(.failure)
            throw ExitCode.failure
        }

        if let duration = duration {
            DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.stopWakeSession()
            }
        }
        
        // Send signal to parent process that Wake Daemon started successfully
        send(.success)
        // Hold the process
        RunLoop.main.run()
    }

    private func stopWakeSession() {
        IOPMAssertionRelease(assertionID)
        try? releaseSession()
        killSelf()
    }
}
