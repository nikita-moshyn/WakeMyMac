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

let SigService = SignalService.shared

final class SignalService {
    
    static let shared = SignalService()
    
    private init() {}
    
    func waitForDaemonStartup(starting daemon: () throws -> Void) throws -> DaemonStartupResult {
        let state = DaemonStartupSignalState()
        let successSignal = DispatchSource.makeSignalSource(signal: Signal.success.rawValue, queue: .main)
        let failureSignal = DispatchSource.makeSignalSource(signal: Signal.failure.rawValue, queue: .main)

        signal(Signal.success.rawValue, SIG_IGN)
        signal(Signal.failure.rawValue, SIG_IGN)

        successSignal.setEventHandler {
            state.result = .success
        }

        failureSignal.setEventHandler {
            state.result = .failure
        }

        successSignal.resume()
        failureSignal.resume()

        do {
            try daemon()
        } catch {
            successSignal.cancel()
            failureSignal.cancel()
            throw error
        }

        while state.result == nil {
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }

        successSignal.cancel()
        failureSignal.cancel()
        return state.result ?? .failure
    }
}

enum DaemonStartupResult {
    case success
    case failure
}

private final class DaemonStartupSignalState {
    var result: DaemonStartupResult?
}
