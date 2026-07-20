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

import ArgumentParser
import Foundation
import Noora

final class WakeInteractiveUI {
    private let wakeManager: WakeManager
    private let alwaysActiveManager: AlwaysActiveManager
    private let settingsManager: SettingsManager
    private let allSessionsManager: AllSessionsManager
    private let dataRemovalManager: DataRemovalManager
    private let terminalSession: WakeTerminalSession
    private let renderer: WakeFullScreenRenderer
    private var state = WakeUIState()

    init(wakeManager: WakeManager = .current, alwaysActiveManager: AlwaysActiveManager = .current, settingsManager: SettingsManager = .current, allSessionsManager: AllSessionsManager? = nil, dataRemovalManager: DataRemovalManager = .current, terminalSession: WakeTerminalSession = WakeTerminalSession(), renderer: WakeFullScreenRenderer = WakeFullScreenRenderer()) {
        self.wakeManager = wakeManager
        self.alwaysActiveManager = alwaysActiveManager
        self.settingsManager = settingsManager
        self.allSessionsManager = allSessionsManager ?? AllSessionsManager(wakeManager: wakeManager, alwaysActiveManager: alwaysActiveManager)
        self.dataRemovalManager = dataRemovalManager
        self.terminalSession = terminalSession
        self.renderer = renderer
    }

    func run() throws {
        try terminalSession.enter()
        defer { terminalSession.leave() }

        var snapshot = WakeUIStatusSnapshot()
        var lastRenderedSecond = Int.min
        var lastSize = TerminalSize(rows: 0, columns: 0)
        var needsRender = true

        while state.isRunning {
            let now = Date()
            let currentSecond = Int(now.timeIntervalSince1970)
            let size = terminalSession.size()

            if needsRender || currentSecond != lastRenderedSecond || size.rows != lastSize.rows || size.columns != lastSize.columns {
                do {
                    snapshot = try loadSnapshot()
                } catch {
                    state.showNotification(error.localizedDescription, kind: .error, now: now)
                }
                state.reconcile(with: snapshot)
                state.normalizeSelection(itemCount: itemCount(for: state.screen, snapshot: snapshot))
                terminalSession.render(renderer.render(state: state, snapshot: snapshot, size: size, now: now))
                lastRenderedSecond = currentSecond
                lastSize = size
                needsRender = false
            }

            guard let key = terminalSession.readKey(timeoutMilliseconds: 100) else { continue }
            do {
                try handle(key: key, snapshot: snapshot, now: now)
            } catch {
                state.showNotification(error.localizedDescription, kind: .error, now: now)
            }
            needsRender = true
        }
    }

    private func loadSnapshot() throws -> WakeUIStatusSnapshot {
        wakeManager.refreshSession()
        return WakeUIStatusSnapshot(wakeSession: try wakeManager.status(), alwaysActiveSession: try alwaysActiveManager.status(), settings: try settingsManager.load())
    }

    private func handle(key: WakeTerminalKey, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        if key == .interrupt {
            state.isRunning = false
            return
        }

        if case .textInput(let input) = state.screen {
            try handleTextInputKey(key, input: input, snapshot: snapshot, now: now)
            return
        }

        switch key {
        case .up, .printable("k"):
            state.moveSelection(by: -1, itemCount: itemCount(for: state.screen, snapshot: snapshot))
        case .down, .printable("j"):
            state.moveSelection(by: 1, itemCount: itemCount(for: state.screen, snapshot: snapshot))
        case .left:
            state.moveSelection(by: -1, itemCount: itemCount(for: state.screen, snapshot: snapshot))
        case .right:
            state.moveSelection(by: 1, itemCount: itemCount(for: state.screen, snapshot: snapshot))
        case .enter:
            try selectCurrentItem(snapshot: snapshot, now: now)
        case .escape:
            navigateBack(snapshot: snapshot)
        default:
            break
        }
    }

    private func handleTextInputKey(_ key: WakeTerminalKey, input: WakeTextInput, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        switch key {
        case .escape:
            state.show(returnScreen(for: input))
        case .backspace:
            if !state.textInput.isEmpty {
                state.textInput.removeLast()
            }
        case .enter:
            try submitTextInput(input, snapshot: snapshot, now: now)
        case .printable(let character):
            if input.accepts(character), state.textInput.count < input.maximumLength {
                state.textInput.append(character)
            }
        default:
            break
        }
    }

