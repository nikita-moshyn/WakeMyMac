# WakeMyMac

**WakeMyMac** is a secure CLI tool designed to prevent your macOS device from sleeping with configuration options. Originally designed to extend or disable display sleep when inactive, this tool is especially useful on devices subject to MDM restrictions. Although it is built with security in mind, keeping your device continuously awake may increase the risk of unauthorized access if the device is left unattended and unlocked.

## Features

- Prevent macOS from sleeping with configurable wake sessions.
- Schedule sessions for specified durations (e.g., "1h", "120m") or run indefinitely.
- Run Wake and Always Active together for one shared duration.
- Customize the Always Active default mode, Inactivity interval, and shared named duration presets.
- Start, stop, and check the status of a wake session.
- Use a guided terminal interface powered by [Noora](https://github.com/tuist/Noora).
- Integrated daemon mode to maintain an active session in the background.
- Built with Swift and [swift-argument-parser](https://github.com/apple/swift-argument-parser).
- **Security Focus:** Designed to operate securely in environments with MDM restrictions. However, extended wake sessions mean that if a device is lost or stolen while unlocked, there could be an increased risk of unauthorized access. Always monitor your devices, even when using secure software.

## Requirements

- macOS 12 or later.
- Xcode 13 or later (for building from source).

## Installation

### Via Homebrew

####

If you have already added the custom tap, you can update and install without removing it.

1. **Add the tap (if not already added):**

```bash
brew tap mnmn13/wakemymac https://github.com/mnmn13/WakeMyMac
```

> Smash the ⭐ Star and 👁️ Watch buttons to stay updated and help this project get added to the official Homebrew repository! This way, you won't need to enter the full URL anymore!

2. **Install the formula:**

```bash
brew install wakemymac
```

3. **Upgrade to a new version (when available):**

```bash
brew update
brew upgrade wakemymac
```

## Usage

Once installed, use the command `wake` to manage your wake sessions.

### Interactive Interface

Run `wake` without a subcommand in an interactive terminal to open the guided interface:

```bash
wake
```

WakeMyMac opens in an isolated full-screen terminal buffer, so navigation and status updates never add prompt history. When the interface closes, the previous terminal screen is restored exactly as it was.

Use the up and down arrows (or `k` and `j`) to move, press Return to select, `Esc` to go back, and Ctrl-C to quit. Wake and Always Active timing updates live in the header. Duration controls, settings, details, confirmations, custom input, Accessibility setup, and Always Active modes all replace content inside the same frame.

The main menu can start Wake, Always Active, or both sessions together. All three flows share the configured duration picker: Indefinite, named timed presets, and a one-off Custom duration.

All direct commands remain available for scripts and experienced users. When input or output is redirected, running `wake` without a subcommand continues to print command help instead of opening an interactive prompt.

### Starting a Wake Session

```bash
wake start [duration]
```

- **duration:** (optional) Specify the session duration (e.g., 1h, 120m). If omitted, the session runs indefinitely.
- **Force start:** To force a session when one is already active, include the `--force` flag or `-f`.

Indefinit example:

```bash
wake start
```

1 hour Exapmle

```bash
wake start 1h
```

Named presets can be selected explicitly:

```bash
wake start --preset Workday
```

Start Wake and Always Active together with `--all` (or `-a`). When `--mode` is omitted, Always Active uses the configured default mode. An explicit mode overrides the default for that session only:

```bash
wake start 8h --all
wake start 8h --all --mode mouse
wake start --all --preset Workday --mode keyboard
```

If either service is already running, Start All asks before replacing active sessions. `--force` skips that confirmation. If Wake fails after Always Active starts, WakeMyMac stops the newly started Always Active session so the result is not left half-started.

If a session is already active, you will be prompted:

```bash
A wake session is already active
Do you want to overwrite the current session? (y/n):
```

Type y to overwrite or n to cancel.

### Stopping a Wake Session

```bash
wake stop
```

This command stops any active wake session.

### Checking Session Status

```bash
wake status
```

This displays the start time of the session and any remaining time if a duration was set.

### Always Active Sessions

Always Active simulates input after the configured Inactivity interval without keyboard or mouse activity. The default interval is four minutes. Keyboard is the initial default mode, and `wake aa start` uses whichever default is currently configured:

```bash
wake aa start
wake aa start keyboard
wake aa start k
```

Keyboard mode presses and releases Shift, keeps the pointer still, and does not type text. It is recommended for most setups. Mouse mode moves the cursor by one unit and can be useful if keyboard activity does not prevent dimming, though it may affect hover-sensitive interfaces:

```bash
wake aa start mouse
wake aa start m
```

Always Active sessions can run indefinitely or stop after a raw duration or named preset:

```bash
wake aa start keyboard --duration 2h
wake aa start mouse --preset Workday
```

Only one Always Active session can run at a time. Stop the current session before changing modes, or use `wake aa start <mode> --force` to replace it. Supplying a mode overrides the saved default for that session without changing the setting. Use `wake aa status` to see the active mode.

`wake aa status` reports the selected mode, time remaining, and the Inactivity interval captured when the session started. Changing the default mode or interval does not alter an already running daemon; restart Always Active to apply updated settings.

### Settings and Duration Presets

Open **Settings** from the interactive main menu, or use the equivalent direct commands:

```bash
wake settings show
wake settings interval show
wake settings interval set 3m45s
wake settings interval set "3m 45s"
wake settings interval reset
wake settings mode show
wake settings mode set mouse
wake settings mode reset
```

The Inactivity interval accepts hours, minutes, and seconds in descending unit order, including compact values such as `15s`, `3m30s`, and `1h30m15s`. Quote values that contain spaces. Seconds are intentionally limited to this setting; session durations and named preset durations continue to accept hours and minutes only.

The interactive mode picker remains available for every Always Active and Start All session, with the saved default preselected. `wake settings mode set` accepts `keyboard`/`k` and `mouse`/`m`; resetting restores Keyboard. Picking or passing another mode for one session does not change the saved default.

Timed duration presets are fully editable. Indefinite and Custom remain available as fixed picker options:

```bash
wake settings presets list
wake settings presets add Workday 8h
wake settings presets edit Workday --name "Office day" --duration 7h30m
wake settings presets move "Office day" 1
wake settings presets remove "Office day"
wake settings presets reset --force
```

Preset names are matched case-insensitively. Quote names containing spaces. The initial picker contains 1h, 4h, and 8h; resetting presets restores that list.

To remove every saved WakeMyMac file, select **Remove all saved data** in Settings or use:

```bash
wake settings clear
wake settings clear --force
```

WakeMyMac warns before stopping both sessions normally and deleting the complete `~/.wake` directory plus legacy `~/wakeSession` state. `--force` skips only the confirmation. If either session cannot be stopped, saved data is retained. Successful removal closes the interactive interface.

Debug builds also provide a short diagnostic flow:

```bash
wake test aa start mouse
```

The diagnostic uses a one-second Inactivity interval, holds the current process run loop, verifies the generated event and cursor movement, releases its event service and idle watcher, and prints the results. It does not launch a daemon or modify Always Active session storage. The `test` command is excluded from Release builds.

### Local Session Storage

WakeMyMac keeps its local runtime state in separate JSON files inside `~/.wake/`:

- `~/.wake/wakeSession` for a standard wake session.
- `~/.wake/alwaysActiveSession` for an always-active session.
- `~/.wake/wakeConfig` for the Inactivity interval, default Always Active mode, and duration presets after settings are customized.

The always-active session file records its selected mode, duration, and startup Inactivity interval for status output. The daemon receives a snapshot of those values through its launch arguments and does not read live configuration changes.

The directory is created with owner-only permissions and is removed automatically when it becomes empty. Existing `~/wakeSession` data from older versions is migrated into `~/.wake/` the next time it is loaded. `wake settings clear` removes this entire directory, including unrecognized files inside it, as well as the legacy state file.

### Security Note

#### Security Considerations:

- **Designed** for Secure Environments: WakeMyMac is built to be a secure tool and can be installed on devices even with strict MDM restrictions.

- **Risk Awareness:** Extended wake sessions help keep your display active and prevent your device from sleeping. However, if your device is left unattended and remains unlocked, there is an inherent risk of unauthorized access. Always ensure that your environment is secure and that you regularly monitor your devices.

- **Company Policies:** Even if the software itself is secure, always verify that using a tool like this aligns with your company's security policies and device management practices. There is always some work that requires more active monitoring, and in any scenario where devices are at risk of unauthorized access, consider additional safeguards.

### Troubleshooting

- **"The file “wake” doesn’t exist." error:**
  This error may occur if the daemon process is launched with an incorrect executable path. Ensure that your installation is complete and that the Homebrew formula points to the correct binary location.

- **Session Already Active Prompt:**
  When starting a new session while one is active, the tool will ask for confirmation before overwriting. Use --force to bypass this prompt if necessary.

### Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

### License

WakeMyMac is distributed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
