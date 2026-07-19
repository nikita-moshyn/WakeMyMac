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

/// Prompts the user for a yes/no confirmation.
/// - Parameter message: The message to display to the user.
/// - Returns: `true` if the user confirms, `false` otherwise.
func askForConfirmation(_ message: String, readInput: () -> String? = { readLine() }, writeOutput: (String, String) -> Void = { writeConsole($0, terminator: $1) }) -> Bool {
    guard !message.isEmpty else {
        logger.critical("Failed to ask for confirmation. Message is empty")
        return false
    }

    while true {
        writeOutput("\(message) [y/N] ", "")

        guard let rawInput = readInput() else {
            logger.info("Confirmation input ended before the user responded.")
            writeOutput("", "\n")
            return false
        }

        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !input.isEmpty else {
            logger.info("User accepted the default negative confirmation response.")
            return false
        }

        switch input {
        case "y", "yes":
            logger.info("User confirmed action with input \(input).")
            return true
        case "n", "no":
            logger.info("User declined action with input \(input).")
            return false
        default:
            logger.warning("Invalid input detected: \(input). Prompting user again.")
            writeOutput("Please enter 'y' or 'n'.", "\n")
        }
    }
}