    private func submitTextInput(_ input: WakeTextInput, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        switch input {
        case .customDuration(let target):
            guard let duration = parseDurationInput() else { return }
            try selectDurationOption(.timed(duration), target: target, snapshot: snapshot)
        case .inactivityInterval:
            guard let interval = parseInactivityIntervalInput() else { return }
            try settingsManager.setInactivityInterval(interval)
            state.show(.settings)
            state.showNotification("Inactivity interval saved. It applies to the next Always Active session.", kind: .success, now: now)
        case .newPresetName:
            let name = state.textInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                state.showNotification("Enter a preset name.", kind: .error, now: now)
                return
            }
            state.textInput = ""
            state.show(.textInput(.newPresetDuration(name: name)))
        case .newPresetDuration(let name):
            guard let duration = parseDurationInput() else { return }
            try settingsManager.addPreset(name: name, duration: duration)
            state.show(.presets)
            state.showNotification("Preset '\(name)' added.", kind: .success, now: now)
        case .renamePreset(let id):
            guard let preset = snapshot.settings.durationPresets.first(where: { $0.id == id }) else { return }
            try settingsManager.editPreset(named: preset.name, newName: state.textInput, duration: nil)
            state.show(.presetActions(id))
            state.showNotification("Preset renamed.", kind: .success, now: now)
        case .changePresetDuration(let id):
            guard let duration = parseDurationInput(), let preset = snapshot.settings.durationPresets.first(where: { $0.id == id }) else { return }
            try settingsManager.editPreset(named: preset.name, newName: nil, duration: duration)
            state.show(.presetActions(id))
            state.showNotification("Preset duration updated.", kind: .success, now: now)
        }
    }

    private func parseDurationInput() -> TimeInterval? {
        let normalizedInput = state.textInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let duration = parseDuration(normalizedInput) else {
            state.showNotification("Enter a duration such as 45m, 1h, or 1h30m.", kind: .error, now: Date())
            return nil
        }
        return duration
    }

    private func parseInactivityIntervalInput() -> TimeInterval? {
        let normalizedInput = state.textInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let interval = parseInactivityInterval(normalizedInput) else {
            state.showNotification("Enter an interval such as 3m45s or 1h 30m 15s.", kind: .error, now: Date())
            return nil
        }
        return interval
    }

    private func selectCurrentItem(snapshot: WakeUIStatusSnapshot, now: Date) throws {
        switch state.screen {
        case .home:
            try selectHomeItem(snapshot: snapshot)
        case .durations(let target):
            try selectDuration(target: target, snapshot: snapshot)
        case .alwaysActive:
            selectAlwaysActiveItem()
        case .alwaysActiveMode(let target, let option):
            try selectAlwaysActiveMode(target: target, option: option, snapshot: snapshot)
        case .settings:
            try selectSettingsItem(snapshot: snapshot)
        case .defaultAlwaysActiveMode:
            try selectDefaultAlwaysActiveMode(now: now)
        case .presets:
            try selectPresetItem(snapshot: snapshot, now: now)
        case .presetActions(let id):
            try selectPresetAction(id: id, snapshot: snapshot, now: now)
        case .confirmation(let confirmation):
            try resolveConfirmation(confirmation, snapshot: snapshot, now: now)
        case .textInput:
            break
        }
    }

    private func selectHomeItem(snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.homeItems(snapshot: snapshot)
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .manageWake:
            state.show(.durations(.wake))
        case .stopWake:
            state.show(.confirmation(.stopWake))
        case .startAll:
            state.show(.durations(.all))
        case .startAlwaysActive:
            state.show(.durations(.alwaysActive))
        case .manageAlwaysActive:
            state.show(.alwaysActive)
        case .stopAll:
            state.show(.confirmation(.stopAll))
        case .settings:
            state.show(.settings)
        case .exit:
            state.isRunning = false
        }
    }

    private func selectDuration(target: WakeDurationTarget, snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.durationItems(settings: snapshot.settings)
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .duration(let option):
            try selectDurationOption(option, target: target, snapshot: snapshot)
        case .custom:
            state.textInput = ""
            state.show(.textInput(.customDuration(target)))
        case .back:
            state.show(returnScreen(for: target, snapshot: snapshot))
        }
    }

    private func selectDurationOption(_ option: WakeDurationOption, target: WakeDurationTarget, snapshot: WakeUIStatusSnapshot) throws {
        switch target {
        case .wake:
            if snapshot.wakeSession == nil {
                try startWakeSession(option)
            } else {
                state.show(.confirmation(.replaceWake(option)))
            }
        case .alwaysActive, .all:
            state.show(.alwaysActiveMode(target, option), selectedIndex: WakeUIContent.modeSelectionIndex(for: snapshot.settings.defaultAlwaysActiveMode))
        }
    }

    private func selectAlwaysActiveItem() {
        let items = WakeUIContent.alwaysActiveItems
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .configure:
            state.show(.durations(.alwaysActive))
        case .stop:
            state.show(.confirmation(.stopAlwaysActive))
        case .back:
            state.show(.home)
        }
    }

    private func selectAlwaysActiveMode(target: WakeDurationTarget, option: WakeDurationOption, snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.modeItems
        guard items.indices.contains(state.selectedIndex) else { return }
        switch items[state.selectedIndex].action {
        case .mode(let mode):
            guard A11yService.isAccessibilityEnabled() else {
                state.show(.confirmation(.openAccessibility(target)))
                return
            }
            switch target {
            case .alwaysActive:
                if snapshot.alwaysActiveSession == nil {
                    try startAlwaysActive(option: option, mode: mode, replacingActiveSession: false)
                } else {
                    state.show(.confirmation(.replaceAlwaysActive(option, mode)))
                }
            case .all:
                if snapshot.wakeSession == nil, snapshot.alwaysActiveSession == nil {
                    try startAllSessions(option: option, mode: mode, replacingActiveSessions: false)
                } else {
                    state.show(.confirmation(.replaceAll(option, mode)))
                }
            case .wake:
                break
            }
        case .back:
            state.show(.durations(target))
        }
    }

    private func selectSettingsItem(snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.settingsItems(settings: snapshot.settings)
        guard items.indices.contains(state.selectedIndex) else { return }
        switch items[state.selectedIndex].action {
        case .inactivityInterval:
            state.textInput = formatInactivityInterval(snapshot.settings.inactivityInterval)
            state.show(.textInput(.inactivityInterval))
        case .defaultAlwaysActiveMode:
            state.show(.defaultAlwaysActiveMode, selectedIndex: WakeUIContent.modeSelectionIndex(for: snapshot.settings.defaultAlwaysActiveMode))
        case .presets:
            state.show(.presets)
        case .clearData:
            state.show(.confirmation(.clearAllData))
        case .back:
            state.show(.home)
        }
    }

    private func selectDefaultAlwaysActiveMode(now: Date) throws {
        let items = WakeUIContent.modeItems
        guard items.indices.contains(state.selectedIndex) else { return }
        switch items[state.selectedIndex].action {
        case .mode(let mode):
            try settingsManager.setDefaultAlwaysActiveMode(mode)
            state.show(.settings)
            state.showNotification("Default Always Active mode set to \(mode.rawValue). It applies to future sessions.", kind: .success, now: now)
        case .back:
            state.show(.settings)
        }
    }

    private func selectPresetItem(snapshot: WakeUIStatusSnapshot, now: Date) throws {
        let items = WakeUIContent.presetItems(settings: snapshot.settings)
        guard items.indices.contains(state.selectedIndex) else { return }
        switch items[state.selectedIndex].action {
        case .edit(let id):
            state.show(.presetActions(id))
        case .add:
            state.textInput = ""
            state.show(.textInput(.newPresetName))
        case .reset:
            state.show(.confirmation(.resetPresets))
        case .back:
            state.show(.settings)
        }
    }

    private func selectPresetAction(id: UUID, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        guard let preset = snapshot.settings.durationPresets.first(where: { $0.id == id }) else {
            state.show(.presets)
            return
        }
        let items = WakeUIContent.presetActionItems(preset: preset, settings: snapshot.settings)
        guard items.indices.contains(state.selectedIndex) else { return }
        switch items[state.selectedIndex].action {
        case .rename:
            state.textInput = preset.name
            state.show(.textInput(.renamePreset(id)))
        case .changeDuration:
            state.textInput = formatDuration(preset.duration).replacingOccurrences(of: " ", with: "")
            state.show(.textInput(.changePresetDuration(id)))
        case .moveUp:
            try settingsManager.movePreset(id: id, by: -1)
            state.showNotification("Preset moved up.", kind: .success, now: now)
        case .moveDown:
            try settingsManager.movePreset(id: id, by: 1)
            state.showNotification("Preset moved down.", kind: .success, now: now)
        case .delete:
            state.show(.confirmation(.deletePreset(id, preset.name)))
        case .back:
            state.show(.presets)
        }
    }

    private func resolveConfirmation(_ confirmation: WakeConfirmation, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        let items = WakeUIContent.confirmationItems(confirmation)
        guard items.indices.contains(state.selectedIndex), items[state.selectedIndex].action else {
            state.show(returnScreen(for: confirmation, snapshot: snapshot))
            return
        }

        switch confirmation {
        case .stopWake:
            switch try wakeManager.stop() {
            case .stopped:
                state.show(.home)
                state.showNotification("Wake session stopped.", kind: .success, now: now)
            case .notRunning:
                state.show(.home)
                state.showNotification("Wake session is already inactive.", kind: .info, now: now)
            }
        case .replaceWake(let option):
            try startWakeSession(option)
        case .stopAlwaysActive:
            switch try alwaysActiveManager.stop() {
            case .stopped:
                state.show(.home)
                state.showNotification("Always Active stopped.", kind: .success, now: now)
            case .notRunning, .staleStateRemoved:
                state.show(.home)
                state.showNotification("Always Active is already inactive.", kind: .info, now: now)
            }
        case .stopAll:
            stopAllSessions(now: now)
        case .replaceAlwaysActive(let option, let mode):
            try startAlwaysActive(option: option, mode: mode, replacingActiveSession: true)
        case .replaceAll(let option, let mode):
            try startAllSessions(option: option, mode: mode, replacingActiveSessions: true)
        case .openAccessibility(let target):
            state.show(returnScreen(for: target, snapshot: snapshot))
            if A11yService.openAccessibilitySettings() {
                state.showNotification("Enable Terminal in Accessibility, then return here.", kind: .info, now: now)
            } else {
                state.showNotification("Accessibility settings could not be opened.", kind: .error, now: now)
            }
        case .deletePreset(let id, let name):
            try settingsManager.removePreset(id: id)
            state.show(.presets)
            state.showNotification("Preset '\(name)' removed.", kind: .success, now: now)
        case .resetPresets:
            try settingsManager.resetPresets()
            state.show(.presets)
            state.showNotification("Duration presets reset to 1h, 4h, and 8h.", kind: .success, now: now)
        case .clearAllData:
            try dataRemovalManager.removeAllData()
            state.isRunning = false
        }
    }

    private func stopAllSessions(now: Date) {
        var stoppedSession = false
        var failures = [(name: String, error: Error)]()

        do {
            if case .stopped = try wakeManager.stop() {
                stoppedSession = true
            }
        } catch {
            failures.append(("Wake session", error))
        }

        do {
            if case .stopped = try alwaysActiveManager.stop() {
                stoppedSession = true
            }
        } catch {
            failures.append(("Always Active", error))
        }

        state.show(.home)
        if failures.isEmpty {
            let message = stoppedSession ? "All sessions stopped." : "All sessions are already inactive."
            state.showNotification(message, kind: stoppedSession ? .success : .info, now: now)
        } else if failures.count == 1, let failure = failures.first {
            state.showNotification("\(failure.name) could not be stopped: \(failure.error.localizedDescription)", kind: .error, now: now)
        } else {
            state.showNotification("Wake and Always Active could not be stopped.", kind: .error, now: now)
        }
    }

    private func startWakeSession(_ option: WakeDurationOption) throws {
        do {
            try wakeManager.start(duration: option.duration, force: true, onSuccess: {}, onFailure: {})
            state.show(.home)
            state.showNotification("Wake session started.", kind: .success, now: Date())
        } catch {
            state.show(.durations(.wake))
            throw error
        }
    }

    private func startAlwaysActive(option: WakeDurationOption, mode: AlwaysActiveMode, replacingActiveSession: Bool) throws {
        do {
            let settings = try settingsManager.load()
            try alwaysActiveManager.start(mode: mode, duration: option.duration, inactivityInterval: settings.inactivityInterval, replacingActiveSession: replacingActiveSession, onSuccess: {}, onFailure: {})
            state.show(.home)
            state.showNotification("Always Active started in \(mode.rawValue) mode.", kind: .success, now: Date())
        } catch {
            state.show(replacingActiveSession ? .alwaysActive : .home)
            throw error
        }
    }

    private func startAllSessions(option: WakeDurationOption, mode: AlwaysActiveMode, replacingActiveSessions: Bool) throws {
        do {
            let settings = try settingsManager.load()
            try allSessionsManager.start(duration: option.duration, mode: mode, inactivityInterval: settings.inactivityInterval, replacingActiveSessions: replacingActiveSessions)
            state.show(.home)
            state.showNotification("Wake and Always Active started.", kind: .success, now: Date())
        } catch {
            state.show(.home)
            throw error
        }
    }

    private func navigateBack(snapshot: WakeUIStatusSnapshot) {
        switch state.screen {
        case .home:
            break
        case .durations(let target):
            state.show(returnScreen(for: target, snapshot: snapshot))
        case .alwaysActive, .settings:
            state.show(.home)
        case .alwaysActiveMode(let target, _):
            state.show(.durations(target))
        case .defaultAlwaysActiveMode:
            state.show(.settings)
        case .presets:
            state.show(.settings)
        case .presetActions:
            state.show(.presets)
        case .textInput(let input):
            state.show(returnScreen(for: input))
        case .confirmation(let confirmation):
            state.show(returnScreen(for: confirmation, snapshot: snapshot))
        }
    }

    private func returnScreen(for confirmation: WakeConfirmation, snapshot: WakeUIStatusSnapshot) -> WakeUIScreen {
        switch confirmation {
        case .replaceWake:
            .durations(.wake)
        case .stopAlwaysActive, .replaceAlwaysActive:
            .alwaysActive
        case .openAccessibility(let target):
            returnScreen(for: target, snapshot: snapshot)
        case .deletePreset:
            .presets
        case .resetPresets:
            .presets
        case .clearAllData:
            .settings
        case .stopWake, .stopAll, .replaceAll:
            .home
        }
    }

    private func returnScreen(for target: WakeDurationTarget, snapshot: WakeUIStatusSnapshot) -> WakeUIScreen {
        guard target == .alwaysActive, snapshot.alwaysActiveSession != nil else { return .home }
        return .alwaysActive
    }

    private func returnScreen(for input: WakeTextInput) -> WakeUIScreen {
        switch input {
        case .customDuration(let target):
            .durations(target)
        case .inactivityInterval:
            .settings
        case .newPresetName, .newPresetDuration:
            .presets
        case .renamePreset(let id), .changePresetDuration(let id):
            .presetActions(id)
        }
    }

    private func itemCount(for screen: WakeUIScreen, snapshot: WakeUIStatusSnapshot) -> Int {
        switch screen {
        case .home:
            return WakeUIContent.homeItems(snapshot: snapshot).count
        case .durations:
            return WakeUIContent.durationItems(settings: snapshot.settings).count
        case .alwaysActive:
            return WakeUIContent.alwaysActiveItems.count
        case .alwaysActiveMode, .defaultAlwaysActiveMode:
            return WakeUIContent.modeItems.count
        case .settings:
            return WakeUIContent.settingsItems(settings: snapshot.settings).count
        case .presets:
            return WakeUIContent.presetItems(settings: snapshot.settings).count
        case .presetActions(let id):
            guard let preset = snapshot.settings.durationPresets.first(where: { $0.id == id }) else { return 0 }
            return WakeUIContent.presetActionItems(preset: preset, settings: snapshot.settings).count
        case .confirmation:
            return 2
        case .textInput:
            return 0
        }
    }
}

