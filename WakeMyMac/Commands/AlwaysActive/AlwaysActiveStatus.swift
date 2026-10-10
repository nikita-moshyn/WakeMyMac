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

struct AlwaysActiveStatus: ParsableCommand {
    static var configuration = CommandConfiguration(commandName: "status", abstract: "Check the status of the Always Active session.")

    private var manager = AlwaysActiveManager.current

    @Flag(name: .shortAndLong, help: "Print the active daemon PID.")
    var debug: Bool = false

    private enum CodingKeys: String, CodingKey {
        case debug
    }

    init() {}

    init(storage: any SessionStorage) {
        manager = AlwaysActiveManager(storage: storage)
    }

    func run() throws {
        do {
            switch try manager.statusResult() {
            case .inactive:
                cprint("Always Active is inactive.")
            case .staleStateRemoved:
                cprint("Always Active is inactive. Stale session state was removed.")
            case .active(let session):
                cprint("Always Active session is active in \(session.mode.rawValue) mode.", .success)
                let status = SessionStatus(session: session)
                if let remainingTime = status?.remainingTime {
                    cprint("Time remaining: \(formatDuration(remainingTime))")
                } else {
                    cprint("Session duration: indefinite.")
                }
                cprint("Inactivity interval: \(formatInactivityInterval(session.inactivityInterval))")
                dprint("Daemon ID: \(session.daemonID)", debug)
            }
        } catch {
            cprint("Failed to check Always Active status: \(error.localizedDescription)", .error)
            throw ExitCode.failure
        }
    }
}
