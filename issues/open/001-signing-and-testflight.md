# 001: Signing and TestFlight

**Status:** open, nearly done. **Milestone:** 1.

Done: the App Store Connect record and internal group; the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8_BASE64` and `APPLE_TEAM_ID`; `scripts/release/testflight.sh` and the TestFlight step of `ios.yml`.
Run 4 of `ios.yml` uploaded 0.1.0 (4) on 13 November 2026 and App Store Connect accepted it.

Still to do:

- the owner confirms the build installs from TestFlight on an iPhone, an iPad and (as an iPad app) an Apple
  silicon Mac; then this issue moves to `done/`;
- later, when the app gains capabilities (Associated Domains, App Groups) and extensions: enable them on
  the app id and sign each extension with its own entitlements.