struct WakeFullScreenRenderer {
    private let noora: Noora
    private let colorsEnabled: Bool
    private let clockFormatter: DateFormatter

    init(colorsEnabled: Bool = ProcessInfo.processInfo.environment["NO_COLOR"] == nil) {
        self.colorsEnabled = colorsEnabled
        noora = Noora(theme: Self.theme, terminal: WakeNooraTerminal(isColored: colorsEnabled))
        clockFormatter = DateFormatter()
        clockFormatter.dateFormat = "HH:mm:ss"
    }

    func render(state: WakeUIState, snapshot: WakeUIStatusSnapshot, size: TerminalSize, now: Date) -> String {
        let width = max(size.columns - 1, 1)
        let height = max(size.rows, 1)
        guard width >= 48, height >= 16 else {
            return renderSmallTerminal(width: width, height: height)
        }

        var lines = headerLines(snapshot: snapshot, width: width, now: now)
        let mainHeight = max(height - lines.count - 1, 1)
        var mainLines = screenLines(state: state, snapshot: snapshot, width: width, height: mainHeight, now: now)
        mainLines = Array(mainLines.prefix(mainHeight))
        while mainLines.count < mainHeight {
            mainLines.append("")
        }
        lines.append(contentsOf: mainLines)
        lines.append(footerLine(for: state.screen, width: width))

        return lines.prefix(height).map { "\(truncateStyledLine($0, width: width))\u{001B}[K" }.joined(separator: "\r\n")
    }

