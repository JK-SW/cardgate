# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). The current version is in `VERSION`.

## [Unreleased]
### Added
- Repository structure and license.
- FreeRDP 3.33.0 patch implementing RD Gateway smart card extended authentication.
- Reproducible build of FreeRDP and its dependencies (OpenSSL, SDL3, SDL3_ttf, FreeType,
  cJSON) from pinned, checksum-verified sources (`scripts/build-deps.sh`).
- Self-contained, relocatable FreeRDP helper with automatic dependency checks
  (`scripts/assemble-helper.sh`, `scripts/check-helper.sh`).
- GitHub Actions CI building and checking the helper.
- macOS app: first start, connection settings (computer, gateway, display, clipboard, sound),
  multiple connections, .rdp import, connection status with clear error messages, connection log.
- English, Czech and Slovak localization.
- Native PIN dialog instead of the FreeRDP one (via `FREERDP_ASKPASS`); the PIN is never stored
  or passed on a command line.
- Card detection: the app shows whether a card with a sign-in certificate is inserted (holder
  name) and enables Connect only then; insertion and removal are noticed immediately.
- The card is also checked through the middleware's PKCS#11 module (as the RDP client uses it);
  when the system lists the card but the module does not (e.g. after sleep), the app asks to
  re-insert it instead of failing the connection.
- No more screens sliding away and back on all displays when connecting and disconnecting
  (FreeRDP patch: displays are queried without a temporary full screen window on macOS).
- Redesigned, centered PIN dialog.
- Compact main window that fits its content.
- Connection progress is shown live (FreeRDP patch: log messages are flushed immediately).
- The last session's log is kept in `~/Library/Logs/CardGate/last-session.log`.
- FreeRDP's own connection/error dialog is turned off; errors are shown in the app only.
- Scroll direction in the session follows this Mac by default (setting per connection).
- FreeRDP hotkeys need Left Control + Left Option + Left Shift, so typing no longer disconnects.
