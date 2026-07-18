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

struct AlwaysActiveStart: ParsableCommand {

    static var configuration = CommandConfiguration(commandName: "start", abstract: "Start an always active session.")

    private var storage: any SessionStorage = AppServices.sessionStorage

    @Flag(name: .shortAndLong, help: "Force start if another session is active.")
    var force: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable debug mode for additional logging")
    var debug: Bool = false

    private enum CodingKeys: String, CodingKey {
        case force
        case debug
    }

    init() {}

    init(storage: any SessionStorage) {
        self.storage = storage
    }

    func run() throws {
        if !A11yService.isAccessibilityEnabled() {
            cprint("Always Active requires accessibility access to function correctly", .warning)
            if askForConfirmation("Do you want to open Accessibility settings?") {
                A11yService.openAccessibilitySettings()
            }
        } else {
            startAlwaysActiveDeamon()
        }
    }
    
    private func startAlwaysActiveDeamon() {
        setupSignalHandler()
        
        let daemon = DmnService.createBackgroundDaemon()
        daemon.arguments = ["alwaysActive-wake-daemon", "--start"]
        
        do {
            try daemon.run()
            
            dprint("Daemon started with PID: \(daemon.processIdentifier)", debug)
        
            let session = AlwaysActiveSession(daemonID: daemon.processIdentifier)
            try storage.saveAlwaysActiveSession(session)
            
            RunLoop.main.run()
        } catch {
            cprint("Failed to start Always Active session: \(error.localizedDescription)", .error)
        }
    }
    
    private func setupSignalHandler() {
        SigService.setupSignalHandler {
            cprint("Always active session started successfully!", .success)
            killSelf()
        } _: {
            cprint("Failed to start Always Active session.", .error)
            dprint("Attempting to terminate daemon and clean session", debug)

            do {
                try storage.deleteAlwaysActiveSession()
            } catch {
                dprint("Failed to clean session storage: \(error.localizedDescription)", debug)
            }
            killSelf()
        }
    }
}
