# Security policy / Bezpečnost

## Reporting a vulnerability

Please report security problems **privately** through GitHub: open the repository's **Security** tab
and choose **Report a vulnerability**. Do not open a public issue for them.

Describe what is affected and how to reproduce it. Never include a PIN, a certificate or private
key, a token, or logs and addresses from a real environment; use placeholders such as
`gateway.example.com` instead.

CardGate is maintained by one person in their spare time. You will get an answer as soon as
possible; a fix comes with the next release and its notes in [CHANGELOG.md](CHANGELOG.md).

## Supported versions

Only the latest release is supported. CardGate updates itself (CardGate → Check for Updates…).

## Scope

The app, its build and release scripts, and the patches in `patches/` that CardGate applies to the
bundled FreeRDP. A problem in FreeRDP, OpenSSL, SDL, FreeType, cJSON or Sparkle that is not caused by
these patches belongs to that project; a report here is still welcome if it affects CardGate.

## Hlášení zranitelnosti (česky)

Bezpečnostní problémy hlaste **neveřejně** přes GitHub: záložka **Security** → **Report a
vulnerability**, ne veřejným issue. Nikdy nepřikládejte PIN, certifikát, klíč, token ani logy
a adresy ze skutečného prostředí. Podporovaná je jen poslední vydaná verze.
