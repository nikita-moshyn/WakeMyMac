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

import Cocoa
import Foundation

let MEService = MouseEventService.shared

final class MouseEventService {
    static let shared = MouseEventService()

    private var watcher: IdleWatcher?

    private init() {}

#if DEBUG
    static func makeForTesting() -> MouseEventService {
        MouseEventService()
    }
#endif

    // MARK: - Public Methods

    func startActivity(inactivityInterval: TimeInterval = WakeSettings.defaultInactivityInterval) -> Bool {
        beginActivity(inactivityInterval: inactivityInterval)
    }

#if DEBUG
    func startTestActivity(inactivityInterval: TimeInterval, eventHandler: @escaping (Bool) -> Void) -> Bool {
        beginActivity(inactivityInterval: inactivityInterval, eventHandler: eventHandler)
    }
#endif

    private func beginActivity(inactivityInterval: TimeInterval, eventHandler: ((Bool) -> Void)? = nil) -> Bool {
        guard let watcher = IdleWatcher(inactivityInterval: inactivityInterval, inactivityHandler: { [weak self] in
            let didGenerateEvent = self?.generateMouseEvent() ?? false
            eventHandler?(didGenerateEvent)
        }) else {
            return false
        }
        self.watcher = watcher
        return true
    }

    func stopActivity() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Private Methods

    /// Moves the cursor by one coordinate unit in a random valid cardinal direction.
    private func generateMouseEvent() -> Bool {
        guard let currentPosition = CGEvent(source: nil)?.location,
              let destination = randomDestination(from: currentPosition),
              let event = CGEvent(mouseEventSource: nil,
                                  mouseType: .mouseMoved,
                                  mouseCursorPosition: destination,
                                  mouseButton: .left) else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }

    private func randomDestination(from currentPosition: CGPoint) -> CGPoint? {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        let result = CGGetDisplaysWithPoint(currentPosition, 1, &displayID, &displayCount)
        guard result == .success, displayCount > 0 else { return nil }

        let displayBounds = CGDisplayBounds(displayID)
        let offsets = [
            CGPoint(x: -1, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0, y: -1),
            CGPoint(x: 0, y: 1)
        ]
        let destinations = offsets
            .map { CGPoint(x: currentPosition.x + $0.x, y: currentPosition.y + $0.y) }
            .filter(displayBounds.contains)

        return destinations.randomElement()
    }
}