    private func headerLines(snapshot: WakeUIStatusSnapshot, width: Int, now: Date) -> [String] {
        let title = primary("WakeMyMac")
        let clock = success("LIVE") + muted(" · \(clockFormatter.string(from: now))")
        return [
            aligned(left: title, leftPlain: "WakeMyMac", right: clock, rightPlain: "LIVE · \(clockFormatter.string(from: now))", width: width),
            "",
            statusLine(label: "Wake session", active: snapshot.wakeSession != nil, detail: wakeStatusDetail(snapshot.wakeSession), width: width),
            statusLine(label: "Always Active", active: snapshot.alwaysActiveSession != nil, detail: alwaysActiveStatusDetail(snapshot.alwaysActiveSession, now: now), width: width),
            muted(String(repeating: "─", count: width))
        ]
    }

    private func screenLines(state: WakeUIState, snapshot: WakeUIStatusSnapshot, width: Int, height: Int, now: Date) -> [String] {
        var lines: [String]
        switch state.screen {
        case .home:
            lines = menuLines(title: "What would you like to do?", items: WakeUIContent.homeItems(snapshot: snapshot), selectedIndex: state.selectedIndex, width: width, height: height)
        case .durations(let target):
            lines = menuLines(title: durationTitle(target: target, snapshot: snapshot), items: WakeUIContent.durationItems(settings: snapshot.settings), selectedIndex: state.selectedIndex, width: width, height: height)
        case .alwaysActive:
            lines = menuLines(title: "Always Active", items: WakeUIContent.alwaysActiveItems, selectedIndex: state.selectedIndex, width: width, height: height)
        case .alwaysActiveMode:
            lines = menuLines(title: "Choose Always Active mode", items: WakeUIContent.modeItems, selectedIndex: state.selectedIndex, width: width, height: height)
        case .defaultAlwaysActiveMode:
            lines = menuLines(title: "Default Always Active mode", items: WakeUIContent.modeItems, selectedIndex: state.selectedIndex, width: width, height: height)
        case .settings:
            lines = menuLines(title: "Settings", items: WakeUIContent.settingsItems(settings: snapshot.settings), selectedIndex: state.selectedIndex, width: width, height: height)
        case .presets:
            lines = menuLines(title: "Duration presets", items: WakeUIContent.presetItems(settings: snapshot.settings), selectedIndex: state.selectedIndex, width: width, height: height)
        case .presetActions(let id):
            if let preset = snapshot.settings.durationPresets.first(where: { $0.id == id }) {
                lines = menuLines(title: "Edit \(preset.name)", items: WakeUIContent.presetActionItems(preset: preset, settings: snapshot.settings), selectedIndex: state.selectedIndex, width: width, height: height)
            } else {
                lines = []
            }
        case .confirmation(let confirmation):
            lines = confirmationLines(confirmation, selectedIndex: state.selectedIndex, width: width)
        case .textInput(let input):
            lines = textInputLines(input: input, value: state.textInput, width: width)
        }

        if let notification = state.visibleNotification(at: now) {
            lines.append("")
            lines.append(notificationLine(notification))
        }
        return lines
    }

