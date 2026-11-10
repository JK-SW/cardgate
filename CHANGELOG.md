# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). The current version is in `VERSION`.

## [Unreleased]

### Security
- A PIN rejected by the card is never offered to it again by the same connection (reconnects or
  protocol fallbacks) and is removed from memory.
- The PIN dialog ignores typing in the first moment after it appears (keystrokes meant for another
  app), sends only PINs of the length the card accepts, and shows warnings from the card: a wrong
  PIN was entered before, last attempt, or card locked.
- The gateway's certificate is checked with the macOS trust evaluation (keychain, revocation)
  before the client starts; the smart card sign-in additionally requires the gateway to present
  the same certificate inside the tunnel.
- Only validly code signed PKCS#11 modules are loaded.
- Release downloads come with SHA-256 checksums; CI actions are pinned to commits.

### Added
- IPv6 addresses (in brackets) for computer and gateway.
- Clear messages when the PIN was not entered in time (the dialog gives up after 2 minutes) or the
  card has several sign-in certificates; cancelling the PIN dialog simply ends the attempt.
- Quitting CardGate with an open connection asks first and disconnects.

### Fixed
- The PIN dialog closes when its connection ends.
- Connect is enabled only after the first check of a newly inserted card.

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
