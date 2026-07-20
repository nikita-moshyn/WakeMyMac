// Copyright 2025 Nikita Moshyn
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest
@testable import WakeMyMac

final class CommandParsingTests: XCTestCase {
    func testStartAllParsesDurationAndMode() throws {
        let command = try Start.parse(["8h", "--all", "--mode", "mouse"])

        XCTAssertEqual(command.duration, "8h")
        XCTAssertTrue(command.startAll)
        XCTAssertEqual(command.mode, .mouse)
    }

    func testStartParsesNamedPreset() throws {
        let command = try Start.parse(["--preset", "Workday"])

        XCTAssertEqual(command.preset, "Workday")
        XCTAssertFalse(command.startAll)
    }

    func testAlwaysActiveParsesTimedSession() throws {
        let command = try AlwaysActiveStart.parse(["mouse", "--duration", "2h"])

        XCTAssertEqual(command.mode, .mouse)
        XCTAssertEqual(command.duration, "2h")
    }

    func testAlwaysActiveModeCanBeOmittedOrProvidedByAlias() throws {
        XCTAssertNil(try AlwaysActiveStart.parse([]).mode)
        XCTAssertEqual(try AlwaysActiveStart.parse(["m"]).mode, .mouse)
        XCTAssertEqual(try AlwaysActiveStart.parse(["k"]).mode, .keyboard)
    }

    func testSavedModeIsUsedOnlyWhenNoExplicitModeIsProvided() {
        let settings = WakeSettings(defaultAlwaysActiveMode: .mouse)

        XCTAssertEqual(resolveAlwaysActiveMode(nil, settings: settings), .mouse)
        XCTAssertEqual(resolveAlwaysActiveMode(.keyboard, settings: settings), .keyboard)
        XCTAssertEqual(settings.defaultAlwaysActiveMode, .mouse)
    }

    func testStartAllModeCanBeOmittedOrProvidedByAlias() throws {
        XCTAssertNil(try Start.parse(["--all"]).mode)
        XCTAssertEqual(try Start.parse(["--all", "--mode", "m"]).mode, .mouse)
        XCTAssertEqual(try Start.parse(["--all", "--mode", "k"]).mode, .keyboard)
    }

    func testSettingsModeSetAcceptsFullNamesAndAliases() throws {
        XCTAssertEqual(try SettingsModeSet.parse(["mouse"]).mode, .mouse)
        XCTAssertEqual(try SettingsModeSet.parse(["m"]).mode, .mouse)
        XCTAssertEqual(try SettingsModeSet.parse(["keyboard"]).mode, .keyboard)
        XCTAssertEqual(try SettingsModeSet.parse(["k"]).mode, .keyboard)
    }

    func testSettingsClearParsesForceConfirmationBypass() throws {
        let command = try SettingsClear.parse(["--force"])

        XCTAssertTrue(command.force)
    }

    func testSpacedInactivityIntervalRemainsOneQuotedArgument() throws {
        let command = try SettingsIntervalSet.parse(["3m 45s"])

        XCTAssertEqual(command.duration, "3m 45s")
    }
}
