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

func formatDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(Int(ceil(interval)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
    if minutes > 0 {
        return "\(minutes)m"
    }
    return "\(seconds)s"
}

func parseDuration(_ input: String) -> TimeInterval? {
    let pattern = #"^(?:(\d+)h)?(?:(\d+)m)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
          match.range.length == input.utf16.count else {
        return nil
    }

    let hours = Range(match.range(at: 1), in: input).flatMap { Int(input[$0]) } ?? 0
    let minutes = Range(match.range(at: 2), in: input).flatMap { Int(input[$0]) } ?? 0
    let duration = hours * 3600 + minutes * 60
    return duration > 0 ? TimeInterval(duration) : nil
}

extension Date {
    func formatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm E, d MMM y"
        return formatter.string(from: self)
    }
}
