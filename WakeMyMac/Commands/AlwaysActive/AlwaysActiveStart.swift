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

    @Argument(help: "Activity mode: 'keyboard'/'k' or 'mouse'/'m'. Omit to use the configured default.")
    var mode: AlwaysActiveMode?

    @Option(help: "Session duration (e.g. '30m' or '8h'). Omit for an indefinite session.")
    var duration: String?

    @Option(help: "Named duration preset. Cannot be combined with --duration.")
    var preset: String?

    @Flag(name: .shortAndLong, help: "Force restart if already active.")
    var force: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable debug output.")
    var debug: Bool = false

    private enum CodingKeys: String, CodingKey {
        case mode
        case duration
        case preset
        case force
        case debug
    }

    init() {}

    init(storage: any SessionStorage) {
        manager = AlwaysActiveManager(storage: storage)
    }

    func run() throws {
        let selectedDuration = try resolveDuration()
        let settings = try SettingsManager.current.load()
        let selectedMode = resolveAlwaysActiveMode(mode, settings: settings)

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
                mode: selectedMode,
                duration: selectedDuration,
                inactivityInterval: settings.inactivityInterval,
                replacingActiveSession: shouldReplaceActiveSession,
                force: force,
                debug: debug,
                onSuccess: {
                    let durationDescription = selectedDuration.map(formatDuration) ?? "indefinite"
                    cprint("Always Active session started successfully. Duration: \(durationDescription). Mode: \(selectedMode.rawValue). Inactivity interval: \(formatInactivityInterval(settings.inactivityInterval)).", .success)
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

    private func resolveDuration() throws -> TimeInterval? {
        guard duration == nil || preset == nil else {
            throw ValidationError("Use either --duration or --preset, not both.")
        }
        if let duration {
            guard let parsedDuration = parseDuration(duration) else {
                throw ValidationError("Invalid duration '\(duration)'. Use a value such as '30m', '1h', or '1h30m'.")
            }
            return parsedDuration
        }
        if let preset {
            return try SettingsManager.current.preset(named: preset).duration
        }
        return nil
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
