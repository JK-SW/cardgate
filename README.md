# CardGate

A simple macOS (Apple Silicon) app for connecting to Windows desktops through a
Remote Desktop Gateway that requires **smart card authentication** (the
`HTTP_EXTENDED_AUTH_SC` scheme used by mstsc), with the private key on a card or
token accessed through a PKCS#11 module.

It bundles a patched [FreeRDP](https://github.com/FreeRDP/FreeRDP) client and
adds a friendly UI: a big *Connect* button, connection profiles and settings.

> Status: early development, not ready for use.

## Layout

| Path | Content |
|------|---------|
| `app/` | SwiftUI application |
| `patches/` | Patches applied on top of upstream sources (FreeRDP, Kerberos) |
| `scripts/` | Reproducible build of FreeRDP and its dependencies (pinned in `scripts/deps.lock`), app bundling |
| `docs/` | User guide |

## Requirements

- Apple Silicon Mac, macOS 15 or newer
- Smart card middleware providing a PKCS#11 module (e.g. ProID+)

## License

Apache License 2.0, see [LICENSE](LICENSE). Bundled third-party components keep
their own licenses (FreeRDP – Apache 2.0, OpenSSL – Apache 2.0, SDL – zlib,
MIT Kerberos – MIT).
