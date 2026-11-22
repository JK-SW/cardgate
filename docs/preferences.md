# CardGate preferences

For administrators. These preferences are read from the app's user defaults (domain
`io.github.jk-sw.cardgate`). Set them on one Mac with `defaults write` in Terminal, or on many Macs
with a configuration profile (MDM) for that domain. Quit and reopen CardGate after a change.

## Settings window

The switches in **CardGate → Settings…**. All are on unless set to `NO`.

| Key | Type | Effect |
|---|---|---|
| `KeepConnection` | Bool | Keep-alive packets to the gateway and automatic reconnection after an outage. |
| `PreventSleepWhileConnected` | Bool | The Mac does not go to sleep when idle while connected. |
| `ConfirmDisconnect` | Bool | Closing the remote desktop window (or ⌘Q in it) asks first. |

```sh
defaults write io.github.jk-sw.cardgate ConfirmDisconnect -bool NO
```

## Not in the Settings window

| Key | Type | Effect |
|---|---|---|
| `DonationPromptDisabled` | Bool | `YES`: CardGate never offers to support the project. |
| `SUEnableAutomaticChecks` | Bool | `NO`: no automatic check for updates (Sparkle). **Check for Updates…** still works. |
| `AllowKeepSessionActive` | Bool | `YES`: the connection settings offer **Keep the session active when idle** (see below). |

### Keep the session active when idle

Off and not shown unless `AllowKeepSessionActive` is `YES`:

```sh
defaults write io.github.jk-sw.cardgate AllowKeepSessionActive -bool YES
```

The switch then appears in each connection's settings under **Advanced**, off until turned on there.
For a connection where it is on, CardGate taps F15 (a key no app reacts to) in Windows after 30 s
without input (only after signing in to Windows). Windows then neither disconnects nor locks the
session for being idle. **This bypasses the idle limits of the computer** (Remote Desktop Services
time limits, screen lock): use it only where it is necessary and allowed. Removing the key turns it
off for every connection, also where the switch is on:

```sh
defaults delete io.github.jk-sw.cardgate AllowKeepSessionActive
```

## Saved by CardGate

CardGate keeps its own state in these keys; do not set them: `RememberedSecurity`, `PKINITAnchors`,
`ApprovedPKCS11Modules` (smart card modules approved in the app; only approvals saved by the app
count, not values from a configuration profile or the command line).
