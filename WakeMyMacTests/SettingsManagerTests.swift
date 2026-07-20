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
    func testMissingSettingsUseFourMinuteIntervalAndHourlyDefaults() throws {
        let manager = SettingsManager(storage: InMemorySettingsStorage())

        let settings = try manager.load()

        XCTAssertEqual(settings.inactivityInterval, 4 * 60)
        XCTAssertEqual(settings.durationPresets.map(\.name), ["1h", "2h", "3h", "4h", "5h", "6h", "7h", "8h"])
        XCTAssertEqual(settings.durationPresets.map(\.duration), (1 ... 8).map { TimeInterval($0 * 60 * 60) })
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

    func testResetOperationsRecoverInvalidStoredSettings() throws {
        let storage = InMemorySettingsStorage(settings: WakeSettings(inactivityInterval: 0, durationPresets: []))
        let manager = SettingsManager(storage: storage)

        XCTAssertThrowsError(try manager.load())
        try manager.resetPresets()

        let settings = try manager.load()
        XCTAssertEqual(settings.inactivityInterval, WakeSettings.defaultInactivityInterval)
        XCTAssertEqual(settings.durationPresets.count, 8)
    }

    func testFileStoragePersistsSettingsInWakeConfig() throws {
        let temporaryHome = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMyMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let storage = FileSessionStorage(fileManager: .default, homeDirectoryURL: temporaryHome)
        let manager = SettingsManager(storage: storage)

        try manager.setInactivityInterval(5 * 60)
        try manager.addPreset(name: "Workday", duration: 8 * 60 * 60)

        let reloadedSettings = try FileSessionStorage(fileManager: .default, homeDirectoryURL: temporaryHome).loadSettings()
        XCTAssertEqual(reloadedSettings?.inactivityInterval, 5 * 60)
        XCTAssertEqual(reloadedSettings?.durationPresets.last?.name, "Workday")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryHome.appendingPathComponent(".wake/wakeConfig").path))
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
