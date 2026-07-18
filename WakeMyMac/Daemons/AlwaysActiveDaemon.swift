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
import ArgumentParser
import Cocoa

final class AlwaysActiveDaemon: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "alwaysActive-wake-daemon", abstract: "Daemon process to manage macOS sleep prevention session", shouldDisplay: false)

    private var storage: any SessionStorage = AppServices.sessionStorage

    @Flag(help: "Start the always active session.")
    var start: Bool = false

    private enum CodingKeys: String, CodingKey {
        case start
    }

    required init() {}

    init(storage: any SessionStorage) {
        self.storage = storage
    }

    func run() throws {
        guard preCheck() else { send(.failure); return }
        
        dprint("Always Active session is about to start")
        startAlwaysActiveSession()
    }
    
    func preCheck() -> Bool {
        A11yService.isAccessibilityEnabled() &&
        start
    }
    
    private func startAlwaysActiveSession() {
        KEService.startActivity()
        send(.success)
        RunLoop.main.run()
    }
    
    private func stopAlwaysActiveSession() {
        KEService.stopActivity()
        try? storage.deleteAlwaysActiveSession()
        killSelf()
    }
}
