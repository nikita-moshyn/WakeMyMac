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
        XCTAssertTrue(plainFrame.contains("mouse · until stopped · 4m interval"))
        XCTAssertFalse(plainFrame.contains("Takeaways"))
        XCTAssertTrue(frame.contains("\u{001B}[7m"))
    }

    func testSelectedDescriptionWrapsAcrossRowsInNarrowTerminal() {
        var state = WakeUIState()
        state.show(.settings, selectedIndex: 3)

        let frame = WakeFullScreenRenderer(colorsEnabled: false).render(state: state, snapshot: WakeUIStatusSnapshot(), size: TerminalSize(rows: 16, columns: 49), now: Date())
        let plainFrame = removingANSI(from: frame)

        XCTAssertTrue(plainFrame.contains("Selected\r\n  Stop all sessions, delete ~/.wake and legacy\r\n  session state, then close WakeMyMac."))
        XCTAssertEqual(frame.components(separatedBy: "\r\n").count, 16)
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

    func testDurationParserRejectsOverflowInsteadOfFallingBackToMinutes() {
        XCTAssertNil(parseDuration("999999999999999999999999999999h1m"))
    }

    func testInactivityIntervalSupportsSecondsAndOptionalSpaces() {
        XCTAssertEqual(parseInactivityInterval("15s"), 15)
        XCTAssertEqual(parseInactivityInterval("3m30s"), 210)
        XCTAssertEqual(parseInactivityInterval("1h30m15s"), 5_415)
        XCTAssertEqual(parseInactivityInterval("1h 30m 15s"), 5_415)
        XCTAssertEqual(formatInactivityInterval(5_415), "1h 30m 15s")
        XCTAssertEqual(formatInactivityInterval(210), "3m 30s")
        XCTAssertEqual(formatInactivityInterval(1), "1s")
    }

    func testInactivityIntervalRejectsInvalidAndOverflowingValues() {
        XCTAssertNil(parseInactivityInterval("225"))
        XCTAssertNil(parseInactivityInterval("0s"))
        XCTAssertNil(parseInactivityInterval("30s3m"))
        XCTAssertNil(parseInactivityInterval("3m2m"))
        XCTAssertNil(parseInactivityInterval("999999999999999999999999999999h1s"))
        XCTAssertNil(parseInactivityInterval("\(Int.max)s"))
        XCTAssertNil(parseDuration("15s"))
        XCTAssertNil(parseDuration("3m30s"))
        XCTAssertNil(parseDuration("1h 30m"))
    }

    func testOnlyInactivityInputAcceptsSecondsAndSpaces() {
        XCTAssertTrue(WakeTextInput.inactivityInterval.accepts("s"))
        XCTAssertTrue(WakeTextInput.inactivityInterval.accepts(" "))
        XCTAssertFalse(WakeTextInput.customDuration(.wake).accepts("s"))
        XCTAssertFalse(WakeTextInput.newPresetDuration(name: "Workday").accepts(" "))
    }

    func testWakeDurationMenuUsesReducedDefaults() {
        let items = WakeUIContent.durationItems(settings: WakeSettings())
        XCTAssertEqual(items.map(\.label), ["Indefinite", "1h", "4h", "8h", "Custom", "Back"])

        guard case .duration(.indefinite) = items.first?.action else {
            return XCTFail("Expected Indefinite to be the first wake duration.")
        }
    }

    func testNamedPresetAppearsInEverySharedDurationPicker() {
        let settings = WakeSettings(durationPresets: [WakeDurationPreset(name: "Workday", duration: 7.5 * 60 * 60)])

        XCTAssertEqual(WakeUIContent.durationItems(settings: settings).map(\.label), ["Indefinite", "Workday", "Custom", "Back"])
    }

    func testInactiveHomeStartsAlwaysActiveDirectly() {
        let items = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot())
        let labels = items.map(\.label)

        XCTAssertTrue(labels.contains("Start all sessions"))
        XCTAssertTrue(labels.contains("Settings"))
        XCTAssertTrue(labels.contains("Start Always Active"))
        XCTAssertFalse(labels.contains("Manage Always Active"))
        XCTAssertFalse(labels.contains("View details"))

        guard let item = items.first(where: { $0.label == "Start Always Active" }), case .startAlwaysActive = item.action else {
            return XCTFail("Expected the inactive home action to start Always Active.")
        }
    }

    func testActiveHomeManagesAlwaysActive() {
        let snapshot = WakeUIStatusSnapshot(alwaysActiveSession: AlwaysActiveSession(daemonID: 42))
        let items = WakeUIContent.homeItems(snapshot: snapshot)
        let labels = items.map(\.label)

        XCTAssertTrue(labels.contains("Manage Always Active"))
        XCTAssertFalse(labels.contains("Start Always Active"))

        guard let item = items.first(where: { $0.label == "Manage Always Active" }), case .manageAlwaysActive = item.action else {
            return XCTFail("Expected the active home action to manage Always Active.")
        }
    }

    func testAlwaysActiveManagementExcludesDetails() {
        XCTAssertEqual(WakeUIContent.alwaysActiveItems.map(\.label), ["Change Always Active", "Stop Always Active", "Back"])
    }

    func testModePickerExplainsKeyboardAndMouseTradeoffs() {
        let items = WakeUIContent.modeItems

        XCTAssertEqual(items.map(\.label), ["Keyboard (recommended)", "Mouse", "Back"])
        XCTAssertTrue(items[0].description.contains("does not type text"))
        XCTAssertTrue(items[1].description.contains("hover-sensitive interfaces"))
    }

    func testSavedModeIsPreselectedForEveryModePicker() {
        let selectedIndex = WakeUIContent.modeSelectionIndex(for: .mouse)
        let screens: [WakeUIScreen] = [
            .alwaysActiveMode(.alwaysActive, .indefinite),
            .alwaysActiveMode(.all, .indefinite),
            .defaultAlwaysActiveMode
        ]

        for screen in screens {
            var state = WakeUIState()
            state.show(screen, selectedIndex: selectedIndex)
            XCTAssertEqual(state.selectedIndex, 1)
        }
        XCTAssertEqual(WakeUIContent.modeSelectionIndex(for: .keyboard), 0)
    }

    func testInactiveSessionClosesAlwaysActiveManagement() {
        var state = WakeUIState()
        state.show(.alwaysActive)

        state.reconcile(with: WakeUIStatusSnapshot())

        XCTAssertEqual(state.screen, .home)
    }

    func testActiveSessionKeepsAlwaysActiveManagementOpen() {
        var state = WakeUIState()
        state.show(.alwaysActive)

        state.reconcile(with: WakeUIStatusSnapshot(alwaysActiveSession: AlwaysActiveSession(daemonID: 42)))

        XCTAssertEqual(state.screen, .alwaysActive)
    }

    func testSettingsIncludesDestructiveDataRemoval() {
        let labels = WakeUIContent.settingsItems(settings: WakeSettings(defaultAlwaysActiveMode: .mouse)).map(\.label)
        let items = WakeUIContent.confirmationItems(.clearAllData)
        var state = WakeUIState()
        state.show(.confirmation(.clearAllData))

        XCTAssertTrue(labels.contains("Remove all saved data"))
        XCTAssertTrue(labels.contains("Default Always Active mode  Mouse"))
        XCTAssertEqual(items.map(\.label), ["Remove all data", "Cancel"])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testLongPresetMenuKeepsSelectionVisible() {
        let presets = (1 ... 20).map { WakeDurationPreset(name: "Preset \($0)", duration: TimeInterval($0 * 60)) }
        let snapshot = WakeUIStatusSnapshot(settings: WakeSettings(durationPresets: presets))
        var state = WakeUIState()
        state.show(.durations(.wake))
        state.selectedIndex = 20

        let frame = WakeFullScreenRenderer(colorsEnabled: false).render(state: state, snapshot: snapshot, size: TerminalSize(rows: 20, columns: 76), now: Date())

        XCTAssertTrue(removingANSI(from: frame).contains("Preset 20"))
    }

    func testAlwaysActiveSessionDecodesLegacyDefaults() throws {
        let data = Data(#"{"daemonID":42,"startTime":0,"mode":"mouse"}"#.utf8)

        let session = try JSONDecoder().decode(AlwaysActiveSession.self, from: data)

        XCTAssertNil(session.duration)
        XCTAssertEqual(session.inactivityInterval, 4 * 60)
        XCTAssertEqual(session.mode, .mouse)
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
        XCTAssertEqual(wakeLabels.firstIndex(of: "Stop all sessions"), wakeLabels.firstIndex(of: "Restart all sessions").map { $0 + 1 })
        XCTAssertEqual(alwaysActiveLabels.firstIndex(of: "Stop all sessions"), alwaysActiveLabels.firstIndex(of: "Restart all sessions").map { $0 + 1 })
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
