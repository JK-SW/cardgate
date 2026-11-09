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
- FreeRDP hotkeys need Left Control + Left Option + Left Shift, so typing no longer disconnects.
