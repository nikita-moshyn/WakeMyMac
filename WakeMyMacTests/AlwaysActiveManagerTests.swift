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

import Darwin
import XCTest
@testable import WakeMyMac

final class AlwaysActiveManagerTests: XCTestCase {
    func testStatusIsInactiveWithoutStoredSession() throws {
        let storage = InMemorySessionStorage()
        let manager = AlwaysActiveManager(storage: storage)

        guard case .inactive = try manager.statusResult() else {
            return XCTFail("Expected an inactive status.")
        }
    }

    func testStatusRemovesStaleSession() throws {
        let storage = InMemorySessionStorage()
        storage.alwaysActiveSession = AlwaysActiveSession(daemonID: Int32.max)
        let manager = AlwaysActiveManager(storage: storage)

        guard case .staleStateRemoved = try manager.statusResult() else {
            return XCTFail("Expected stale state to be removed.")
        }
        XCTAssertNil(storage.alwaysActiveSession)
    }

    func testStatusReturnsRunningSession() throws {
        let storage = InMemorySessionStorage()
        storage.alwaysActiveSession = AlwaysActiveSession(daemonID: getpid(), mode: .mouse)
        let manager = AlwaysActiveManager(storage: storage)

        guard case .active(let session) = try manager.statusResult() else {
            return XCTFail("Expected an active status.")
        }
        XCTAssertEqual(session.mode, .mouse)
        XCTAssertEqual(session.daemonID, getpid())
    }

    func testStopReportsNotRunningWithoutStoredSession() throws {
        let manager = AlwaysActiveManager(storage: InMemorySessionStorage())

        guard case .notRunning = try manager.stop() else {
            return XCTFail("Expected stop to report that no daemon is running.")
        }
    }
}

private final class InMemorySessionStorage: SessionStorage {
    var wakeSession: WakeSession?
    var alwaysActiveSession: AlwaysActiveSession?

    func loadWakeSession() throws -> WakeSession? {
        wakeSession
    }

    func saveWakeSession(_ session: WakeSession) throws {
        wakeSession = session
    }

    func deleteWakeSession() throws {
        wakeSession = nil
    }

    func loadAlwaysActiveSession() throws -> AlwaysActiveSession? {
        alwaysActiveSession
    }

    func saveAlwaysActiveSession(_ session: AlwaysActiveSession) throws {
        alwaysActiveSession = session
    }

    func deleteAlwaysActiveSession() throws {
        alwaysActiveSession = nil
    }
}
