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
import IOKit.pwr_mgt

struct WakeSession: Codable {
    // Background process ID (daemon)
    var daemonID: Int32
    // IOPMAssertion ID (process to keep mac active)
    var assertionID: IOPMAssertionID
    
    let startTime: Date
    var duration: TimeInterval?
    var endTime: Date? { duration.map { startTime.addingTimeInterval($0) } }
    
    init(daemonID: Int32 = 0, assertionID: IOPMAssertionID = 0, duration: TimeInterval? = nil) {
        self.daemonID = daemonID
        self.assertionID = assertionID
        self.startTime = Date()
        self.duration = duration
    }
}
