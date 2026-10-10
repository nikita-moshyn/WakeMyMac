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

import XCTest
@testable import WakeMyMac

final class SettingsManagerTests: XCTestCase {
    func testMissingSettingsUseFourMinuteIntervalAndReducedDefaults() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())

        let settings = try manager.load()

        XCTAssertEqual(settings.inactivityInterval, 4 * 60)
        XCTAssertEqual(settings.defaultAlwaysActiveMode, .keyboard)
        XCTAssertEqual(settings.defaultSessionDuration, .interactive)
        XCTAssertEqual(settings.defaultAlwaysActiveDuration, .interactive)
        XCTAssertFalse(settings.confirmBeforeStopping)
        XCTAssertFalse(settings.showSessionChangeControls)
        XCTAssertEqual(settings.durationPresets.map(\.name), ["1h", "4h", "8h"])
        XCTAssertEqual(settings.durationPresets.map(\.duration), [1, 4, 8].map { TimeInterval($0 * 60 * 60) })
    }

    func testPresetCRUDAndOrderingPersist() throws {
        let storage = InMemorySettingsStorage()
        let manager = SettingsManager(storage: storage)

        try manager.addPreset(name: "Workday", duration: 7.5 * 60 * 60)
        try manager.editPreset(named: "workDAY", newName: "Office day", duration: 8 * 60 * 60)
        try manager.movePreset(named: "Office day", to: 1)

        var settings = try manager.load()
        XCTAssertEqual(settings.durationPresets.first?.name, "Office day")
        XCTAssertEqual(settings.durationPresets.first?.duration, 8 * 60 * 60)
        XCTAssertEqual(try manager.preset(named: "OFFICE DAY").name, "Office day")

        try manager.removePreset(named: "office day")
        settings = try manager.load()
        XCTAssertFalse(settings.durationPresets.contains(where: { $0.name == "Office day" }))
    }

    func testPresetNamesAreUniqueAndReservePickerLabels() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())

        XCTAssertThrowsError(try manager.addPreset(name: "1H", duration: 60)) { error in
            XCTAssertEqual(error as? SettingsManagerError, .duplicatePresetName("1H"))
        }
        XCTAssertThrowsError(try manager.addPreset(name: "Custom", duration: 60)) { error in
            XCTAssertEqual(error as? SettingsManagerError, .reservedPresetName("Custom"))
        }
    }

    func testInactivityIntervalRequiresAtLeastOneSecond() {
        let manager = SettingsManager(storage: InMemorySettingsStorage())

        XCTAssertThrowsError(try manager.setInactivityInterval(0.5)) { error in
            XCTAssertEqual(error as? SettingsManagerError, .invalidInactivityInterval)
        }
    }

    func testDefaultAlwaysActiveModePersistsAndResets() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())

        try manager.setDefaultAlwaysActiveMode(.mouse)
        XCTAssertEqual(try manager.load().defaultAlwaysActiveMode, .mouse)

        try manager.resetDefaultAlwaysActiveMode()
        XCTAssertEqual(try manager.load().defaultAlwaysActiveMode, .keyboard)
    }

    func testLegacySettingsWithoutDefaultModeDecodeAsKeyboard() throws {
        let data = Data(#"{"inactivityInterval":240,"durationPresets":[]}"#.utf8)

        let settings = try JSONDecoder().decode(WakeSettings.self, from: data)

        XCTAssertEqual(settings.defaultAlwaysActiveMode, .keyboard)
        XCTAssertEqual(settings.defaultSessionDuration, .interactive)
        XCTAssertEqual(settings.defaultAlwaysActiveDuration, .interactive)
        XCTAssertFalse(settings.confirmBeforeStopping)
        XCTAssertFalse(settings.showSessionChangeControls)
    }

    func testLegacySettingsWithoutStopConfirmationPreserveOtherSettings() throws {
        let data = Data(#"{"inactivityInterval":90,"defaultAlwaysActiveMode":"mouse","durationPresets":[]}"#.utf8)

        let settings = try JSONDecoder().decode(WakeSettings.self, from: data)

        XCTAssertFalse(settings.confirmBeforeStopping)
        XCTAssertEqual(settings.inactivityInterval, 90)
        XCTAssertEqual(settings.defaultAlwaysActiveMode, .mouse)
        XCTAssertEqual(settings.defaultSessionDuration, .interactive)
        XCTAssertTrue(settings.durationPresets.isEmpty)
    }

    func testDefaultDurationFollowsPresetEditsAndOrdering() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        try manager.addPreset(name: "Workday", duration: 8 * 60 * 60)
        let preset = try manager.preset(named: "Workday")
        try manager.setDefaultSessionDuration(.preset(preset.id))
        try manager.editPreset(named: "Workday", newName: "Office", duration: 7.5 * 60 * 60)
        try manager.movePreset(named: "Office", to: 1)
        try manager.removePreset(named: "1h")

        let settings = try manager.load()
        XCTAssertEqual(settings.defaultSessionDuration, .preset(preset.id))
        XCTAssertEqual(WakeUIContent.defaultDurationOption(settings: settings), .timed(7.5 * 60 * 60))
        XCTAssertEqual(WakeUIContent.defaultDurationLabel(settings: settings), "Office (7h 30m)")

        try manager.removePreset(id: preset.id)
        XCTAssertEqual(try manager.load().defaultSessionDuration, .interactive)
    }

    func testLegacySharedDurationMigratesToAlwaysActive() throws {
        let preset = WakeDurationPreset(name: "Office", duration: 7.5 * 60 * 60)
        for duration in [WakeDefaultDuration.interactive, .indefinite, .preset(preset.id)] {
            let originalSettings = WakeSettings(defaultSessionDuration: duration, confirmBeforeStopping: true, durationPresets: [preset])
            let encoded = try JSONEncoder().encode(originalSettings)
            var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            legacyJSON.removeValue(forKey: "defaultAlwaysActiveDuration")
            let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)

            let settings = try JSONDecoder().decode(WakeSettings.self, from: legacyData)

            XCTAssertEqual(settings.defaultSessionDuration, duration)
            XCTAssertEqual(settings.defaultAlwaysActiveDuration, duration)
            XCTAssertTrue(settings.confirmBeforeStopping)
            XCTAssertEqual(settings.durationPresets, [preset])
        }
    }

    func testExplicitAlwaysActiveInteractiveChoiceDoesNotInheritWakeDefault() throws {
        let settings = WakeSettings(defaultSessionDuration: .indefinite, defaultAlwaysActiveDuration: .interactive)

        let reloadedSettings = try JSONDecoder().decode(WakeSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(reloadedSettings.defaultSessionDuration, .indefinite)
        XCTAssertEqual(reloadedSettings.defaultAlwaysActiveDuration, .interactive)
    }

    func testAlwaysActiveDurationIsIndependentAndFollowsPresetEdits() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        let wakePreset = try manager.preset(named: "4h")
        try manager.setDefaultSessionDuration(.preset(wakePreset.id))
        try manager.addPreset(name: "Office", duration: 7.5 * 60 * 60)
        let preset = try manager.preset(named: "Office")
        try manager.setDefaultAlwaysActiveDuration(.preset(preset.id))
        try manager.editPreset(named: "Office", newName: "Focus", duration: 6 * 60 * 60)
        try manager.movePreset(named: "Focus", to: 1)

        let settings = try manager.load()
        XCTAssertEqual(settings.defaultSessionDuration, .preset(wakePreset.id))
        XCTAssertEqual(settings.defaultAlwaysActiveDuration, .preset(preset.id))
        XCTAssertEqual(WakeUIContent.defaultDurationOption(settings: settings, target: .alwaysActive), .timed(6 * 60 * 60))
        XCTAssertEqual(WakeUIContent.defaultDurationLabel(settings: settings, target: .alwaysActive), "Focus (6h)")

        try manager.removePreset(id: preset.id)
        let removedSettings = try manager.load()
        XCTAssertEqual(removedSettings.defaultSessionDuration, .preset(wakePreset.id))
        XCTAssertEqual(removedSettings.defaultAlwaysActiveDuration, .interactive)
    }

    func testRemovingSelectedPresetByNameReturnsToInteractive() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        let preset = try manager.preset(named: "4h")
        try manager.setDefaultSessionDuration(.preset(preset.id))
        try manager.setDefaultAlwaysActiveDuration(.preset(preset.id))

        try manager.removePreset(named: "4H")

        XCTAssertEqual(try manager.load().defaultSessionDuration, .interactive)
        XCTAssertEqual(try manager.load().defaultAlwaysActiveDuration, .interactive)
    }

    func testResetPresetsPreservesWakeAndOnlyClearsMissingAlwaysActiveDefault() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        let wakePreset = try manager.preset(named: "4h")
        try manager.setDefaultSessionDuration(.preset(wakePreset.id))
        try manager.addPreset(name: "Office", duration: 7.5 * 60 * 60)
        let customPreset = try manager.preset(named: "Office")
        try manager.setDefaultAlwaysActiveDuration(.preset(customPreset.id))

        try manager.resetPresets()
        XCTAssertEqual(try manager.load().defaultSessionDuration, .preset(wakePreset.id))
        XCTAssertEqual(try manager.load().defaultAlwaysActiveDuration, .interactive)

        try manager.setDefaultAlwaysActiveDuration(.preset(wakePreset.id))
        try manager.resetPresets()
        XCTAssertEqual(try manager.load().defaultAlwaysActiveDuration, .preset(wakePreset.id))
    }

    func testResetPresetsRetainsAvailableDefaultsAndClearsRemovedDefault() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        let preset = try manager.preset(named: "4h")
        try manager.setDefaultSessionDuration(.preset(preset.id))
        try manager.resetPresets()
        XCTAssertEqual(try manager.load().defaultSessionDuration, .preset(preset.id))

        try manager.addPreset(name: "Workday", duration: 8 * 60 * 60)
        let customPreset = try manager.preset(named: "Workday")
        try manager.setDefaultSessionDuration(.preset(customPreset.id))
        try manager.resetPresets()
        XCTAssertEqual(try manager.load().defaultSessionDuration, .interactive)

        try manager.setDefaultSessionDuration(.indefinite)
        try manager.resetPresets()
        XCTAssertEqual(try manager.load().defaultSessionDuration, .indefinite)
    }

    func testDefaultDurationRejectsUnknownPreset() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())
        let missingID = UUID()
        try manager.setDefaultSessionDuration(.indefinite)

        XCTAssertThrowsError(try manager.setDefaultSessionDuration(.preset(missingID))) { error in
            XCTAssertEqual(error as? SettingsManagerError, .presetNotFound(missingID.uuidString))
        }
        XCTAssertThrowsError(try manager.setDefaultAlwaysActiveDuration(.preset(missingID))) { error in
            XCTAssertEqual(error as? SettingsManagerError, .presetNotFound(missingID.uuidString))
        }
        XCTAssertEqual(try manager.load().defaultSessionDuration, .indefinite)
        XCTAssertEqual(try manager.load().defaultAlwaysActiveDuration, .interactive)
    }

    func testLoadingMissingAlwaysActivePresetPreservesWakeDefault() throws {
        let storedSettings = WakeSettings(defaultSessionDuration: .indefinite, defaultAlwaysActiveDuration: .preset(UUID()))
        let manager = SettingsManager(storage: InMemorySettingsStorage(settings: storedSettings))

        let settings = try manager.load()

        XCTAssertEqual(settings.defaultSessionDuration, .indefinite)
        XCTAssertEqual(settings.defaultAlwaysActiveDuration, .interactive)
    }

    func testLoadingMissingDefaultPresetFallsBackToInteractive() throws {
        let storedSettings = WakeSettings(defaultAlwaysActiveMode: .mouse, defaultSessionDuration: .preset(UUID()), confirmBeforeStopping: true)
        let manager = SettingsManager(storage: InMemorySettingsStorage(settings: storedSettings))

        let settings = try manager.load()

        XCTAssertEqual(settings.defaultSessionDuration, .interactive)
        XCTAssertEqual(settings.defaultAlwaysActiveMode, .mouse)
        XCTAssertTrue(settings.confirmBeforeStopping)
        XCTAssertEqual(settings.durationPresets, storedSettings.durationPresets)
    }

    func testResetOperationsRecoverInvalidStoredSettings() throws {
        let storage = InMemorySettingsStorage(settings: WakeSettings(inactivityInterval: 0, durationPresets: []))
        let manager = SettingsManager(storage: storage)

        XCTAssertThrowsError(try manager.load())
        try manager.resetPresets()

        let settings = try manager.load()
        XCTAssertEqual(settings.inactivityInterval, WakeSettings.defaultInactivityInterval)
        XCTAssertEqual(settings.durationPresets.map(\.name), ["1h", "4h", "8h"])
    }

    func testFileStoragePersistsSettingsInWakeConfig() throws {
        let temporaryHome = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMyMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let storage = FileSessionStorage(fileManager: .default, homeDirectoryURL: temporaryHome)
        let manager = SettingsManager(storage: storage)
        try storage.saveAlwaysActiveSession(AlwaysActiveSession(daemonID: 42, mode: .keyboard))

        try manager.setInactivityInterval(5 * 60)
        try manager.setDefaultAlwaysActiveMode(.mouse)
        try manager.setConfirmBeforeStopping(true)
        try manager.setShowSessionChangeControls(true)
        try manager.addPreset(name: "Workday", duration: 8 * 60 * 60)

        let defaultPreset = try manager.preset(named: "Workday")
        try manager.setDefaultSessionDuration(.preset(defaultPreset.id))
        try manager.setDefaultAlwaysActiveDuration(.indefinite)

        let reloadedStorage = FileSessionStorage(fileManager: .default, homeDirectoryURL: temporaryHome)
        let reloadedSettings = try reloadedStorage.loadSettings()
        XCTAssertEqual(reloadedSettings?.inactivityInterval, 5 * 60)
        XCTAssertEqual(reloadedSettings?.defaultAlwaysActiveMode, .mouse)
        XCTAssertEqual(reloadedSettings?.defaultSessionDuration, .preset(defaultPreset.id))
        XCTAssertEqual(reloadedSettings?.defaultAlwaysActiveDuration, .indefinite)
        XCTAssertEqual(reloadedSettings?.confirmBeforeStopping, true)
        XCTAssertEqual(reloadedSettings?.showSessionChangeControls, true)
        XCTAssertEqual(reloadedSettings?.durationPresets.last?.name, "Workday")
        XCTAssertEqual(try reloadedStorage.loadAlwaysActiveSession()?.mode, .keyboard)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryHome.appendingPathComponent(".wake/wakeConfig").path))

        try SettingsManager(storage: reloadedStorage).setConfirmBeforeStopping(false)
        let disabledSettings = try storage.loadSettings()
        XCTAssertEqual(disabledSettings?.confirmBeforeStopping, false)
        XCTAssertEqual(disabledSettings?.showSessionChangeControls, true)
        XCTAssertEqual(disabledSettings?.inactivityInterval, 5 * 60)
        XCTAssertEqual(disabledSettings?.defaultAlwaysActiveMode, .mouse)
        XCTAssertEqual(disabledSettings?.defaultSessionDuration, .preset(defaultPreset.id))
        XCTAssertEqual(disabledSettings?.defaultAlwaysActiveDuration, .indefinite)
        XCTAssertEqual(disabledSettings?.durationPresets.last?.name, "Workday")

        try manager.setShowSessionChangeControls(false)
        let hiddenSettings = try reloadedStorage.loadSettings()
        XCTAssertEqual(hiddenSettings?.showSessionChangeControls, false)
        XCTAssertEqual(hiddenSettings?.defaultSessionDuration, .preset(defaultPreset.id))
        XCTAssertEqual(hiddenSettings?.defaultAlwaysActiveDuration, .indefinite)
    }
}

private final class InMemorySettingsStorage: SettingsStorage {
    var settings: WakeSettings?

    init(settings: WakeSettings? = nil) {
        self.settings = settings
    }

    func loadSettings() throws -> WakeSettings? {
        settings
    }

    func saveSettings(_ settings: WakeSettings) throws {
        self.settings = settings
    }

    func deleteSettings() throws {
        settings = nil
    }
}
