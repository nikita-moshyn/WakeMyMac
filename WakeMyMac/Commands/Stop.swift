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

struct Stop: ParsableCommand {
    static var configuration = CommandConfiguration(abstract: "Stop the current wake session.")
    
    @Flag(name: .shortAndLong, help: "Send SIGKILL instead of SIGTERM to the wake daemon.")
    var force: Bool = false
    
    func run() throws {
        do {
            switch try WakeManager.current.stop(force: force) {
            case .stopped:
                cprint("Wake session successfully stopped.", .success)
            case .notRunning:
                cprint("No active wake session found.")
            }
        } catch {
            let suggestion = force ? "" : " Try 'wake stop --force'."
            cprint("\(error.localizedDescription)\(suggestion)", .error)
            throw ExitCode.failure
        }
    }
}
