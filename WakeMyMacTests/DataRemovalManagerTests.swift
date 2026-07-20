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

final class DataRemovalManagerTests: XCTestCase {
    func testStopsBothSessionsBeforeRemovingData() throws {
        let events = DataRemovalEvents()
        let wake = DataRemovalWakeDouble(events: events)
        let alwaysActive = DataRemovalAlwaysActiveDouble(events: events)
        let storage = DataRemovalStorageDouble(events: events)
        let manager = DataRemovalManager(wakeManager: wake, alwaysActiveManager: alwaysActive, storage: storage)

        try manager.removeAllData()

        XCTAssertEqual(events.values, ["stop-wake", "stop-always-active", "remove-data"])
    }

    func testStopFailurePreventsDataRemovalAndStillAttemptsBothStops() throws {
        let events = DataRemovalEvents()
        let wake = DataRemovalWakeDouble(error: DataRemovalTestError.stopFailed, events: events)
        let alwaysActive = DataRemovalAlwaysActiveDouble(events: events)
        let storage = DataRemovalStorageDouble(events: events)
        let manager = DataRemovalManager(wakeManager: wake, alwaysActiveManager: alwaysActive, storage: storage)

        XCTAssertThrowsError(try manager.removeAllData()) { error in
            XCTAssertTrue(error.localizedDescription.contains("all sessions must stop first"))
        }
        XCTAssertEqual(events.values, ["stop-wake", "stop-always-active"])
        XCTAssertFalse(storage.didRemoveData)
    }

    func testFileStorageRemovesWakeDirectoryAndLegacySession() throws {
        let fileManager = FileManager.default
        let temporaryHome = fileManager.temporaryDirectory.appendingPathComponent("WakeMyMacRemovalTests-\(UUID().uuidString)", isDirectory: true)
        let wakeDirectory = temporaryHome.appendingPathComponent(".wake", isDirectory: true)
        let customFile = wakeDirectory.appendingPathComponent("custom-file")
        let legacySession = temporaryHome.appendingPathComponent("wakeSession")
        try fileManager.createDirectory(at: wakeDirectory, withIntermediateDirectories: true)
        XCTAssertTrue(fileManager.createFile(atPath: customFile.path, contents: Data("custom".utf8)))
        XCTAssertTrue(fileManager.createFile(atPath: legacySession.path, contents: Data("legacy".utf8)))
        defer { try? fileManager.removeItem(at: temporaryHome) }
        let storage = FileSessionStorage(fileManager: fileManager, homeDirectoryURL: temporaryHome)

        try storage.removeAllData()

        XCTAssertFalse(fileManager.fileExists(atPath: wakeDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacySession.path))
        XCTAssertNoThrow(try storage.removeAllData())
    }
}

private final class DataRemovalEvents {
    var values = [String]()
}

private enum DataRemovalTestError: LocalizedError {
    case stopFailed

    var errorDescription: String? {
        "Expected stop failure"
    }
}

private final class DataRemovalWakeDouble: DataRemovalWakeManaging {
    private let error: Error?
    private let events: DataRemovalEvents

    init(error: Error? = nil, events: DataRemovalEvents) {
        self.error = error
        self.events = events
    }

    func stopForDataRemoval() throws {
        events.values.append("stop-wake")
        if let error { throw error }
    }
}

private final class DataRemovalAlwaysActiveDouble: DataRemovalAlwaysActiveManaging {
    private let error: Error?
    private let events: DataRemovalEvents

    init(error: Error? = nil, events: DataRemovalEvents) {
        self.error = error
        self.events = events
    }

    func stopForDataRemoval() throws {
        events.values.append("stop-always-active")
        if let error { throw error }
    }
}

private final class DataRemovalStorageDouble: ApplicationDataStorage {
    private let events: DataRemovalEvents
    var didRemoveData = false

    init(events: DataRemovalEvents) {
        self.events = events
    }

    func removeAllData() throws {
        didRemoveData = true
        events.values.append("remove-data")
    }
}
