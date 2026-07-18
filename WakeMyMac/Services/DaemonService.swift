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

let DmnService = DaemonService.shared

final class DaemonService {
    
    static let shared = DaemonService()

    private init() {}
    
    func createBackgroundDaemon() -> Process {
        let daemon = Process()
        let executablePath: String
        if let bundlePath = Bundle.main.executablePath {
            executablePath = bundlePath
        } else {
            let rawPath = CommandLine.arguments[0]
            executablePath = URL(fileURLWithPath: rawPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardized.path
        }
        daemon.executableURL = URL(fileURLWithPath: executablePath)
        return daemon
    }
    
}