    private func durationTitle(target: WakeDurationTarget, snapshot: WakeUIStatusSnapshot) -> String {
        switch target {
        case .wake:
            snapshot.wakeSession == nil ? "Start wake session" : "Change wake duration"
        case .alwaysActive:
            snapshot.alwaysActiveSession == nil ? "Start Always Active" : "Change Always Active"
        case .all:
            snapshot.wakeSession == nil && snapshot.alwaysActiveSession == nil ? "Start all sessions" : "Restart all sessions"
        }
    }

    private func menuLines<Action>(title: String, items: [WakeMenuItem<Action>], selectedIndex: Int, width: Int, height: Int) -> [String] {
        var lines = ["", "  \(primary(title))", ""]
        let descriptionLines = items.indices.contains(selectedIndex)
            ? wrap(items[selectedIndex].description, width: max(width - 4, 1))
            : []
        let availableItemRows = max(height - descriptionLines.count - 6, 1)
        let startIndex = min(max(selectedIndex - availableItemRows / 2, 0), max(items.count - availableItemRows, 0))
        let endIndex = min(startIndex + availableItemRows, items.count)
        for index in startIndex ..< endIndex {
            let item = items[index]
            if index == selectedIndex {
                lines.append(selectedRow(item.label, width: width))
            } else {
                lines.append("    \(item.label)")
            }
        }

        if items.indices.contains(selectedIndex) {
            lines.append("")
            lines.append("  \(primary("Selected"))")
            lines.append(contentsOf: descriptionLines.map { "  \(muted($0))" })
        }
        return lines
    }

    private func confirmationLines(_ confirmation: WakeConfirmation, selectedIndex: Int, width: Int) -> [String] {
        let copy = WakeUIContent.confirmationCopy(confirmation)
        let items = WakeUIContent.confirmationItems(confirmation)
        var lines = ["", "  \(primary(copy.title))", ""]
        lines.append(contentsOf: wrap(copy.question, width: max(width - 4, 1)).map { "  \($0)" })
        lines.append("")
        for (index, item) in items.enumerated() {
            lines.append(index == selectedIndex ? selectedRow(item.label, width: width) : "    \(item.label)")
        }
        lines.append("")
        lines.append("  \(muted(items[selectedIndex].description))")
        return lines
    }

    private func textInputLines(input: WakeTextInput, value: String, width: Int) -> [String] {
        [
            "",
            "  \(primary(input.title))",
            "",
            "  \(input.instructions)",
            "",
            selectedRow("\(input.fieldLabel)  \(value)█", width: width),
            "",
            "  \(muted("Enter confirm · Backspace edit · Esc back"))"
        ]
    }

    private func renderSmallTerminal(width: Int, height: Int) -> String {
        var lines = [primary("WakeMyMac"), "", "Terminal is too small.", muted("Resize to at least 48 × 16.")]
        while lines.count < height {
            lines.append("")
        }
        return lines.prefix(height).map { "\(truncateStyledLine($0, width: width))\u{001B}[K" }.joined(separator: "\r\n")
    }

    private func statusLine(label: String, active: Bool, detail: String, width: Int) -> String {
        let labelPlain = pad(label, to: 15)
        let statePlain = pad(active ? "● ACTIVE" : "○ INACTIVE", to: 12)
        let prefixWidth = 2 + labelPlain.count + 1 + statePlain.count + 1
        let detailPlain = truncate(detail, to: max(width - prefixWidth, 0))
        let stateText = active ? success(statePlain) : muted(statePlain)
        return "  \(muted(labelPlain)) \(stateText) \(muted(detailPlain))"
    }

    private func wakeStatusDetail(_ session: (startTime: Date, remainingTime: TimeInterval?)?) -> String {
        guard let session else { return "No active wake session" }
        return session.remainingTime.map { "\(formatLiveDuration($0)) remaining" } ?? "Until stopped"
    }

    private func alwaysActiveStatusDetail(_ session: AlwaysActiveSession?, now: Date) -> String {
        guard let session else { return "Input simulation is off" }
        let timing: String
        if let duration = session.duration {
            timing = "\(formatLiveDuration(max(duration - now.timeIntervalSince(session.startTime), 0))) remaining"
        } else {
            timing = "until stopped"
        }
        return "\(session.mode.rawValue) · \(timing) · \(formatInactivityInterval(session.inactivityInterval)) interval"
    }

    private func notificationLine(_ notification: WakeNotification) -> String {
        switch notification.kind {
        case .success:
            "  \(success("SUCCESS"))  \(notification.message)"
        case .info:
            "  \(primary("INFO"))  \(notification.message)"
        case .error:
            "  \(danger("ERROR"))  \(notification.message)"
        }
    }

    private func footerLine(for screen: WakeUIScreen, width: Int) -> String {
        let plain = switch screen {
        case .home:
            "↑↓/j k move · Enter select · Ctrl-C quit"
        case .textInput:
            "Type value · Enter confirm · Esc back · Ctrl-C quit"
        default:
            "↑↓/j k move · Enter select · Esc back · Ctrl-C quit"
        }
        return muted("  \(truncate(plain, to: max(width - 2, 0)))")
    }

