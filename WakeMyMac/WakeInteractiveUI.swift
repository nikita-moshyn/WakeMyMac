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
    private let terminalSession: WakeTerminalSession
    private let renderer: WakeFullScreenRenderer
    private var state = WakeUIState()

    init(wakeManager: WakeManager = .current, alwaysActiveManager: AlwaysActiveManager = .current, terminalSession: WakeTerminalSession = WakeTerminalSession(), renderer: WakeFullScreenRenderer = WakeFullScreenRenderer()) {
        self.wakeManager = wakeManager
        self.alwaysActiveManager = alwaysActiveManager
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
        return WakeUIStatusSnapshot(wakeSession: try wakeManager.status(), alwaysActiveSession: try alwaysActiveManager.status())
    }

    private func handle(key: WakeTerminalKey, snapshot: WakeUIStatusSnapshot, now: Date) throws {
        if key == .interrupt {
            state.isRunning = false
            return
        }

        if case .customDuration = state.screen {
            try handleCustomDurationKey(key, snapshot: snapshot)
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
            navigateBack()
        default:
            break
        }
    }

    private func handleCustomDurationKey(_ key: WakeTerminalKey, snapshot: WakeUIStatusSnapshot) throws {
        switch key {
        case .escape:
            state.show(.durations)
        case .backspace:
            if !state.customDuration.isEmpty {
                state.customDuration.removeLast()
            }
        case .enter:
            let normalizedInput = state.customDuration.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let duration = parseDuration(normalizedInput) else {
                state.showNotification("Enter a duration such as 45m, 1h, or 1h30m.", kind: .error, now: Date())
                return
            }
            let option = WakeDurationOption.timed(duration)
            if snapshot.wakeSession == nil {
                try startWakeSession(option)
            } else {
                state.show(.confirmation(.replaceWake(option)))
            }
        case .printable(let character):
            if character.isNumber || character == "h" || character == "m" {
                state.customDuration.append(character)
            }
        default:
            break
        }
    }

    private func selectCurrentItem(snapshot: WakeUIStatusSnapshot, now: Date) throws {
        switch state.screen {
        case .home:
            try selectHomeItem(snapshot: snapshot)
        case .durations:
            try selectDuration(snapshot: snapshot)
        case .alwaysActive:
            try selectAlwaysActiveItem(snapshot: snapshot)
        case .details:
            state.show(.home)
        case .confirmation(let confirmation):
            try resolveConfirmation(confirmation, now: now)
        case .customDuration:
            break
        }
    }

    private func selectHomeItem(snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.homeItems(snapshot: snapshot)
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .manageWake:
            state.show(.durations)
        case .stopWake:
            state.show(.confirmation(.stopWake))
        case .manageAlwaysActive:
            state.show(.alwaysActive)
        case .stopAll:
            state.show(.confirmation(.stopAll))
        case .details:
            state.show(.details)
        case .exit:
            state.isRunning = false
        }
    }

    private func selectDuration(snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.durationItems
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .duration(let option):
            if snapshot.wakeSession == nil {
                try startWakeSession(option)
            } else {
                state.show(.confirmation(.replaceWake(option)))
            }
        case .custom:
            state.customDuration = ""
            state.show(.customDuration)
        case .back:
            state.show(.home)
        }
    }

    private func selectAlwaysActiveItem(snapshot: WakeUIStatusSnapshot) throws {
        let items = WakeUIContent.alwaysActiveItems(snapshot: snapshot)
        guard items.indices.contains(state.selectedIndex) else { return }

        switch items[state.selectedIndex].action {
        case .start(let mode):
            guard A11yService.isAccessibilityEnabled() else {
                state.show(.confirmation(.openAccessibility(mode)))
                return
            }
            if snapshot.alwaysActiveSession == nil {
                try startAlwaysActive(mode: mode, replacingActiveSession: false)
            } else {
                state.show(.confirmation(.replaceAlwaysActive(mode)))
            }
        case .stop:
            state.show(.confirmation(.stopAlwaysActive))
        case .details:
            state.show(.details)
        case .back:
            state.show(.home)
        }
    }

    private func resolveConfirmation(_ confirmation: WakeConfirmation, now: Date) throws {
        let items = WakeUIContent.confirmationItems(confirmation)
        guard items.indices.contains(state.selectedIndex), items[state.selectedIndex].action else {
            state.show(returnScreen(for: confirmation))
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
                state.show(.alwaysActive)
                state.showNotification("Always Active stopped.", kind: .success, now: now)
            case .notRunning, .staleStateRemoved:
                state.show(.alwaysActive)
                state.showNotification("Always Active is already inactive.", kind: .info, now: now)
            }
        case .stopAll:
            stopAllSessions(now: now)
        case .replaceAlwaysActive(let mode):
            try startAlwaysActive(mode: mode, replacingActiveSession: true)
        case .openAccessibility:
            state.show(.alwaysActive)
            if A11yService.openAccessibilitySettings() {
                state.showNotification("Enable Terminal in Accessibility, then return here.", kind: .info, now: now)
            } else {
                state.showNotification("Accessibility settings could not be opened.", kind: .error, now: now)
            }
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
            state.show(.durations)
            throw error
        }
    }

    private func startAlwaysActive(mode: AlwaysActiveMode, replacingActiveSession: Bool) throws {
        do {
            try alwaysActiveManager.start(mode: mode, replacingActiveSession: replacingActiveSession, onSuccess: {}, onFailure: {})
            state.show(.home)
            state.showNotification("Always Active started in \(mode.rawValue) mode.", kind: .success, now: Date())
        } catch {
            state.show(.alwaysActive)
            throw error
        }
    }

    private func navigateBack() {
        switch state.screen {
        case .home:
            break
        case .durations, .alwaysActive, .details:
            state.show(.home)
        case .customDuration:
            state.show(.durations)
        case .confirmation(let confirmation):
            state.show(returnScreen(for: confirmation))
        }
    }

    private func returnScreen(for confirmation: WakeConfirmation) -> WakeUIScreen {
        switch confirmation {
        case .replaceWake:
            .durations
        case .stopAlwaysActive, .replaceAlwaysActive, .openAccessibility:
            .alwaysActive
        case .stopWake, .stopAll:
            .home
        }
    }

    private func itemCount(for screen: WakeUIScreen, snapshot: WakeUIStatusSnapshot) -> Int {
        switch screen {
        case .home:
            WakeUIContent.homeItems(snapshot: snapshot).count
        case .durations:
            WakeUIContent.durationItems.count
        case .alwaysActive:
            WakeUIContent.alwaysActiveItems(snapshot: snapshot).count
        case .confirmation:
            2
        case .details, .customDuration:
            0
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
        var mainLines = screenLines(state: state, snapshot: snapshot, width: width, now: now)
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

    private func screenLines(state: WakeUIState, snapshot: WakeUIStatusSnapshot, width: Int, now: Date) -> [String] {
        var lines: [String]
        switch state.screen {
        case .home:
            lines = menuLines(title: "What would you like to do?", items: WakeUIContent.homeItems(snapshot: snapshot), selectedIndex: state.selectedIndex, width: width)
        case .durations:
            lines = menuLines(title: snapshot.wakeSession == nil ? "Start wake session" : "Change wake duration", items: WakeUIContent.durationItems, selectedIndex: state.selectedIndex, width: width)
        case .alwaysActive:
            lines = menuLines(title: "Always Active", items: WakeUIContent.alwaysActiveItems(snapshot: snapshot), selectedIndex: state.selectedIndex, width: width)
        case .details:
            lines = detailsLines(snapshot: snapshot, width: width, now: now)
        case .confirmation(let confirmation):
            lines = confirmationLines(confirmation, selectedIndex: state.selectedIndex, width: width)
        case .customDuration:
            lines = customDurationLines(input: state.customDuration, width: width)
        }

        if let notification = state.visibleNotification(at: now) {
            lines.append("")
            lines.append(notificationLine(notification))
        }
        return lines
    }

    private func menuLines<Action>(title: String, items: [WakeMenuItem<Action>], selectedIndex: Int, width: Int) -> [String] {
        var lines = ["", "  \(primary(title))", ""]
        for (index, item) in items.enumerated() {
            if index == selectedIndex {
                lines.append(selectedRow(item.label, width: width))
            } else {
                lines.append("    \(item.label)")
            }
        }

        if items.indices.contains(selectedIndex) {
            lines.append("")
            lines.append("  \(primary("Selected"))")
            lines.append(contentsOf: wrap(items[selectedIndex].description, width: max(width - 4, 1)).map { "  \(muted($0))" })
        }
        return lines
    }

    private func detailsLines(snapshot: WakeUIStatusSnapshot, width: Int, now: Date) -> [String] {
        var lines = ["", "  \(primary("Session details"))", ""]

        lines.append("  \(strong("Wake session"))  \(snapshot.wakeSession == nil ? muted("INACTIVE") : success("ACTIVE"))")
        if let wakeSession = snapshot.wakeSession {
            lines.append("    \(muted("Started"))     \(wakeSession.startTime.formatted())")
            lines.append("    \(muted("Remaining"))   \(wakeSession.remainingTime.map(formatLiveDuration) ?? "Until stopped")")
        } else {
            lines.append("    \(muted("No display-sleep assertion is running."))")
        }

        lines.append("")
        lines.append("  \(strong("Always Active"))  \(snapshot.alwaysActiveSession == nil ? muted("INACTIVE") : success("ACTIVE"))")
        if let alwaysActiveSession = snapshot.alwaysActiveSession {
            lines.append("    \(muted("Mode"))        \(alwaysActiveSession.mode.rawValue)")
            lines.append("    \(muted("Started"))     \(alwaysActiveSession.startTime.formatted())")
            lines.append("    \(muted("Elapsed"))     \(formatLiveDuration(now.timeIntervalSince(alwaysActiveSession.startTime)))")
            lines.append("    \(muted("Idle rule"))   Simulates activity after 4m idle")
        } else {
            lines.append("    \(muted("No input-simulation daemon is running."))")
        }
        lines.append("")
        lines.append("  \(muted("Press Enter or Esc to return."))")
        return lines.map { truncateStyledLine($0, width: width) }
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

    private func customDurationLines(input: String, width: Int) -> [String] {
        [
            "",
            "  \(primary("Custom duration"))",
            "",
            "  Enter hours and minutes, for example 45m or 1h30m.",
            "",
            selectedRow("Duration  \(input.isEmpty ? "" : input)█", width: width),
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
        let elapsed = formatLiveDuration(now.timeIntervalSince(session.startTime))
        return "\(session.mode.rawValue) mode · \(elapsed) elapsed · 4m idle rule"
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
        case .details:
            "Enter/Esc back · Ctrl-C quit"
        case .customDuration:
            "Type duration · Enter confirm · Esc back · Ctrl-C quit"
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

    private func strong(_ text: String) -> String {
        "\u{001B}[1m\(text)\u{001B}[22m"
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

    init(wakeSession: (startTime: Date, remainingTime: TimeInterval?)? = nil, alwaysActiveSession: AlwaysActiveSession? = nil) {
        self.wakeSession = wakeSession
        self.alwaysActiveSession = alwaysActiveSession
    }
}

struct WakeUIState {
    var screen = WakeUIScreen.home
    var selectedIndex = 0
    var customDuration = ""
    var notification: WakeNotification?
    var isRunning = true

    mutating func show(_ screen: WakeUIScreen) {
        self.screen = screen
        switch screen {
        case .confirmation(.stopAlwaysActive), .confirmation(.stopAll):
            selectedIndex = 1
        default:
            selectedIndex = 0
        }
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
    case durations
    case alwaysActive
    case details
    case confirmation(WakeConfirmation)
    case customDuration
}

enum WakeConfirmation: Equatable {
    case stopWake
    case replaceWake(WakeDurationOption)
    case stopAlwaysActive
    case stopAll
    case replaceAlwaysActive(AlwaysActiveMode)
    case openAccessibility(AlwaysActiveMode)
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
    case manageAlwaysActive
    case stopAll
    case details
    case exit
}

enum WakeDurationAction {
    case duration(WakeDurationOption)
    case custom
    case back
}

enum WakeAlwaysActiveAction {
    case start(AlwaysActiveMode)
    case stop
    case details
    case back
}

enum WakeUIContent {
    static func homeItems(snapshot: WakeUIStatusSnapshot) -> [WakeMenuItem<WakeHomeAction>] {
        var items = [WakeMenuItem(action: WakeHomeAction.manageWake, label: snapshot.wakeSession == nil ? "Start wake session" : "Change wake duration", description: snapshot.wakeSession == nil ? "Keep the display awake for a preset or custom duration." : "Replace the current wake session with a new duration.")]
        if snapshot.wakeSession != nil {
            items.append(WakeMenuItem(action: .stopWake, label: "Stop wake session", description: "Return display sleep behavior to the normal macOS settings."))
        }
        items.append(WakeMenuItem(action: .manageAlwaysActive, label: "Manage Always Active", description: "Start, stop, or switch keyboard and mouse activity simulation."))
        if snapshot.wakeSession != nil || snapshot.alwaysActiveSession != nil {
            items.append(WakeMenuItem(action: .stopAll, label: "Stop all sessions", description: "Stop both Wake and Always Active in one action."))
        }
        items.append(contentsOf: [
            WakeMenuItem(action: .details, label: "View details", description: "Inspect live timing and configuration for both services."),
            WakeMenuItem(action: .exit, label: "Exit", description: "Close WakeMyMac and restore the previous terminal screen.")
        ])
        return items
    }

    static let durationItems = [
        WakeMenuItem(action: WakeDurationAction.duration(.indefinite), label: "Infinite", description: "Keep the display awake until you stop the session."),
        WakeMenuItem(action: WakeDurationAction.duration(.timed(60 * 60)), label: "1h", description: "Keep the display awake for 1 hour."),
        WakeMenuItem(action: WakeDurationAction.duration(.timed(4 * 60 * 60)), label: "4h", description: "Keep the display awake for 4 hours."),
        WakeMenuItem(action: WakeDurationAction.duration(.timed(8 * 60 * 60)), label: "8h", description: "Keep the display awake for 8 hours."),
        WakeMenuItem(action: WakeDurationAction.custom, label: "Custom", description: "Enter a duration such as 45m or 1h30m."),
        WakeMenuItem(action: WakeDurationAction.back, label: "Back", description: "Return to the WakeMyMac actions.")
    ]

    static func alwaysActiveItems(snapshot: WakeUIStatusSnapshot) -> [WakeMenuItem<WakeAlwaysActiveAction>] {
        if let session = snapshot.alwaysActiveSession {
            let nextMode: AlwaysActiveMode = session.mode == .keyboard ? .mouse : .keyboard
            return [
                WakeMenuItem(action: .start(nextMode), label: "Switch to \(nextMode.rawValue) mode", description: "Replace the current \(session.mode.rawValue) activity simulation."),
                WakeMenuItem(action: .stop, label: "Stop Always Active", description: "Stop simulating input after idle periods."),
                WakeMenuItem(action: .details, label: "View details", description: "Inspect the active mode, elapsed time, and idle rule."),
                WakeMenuItem(action: .back, label: "Back", description: "Return to the WakeMyMac actions.")
            ]
        }
        return [
            WakeMenuItem(action: .start(.keyboard), label: "Start with keyboard", description: "Simulate a Shift key press after four idle minutes."),
            WakeMenuItem(action: .start(.mouse), label: "Start with mouse", description: "Move the pointer by one unit after four idle minutes."),
            WakeMenuItem(action: .details, label: "View details", description: "Review how Always Active behaves."),
            WakeMenuItem(action: .back, label: "Back", description: "Return to the WakeMyMac actions.")
        ]
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
        case .replaceAlwaysActive(let mode):
            ("Switch Always Active", "Replace the current mode with \(mode.rawValue) mode?", "Switch mode", "Restart Always Active in \(mode.rawValue) mode.")
        case .openAccessibility:
            ("Accessibility required", "Always Active needs Accessibility access for Terminal.", "Open Settings", "Open Privacy & Security > Accessibility.")
        }
    }

    static func confirmationItems(_ confirmation: WakeConfirmation) -> [WakeMenuItem<Bool>] {
        let copy = confirmationCopy(confirmation)
        let cancel = WakeMenuItem(action: false, label: "Cancel", description: "Keep the current state.")
        let confirm = WakeMenuItem(action: true, label: copy.confirmLabel, description: copy.confirmDescription)
        switch confirmation {
        case .stopAlwaysActive, .stopAll:
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
