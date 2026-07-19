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
    
    // MARK: - Public Methods
    
    func startActivity() -> Bool {
        guard let watcher = IdleWatcher(timeout: 240, timeoutHandler: generateKeyboardEvent) else {
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
    private func generateKeyboardEvent() {
        let keyCode: CGKeyCode = 60 // Left Shift
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        guard let keyUp, let keyDown else { return }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