    private func selectedRow(_ label: String, width: Int) -> String {
        let content = pad(truncate("  > \(label)", to: width), to: width)
        if colorsEnabled {
            return "\u{001B}[48;2;52;42;78m\u{001B}[38;2;255;255;255m\u{001B}[1m\(content)\u{001B}[0m"
        }
        return "\u{001B}[7m\(content)\u{001B}[0m"
    }

    private func primary(_ text: String) -> String {
        noora.format(TerminalText("\(.primary(text))"))
    }

    private func success(_ text: String) -> String {
        noora.format(TerminalText("\(.success(text))"))
    }

    private func danger(_ text: String) -> String {
        noora.format(TerminalText("\(.danger(text))"))
    }

    private func muted(_ text: String) -> String {
        noora.format(TerminalText("\(.muted(text))"))
    }

    private func aligned(left: String, leftPlain: String, right: String, rightPlain: String, width: Int) -> String {
        let gap = max(width - leftPlain.count - rightPlain.count, 1)
        return "\(left)\(String(repeating: " ", count: gap))\(right)"
    }

    private func pad(_ text: String, to width: Int) -> String {
        let truncated = truncate(text, to: width)
        return truncated + String(repeating: " ", count: max(width - truncated.count, 0))
    }

    private func truncate(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        guard text.count > width else { return text }
        guard width > 1 else { return String(text.prefix(width)) }
        return String(text.prefix(width - 1)) + "…"
    }

    private func truncateStyledLine(_ line: String, width: Int) -> String {
        enum EscapeState {
            case none
            case started
            case controlSequence
        }

        guard width > 0 else { return "" }
        var result = ""
        var visibleWidth = 0
        var escapeState = EscapeState.none
        var wasTruncated = false

        for scalar in line.unicodeScalars {
            switch escapeState {
            case .none:
                if scalar.value == 0x1B {
                    result.unicodeScalars.append(scalar)
                    escapeState = .started
                } else if visibleWidth < width {
                    result.unicodeScalars.append(scalar)
                    visibleWidth += 1
                } else {
                    wasTruncated = true
                }
            case .started:
                result.unicodeScalars.append(scalar)
                escapeState = scalar == "[" ? .controlSequence : .none
            case .controlSequence:
                result.unicodeScalars.append(scalar)
                if (0x40 ... 0x7E).contains(scalar.value) {
                    escapeState = .none
                }
            }
        }

        return wasTruncated ? "\(result)\u{001B}[0m" : result
    }

    private func wrap(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [] }
        var lines = [String]()
        var currentLine = ""
        for word in text.split(separator: " ").map(String.init) {
            let candidate = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            if candidate.count <= width {
                currentLine = candidate
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = truncate(word, to: width)
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
    }

    private static let theme = Theme(primary: "A78BFA", secondary: "C084FC", muted: "8B949E", accent: "F0A35E", danger: "FF6B6B", success: "3DDC84", info: "58A6FF", selectedRowText: "FFFFFF", selectedRowBackground: "342A4E")
}

struct WakeUIStatusSnapshot {
    var wakeSession: (startTime: Date, remainingTime: TimeInterval?)?
    var alwaysActiveSession: AlwaysActiveSession?
    var settings: WakeSettings

    init(wakeSession: (startTime: Date, remainingTime: TimeInterval?)? = nil, alwaysActiveSession: AlwaysActiveSession? = nil, settings: WakeSettings = WakeSettings()) {
        self.wakeSession = wakeSession
        self.alwaysActiveSession = alwaysActiveSession
        self.settings = settings
    }
}

struct WakeUIState {
    var screen = WakeUIScreen.home
    var selectedIndex = 0
    var textInput = ""
    var notification: WakeNotification?
    var isRunning = true

    mutating func show(_ screen: WakeUIScreen) {
        self.screen = screen
        switch screen {
        case .confirmation(.stopAlwaysActive), .confirmation(.stopAll), .confirmation(.deletePreset), .confirmation(.resetPresets), .confirmation(.clearAllData):
            selectedIndex = 1
        default:
            selectedIndex = 0
        }
    }

    mutating func show(_ screen: WakeUIScreen, selectedIndex: Int) {
        show(screen)
        self.selectedIndex = selectedIndex
    }

    mutating func moveSelection(by offset: Int, itemCount: Int) {
        guard itemCount > 0 else { return }
        selectedIndex = (selectedIndex + offset + itemCount) % itemCount
    }

    mutating func normalizeSelection(itemCount: Int) {
        guard itemCount > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex, 0), itemCount - 1)
    }

    mutating func reconcile(with snapshot: WakeUIStatusSnapshot) {
        guard screen == .alwaysActive, snapshot.alwaysActiveSession == nil else { return }
        show(.home)
    }

    mutating func showNotification(_ message: String, kind: WakeNotification.Kind, now: Date) {
        notification = WakeNotification(message: message, kind: kind, expiresAt: now.addingTimeInterval(4))
    }

    func visibleNotification(at date: Date) -> WakeNotification? {
        guard let notification, notification.expiresAt > date else { return nil }
        return notification
    }
}

enum WakeUIScreen: Equatable {
    case home
    case durations(WakeDurationTarget)
    case alwaysActive
    case alwaysActiveMode(WakeDurationTarget, WakeDurationOption)
    case defaultAlwaysActiveMode
    case settings
    case presets
    case presetActions(UUID)
    case confirmation(WakeConfirmation)
    case textInput(WakeTextInput)
}

enum WakeConfirmation: Equatable {
    case stopWake
    case replaceWake(WakeDurationOption)
    case stopAlwaysActive
    case stopAll
    case replaceAlwaysActive(WakeDurationOption, AlwaysActiveMode)
    case replaceAll(WakeDurationOption, AlwaysActiveMode)
    case openAccessibility(WakeDurationTarget)
    case deletePreset(UUID, String)
    case resetPresets
    case clearAllData
}

enum WakeDurationTarget: Equatable {
    case wake
    case alwaysActive
    case all
}

