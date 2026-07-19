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
import Cocoa

final class AlwaysActiveDaemon: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "always-active-daemon", abstract: "Daemon process for the Always Active session.", shouldDisplay: false, aliases: ["alwaysActive-wake-daemon"])

    @Flag(help: "Start the always active session.")
    var start: Bool = false

    @Option(help: "Activity mode to use for the always active session.")
    var mode: AlwaysActiveMode = .keyboard

    required init() {}

    func run() throws {
        guard start else {
            cprint("Always Active daemon was started without the required '--start' option.", .error)
            send(.failure)
            throw ExitCode.failure
        }
        guard A11yService.isAccessibilityEnabled() else {
            cprint("Terminal does not have Accessibility access required by the Always Active daemon.", .error)
            send(.failure)
            throw ExitCode.failure
        }

        let didStartActivity = switch mode {
        case .keyboard:
            KEService.startActivity()
        case .mouse:
            MEService.startActivity()
        }
        guard didStartActivity else {
            cprint("Failed to create the activity event tap. Verify Terminal Accessibility access.", .error)
            send(.failure)
            throw ExitCode.failure
        }

        send(.success)
        RunLoop.main.run()
    }
}
