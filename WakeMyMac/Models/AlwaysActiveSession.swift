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

struct AlwaysActiveSession: Session {
    var daemonID: Int32
    let startTime: Date
    var duration: TimeInterval?
    let mode: AlwaysActiveMode
    
    init(daemonID: Int32, mode: AlwaysActiveMode = .keyboard, startTime: Date = Date()) {
        self.daemonID = daemonID
        self.mode = mode
        self.startTime = startTime
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        daemonID = try container.decode(Int32.self, forKey: .daemonID)
        startTime = try container.decode(Date.self, forKey: .startTime)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        mode = try container.decodeIfPresent(AlwaysActiveMode.self, forKey: .mode) ?? .keyboard
    }

    private enum CodingKeys: String, CodingKey {
        case daemonID
        case startTime
        case duration
        case mode
    }
}
