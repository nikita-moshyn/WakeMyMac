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

    @Option(help: "Named duration preset. Cannot be combined with a duration argument.")
    var preset: String?

    @Flag(name: [.customShort("a"), .customLong("all")], help: "Start Wake and Always Active together.")
    var startAll = false

    @Option(help: "Always Active mode when using --all. Omit to use the configured default.")
    var mode: AlwaysActiveMode?
    
    @Flag(name: .shortAndLong, help: "Replace active sessions without confirmation.")
    var force: Bool = false
    
    func run() throws {
        guard startAll || mode == nil else {
            throw ValidationError("--mode can only be used with --all.")
        }
        let selectedDuration = try resolveDuration()

        if startAll {
            try startAllSessions(duration: selectedDuration)
        } else {
            try startWakeSession(duration: selectedDuration)
        }
    }

    private func resolveDuration() throws -> TimeInterval? {
        guard duration == nil || preset == nil else {
            throw ValidationError("Use either a duration argument or --preset, not both.")
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

    private func startWakeSession(duration: TimeInterval?) throws {
        do {
            try WakeManager.current.start(duration: duration, force: force)
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            cprint(error.localizedDescription, .error)
            throw ExitCode.failure
        }
    }

    private func startAllSessions(duration: TimeInterval?) throws {
        guard A11yService.isAccessibilityEnabled() else {
            cprint("Starting all sessions requires Accessibility access for Terminal.", .warning)
            guard askForConfirmation("Do you want to open Accessibility settings for Terminal?") else {
                cprint("Operation canceled. No sessions were changed.")
                return
            }
            guard A11yService.openAccessibilitySettings() else {
                cprint("Failed to open Accessibility settings.", .error)
                throw ExitCode.failure
            }
            cprint("Enable Terminal under Privacy & Security > Accessibility, then run the command again.")
            return
        }

        do {
            let settings = try SettingsManager.current.load()
            let selectedMode = resolveAlwaysActiveMode(mode, settings: settings)
            let hasActiveSessions = try AllSessionsManager.current.hasActiveSessions()
            var shouldReplace = force
            if hasActiveSessions, !force {
                cprint("A Wake or Always Active session is already active.", .warning)
                guard askForConfirmation("Do you want to replace active sessions and start both?") else {
                    cprint("Operation canceled. Existing sessions remain active.")
                    return
                }
                shouldReplace = true
            }
            try AllSessionsManager.current.start(
                duration: duration,
                mode: selectedMode,
                inactivityInterval: settings.inactivityInterval,
                replacingActiveSessions: shouldReplace,
                force: force
            )
            let durationDescription = duration.map(formatDuration) ?? "indefinite"
            cprint("Wake and Always Active started successfully. Duration: \(durationDescription). Always Active mode: \(selectedMode.rawValue).", .success)
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            cprint(error.localizedDescription, .error)
            throw ExitCode.failure
        }
    }
}
