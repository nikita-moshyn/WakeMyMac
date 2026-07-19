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
    static var configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the Always Active session.")

    private var storage: any SessionStorage = AppServices.sessionStorage

    @Flag(name: .shortAndLong, help: "Send SIGKILL instead of SIGTERM to the Always Active daemon.")
    var force: Bool = false

    private enum CodingKeys: String, CodingKey {
        case force
    }

    init() {}

    init(storage: any SessionStorage) {
        self.storage = storage
    }

    func run() throws {
        do {
            guard let session = try storage.loadAlwaysActiveSession() else {
                cprint("No active Always Active daemon found.")
                return
            }

            guard processIsRunning(session.daemonID) else {
                try storage.deleteAlwaysActiveSession()
                cprint("No active Always Active daemon found. Stale session state was removed.")
                return
            }

            let signal: Signal = force ? .kill : .terminate
            guard send(signal, session.daemonID) == .success else {
                let message = force
                    ? "Failed to forcefully terminate the Always Active daemon."
                    : "Failed to gracefully terminate the Always Active daemon. Use 'wake aa stop --force' to send SIGKILL."
                cprint(message, .error)
                throw ExitCode.failure
            }

            try storage.deleteAlwaysActiveSession()
            cprint("Always Active session successfully stopped.", .success)
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            cprint("Failed to stop Always Active session: \(error.localizedDescription)", .error)
            throw ExitCode.failure
        }
    }
}
