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

struct AlwaysActiveStop: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "stop", abstract: "Stop an Always Active session")

    private var storage: any SessionStorage = AppServices.sessionStorage

    @Flag(name: .shortAndLong, help: "Forcefully terminate the daemon if it cannot be stopped gracefully")
    var force: Bool = false

    private enum CodingKeys: String, CodingKey {
        case force
    }

    init() {}

    init(storage: any SessionStorage) {
        self.storage = storage
    }

    func run() throws {
        guard let session = try storage.loadAlwaysActiveSession() else {
            cprint("No Always Active session is currently running", .warning)
            return
        }
        printDebugDaemonStatus(session)
        
        let result: SignalResult
        if force {
            result = send(.kill, session.daemonID)
        } else {
            result = send(.terminate, session.daemonID)
        }
        
        guard result == .success else {
            cprint("Failed to stop the daemon. Use '--force' to terminate it", .error)
            return
        }
        try storage.deleteAlwaysActiveSession()
        cprint("Always Active session has been successfully stopped", .success)
    }
    
    private func printDebugDaemonStatus(_ session: AlwaysActiveSession) {
        let daemonIsActive = daemonIsActive(session: session)
        
        if daemonIsActive {
            dprint("Found active daemon with id: \(session.daemonID)")
        } else {
            dprint("No active daemon found")
        }
    }
    
    private func daemonIsActive(session: AlwaysActiveSession) -> Bool {
        kill(session.daemonID, 0) == 0
    }
}
