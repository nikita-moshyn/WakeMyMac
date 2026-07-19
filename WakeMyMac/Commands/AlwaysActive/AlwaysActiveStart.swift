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

    static var configuration = CommandConfiguration(commandName: "start", abstract: "Start an Always Active session.")

    private var manager = AlwaysActiveManager.current

    @Argument(help: "Activity mode: 'keyboard'/'k' or 'mouse'/'m'.")
    var mode: AlwaysActiveMode = .keyboard

    @Flag(name: .shortAndLong, help: "Force restart if already active.")
    var force: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable debug output.")
    var debug: Bool = false

    private enum CodingKeys: String, CodingKey {
        case mode
        case force
        case debug
    }

    init() {}

    init(storage: any SessionStorage) {
        manager = AlwaysActiveManager(storage: storage)
    }

    func run() throws {
        guard A11yService.isAccessibilityEnabled() else {
            try handleMissingAccessibilityPermission()
            return
        }

        do {
            let hasActiveSession = try manager.status() != nil
            var shouldReplaceActiveSession = force

            if hasActiveSession, !force {
                cprint("An Always Active session is already active.", .warning)
                guard askForConfirmation("Do you want to overwrite the current Always Active session?") else {
                    cprint("Operation canceled. Existing Always Active session remains active.")
                    return
                }
                shouldReplaceActiveSession = true
            }

            try manager.start(
                mode: mode,
                replacingActiveSession: shouldReplaceActiveSession,
                force: force,
                debug: debug,
                onSuccess: {
                    cprint("Always Active session started successfully.", .success)
                },
                onFailure: {}
            )
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            cprint(error.localizedDescription, .error)
            throw ExitCode.failure
        }
    }

    private func handleMissingAccessibilityPermission() throws {
        cprint("Always Active requires Accessibility access for Terminal.", .warning)
        guard askForConfirmation("Do you want to open Accessibility settings for Terminal?") else {
            cprint("Operation canceled. Always Active session was not started.")
            return
        }

        guard A11yService.openAccessibilitySettings() else {
            cprint("Failed to open Accessibility settings.", .error)
            throw ExitCode.failure
        }
        cprint("Enable Terminal under Privacy & Security > Accessibility, then run 'wake aa start' again.")
    }
}
