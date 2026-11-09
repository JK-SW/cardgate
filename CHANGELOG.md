# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). The current version is in `VERSION`.

## [Unreleased]

## [0.1.0] - 2026-11-09

First version for testing. Apple silicon, macOS 15 or later; requires smart card software with
a PKCS#11 module (e.g. ProID+). The app is not notarized – see the user guide for the first start.

### Added
- Connect to a Windows computer through an RD Gateway that requires smart card sign-in
  (the `HTTP_EXTENDED_AUTH_SC` scheme of the Microsoft client), with the card redirected into
  the session for the Windows sign-in.
- First start guide, connection settings (computer, gateway, window or full screen, initial
  window size, clipboard, sound, scroll direction, PKCS#11 module), multiple connections and
  import of `.rdp` files.
- Card detection: shows the card holder and enables Connect only with a usable card; insertion
  and removal are noticed immediately, and a card the middleware lost (e.g. after sleep) is
  reported with a request to re-insert it.
- Native PIN dialog on the display where you clicked Connect; the PIN is never stored, logged or
  passed on a command line, and a wrong PIN is never retried.
- Live connection status and clear error messages with advice; connection log window and
  `~/Library/Logs/CardGate/last-session.log` for support.
- The gateway certificate must be trusted by the system certificate authorities.
- Safe client hotkeys (Left Control + Left Option + Left Shift), so typing cannot disconnect.
- Window sizes in screen points with sharp Retina rendering; automatic size is 80 % of the screen.
- About window with author and third-party licenses.
- English, Czech and Slovak user interface and user guide.
- Self-contained app: FreeRDP 3.33.0 with CardGate patches, OpenSSL, SDL, SDL_ttf, FreeType and
  cJSON built from pinned, checksum-verified sources.
