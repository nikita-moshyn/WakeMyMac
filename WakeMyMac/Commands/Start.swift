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

struct Start: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Start a wake session.")
    
    @Argument(help: "Wake session duration (e.g., '30m', '1h', or '1h30m'). Omit for an indefinite session.")
    var duration: String?
    
    @Flag(name: .shortAndLong, help: "Terminate and replace an active wake session without confirmation.")
    var force: Bool = false
    
    func run() throws {
        guard let duration else {
            try startWakeSession()
            return
        }

        guard parseDuration(duration) != nil else {
            throw ValidationError("Invalid duration '\(duration)'. Use a value such as '30m', '1h', or '1h30m'.")
        }
        try startWakeSession()
    }

    private func startWakeSession() throws {
        do {
            try WakeManager.current.start(duration: duration.flatMap(parseDuration), force: force)
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            cprint(error.localizedDescription, .error)
            throw ExitCode.failure
        }
    }
}
