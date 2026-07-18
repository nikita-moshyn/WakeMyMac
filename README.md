# WakeMyMac

**WakeMyMac** is a secure CLI tool designed to prevent your macOS device from sleeping with configuration options. Originally designed to extend or disable display sleep when inactive, this tool is especially useful on devices subject to MDM restrictions. Although it is built with security in mind, keeping your device continuously awake may increase the risk of unauthorized access if the device is left unattended and unlocked.

## Features

- Prevent macOS from sleeping with configurable wake sessions.
- Schedule sessions for specified durations (e.g., "1h", "120min") or run indefinitely.
- Start, stop, and check the status of a wake session.
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

### Starting a Wake Session

```bash
wake start [duration]
```

- **duration:** (optional) Specify the session duration (e.g., 1h, 120min). If omitted, the session runs indefinitely.
- **Force start:** To force a session when one is already active, include the `--force` flag or `-f`.

Indefinit example:

```bash
wake start
```

1 hour Exapmle

```bash
wake start 1h
```

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

### Local Session Storage

WakeMyMac keeps its local runtime state in separate JSON files inside `~/.wake/`:

- `~/.wake/wakeSession` for a standard wake session.
- `~/.wake/alwaysActiveSession` for an always-active session.

The directory is created with owner-only permissions and is removed automatically when it becomes empty. Existing `~/wakeSession` data from older versions is migrated into `~/.wake/` the next time it is loaded.

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