enum WakeTextInput: Equatable {
    case customDuration(WakeDurationTarget)
    case inactivityInterval
    case newPresetName
    case newPresetDuration(name: String)
    case renamePreset(UUID)
    case changePresetDuration(UUID)

    var title: String {
        switch self {
        case .customDuration:
            "Custom duration"
        case .inactivityInterval:
            "Inactivity interval"
        case .newPresetName:
            "New preset name"
        case .newPresetDuration(let name):
            "Duration for \(name)"
        case .renamePreset:
            "Rename preset"
        case .changePresetDuration:
            "Change preset duration"
        }
    }

    var instructions: String {
        switch self {
        case .newPresetName, .renamePreset:
            "Enter a unique name with no more than 40 characters."
        case .inactivityInterval:
            "Enter hours, minutes, and seconds, for example 3m45s."
        default:
            "Enter hours and minutes, for example 45m or 1h30m."
        }
    }

    var fieldLabel: String {
        switch self {
        case .newPresetName, .renamePreset:
            "Name"
        default:
            "Duration"
        }
    }

    var maximumLength: Int {
        switch self {
        case .newPresetName, .renamePreset:
            40
        case .inactivityInterval:
            24
        default:
            16
        }
    }

    func accepts(_ character: Character) -> Bool {
        switch self {
        case .newPresetName, .renamePreset:
            true
        case .inactivityInterval:
            character.isNumber || character == "h" || character == "m" || character == "s" || character == "H" || character == "M" || character == "S" || character == " "
        default:
            character.isNumber || character == "h" || character == "m" || character == "H" || character == "M"
        }
    }
}

enum WakeDurationOption: Equatable {
    case timed(TimeInterval)
    case indefinite

    var duration: TimeInterval? {
        switch self {
        case .timed(let duration):
            duration
        case .indefinite:
            nil
        }
    }
}

struct WakeNotification {
    enum Kind {
        case success
        case info
        case error
    }

    let message: String
    let kind: Kind
    let expiresAt: Date
}

struct WakeMenuItem<Action> {
    let action: Action
    let label: String
    let description: String
}

enum WakeHomeAction {
    case manageWake
    case stopWake
    case startAll
    case startAlwaysActive
    case manageAlwaysActive
    case stopAll
    case settings
    case exit
}

enum WakeDurationAction {
    case duration(WakeDurationOption)
    case custom
    case back
}

enum WakeAlwaysActiveAction {
    case configure
    case stop
    case back
}

enum WakeModeAction {
    case mode(AlwaysActiveMode)
    case back
}

enum WakeSettingsAction {
    case inactivityInterval
    case defaultAlwaysActiveMode
    case presets
    case clearData
    case back
}

enum WakePresetAction {
    case edit(UUID)
    case add
    case reset
    case back
}

enum WakePresetEditAction {
    case rename
    case changeDuration
    case moveUp
    case moveDown
    case delete
    case back
}

enum WakeUIContent {
    static func homeItems(snapshot: WakeUIStatusSnapshot) -> [WakeMenuItem<WakeHomeAction>] {
        var items = [WakeMenuItem(action: WakeHomeAction.manageWake, label: snapshot.wakeSession == nil ? "Start wake session" : "Change wake duration", description: snapshot.wakeSession == nil ? "Keep the display awake for a preset or custom duration." : "Replace the current wake session with a new duration.")]
        if snapshot.wakeSession != nil {
            items.append(WakeMenuItem(action: .stopWake, label: "Stop wake session", description: "Return display sleep behavior to the normal macOS settings."))
        }
        let allAreInactive = snapshot.wakeSession == nil && snapshot.alwaysActiveSession == nil
        if snapshot.alwaysActiveSession == nil {
            items.append(WakeMenuItem(action: .startAlwaysActive, label: "Start Always Active", description: "Choose a duration and keyboard or mouse activity simulation."))
        } else {
            items.append(WakeMenuItem(action: .manageAlwaysActive, label: "Manage Always Active", description: "Change or stop keyboard and mouse activity simulation."))
        }
        items.append(WakeMenuItem(action: .startAll, label: allAreInactive ? "Start all sessions" : "Restart all sessions", description: "Start Wake and Always Active together for one shared duration."))
        if snapshot.wakeSession != nil || snapshot.alwaysActiveSession != nil {
            items.append(WakeMenuItem(action: .stopAll, label: "Stop all sessions", description: "Stop both Wake and Always Active in one action."))
        }
        items.append(contentsOf: [
            WakeMenuItem(action: .settings, label: "Settings", description: "Customize Always Active defaults and duration presets."),
            WakeMenuItem(action: .exit, label: "Exit", description: "Close WakeMyMac and restore the previous terminal screen.")
        ])
        return items
    }

    static func durationItems(settings: WakeSettings) -> [WakeMenuItem<WakeDurationAction>] {
        var items = [WakeMenuItem(action: WakeDurationAction.duration(.indefinite), label: "Indefinite", description: "Run until you stop the session.")]
        items.append(contentsOf: settings.durationPresets.map { preset in
            WakeMenuItem(action: .duration(.timed(preset.duration)), label: preset.name, description: "Run for \(formatDuration(preset.duration)).")
        })
        items.append(WakeMenuItem(action: .custom, label: "Custom", description: "Enter a one-off duration such as 45m or 1h30m."))
        items.append(WakeMenuItem(action: .back, label: "Back", description: "Return to the previous menu."))
        return items
    }

    static let alwaysActiveItems = [
        WakeMenuItem(action: WakeAlwaysActiveAction.configure, label: "Change Always Active", description: "Choose a new duration and keyboard or mouse mode."),
        WakeMenuItem(action: .stop, label: "Stop Always Active", description: "Stop simulating input after idle periods."),
        WakeMenuItem(action: .back, label: "Back", description: "Return to the WakeMyMac actions.")
    ]

