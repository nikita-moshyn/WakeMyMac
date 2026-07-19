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
import Noora
import XCTest
@testable import WakeMyMac

final class WakeInteractiveUITests: XCTestCase {
    func testTerminalSessionUsesAlternateScreenBuffer() {
        XCTAssertTrue(WakeTerminalSession.enterSequence.contains("[?1049h"))
        XCTAssertTrue(WakeTerminalSession.leaveSequence.contains("[?1049l"))
        XCTAssertTrue(WakeTerminalSession.enterSequence.contains("[?25l"))
        XCTAssertTrue(WakeTerminalSession.leaveSequence.contains("[?25h"))
    }

    func testRendererProducesOneFullTerminalFrameWithLiveStatus() {
        let now = Date(timeIntervalSince1970: 1_752_943_200)
        let snapshot = WakeUIStatusSnapshot(
            wakeSession: (startTime: now.addingTimeInterval(-162), remainingTime: 2_838),
            alwaysActiveSession: AlwaysActiveSession(daemonID: 42, mode: .mouse, startTime: now.addingTimeInterval(-161))
        )
        let renderer = WakeFullScreenRenderer(colorsEnabled: false)

        let frame = renderer.render(state: WakeUIState(), snapshot: snapshot, size: TerminalSize(rows: 24, columns: 76), now: now)
        let plainFrame = removingANSI(from: frame)

        XCTAssertEqual(frame.components(separatedBy: "\r\n").count, 24)
        XCTAssertEqual(plainFrame.components(separatedBy: "WakeMyMac").count - 1, 1)
        XCTAssertTrue(plainFrame.contains("47m 18s remaining"))
        XCTAssertTrue(plainFrame.contains("mouse mode · 2m 41s elapsed"))
        XCTAssertFalse(plainFrame.contains("Takeaways"))
        XCTAssertTrue(frame.contains("\u{001B}[7m"))
    }

    func testSelectionWrapsWithinCurrentMenu() {
        var state = WakeUIState()

        state.moveSelection(by: -1, itemCount: 4)
        XCTAssertEqual(state.selectedIndex, 3)

        state.moveSelection(by: 1, itemCount: 4)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testLiveDurationIncludesSeconds() {
        XCTAssertEqual(formatLiveDuration(2_838), "47m 18s")
        XCTAssertEqual(formatLiveDuration(3_723), "1h 02m 03s")
    }

    func testWakeDurationMenuStartsWithInfiniteAndUsesReducedPresets() {
        XCTAssertEqual(WakeUIContent.durationItems.map(\.label), ["Infinite", "1h", "4h", "8h", "Custom", "Back"])

        guard case .duration(.indefinite) = WakeUIContent.durationItems.first?.action else {
            return XCTFail("Expected Infinite to be the first wake duration.")
        }
    }

    func testStopAlwaysActiveAppearsBeforeCancel() {
        let items = WakeUIContent.confirmationItems(.stopAlwaysActive)
        var state = WakeUIState()
        state.show(.confirmation(.stopAlwaysActive))

        XCTAssertEqual(items.map(\.label), ["Stop Always Active", "Cancel"])
        XCTAssertEqual(items.map(\.action), [true, false])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testStopAllAppearsAfterAlwaysActiveOnlyWhileASessionIsRunning() {
        let inactiveLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot()).map(\.label)
        let wakeLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(wakeSession: (Date(), nil))).map(\.label)
        let alwaysActiveLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(alwaysActiveSession: AlwaysActiveSession(daemonID: 42))).map(\.label)

        XCTAssertFalse(inactiveLabels.contains("Stop all sessions"))
        XCTAssertEqual(wakeLabels.firstIndex(of: "Stop all sessions"), wakeLabels.firstIndex(of: "Manage Always Active").map { $0 + 1 })
        XCTAssertEqual(alwaysActiveLabels.firstIndex(of: "Stop all sessions"), alwaysActiveLabels.firstIndex(of: "Manage Always Active").map { $0 + 1 })
    }

    func testStopAllConfirmationShowsActionBeforeCancel() {
        let items = WakeUIContent.confirmationItems(.stopAll)
        var state = WakeUIState()
        state.show(.confirmation(.stopAll))

        XCTAssertEqual(items.map(\.label), ["Stop all sessions", "Cancel"])
        XCTAssertEqual(items.map(\.action), [true, false])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testDaemonStartupWaitReturnsAfterSuccessSignal() throws {
        let result = try SigService.waitForDaemonStartup {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
                send(.success, getpid())
            }
        }

        guard case .success = result else {
            return XCTFail("Expected the daemon startup waiter to return success.")
        }
    }

    func testDaemonStartupWaitReturnsAfterFailureSignal() throws {
        let result = try SigService.waitForDaemonStartup {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
                send(.failure, getpid())
            }
        }

        guard case .failure = result else {
            return XCTFail("Expected the daemon startup waiter to return failure.")
        }
    }

    private func removingANSI(from string: String) -> String {
        string.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
    }
}
