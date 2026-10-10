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
        let items = WakeUIContent.settingsItems(settings: WakeSettings())
        state.show(.settings, selectedIndex: items.firstIndex(where: { $0.label == "Remove all saved data" })!)

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

    func testSelectionIsRestoredAcrossNestedMenus() {
        var state = WakeUIState()
        let presetID = UUID()
        state.selectedIndex = 3
        state.show(.settings)
        state.selectedIndex = 4
        state.show(.presets)
        state.selectedIndex = 2
        state.show(.presetActions(presetID))
        state.selectedIndex = 1
        state.show(.textInput(.changePresetDuration(presetID)))

        state.show(.presetActions(presetID))
        XCTAssertEqual(state.selectedIndex, 1)
        state.show(.presets)
        XCTAssertEqual(state.selectedIndex, 2)
        state.show(.settings)
        XCTAssertEqual(state.selectedIndex, 4)
        state.show(.home)
        XCTAssertEqual(state.selectedIndex, 3)
        state.show(.home)
        XCTAssertEqual(state.selectedIndex, 3)
    }

    func testHomeSelectionFollowsStartAndStopForEverySessionControl() throws {
        let labels: [(WakeDurationTarget, String, String)] = [(.wake, "Start wake session", "Stop wake session"), (.alwaysActive, "Start Always Active", "Stop Always Active"), (.all, "Start all sessions", "Stop all sessions")]
        for showChanges in [false, true] {
            let settings = WakeSettings(showSessionChangeControls: showChanges)
            let inactiveItems = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(settings: settings))
            let activeItems = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(wakeSession: (Date(), nil), alwaysActiveSession: AlwaysActiveSession(daemonID: 42), settings: settings))
            for (target, startLabel, stopLabel) in labels {
                var state = WakeUIState()
                state.normalizeHomeSelection(actions: inactiveItems.map(\.action))
                state.selectedIndex = try XCTUnwrap(inactiveItems.firstIndex(where: { $0.label == startLabel }))
                state.show(.durations(target))
                state.selectedIndex = 2
                if target != .wake {
                    state.show(.alwaysActiveMode(target, .timed(4 * 60 * 60)), selectedIndex: 1)
                }
                state.show(.home)
                state.normalizeHomeSelection(actions: activeItems.map(\.action))
                XCTAssertEqual(activeItems[state.selectedIndex].label, stopLabel)

                state.show(.home)
                state.normalizeHomeSelection(actions: inactiveItems.map(\.action))
                XCTAssertEqual(inactiveItems[state.selectedIndex].label, startLabel)
            }
        }
    }

    func testConfirmationsResetToCancelWhenReopened() throws {
        let confirmations: [WakeConfirmation] = [.stopWake, .stopAlwaysActive, .stopAll, .deletePreset(UUID(), "Office"), .resetPresets, .clearAllData]
        for confirmation in confirmations {
            var state = WakeUIState()
            state.selectedIndex = 2
            let items = WakeUIContent.confirmationItems(confirmation)
            let cancelIndex = try XCTUnwrap(items.firstIndex(where: { !$0.action }))
            state.show(.confirmation(confirmation))
            XCTAssertEqual(state.selectedIndex, cancelIndex)
            state.moveSelection(by: 1, itemCount: items.count)
            XCTAssertTrue(items[state.selectedIndex].action)

            state.show(.home)
            XCTAssertEqual(state.selectedIndex, 2)
            state.show(.confirmation(confirmation))
            XCTAssertEqual(state.selectedIndex, cancelIndex)
        }
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

    func testActiveHomeStopsAlwaysActiveDirectly() {
        let snapshot = WakeUIStatusSnapshot(alwaysActiveSession: AlwaysActiveSession(daemonID: 42))
        let items = WakeUIContent.homeItems(snapshot: snapshot)
        let labels = items.map(\.label)

        XCTAssertTrue(labels.contains("Stop Always Active"))
        XCTAssertFalse(labels.contains("Manage Always Active"))
        XCTAssertFalse(labels.contains("Start Always Active"))

        guard let item = items.first(where: { $0.label == "Stop Always Active" }), case .stopAlwaysActive = item.action else {
            return XCTFail("Expected the active home action to stop Always Active directly.")
        }
    }

    func testDefaultHomeHasFiveRowsAcrossAllSessionStates() {
        let wake = (Date(), Optional<TimeInterval>.none)
        let alwaysActive = AlwaysActiveSession(daemonID: 42)
        let cases: [(WakeUIStatusSnapshot, [String])] = [
            (WakeUIStatusSnapshot(), ["Start wake session", "Start Always Active", "Start all sessions"]),
            (WakeUIStatusSnapshot(wakeSession: wake), ["Stop wake session", "Start Always Active", "Stop all sessions"]),
            (WakeUIStatusSnapshot(alwaysActiveSession: alwaysActive), ["Start wake session", "Stop Always Active", "Stop all sessions"]),
            (WakeUIStatusSnapshot(wakeSession: wake, alwaysActiveSession: alwaysActive), ["Stop wake session", "Stop Always Active", "Stop all sessions"])
        ]

        for (snapshot, actions) in cases {
            XCTAssertEqual(WakeUIContent.homeItems(snapshot: snapshot).map(\.label), actions + ["Settings", "Exit"])
        }
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

    func testChangeControlsOnlyAppearForActiveSessionsWhenEnabled() {
        let settings = WakeSettings(showSessionChangeControls: true)
        let inactiveLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(settings: settings)).map(\.label)
        let wakeLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(wakeSession: (Date(), nil), settings: settings)).map(\.label)
        let alwaysActiveLabels = WakeUIContent.homeItems(snapshot: WakeUIStatusSnapshot(alwaysActiveSession: AlwaysActiveSession(daemonID: 42), settings: settings)).map(\.label)

        XCTAssertFalse(inactiveLabels.contains("Stop all sessions"))
        XCTAssertFalse(inactiveLabels.contains("Change wake duration"))
        XCTAssertFalse(inactiveLabels.contains("Change Always Active"))
        XCTAssertFalse(inactiveLabels.contains("Restart all sessions"))
        XCTAssertTrue(wakeLabels.contains("Change wake duration"))
        XCTAssertFalse(wakeLabels.contains("Change Always Active"))
        XCTAssertTrue(alwaysActiveLabels.contains("Change Always Active"))
        XCTAssertFalse(alwaysActiveLabels.contains("Change wake duration"))
        XCTAssertTrue(wakeLabels.contains("Restart all sessions"))
        XCTAssertTrue(alwaysActiveLabels.contains("Restart all sessions"))
    }

    func testStopAllConfirmationShowsActionBeforeCancel() {
        let items = WakeUIContent.confirmationItems(.stopAll)
        var state = WakeUIState()
        state.show(.confirmation(.stopAll))

        XCTAssertEqual(items.map(\.label), ["Stop all sessions", "Cancel"])
        XCTAssertEqual(items.map(\.action), [true, false])
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testStoppingSkipsConfirmationByDefaultForEverySessionAction() throws {
        for target in [WakeDurationTarget.wake, .alwaysActive, .all] {
            try withUI { ui, storage, snapshot in
                let selectedIndex = target == .wake ? 0 : target == .alwaysActive ? 1 : 2
                try selectStop(target, ui: ui, snapshot: snapshot)

                XCTAssertEqual(ui.state.screen, .home)
                XCTAssertEqual(ui.state.selectedIndex, selectedIndex)
                XCTAssertEqual(try storage.loadWakeSession() == nil, target != .alwaysActive)
                XCTAssertEqual(try storage.loadAlwaysActiveSession() == nil, target != .wake)
                XCTAssertNotNil(ui.state.notification)
            }
        }
    }

    func testStoppingKeepsSessionControlSelectedWhenChangeRowsDisappear() throws {
        for target in [WakeDurationTarget.wake, .alwaysActive, .all] {
            try withUI(settings: WakeSettings(showSessionChangeControls: true)) { ui, _, initialSnapshot in
                try selectStop(target, ui: ui, snapshot: initialSnapshot)
                var snapshot = initialSnapshot
                if target != .alwaysActive { snapshot.wakeSession = nil }
                if target != .wake { snapshot.alwaysActiveSession = nil }
                ui.normalizeSelection(snapshot: snapshot)

                let label = switch target {
                case .wake: "Start wake session"
                case .alwaysActive: "Start Always Active"
                case .all: "Start all sessions"
                }
                XCTAssertEqual(ui.state.screen, .home)
                XCTAssertEqual(WakeUIContent.homeItems(snapshot: snapshot)[ui.state.selectedIndex].label, label)
            }
        }
    }

    func testEnabledStopConfirmationCanCancelOrConfirmEverySessionAction() throws {
        for target in [WakeDurationTarget.wake, .alwaysActive, .all] {
            try withUI(settings: WakeSettings(confirmBeforeStopping: true)) { ui, storage, snapshot in
                let confirmation: WakeConfirmation = switch target {
                case .wake: .stopWake
                case .alwaysActive: .stopAlwaysActive
                case .all: .stopAll
                }
                try selectStop(target, ui: ui, snapshot: snapshot)

                XCTAssertEqual(ui.state.screen, .confirmation(confirmation))
                XCTAssertNotNil(try storage.loadWakeSession())
                XCTAssertNotNil(try storage.loadAlwaysActiveSession())

                try ui.handle(key: .enter, snapshot: snapshot, now: Date())
                XCTAssertEqual(ui.state.screen, .home)
                XCTAssertEqual(ui.state.selectedIndex, target == .wake ? 0 : target == .alwaysActive ? 1 : 2)
                XCTAssertNotNil(try storage.loadWakeSession())
                XCTAssertNotNil(try storage.loadAlwaysActiveSession())
                XCTAssertNil(ui.state.notification)

                try selectStop(target, ui: ui, snapshot: snapshot)
                try ui.handle(key: .right, snapshot: snapshot, now: Date())
                try ui.handle(key: .enter, snapshot: snapshot, now: Date())

                XCTAssertEqual(ui.state.screen, .home)
                XCTAssertEqual(try storage.loadWakeSession() == nil, target != .alwaysActive)
                XCTAssertEqual(try storage.loadAlwaysActiveSession() == nil, target != .wake)
            }
        }
    }

    func testSettingsTogglePersistsAndAppliesImmediately() throws {
        try withUI { ui, storage, initialSnapshot in
            var snapshot = initialSnapshot
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Confirm before stopping  Off", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)

            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertTrue(snapshot.settings.confirmBeforeStopping)
            XCTAssertEqual(ui.state.screen, .settings)
            let frame = WakeFullScreenRenderer(colorsEnabled: false).render(state: ui.state, snapshot: snapshot, size: TerminalSize(rows: 24, columns: 76), now: Date())
            XCTAssertTrue(removingANSI(from: frame).contains("Confirm before stopping  On"))

            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectStop(.wake, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .confirmation(.stopWake))
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Confirm before stopping  On", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)

            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertFalse(snapshot.settings.confirmBeforeStopping)
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectStop(.wake, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .home)
            XCTAssertNil(try storage.loadWakeSession())
        }
    }

    func testInteractiveDefaultPromptsForEverySessionType() throws {
        let actions: [(WakeDurationTarget, String)] = [(.wake, "Start wake session"), (.alwaysActive, "Start Always Active"), (.all, "Start all sessions")]
        for (target, label) in actions {
            try withUI(includeSessions: false) { ui, _, snapshot in
                try selectMenuItem(label, labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)

                XCTAssertEqual(ui.state.screen, .durations(target))
                XCTAssertNil(ui.state.notification)
                if target != .wake {
                    try selectMenuItem("4h", labels: WakeUIContent.durationItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)
                    XCTAssertEqual(ui.state.screen, .alwaysActiveMode(target, .timed(4 * 60 * 60)))
                }
            }
        }
    }

    func testDefaultWakeDurationSettingUsesCurrentPoolAndSavesSelection() throws {
        let preset = WakeDurationPreset(name: "Office", duration: 7.5 * 60 * 60)
        let settings = WakeSettings(durationPresets: [preset])
        try withUI(settings: settings) { ui, storage, initialSnapshot in
            var snapshot = initialSnapshot
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Default wake duration  Ask every time", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)

            XCTAssertEqual(ui.state.screen, .defaultSessionDuration(.wake))
            let items = WakeUIContent.defaultDurationItems(settings: snapshot.settings)
            XCTAssertEqual(items.map(\.label), ["Ask every time (default)", "Indefinite", "Office", "Back"])
            let frame = WakeFullScreenRenderer(colorsEnabled: false).render(state: ui.state, snapshot: snapshot, size: TerminalSize(rows: 24, columns: 76), now: Date())
            XCTAssertTrue(removingANSI(from: frame).contains("Prompt for a duration on every Wake start"))

            try selectMenuItem("Office", labels: items.map(\.label), ui: ui, snapshot: snapshot)
            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertEqual(snapshot.settings.defaultSessionDuration, .preset(preset.id))
            XCTAssertEqual(ui.state.screen, .settings)

            let savedLabel = "Default wake duration  Office (7h 30m)"
            XCTAssertEqual(WakeUIContent.settingsItems(settings: snapshot.settings)[ui.state.selectedIndex].label, savedLabel)
            try selectMenuItem(savedLabel, labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.selectedIndex, 2)
            try selectMenuItem("Back", labels: items.map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(try storage.loadSettings()?.defaultSessionDuration, .preset(preset.id))

            try selectMenuItem(savedLabel, labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Ask every time (default)", labels: items.map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(try storage.loadSettings()?.defaultSessionDuration, .interactive)
            XCTAssertEqual(ui.state.screen, .settings)
        }
    }

    func testSavedDurationSkipsAlwaysActivePickersAndKeepsAccessibilitySetup() throws {
        let preset = WakeDurationPreset(name: "Office", duration: 7.5 * 60 * 60)
        for duration in [WakeDefaultDuration.indefinite, .preset(preset.id)] {
            let settings = WakeSettings(defaultAlwaysActiveDuration: duration, durationPresets: [preset])
            try withUI(settings: settings, includeSessions: false) { ui, _, snapshot in
                try selectMenuItem("Start Always Active", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)

                XCTAssertEqual(ui.state.screen, .confirmation(.openAccessibility(.alwaysActive)))
            }
        }
    }

    func testAlwaysActiveDurationPickerSavesIndependentlyAndAppliesImmediately() throws {
        let preset = WakeDurationPreset(name: "Office", duration: 7.5 * 60 * 60)
        let settings = WakeSettings(defaultSessionDuration: .indefinite, durationPresets: [preset])
        try withUI(settings: settings, includeSessions: false) { ui, storage, initialSnapshot in
            var snapshot = initialSnapshot
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Default Always Active duration  Ask every time", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)

            XCTAssertEqual(ui.state.screen, .defaultSessionDuration(.alwaysActive))
            let items = WakeUIContent.defaultDurationItems(settings: snapshot.settings, target: .alwaysActive)
            XCTAssertEqual(items.map(\.label), ["Ask every time (default)", "Indefinite", "Office", "Back"])
            let frame = WakeFullScreenRenderer(colorsEnabled: false).render(state: ui.state, snapshot: snapshot, size: TerminalSize(rows: 24, columns: 76), now: Date())
            XCTAssertTrue(removingANSI(from: frame).contains("Default Always Active duration"))
            XCTAssertTrue(removingANSI(from: frame).contains("every Always Active start"))

            try selectMenuItem("Office", labels: items.map(\.label), ui: ui, snapshot: snapshot)
            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertEqual(snapshot.settings.defaultAlwaysActiveDuration, .preset(preset.id))
            XCTAssertEqual(snapshot.settings.defaultSessionDuration, .indefinite)
            XCTAssertEqual(WakeUIContent.settingsItems(settings: snapshot.settings)[ui.state.selectedIndex].label, "Default Always Active duration  Office (7h 30m)")
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectMenuItem("Start Always Active", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .confirmation(.openAccessibility(.alwaysActive)))

            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Default Always Active duration  Office (7h 30m)", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.selectedIndex, 2)
            try selectMenuItem("Ask every time (default)", labels: items.map(\.label), ui: ui, snapshot: snapshot)
            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertEqual(snapshot.settings.defaultAlwaysActiveDuration, .interactive)
            XCTAssertEqual(snapshot.settings.defaultSessionDuration, .indefinite)
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectMenuItem("Start Always Active", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .durations(.alwaysActive))
        }
    }

    func testAlwaysActiveDefaultDoesNotSkipWakePicker() throws {
        let settings = WakeSettings(defaultAlwaysActiveDuration: .indefinite)
        try withUI(settings: settings, includeSessions: false) { ui, _, snapshot in
            try selectMenuItem("Start wake session", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .durations(.wake))
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            try selectMenuItem("Start Always Active", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .confirmation(.openAccessibility(.alwaysActive)))
        }
    }

    func testSavedDurationStartsAllImmediatelyUsingSavedModeAndInterval() throws {
        let preset = WakeDurationPreset(name: "Office", duration: 7.5 * 60 * 60)
        for duration in [WakeDefaultDuration.indefinite, .preset(preset.id)] {
            let recorder = SessionStartRecorder()
            let manager = AllSessionsManager(wakeManager: recorder, alwaysActiveManager: recorder)
            let settings = WakeSettings(inactivityInterval: 225, defaultAlwaysActiveMode: .mouse, defaultSessionDuration: duration, durationPresets: [preset])
            try withUI(settings: settings, includeSessions: false, allSessionsManager: manager, isAccessibilityEnabled: { true }) { ui, _, snapshot in
                try selectMenuItem("Start all sessions", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)

                XCTAssertEqual(ui.state.screen, .home)
                XCTAssertEqual(ui.state.selectedIndex, 2)
                XCTAssertEqual(recorder.wakeStartCount, 1)
                XCTAssertEqual(recorder.alwaysActiveStartCount, 1)
                let expectedDuration: TimeInterval? = duration == .indefinite ? nil : preset.duration
                XCTAssertEqual(recorder.wakeDuration, expectedDuration)
                XCTAssertEqual(recorder.alwaysActiveDuration, expectedDuration)
                XCTAssertEqual(recorder.mode, .mouse)
                XCTAssertEqual(recorder.inactivityInterval, 225)
                XCTAssertEqual(ui.state.notification?.message, "Wake and Always Active started.")
            }
        }
    }

    func testEnabledChangeControlsStillAllowManualChangesToActiveSessions() throws {
        try withUI(settings: WakeSettings(defaultSessionDuration: .indefinite, showSessionChangeControls: true)) { ui, _, snapshot in
            let labels = WakeUIContent.homeItems(snapshot: snapshot).map(\.label)
            try selectMenuItem("Change wake duration", labels: labels, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .durations(.wake))
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())

            try selectMenuItem("Change Always Active", labels: labels, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .durations(.alwaysActive))
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())

            try selectMenuItem("Restart all sessions", labels: labels, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .durations(.all))
        }
    }

    func testSessionChangeTogglePersistsAndUpdatesHomeImmediately() throws {
        try withUI { ui, storage, initialSnapshot in
            var snapshot = initialSnapshot
            try selectMenuItem("Settings", labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
            try selectMenuItem("Show session change controls  Off", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)

            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertTrue(snapshot.settings.showSessionChangeControls)
            XCTAssertNotNil(try storage.loadWakeSession())
            XCTAssertNotNil(try storage.loadAlwaysActiveSession())
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            let expandedLabels = WakeUIContent.homeItems(snapshot: snapshot).map(\.label)
            ui.normalizeSelection(snapshot: snapshot)
            XCTAssertEqual(expandedLabels[ui.state.selectedIndex], "Settings")
            XCTAssertTrue(expandedLabels.contains("Change wake duration"))
            XCTAssertTrue(expandedLabels.contains("Change Always Active"))
            XCTAssertTrue(expandedLabels.contains("Restart all sessions"))

            try selectMenuItem("Settings", labels: expandedLabels, ui: ui, snapshot: snapshot)
            try selectMenuItem("Show session change controls  On", labels: WakeUIContent.settingsItems(settings: snapshot.settings).map(\.label), ui: ui, snapshot: snapshot)
            snapshot.settings = try XCTUnwrap(storage.loadSettings())
            XCTAssertFalse(snapshot.settings.showSessionChangeControls)
            try ui.handle(key: .escape, snapshot: snapshot, now: Date())
            let compactLabels = WakeUIContent.homeItems(snapshot: snapshot).map(\.label)
            ui.normalizeSelection(snapshot: snapshot)
            XCTAssertEqual(compactLabels[ui.state.selectedIndex], "Settings")
            XCTAssertEqual(compactLabels, ["Stop wake session", "Stop Always Active", "Stop all sessions", "Settings", "Exit"])

            try selectMenuItem("Stop Always Active", labels: compactLabels, ui: ui, snapshot: snapshot)
            XCTAssertEqual(ui.state.screen, .home)
            XCTAssertNil(try storage.loadAlwaysActiveSession())
            XCTAssertNotNil(try storage.loadWakeSession())
        }
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

    private func withUI(settings: WakeSettings = WakeSettings(), includeSessions: Bool = true, allSessionsManager: AllSessionsManager? = nil, isAccessibilityEnabled: @escaping () -> Bool = { false }, perform: (WakeInteractiveUI, FileSessionStorage, WakeUIStatusSnapshot) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("WakeMyMacUITests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let storage = FileSessionStorage(fileManager: .default, homeDirectoryURL: home)
        // Stale PIDs exercise the real stop paths without signaling another process.
        let wakeSession = WakeSession(daemonID: Int32.max)
        let alwaysActiveSession = AlwaysActiveSession(daemonID: Int32.max)
        if includeSessions {
            try storage.saveWakeSession(wakeSession)
            try storage.saveAlwaysActiveSession(alwaysActiveSession)
        }
        try storage.saveSettings(settings)
        let ui = WakeInteractiveUI(wakeManager: WakeManager(storage: storage), alwaysActiveManager: AlwaysActiveManager(storage: storage), settingsManager: SettingsManager(storage: storage), allSessionsManager: allSessionsManager, isAccessibilityEnabled: isAccessibilityEnabled)
        let snapshot = WakeUIStatusSnapshot(wakeSession: includeSessions ? (wakeSession.startTime, nil) : nil, alwaysActiveSession: includeSessions ? alwaysActiveSession : nil, settings: settings)

        try perform(ui, storage, snapshot)
    }

    private func selectStop(_ target: WakeDurationTarget, ui: WakeInteractiveUI, snapshot: WakeUIStatusSnapshot) throws {
        let label = switch target {
        case .wake: "Stop wake session"
        case .alwaysActive: "Stop Always Active"
        case .all: "Stop all sessions"
        }
        try selectMenuItem(label, labels: WakeUIContent.homeItems(snapshot: snapshot).map(\.label), ui: ui, snapshot: snapshot)
    }

    private func selectMenuItem(_ label: String, labels: [String], ui: WakeInteractiveUI, snapshot: WakeUIStatusSnapshot) throws {
        let index = try XCTUnwrap(labels.firstIndex(of: label))
        for _ in 0 ..< labels.count {
            if ui.state.selectedIndex == index { break }
            try ui.handle(key: .down, snapshot: snapshot, now: Date())
        }
        try ui.handle(key: .enter, snapshot: snapshot, now: Date())
    }
}

private final class SessionStartRecorder: CombinedWakeManaging, CombinedAlwaysActiveManaging {
    var wakeStartCount = 0
    var alwaysActiveStartCount = 0
    var wakeDuration: TimeInterval?
    var alwaysActiveDuration: TimeInterval?
    var mode: AlwaysActiveMode?
    var inactivityInterval: TimeInterval?

    func combinedIsActive() throws -> Bool {
        false
    }

    func startCombined(duration: TimeInterval?) throws {
        wakeStartCount += 1
        wakeDuration = duration
    }

    func startCombined(mode: AlwaysActiveMode, duration: TimeInterval?, inactivityInterval: TimeInterval, replacingActiveSession: Bool, force: Bool) throws {
        alwaysActiveStartCount += 1
        alwaysActiveDuration = duration
        self.mode = mode
        self.inactivityInterval = inactivityInterval
    }

    func stopCombined(force: Bool) throws {}
}