    static let modeItems = [
        WakeMenuItem(action: WakeModeAction.mode(.keyboard), label: "Keyboard (recommended)", description: "Press and release Shift after the Inactivity interval. Keeps the pointer still and does not type text; recommended for most setups."),
        WakeMenuItem(action: WakeModeAction.mode(.mouse), label: "Mouse", description: "Move the pointer by one unit after the Inactivity interval. Use if keyboard activity does not prevent dimming; may affect hover-sensitive interfaces."),
        WakeMenuItem(action: WakeModeAction.back, label: "Back", description: "Return to the previous menu.")
    ]

    static func modeSelectionIndex(for mode: AlwaysActiveMode) -> Int {
        switch mode {
        case .keyboard:
            0
        case .mouse:
            1
        }
    }

    static func settingsItems(settings: WakeSettings) -> [WakeMenuItem<WakeSettingsAction>] {
        [
            WakeMenuItem(action: .inactivityInterval, label: "Inactivity interval  \(formatInactivityInterval(settings.inactivityInterval))", description: "Set how long Always Active waits after real user input."),
            WakeMenuItem(action: .defaultAlwaysActiveMode, label: "Default Always Active mode  \(settings.defaultAlwaysActiveMode.rawValue.capitalized)", description: "Choose the preselected mode for future Always Active sessions."),
            WakeMenuItem(action: .presets, label: "Duration presets  \(settings.durationPresets.count)", description: "Add, edit, reorder, delete, or reset named duration choices."),
            WakeMenuItem(action: .clearData, label: "Remove all saved data", description: "Stop all sessions, delete ~/.wake and legacy session state, then close WakeMyMac."),
            WakeMenuItem(action: .back, label: "Back", description: "Return to the WakeMyMac actions.")
        ]
    }

    static func presetItems(settings: WakeSettings) -> [WakeMenuItem<WakePresetAction>] {
        var items = settings.durationPresets.map { preset in
            WakeMenuItem(action: WakePresetAction.edit(preset.id), label: "\(preset.name)  \(formatDuration(preset.duration))", description: "Edit, reorder, or delete this timed preset.")
        }
        items.append(WakeMenuItem(action: .add, label: "Add preset", description: "Create a named duration such as Workday."))
        items.append(WakeMenuItem(action: .reset, label: "Reset presets", description: "Replace timed presets with the default 1h, 4h, and 8h list."))
        items.append(WakeMenuItem(action: .back, label: "Back", description: "Return to Settings."))
        return items
    }

    static func presetActionItems(preset: WakeDurationPreset, settings: WakeSettings) -> [WakeMenuItem<WakePresetEditAction>] {
        var items = [
            WakeMenuItem(action: WakePresetEditAction.rename, label: "Rename", description: "Change the display name for \(preset.name)."),
            WakeMenuItem(action: WakePresetEditAction.changeDuration, label: "Change duration", description: "Current duration: \(formatDuration(preset.duration)).")
        ]
        if settings.durationPresets.first?.id != preset.id {
            items.append(WakeMenuItem(action: .moveUp, label: "Move up", description: "Move this preset one position earlier."))
        }
        if settings.durationPresets.last?.id != preset.id {
            items.append(WakeMenuItem(action: .moveDown, label: "Move down", description: "Move this preset one position later."))
        }
        items.append(WakeMenuItem(action: .delete, label: "Delete", description: "Remove this preset from every duration picker."))
        items.append(WakeMenuItem(action: .back, label: "Back", description: "Return to the duration preset list."))
        return items
    }

    static func confirmationCopy(_ confirmation: WakeConfirmation) -> (title: String, question: String, confirmLabel: String, confirmDescription: String) {
        switch confirmation {
        case .stopWake:
            ("Stop wake session", "Allow the display to use its normal macOS sleep settings again?", "Stop wake session", "Stop the current wake daemon.")
        case .replaceWake(let option):
            ("Change wake duration", "Replace the current wake session with \(option.duration.map(formatLiveDuration) ?? "an unlimited duration")?", "Replace session", "Stop the current session and start the new duration.")
        case .stopAlwaysActive:
            ("Stop Always Active", "Stop simulating keyboard or mouse activity?", "Stop Always Active", "Stop the input-simulation daemon.")
        case .stopAll:
            ("Stop all sessions", "Stop both the Wake session and Always Active?", "Stop all sessions", "Shut down every active WakeMyMac session.")
        case .replaceAlwaysActive(let option, let mode):
            ("Change Always Active", "Replace the current session with \(mode.rawValue) mode for \(option.duration.map(formatDuration) ?? "an indefinite duration")?", "Replace session", "Restart Always Active with the selected settings.")
        case .replaceAll(let option, let mode):
            ("Restart all sessions", "Replace active sessions and start Wake plus \(mode.rawValue) Always Active for \(option.duration.map(formatDuration) ?? "an indefinite duration")?", "Restart all", "Replace active sessions with one coordinated start.")
        case .openAccessibility:
            ("Accessibility required", "Always Active needs Accessibility access for Terminal.", "Open Settings", "Open Privacy & Security > Accessibility.")
        case .deletePreset(_, let name):
            ("Delete duration preset", "Remove '\(name)' from every duration picker?", "Delete preset", "Permanently remove this named preset.")
        case .resetPresets:
            ("Reset duration presets", "Replace all timed presets with 1h, 4h, and 8h?", "Reset presets", "Discard custom preset names, durations, and ordering.")
        case .clearAllData:
            ("Remove all saved data", DataRemovalCopy.warning, "Remove all data", "Stop sessions, permanently delete saved data, and close WakeMyMac.")
        }
    }

    static func confirmationItems(_ confirmation: WakeConfirmation) -> [WakeMenuItem<Bool>] {
        let copy = confirmationCopy(confirmation)
        let cancel = WakeMenuItem(action: false, label: "Cancel", description: "Keep the current state.")
        let confirm = WakeMenuItem(action: true, label: copy.confirmLabel, description: copy.confirmDescription)
        switch confirmation {
        case .stopAlwaysActive, .stopAll, .deletePreset, .resetPresets, .clearAllData:
            return [confirm, cancel]
        default:
            return [cancel, confirm]
        }
    }
}

func formatLiveDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(Int(interval.rounded(.down)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
    }
    return String(format: "%dm %02ds", minutes, seconds)
}
