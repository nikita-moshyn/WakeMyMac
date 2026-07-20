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

import Foundation

struct WakeDurationPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var duration: TimeInterval

    init(id: UUID = UUID(), name: String, duration: TimeInterval) {
        self.id = id
        self.name = name
        self.duration = duration
    }
}

struct WakeSettings: Codable, Equatable {
    static let defaultInactivityInterval: TimeInterval = 4 * 60
    static let defaultAlwaysActiveMode: AlwaysActiveMode = .keyboard

    var inactivityInterval: TimeInterval
    var defaultAlwaysActiveMode: AlwaysActiveMode
    var durationPresets: [WakeDurationPreset]

    init(inactivityInterval: TimeInterval = Self.defaultInactivityInterval, defaultAlwaysActiveMode: AlwaysActiveMode = Self.defaultAlwaysActiveMode, durationPresets: [WakeDurationPreset] = Self.defaultDurationPresets) {
        self.inactivityInterval = inactivityInterval
        self.defaultAlwaysActiveMode = defaultAlwaysActiveMode
        self.durationPresets = durationPresets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inactivityInterval = try container.decode(TimeInterval.self, forKey: .inactivityInterval)
        defaultAlwaysActiveMode = try container.decodeIfPresent(AlwaysActiveMode.self, forKey: .defaultAlwaysActiveMode) ?? Self.defaultAlwaysActiveMode
        durationPresets = try container.decode([WakeDurationPreset].self, forKey: .durationPresets)
    }

    static var defaultDurationPresets: [WakeDurationPreset] {
        [1, 4, 8].map { hour in
            WakeDurationPreset(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", hour))!,
                name: "\(hour)h",
                duration: TimeInterval(hour * 60 * 60)
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case inactivityInterval
        case defaultAlwaysActiveMode
        case durationPresets
    }
}
