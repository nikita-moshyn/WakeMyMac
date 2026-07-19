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

enum AlwaysActiveMode: String, Codable, CaseIterable, ExpressibleByArgument {
    case keyboard
    case mouse

    init?(argument: String) {
        switch argument.lowercased() {
        case "k", Self.keyboard.rawValue:
            self = .keyboard
        case "m", Self.mouse.rawValue:
            self = .mouse
        default:
            return nil
        }
    }

    static var allValueStrings: [String] {
        ["keyboard", "k", "mouse", "m"]
    }
}
