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

final class AllSessionsManagerTests: XCTestCase {
    func testStartsAlwaysActiveBeforeWakeWithSharedDuration() throws {
        let events = EventRecorder()
        let wake = WakeDouble(events: events)
        let alwaysActive = AlwaysActiveDouble(events: events)
        let manager = AllSessionsManager(wakeManager: wake, alwaysActiveManager: alwaysActive)

        try manager.start(duration: 8 * 60 * 60, mode: .mouse, inactivityInterval: 5 * 60, replacingActiveSessions: false)

        XCTAssertEqual(events.values, ["always-active", "wake"])
        XCTAssertEqual(wake.startedDuration, 8 * 60 * 60)
        XCTAssertEqual(alwaysActive.startedDuration, 8 * 60 * 60)
        XCTAssertEqual(alwaysActive.startedMode, .mouse)
        XCTAssertEqual(alwaysActive.startedInactivityInterval, 5 * 60)
    }

    func testRejectsReplacementWithoutPermission() throws {
        let manager = AllSessionsManager(wakeManager: WakeDouble(isActive: true), alwaysActiveManager: AlwaysActiveDouble())

        XCTAssertThrowsError(try manager.start(duration: nil, mode: .keyboard, inactivityInterval: 240, replacingActiveSessions: false)) { error in
            XCTAssertTrue(error is AllSessionsManagerError)
        }
    }

    func testWakeFailureRollsBackNewAlwaysActiveSession() throws {
        let wake = WakeDouble(startError: TestFailure.expected)
        let alwaysActive = AlwaysActiveDouble()
        let manager = AllSessionsManager(wakeManager: wake, alwaysActiveManager: alwaysActive)

        XCTAssertThrowsError(try manager.start(duration: 60, mode: .keyboard, inactivityInterval: 240, replacingActiveSessions: false))
        XCTAssertEqual(alwaysActive.stopCount, 1)
    }

    func testRollbackFailureProducesActionableCombinedError() throws {
        let wake = WakeDouble(startError: TestFailure.expected)
        let alwaysActive = AlwaysActiveDouble(stopError: TestFailure.rollback)
        let manager = AllSessionsManager(wakeManager: wake, alwaysActiveManager: alwaysActive)

        XCTAssertThrowsError(try manager.start(duration: 60, mode: .keyboard, inactivityInterval: 240, replacingActiveSessions: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be rolled back"))
        }
    }
}

private final class EventRecorder {
    var values = [String]()
}

private enum TestFailure: LocalizedError {
    case expected
    case rollback

    var errorDescription: String? {
        switch self {
        case .expected:
            "Expected start failure"
        case .rollback:
            "Expected rollback failure"
        }
    }
}

private final class WakeDouble: CombinedWakeManaging {
    var isActive: Bool
    var startError: Error?
    var startedDuration: TimeInterval?
    private let events: EventRecorder?

    init(isActive: Bool = false, startError: Error? = nil, events: EventRecorder? = nil) {
        self.isActive = isActive
        self.startError = startError
        self.events = events
    }

    func combinedIsActive() throws -> Bool {
        isActive
    }

    func startCombined(duration: TimeInterval?) throws {
        if let startError { throw startError }
        startedDuration = duration
        events?.values.append("wake")
    }
}

private final class AlwaysActiveDouble: CombinedAlwaysActiveManaging {
    var isActive: Bool
    var stopError: Error?
    var startedDuration: TimeInterval?
    var startedMode: AlwaysActiveMode?
    var startedInactivityInterval: TimeInterval?
    var stopCount = 0
    private let events: EventRecorder?

    init(isActive: Bool = false, stopError: Error? = nil, events: EventRecorder? = nil) {
        self.isActive = isActive
        self.stopError = stopError
        self.events = events
    }

    func combinedIsActive() throws -> Bool {
        isActive
    }

    func startCombined(mode: AlwaysActiveMode, duration: TimeInterval?, inactivityInterval: TimeInterval, replacingActiveSession: Bool, force: Bool) throws {
        startedMode = mode
        startedDuration = duration
        startedInactivityInterval = inactivityInterval
        events?.values.append("always-active")
    }

    func stopCombined(force: Bool) throws {
        stopCount += 1
        if let stopError { throw stopError }
    }
}
