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

import Foundation

final class SettingsManager {
    static let current = SettingsManager(storage: AppServices.settingsStorage)

    private static let reservedPresetNames = ["indefinite", "custom", "back"]
    private let storage: any SettingsStorage

    init(storage: any SettingsStorage) {
        self.storage = storage
    }

    func load() throws -> WakeSettings {
        let settings = try storage.loadSettings() ?? WakeSettings()
        try validate(settings)
        return settings
    }

    func setInactivityInterval(_ interval: TimeInterval) throws {
        guard inactivityIntervalIsValid(interval) else {
            throw SettingsManagerError.invalidInactivityInterval
        }
        var settings = try load()
        settings.inactivityInterval = interval
        try storage.saveSettings(settings)
    }

    func resetInactivityInterval() throws {
        var settings = (try? load()) ?? WakeSettings()
        settings.inactivityInterval = WakeSettings.defaultInactivityInterval
        try storage.saveSettings(settings)
    }

    func setDefaultAlwaysActiveMode(_ mode: AlwaysActiveMode) throws {
        var settings = try load()
        settings.defaultAlwaysActiveMode = mode
        try storage.saveSettings(settings)
    }

    func resetDefaultAlwaysActiveMode() throws {
        var settings = (try? load()) ?? WakeSettings()
        settings.defaultAlwaysActiveMode = WakeSettings.defaultAlwaysActiveMode
        try storage.saveSettings(settings)
    }

    func addPreset(name: String, duration: TimeInterval) throws {
        var settings = try load()
        let normalizedName = try validatedPresetName(name, excluding: nil, in: settings)
        try validateDuration(duration)
        settings.durationPresets.append(WakeDurationPreset(name: normalizedName, duration: duration))
        try storage.saveSettings(settings)
    }

    func editPreset(named currentName: String, newName: String?, duration: TimeInterval?) throws {
        var settings = try load()
        guard let index = presetIndex(named: currentName, in: settings) else {
            throw SettingsManagerError.presetNotFound(currentName)
        }
        guard newName != nil || duration != nil else {
            throw SettingsManagerError.noPresetChanges
        }
        if let newName {
            settings.durationPresets[index].name = try validatedPresetName(newName, excluding: settings.durationPresets[index].id, in: settings)
        }
        if let duration {
            try validateDuration(duration)
            settings.durationPresets[index].duration = duration
        }
        try storage.saveSettings(settings)
    }

    func movePreset(named name: String, to position: Int) throws {
        var settings = try load()
        guard let sourceIndex = presetIndex(named: name, in: settings) else {
            throw SettingsManagerError.presetNotFound(name)
        }
        guard (1 ... settings.durationPresets.count).contains(position) else {
            throw SettingsManagerError.invalidPresetPosition(maximum: settings.durationPresets.count)
        }
        let preset = settings.durationPresets.remove(at: sourceIndex)
        settings.durationPresets.insert(preset, at: position - 1)
        try storage.saveSettings(settings)
    }

    func movePreset(id: UUID, by offset: Int) throws {
        var settings = try load()
        guard let sourceIndex = settings.durationPresets.firstIndex(where: { $0.id == id }) else {
            throw SettingsManagerError.presetNotFound(id.uuidString)
        }
        let destinationIndex = min(max(sourceIndex + offset, 0), settings.durationPresets.count - 1)
        guard destinationIndex != sourceIndex else { return }
        let preset = settings.durationPresets.remove(at: sourceIndex)
        settings.durationPresets.insert(preset, at: destinationIndex)
        try storage.saveSettings(settings)
    }

    func removePreset(named name: String) throws {
        var settings = try load()
        guard let index = presetIndex(named: name, in: settings) else {
            throw SettingsManagerError.presetNotFound(name)
        }
        settings.durationPresets.remove(at: index)
        try storage.saveSettings(settings)
    }

    func removePreset(id: UUID) throws {
        var settings = try load()
        guard let index = settings.durationPresets.firstIndex(where: { $0.id == id }) else {
            throw SettingsManagerError.presetNotFound(id.uuidString)
        }
        settings.durationPresets.remove(at: index)
        try storage.saveSettings(settings)
    }

    func resetPresets() throws {
        var settings = (try? load()) ?? WakeSettings()
        settings.durationPresets = WakeSettings.defaultDurationPresets
        try storage.saveSettings(settings)
    }

    func preset(named name: String) throws -> WakeDurationPreset {
        let settings = try load()
        guard let index = presetIndex(named: name, in: settings) else {
            throw SettingsManagerError.presetNotFound(name)
        }
        return settings.durationPresets[index]
    }

    private func presetIndex(named name: String, in settings: WakeSettings) -> Int? {
        let lookupName = normalizedLookupName(name)
        return settings.durationPresets.firstIndex { normalizedLookupName($0.name) == lookupName }
    }

    private func validatedPresetName(_ name: String, excluding excludedID: UUID?, in settings: WakeSettings) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 40, !trimmedName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SettingsManagerError.invalidPresetName
        }
        let lookupName = normalizedLookupName(trimmedName)
        guard !Self.reservedPresetNames.contains(lookupName) else {
            throw SettingsManagerError.reservedPresetName(trimmedName)
        }
        guard !settings.durationPresets.contains(where: { $0.id != excludedID && normalizedLookupName($0.name) == lookupName }) else {
            throw SettingsManagerError.duplicatePresetName(trimmedName)
        }
        return trimmedName
    }

    private func normalizedLookupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func validateDuration(_ duration: TimeInterval) throws {
        guard duration.isFinite, duration > 0 else {
            throw SettingsManagerError.invalidPresetDuration
        }
    }

    private func validate(_ settings: WakeSettings) throws {
        guard inactivityIntervalIsValid(settings.inactivityInterval) else {
            throw SettingsManagerError.invalidConfiguration
        }
        var seenNames = Set<String>()
        for preset in settings.durationPresets {
            guard preset.duration.isFinite, preset.duration > 0 else {
                throw SettingsManagerError.invalidConfiguration
            }
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lookupName = normalizedLookupName(trimmedName)
            guard !trimmedName.isEmpty,
                  trimmedName.count <= 40,
                  !trimmedName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !Self.reservedPresetNames.contains(lookupName),
                  seenNames.insert(lookupName).inserted else {
                throw SettingsManagerError.invalidConfiguration
            }
        }
    }
}

enum SettingsManagerError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidInactivityInterval
    case invalidPresetName
    case invalidPresetDuration
    case reservedPresetName(String)
    case duplicatePresetName(String)
    case presetNotFound(String)
    case invalidPresetPosition(maximum: Int)
    case noPresetChanges

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "WakeMyMac settings are invalid. Reset the affected setting to restore its default."
        case .invalidInactivityInterval:
            "The Inactivity interval must be at least one second."
        case .invalidPresetName:
            "Preset names must contain 1 to 40 characters and cannot contain control characters."
        case .invalidPresetDuration:
            "Preset duration must be greater than zero."
        case .reservedPresetName(let name):
            "'\(name)' is reserved by the duration picker."
        case .duplicatePresetName(let name):
            "A duration preset named '\(name)' already exists."
        case .presetNotFound(let name):
            "No duration preset named '\(name)' was found."
        case .invalidPresetPosition(let maximum):
            "Preset position must be between 1 and \(maximum)."
        case .noPresetChanges:
            "Provide a new name, a new duration, or both."
        }
    }
}
