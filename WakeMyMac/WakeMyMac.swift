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
import Darwin


struct WakeMyMac: ParsableCommand {
    private static var availableSubcommands: [ParsableCommand.Type] {
        var subcommands: [ParsableCommand.Type] = [Start.self,
                                                    Stop.self,
                                                    Status.self,
                                                    WakeDaemon.self,
                                                    AlwaysActiveCommand.self,
                                                    AlwaysActiveDaemon.self]
#if DEBUG
        subcommands.append(AlwaysActiveTestCommand.self)
#endif
        return subcommands
    }

    static let configuration = CommandConfiguration(commandName: "wake",
                                                    abstract: "Prevent macOS display sleep with configurable, daemon-backed wake sessions.",
                                                    version: appVersion,
                                                    subcommands: availableSubcommands,
                                                    defaultSubcommand: nil)

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NO_TTY"] == nil,
              isatty(STDIN_FILENO) == 1,
              isatty(STDOUT_FILENO) == 1 else {
            throw CleanExit.helpRequest(self)
        }
        try WakeInteractiveUI().run()
    }
}
