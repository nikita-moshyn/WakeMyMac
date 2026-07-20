// Copyright 2025 Nikita Moshyn
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArgumentParser
import Foundation

struct SettingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "View and customize WakeMyMac settings.",
        subcommands: [SettingsShow.self, SettingsInterval.self, SettingsPresets.self, SettingsClear.self]
    )

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

struct SettingsClear: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clear", abstract: "Stop active sessions and remove all WakeMyMac data.")

    @Flag(name: .shortAndLong, help: "Skip the destructive confirmation. Sessions are still stopped normally.")
    var force = false

    func run() throws {
        if !force, !askForConfirmation(DataRemovalCopy.warning) {
            cprint("Operation canceled. Sessions and saved data were not changed.")
            return
        }
        try DataRemovalManager.current.removeAllData()
        cprint("All WakeMyMac sessions were stopped and saved data was removed.", .success)
    }
}

struct SettingsShow: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show all WakeMyMac settings.")

    func run() throws {
        let settings = try SettingsManager.current.load()
        cprint("Inactivity interval: \(formatInactivityInterval(settings.inactivityInterval))")
        printPresets(settings.durationPresets)
    }
}

struct SettingsInterval: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interval",
        abstract: "Manage the delay before Always Active simulates input.",
        subcommands: [SettingsIntervalShow.self, SettingsIntervalSet.self, SettingsIntervalReset.self]
    )

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

struct SettingsIntervalShow: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show the current Inactivity interval.")

    func run() throws {
        let interval = try SettingsManager.current.load().inactivityInterval
        cprint("Inactivity interval: \(formatInactivityInterval(interval))")
    }
}

struct SettingsIntervalSet: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set the Inactivity interval.")

    @Argument(help: "Positive interval such as '3m45s' or '1h 30m 15s'. Quote values containing spaces.")
    var duration: String

    func run() throws {
        guard let interval = parseInactivityInterval(duration) else {
            throw ValidationError("Invalid interval '\(duration)'. Use a value such as '3m45s' or '1h 30m 15s'.")
        }
        try SettingsManager.current.setInactivityInterval(interval)
        cprint("Inactivity interval set to \(formatInactivityInterval(interval)). It will apply to the next Always Active session.", .success)
    }
}

struct SettingsIntervalReset: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reset", abstract: "Reset the Inactivity interval to four minutes.")

    func run() throws {
        try SettingsManager.current.resetInactivityInterval()
        cprint("Inactivity interval reset to 4m. It will apply to the next Always Active session.", .success)
    }
}

struct SettingsPresets: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "presets",
        abstract: "Manage named duration presets.",
        subcommands: [SettingsPresetsList.self, SettingsPresetsAdd.self, SettingsPresetsEdit.self, SettingsPresetsMove.self, SettingsPresetsRemove.self, SettingsPresetsReset.self]
    )

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

struct SettingsPresetsList: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List duration presets in picker order.")

    func run() throws {
        printPresets(try SettingsManager.current.load().durationPresets)
    }
}

struct SettingsPresetsAdd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a named duration preset.")

    @Argument(help: "Preset name. Quote names containing spaces.")
    var name: String

    @Argument(help: "Positive duration such as '8h' or '7h30m'.")
    var duration: String

    func run() throws {
        guard let interval = parseDuration(duration) else {
            throw ValidationError("Invalid duration '\(duration)'. Use a value such as '8h' or '7h30m'.")
        }
        try SettingsManager.current.addPreset(name: name, duration: interval)
        cprint("Duration preset '\(name)' added.", .success)
    }
}

struct SettingsPresetsEdit: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "Rename a preset, change its duration, or both.")

    @Argument(help: "Current preset name.")
    var currentName: String

    @Option(name: .customLong("name"), help: "Replacement preset name.")
    var newName: String?

    @Option(help: "Replacement duration.")
    var duration: String?

    func run() throws {
        let interval: TimeInterval?
        if let duration {
            guard let parsedDuration = parseDuration(duration) else {
                throw ValidationError("Invalid duration '\(duration)'. Use a value such as '8h' or '7h30m'.")
            }
            interval = parsedDuration
        } else {
            interval = nil
        }
        try SettingsManager.current.editPreset(named: currentName, newName: newName, duration: interval)
        cprint("Duration preset '\(currentName)' updated.", .success)
    }
}

struct SettingsPresetsMove: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "Move a preset to a 1-based picker position.")

    @Argument(help: "Preset name.")
    var name: String

    @Argument(help: "Destination position among timed presets.")
    var position: Int

    func run() throws {
        try SettingsManager.current.movePreset(named: name, to: position)
        cprint("Duration preset '\(name)' moved to position \(position).", .success)
    }
}

struct SettingsPresetsRemove: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a duration preset.")

    @Argument(help: "Preset name.")
    var name: String

    func run() throws {
        try SettingsManager.current.removePreset(named: name)
        cprint("Duration preset '\(name)' removed.", .success)
    }
}

struct SettingsPresetsReset: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reset", abstract: "Restore the default 1h through 8h presets.")

    @Flag(name: .shortAndLong, help: "Reset without confirmation.")
    var force = false

    func run() throws {
        if !force, !askForConfirmation("Replace all timed presets with the default 1h through 8h list?") {
            cprint("Operation canceled. Duration presets were not changed.")
            return
        }
        try SettingsManager.current.resetPresets()
        cprint("Duration presets reset to 1h through 8h.", .success)
    }
}

private func printPresets(_ presets: [WakeDurationPreset]) {
    cprint("Duration presets:")
    guard !presets.isEmpty else {
        cprint("  No timed presets configured.")
        return
    }
    for (index, preset) in presets.enumerated() {
        cprint("  \(index + 1). \(preset.name) — \(formatDuration(preset.duration))")
    }
}
