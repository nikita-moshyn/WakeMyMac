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

import Foundation
import Darwin

enum ConsoleColor: String {
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case orange = "\u{001B}[38;5;214m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"
    case reset = "\u{001B}[0m"
}

enum OutputState {
    case success
    case warning
    case error
    
    case debug
    
    var prefix: String {
        switch self {
        case .success: ""
        case .warning: "Warning"
        case .error: "Error"
        case .debug: "Debug"
        }
    }
    
    var color: ConsoleColor {
        switch self {
        case .success: .green
        case .warning: .yellow
        case .error: .red
        case .debug: .orange
        }
    }
}

enum OutputDestination {
    case standardOutput
    case standardError

    var fileHandle: FileHandle {
        switch self {
        case .standardOutput:
            .standardOutput
        case .standardError:
            .standardError
        }
    }

    var fileDescriptor: Int32 {
        switch self {
        case .standardOutput:
            STDOUT_FILENO
        case .standardError:
            STDERR_FILENO
        }
    }
}

func writeConsole(_ message: String, terminator: String = "\n", to destination: OutputDestination = .standardOutput) {
    guard let data = "\(message)\(terminator)".data(using: .utf8) else { return }
    destination.fileHandle.write(data)
}

func cprint(_ message: String, _ color: ConsoleColor = .reset, to destination: OutputDestination = .standardOutput) {
    let coloredMessage: String
    if shouldUseColor(for: destination), color != .reset {
        coloredMessage = "\(color.rawValue)\(message)\(ConsoleColor.reset.rawValue)"
    } else {
        coloredMessage = message
    }
    writeConsole(coloredMessage, to: destination)
}

func cprint(_ message: String, _ state: OutputState) {
    var prefix = state.prefix

    if state != .success {
        prefix += ": "
    }

    let destination: OutputDestination = state == .error || state == .debug ? .standardError : .standardOutput
    cprint("\(prefix)\(message)", state.color, to: destination)
}

func dprint(_ message: String, _ debugFlag: Bool = false) {
    guard debugFlag else { return }
    cprint(message, .debug)
}

private func shouldUseColor(for destination: OutputDestination) -> Bool {
    let environment = ProcessInfo.processInfo.environment
    guard environment["NO_COLOR"] == nil, environment["TERM"] != "dumb" else { return false }
    return isatty(destination.fileDescriptor) == 1
}
