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

#if DEBUG
import ArgumentParser
import Cocoa

struct AlwaysActiveTestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "test",
                                                    abstract: "Run debug-only diagnostic flows.",
                                                    subcommands: [AlwaysActiveTestGroup.self])

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

private struct AlwaysActiveTestGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "always-active",
                                                    abstract: "Test Always Active input generation.",
                                                    subcommands: [AlwaysActiveTestStartCommand.self],
                                                    aliases: ["aa"])

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}

private struct AlwaysActiveTestStartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start",
                                                    abstract: "Run a short Always Active input test.")

    @Argument(help: "Activity mode: 'keyboard'/'k' or 'mouse'/'m'.")
    var mode: AlwaysActiveMode = .keyboard

    func run() throws {
        guard A11yService.isAccessibilityEnabled() else {
            cprint("Always Active tests require Accessibility access for Terminal.", .error)
            throw ExitCode.failure
        }

        var runner: AlwaysActiveTestRunner? = AlwaysActiveTestRunner(mode: mode)
        let didPass = runner?.run() ?? false
        runner = nil
        killSelf(exitCode: didPass ? 0 : 1)
    }
}

private final class AlwaysActiveTestRunner {
    private static let inactivityInterval: TimeInterval = 1
    private static let verificationDelay: TimeInterval = 0.15
    private static let verificationAllowance: TimeInterval = 2

    private let mode: AlwaysActiveMode
    private var keyboardService: KeyboardEventService?
    private weak var releasedKeyboardService: KeyboardEventService?
    private var mouseService: MouseEventService?
    private weak var releasedMouseService: MouseEventService?
    private var initialCursorPosition: CGPoint?
    private var testRunLoop: CFRunLoop?
    private var watchdog: DispatchWorkItem?
    private var didFinish = false
    private var didPass = false

    init(mode: AlwaysActiveMode) {
        self.mode = mode
    }

    deinit {
        cprint("PASS: Always Active test runner deallocated.", .green)
    }

    func run() -> Bool {
        cprint("Starting \(mode.rawValue) test with a \(Self.inactivityInterval)-second Inactivity interval.")
        cprint("Do not use the keyboard, mouse, or trackpad until the test finishes.")

        let didStart = switch mode {
        case .keyboard:
            startKeyboardTest()
        case .mouse:
            startMouseTest()
        }
        guard didStart else {
            releaseServices()
            cprint("Failed to create the test activity event tap.", .error)
            return false
        }

        scheduleWatchdog()
        testRunLoop = CFRunLoopGetCurrent()
        RunLoop.current.run()

        let didStopRunLoop = didFinish
        testRunLoop = nil
        printResult("Test run loop stopped and its retained reference was released.", passed: didStopRunLoop)
        didPass = didPass && didStopRunLoop
        printCompletionResult()
        return didPass
    }

    private func startKeyboardTest() -> Bool {
        let service = KeyboardEventService.makeForTesting()
        keyboardService = service
        releasedKeyboardService = service

        return service.startTestActivity(inactivityInterval: Self.inactivityInterval) { [weak self] didGenerateEvent in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.verificationDelay) { [weak self] in
                self?.finishKeyboardTest(didGenerateEvent: didGenerateEvent)
            }
        }
    }

    private func startMouseTest() -> Bool {
        guard let initialCursorPosition = CGEvent(source: nil)?.location else { return false }
        self.initialCursorPosition = initialCursorPosition

        let service = MouseEventService.makeForTesting()
        mouseService = service
        releasedMouseService = service

        return service.startTestActivity(inactivityInterval: Self.inactivityInterval) { [weak self] didGenerateEvent in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.verificationDelay) { [weak self] in
                self?.finishMouseTest(didGenerateEvent: didGenerateEvent)
            }
        }
    }

    private func finishKeyboardTest(didGenerateEvent: Bool) {
        guard !didFinish else { return }

        releaseServices()
        let didDeallocate = releasedKeyboardService == nil

        cprint("Test results:")
        printResult("Keyboard event was generated and posted.", passed: didGenerateEvent)
        printResult("Keyboard event service and idle watcher were released.", passed: didDeallocate)
        complete(passed: didGenerateEvent && didDeallocate)
    }

    private func finishMouseTest(didGenerateEvent: Bool) {
        guard !didFinish else { return }

        let finalCursorPosition = CGEvent(source: nil)?.location
        let didMoveOneUnit = cursorMovedOneUnit(from: initialCursorPosition, to: finalCursorPosition)

        releaseServices()
        let didDeallocate = releasedMouseService == nil

        cprint("Test results:")
        printResult("Mouse event was generated and posted.", passed: didGenerateEvent)
        printResult(mouseMovementDescription(from: initialCursorPosition, to: finalCursorPosition), passed: didMoveOneUnit)
        printResult("Mouse event service and idle watcher were released.", passed: didDeallocate)
        complete(passed: didGenerateEvent && didMoveOneUnit && didDeallocate)
    }

    private func cursorMovedOneUnit(from initialPosition: CGPoint?, to finalPosition: CGPoint?) -> Bool {
        guard let initialPosition, let finalPosition else { return false }

        let tolerance = 0.001
        let deltaX = finalPosition.x - initialPosition.x
        let deltaY = finalPosition.y - initialPosition.y
        let movedHorizontally = abs(abs(deltaX) - 1) < tolerance && abs(deltaY) < tolerance
        let movedVertically = abs(abs(deltaY) - 1) < tolerance && abs(deltaX) < tolerance
        return movedHorizontally || movedVertically
    }

    private func mouseMovementDescription(from initialPosition: CGPoint?, to finalPosition: CGPoint?) -> String {
        guard let initialPosition, let finalPosition else {
            return "Cursor positions could not be read."
        }

        let deltaX = finalPosition.x - initialPosition.x
        let deltaY = finalPosition.y - initialPosition.y
        return String(format: "Cursor moved from (%.1f, %.1f) to (%.1f, %.1f), delta (%.1f, %.1f).",
                      initialPosition.x,
                      initialPosition.y,
                      finalPosition.x,
                      finalPosition.y,
                      deltaX,
                      deltaY)
    }

    private func scheduleWatchdog() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishTimedOutTest()
        }
        watchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.inactivityInterval + Self.verificationAllowance, execute: workItem)
    }

    private func finishTimedOutTest() {
        guard !didFinish else { return }

        releaseServices()
        let didDeallocate = releasedKeyboardService == nil && releasedMouseService == nil

        cprint("Test results:")
        printResult("Activity event was generated before the watchdog expired.", passed: false)
        printResult("Activity event service and idle watcher were released.", passed: didDeallocate)
        complete(passed: false)
    }

    private func releaseServices() {
        keyboardService?.stopActivity()
        mouseService?.stopActivity()
        keyboardService = nil
        mouseService = nil
    }

    private func printResult(_ description: String, passed: Bool) {
        let prefix = passed ? "PASS" : "FAIL"
        cprint("\(prefix): \(description)", passed ? .green : .red)
    }

    private func complete(passed: Bool) {
        guard !didFinish else { return }
        didFinish = true
        didPass = passed
        watchdog?.cancel()
        watchdog = nil

        if let testRunLoop {
            CFRunLoopStop(testRunLoop)
        }
    }

    private func printCompletionResult() {
        if didPass {
            cprint("Always Active \(mode.rawValue) test passed. Closing test process.", .success)
        } else {
            cprint("Always Active \(mode.rawValue) test failed. Closing test process.", .error)
        }
    }
}
#endif
