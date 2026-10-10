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
import Cocoa

let KEService = KeyboardEventService.shared

final class KeyboardEventService {
    
    static let shared = KeyboardEventService()
    
    private var watcher: IdleWatcher?
    
    private init() {}

#if DEBUG
    static func makeForTesting() -> KeyboardEventService {
        KeyboardEventService()
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
            let didGenerateEvent = self?.generateKeyboardEvent() ?? false
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
    /// Generates a keyboard event
    private func generateKeyboardEvent() -> Bool {
        let keyCode: CGKeyCode = 60 // Left Shift
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        guard let keyUp, let keyDown else { return false }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
