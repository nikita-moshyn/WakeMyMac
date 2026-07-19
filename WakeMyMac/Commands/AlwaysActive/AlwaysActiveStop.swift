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

    private var manager = AlwaysActiveManager.current

    @Flag(name: .shortAndLong, help: "Send SIGKILL instead of SIGTERM to the Always Active daemon.")
    var force: Bool = false

    private enum CodingKeys: String, CodingKey {
        case force
    }

    init() {}

    init(storage: any SessionStorage) {
        manager = AlwaysActiveManager(storage: storage)
    }

    func run() throws {
        do {
            switch try manager.stop(force: force) {
            case .stopped:
                cprint("Always Active session successfully stopped.", .success)
            case .notRunning:
                cprint("No active Always Active daemon found.")
            case .staleStateRemoved:
                cprint("No active Always Active daemon found. Stale session state was removed.")
            }
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            let suggestion = force ? "" : " Try 'wake aa stop --force'."
            cprint("Failed to stop Always Active session: \(error.localizedDescription)\(suggestion)", .error)
            throw ExitCode.failure
        }
    }
}
