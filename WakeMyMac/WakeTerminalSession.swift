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
import Foundation
import Noora

enum WakeTerminalKey: Equatable {
    case up
    case down
    case left
    case right
    case enter
    case escape
    case backspace
    case printable(Character)
    case interrupt
}

final class WakeTerminalSession {
    static let enterSequence = "\u{001B}[?1049h\u{001B}[?25l\u{001B}[2J\u{001B}[H"
    static let leaveSequence = "\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l"

    private static var activeSession: WakeTerminalSession?

    private var originalAttributes: termios?
    private var originalInputFlags: Int32?
    private var inputBuffer = [UInt8]()
    private var isActive = false

    func enter() throws {
        guard !isActive else { return }

        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else {
            throw WakeTerminalSessionError.couldNotReadTerminal
        }

        originalAttributes = attributes
        originalInputFlags = fcntl(STDIN_FILENO, F_GETFL)

        var rawAttributes = attributes
        cfmakeraw(&rawAttributes)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &rawAttributes) == 0 else {
            throw WakeTerminalSessionError.couldNotEnterRawMode
        }

        isActive = true
        Self.activeSession = self
        installSignalHandlers()
        write(Self.enterSequence)
    }

    func leave() {
        guard isActive else { return }

        write(Self.leaveSequence)
        restoreTerminalState()
        isActive = false
        if Self.activeSession === self {
            Self.activeSession = nil
        }
        restoreDefaultSignalHandlers()
    }

    func render(_ frame: String) {
        guard isActive else { return }
        write("\u{001B}[H\(frame)\u{001B}[0m\u{001B}[J")
    }

    func readKey(timeoutMilliseconds: Int32) -> WakeTerminalKey? {
        if inputBuffer.isEmpty {
            guard waitForInput(timeoutMilliseconds: timeoutMilliseconds) else { return nil }
            readAvailableBytes()
        }

        guard !inputBuffer.isEmpty else { return nil }
        if inputBuffer[0] == 0x1B {
            if inputBuffer.count < 3, waitForInput(timeoutMilliseconds: 12) {
                readAvailableBytes()
            }
            return parseEscapeSequence()
        }

        let byte = inputBuffer.removeFirst()
        switch byte {
        case 0x03:
            return .interrupt
        case 0x0A, 0x0D:
            return .enter
        case 0x08, 0x7F:
            return .backspace
        default:
            guard let scalar = UnicodeScalar(Int(byte)), scalar.isASCII else { return nil }
            return .printable(Character(scalar))
        }
    }

    func size() -> TerminalSize {
        WakeNooraTerminal().size() ?? TerminalSize(rows: 24, columns: 80)
    }

    private func parseEscapeSequence() -> WakeTerminalKey? {
        guard inputBuffer.count >= 3, inputBuffer[0] == 0x1B, inputBuffer[1] == 0x5B else {
            inputBuffer.removeFirst()
            return .escape
        }

        let key: WakeTerminalKey?
        switch inputBuffer[2] {
        case 0x41:
            key = .up
        case 0x42:
            key = .down
        case 0x43:
            key = .right
        case 0x44:
            key = .left
        default:
            key = nil
        }
        inputBuffer.removeFirst(3)
        return key
    }

    private func waitForInput(timeoutMilliseconds: Int32) -> Bool {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, timeoutMilliseconds) > 0 && descriptor.revents & Int16(POLLIN) != 0
    }

    private func readAvailableBytes() {
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
        guard count > 0 else { return }
        inputBuffer.append(contentsOf: bytes.prefix(Int(count)))
    }

    private func write(_ content: String) {
        guard let data = content.data(using: .utf8) else { return }
        try? FileHandle.standardOutput.write(contentsOf: data)
    }

    private func restoreTerminalState() {
        if var originalAttributes {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalAttributes)
        }
        if let originalInputFlags {
            _ = fcntl(STDIN_FILENO, F_SETFL, originalInputFlags)
        }
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGQUIT, SIGHUP] {
            signal(signalNumber) { receivedSignal in
                WakeTerminalSession.activeSession?.restoreAfterSignal()
                signal(receivedSignal, SIG_DFL)
                raise(receivedSignal)
            }
        }
    }

    private func restoreDefaultSignalHandlers() {
        for signalNumber in [SIGTERM, SIGQUIT, SIGHUP] {
            signal(signalNumber, SIG_DFL)
        }
    }

    private func restoreAfterSignal() {
        guard isActive else { return }
        write(Self.leaveSequence)
        restoreTerminalState()
        isActive = false
    }
}

struct WakeNooraTerminal: Terminaling {
    let isInteractive: Bool
    let isColored: Bool

    init(isInteractive: Bool = true, isColored: Bool? = nil) {
        self.isInteractive = isInteractive
        self.isColored = isColored ?? (ProcessInfo.processInfo.environment["NO_COLOR"] == nil)
    }

    func withoutCursor(_ body: () throws -> Void) rethrows {
        try body()
    }

    func inRawMode(_ body: @escaping () throws -> Void) rethrows {
        try body()
    }

    func readRawCharacter() -> Int32? {
        nil
    }

    func readCharacter() -> Character? {
        nil
    }

    func readRawCharacterNonBlocking() -> Int32? {
        nil
    }

    func readCharacterNonBlocking() -> Character? {
        nil
    }

    func size() -> TerminalSize? {
        var windowSize = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &windowSize) == 0 else { return nil }
        let rows = Int(windowSize.ws_row)
        let columns = Int(windowSize.ws_col)
        guard rows > 0, columns > 0 else { return nil }
        return TerminalSize(rows: rows, columns: columns)
    }
}

enum WakeTerminalSessionError: LocalizedError {
    case couldNotReadTerminal
    case couldNotEnterRawMode

    var errorDescription: String? {
        switch self {
        case .couldNotReadTerminal:
            "WakeMyMac could not read the terminal state."
        case .couldNotEnterRawMode:
            "WakeMyMac could not enter full-screen terminal mode."
        }
    }
}
