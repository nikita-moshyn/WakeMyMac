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

func formatInactivityInterval(_ interval: TimeInterval) -> String {
    guard inactivityIntervalIsValid(interval) else { return "invalid" }
    let totalSeconds = max(Int(ceil(interval)), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    var components = [String]()
    if hours > 0 {
        components.append("\(hours)h")
    }
    if minutes > 0 {
        components.append("\(minutes)m")
    }
    if seconds > 0 || components.isEmpty {
        components.append("\(seconds)s")
    }
    return components.joined(separator: " ")
}

func parseDuration(_ input: String) -> TimeInterval? {
    let pattern = #"^(?:(\d+)h)?(?:(\d+)m)?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
          match.range.length == input.utf16.count else {
        return nil
    }

    func capturedInteger(at index: Int) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return 0 }
        guard let stringRange = Range(range, in: input) else { return nil }
        return Int(input[stringRange])
    }

    guard let hours = capturedInteger(at: 1), let minutes = capturedInteger(at: 2) else { return nil }
    let (hourSeconds, hoursOverflowed) = hours.multipliedReportingOverflow(by: 3600)
    let (minuteSeconds, minutesOverflowed) = minutes.multipliedReportingOverflow(by: 60)
    let (duration, sumOverflowed) = hourSeconds.addingReportingOverflow(minuteSeconds)
    guard !hoursOverflowed, !minutesOverflowed, !sumOverflowed else { return nil }
    return duration > 0 ? TimeInterval(duration) : nil
}

func parseInactivityInterval(_ input: String) -> TimeInterval? {
    let pattern = #"^\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?\s*(?:(\d+)\s*s)?\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
          match.range.length == input.utf16.count else {
        return nil
    }

    func capturedInteger(at index: Int) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return 0 }
        guard let stringRange = Range(range, in: input) else { return nil }
        return Int(input[stringRange])
    }

    guard let hours = capturedInteger(at: 1), let minutes = capturedInteger(at: 2), let seconds = capturedInteger(at: 3) else { return nil }
    let (hourSeconds, hoursOverflowed) = hours.multipliedReportingOverflow(by: 3600)
    let (minuteSeconds, minutesOverflowed) = minutes.multipliedReportingOverflow(by: 60)
    let (hoursAndMinutes, firstSumOverflowed) = hourSeconds.addingReportingOverflow(minuteSeconds)
    let (duration, finalSumOverflowed) = hoursAndMinutes.addingReportingOverflow(seconds)
    guard !hoursOverflowed, !minutesOverflowed, !firstSumOverflowed, !finalSumOverflowed, duration > 0 else { return nil }
    let interval = TimeInterval(duration)
    return inactivityIntervalIsValid(interval) ? interval : nil
}

func inactivityIntervalIsValid(_ interval: TimeInterval) -> Bool {
    interval.isFinite && interval >= 1 && interval < TimeInterval(Int.max)
}

extension Date {
    func formatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm E, d MMM y"
        return formatter.string(from: self)
    }
}
