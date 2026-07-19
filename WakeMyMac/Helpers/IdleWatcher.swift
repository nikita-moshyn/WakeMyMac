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

final class IdleWatcher {
    
    private let timeout: TimeInterval
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "IdleWatcherQueue")
    
    private let timeoutHandler: (() -> Void)?
    
    
    init?(timeout: TimeInterval, timeoutHandler: (() -> Void)? = nil) {
        self.timeout = timeout
        self.timeoutHandler = timeoutHandler
        
        
        // Event mask defines the types of events to monitor (e.g., keyboard and mouse activity)
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.mouseMoved.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.rightMouseDragged.rawValue)
        
        // Creating an event tap to listen for the specified events
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: IdleWatcher.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return nil
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        // Adding the event tap to the current run loop
        if let runLoopSource = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        // Enabling event tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        setupTimer()
    }
    
    deinit {
        // Clean up resources when the IdleWatcher is deallocated
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        timer?.cancel()
    }
    
    // MARK: - Timer
    /// Sets up the timer to monitor user inactivity.
    private func setupTimer() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + timeout, repeating: timeout)
        timer?.setEventHandler { [weak self] in
            self?.timerDidFire()
        }
        timer?.resume()
    }
    
    /// Resets the timer when user activity is detected
    private func resetTimer() {
        timer?.schedule(deadline: .now() + timeout, repeating: timeout)
    }
    
    /// Called when the timer fires, triggering the timeout handler
    private func timerDidFire() {
        timeoutHandler?()
    }
    
    // MARK: - Event Tap Callback
    /// Callback function for the event tap to monitor user activity
    private static let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
        // Ignore events disabling the event tap
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return nil
        }
        
        // Extract the IdleWatcher instance from userInfo
        if let refcon = refcon {
            let watcher = Unmanaged<IdleWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.userDidAct()
        }
        
        // Pass the event unmodified
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - User Activity
    /// Called when user activity is detected, resetting the timer
    private func userDidAct() {
        resetTimer()
    }
    
    // MARK: - Public Methods
    /// Stops the IdleWatcher, disabling the event tap and canceling the timer
    func stop() {
        timer?.cancel()
        timer = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
