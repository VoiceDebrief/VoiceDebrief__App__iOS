# 001: Signing and TestFlight

**Status:** open. **Milestone:** 1.

Done: the App Store Connect record and internal group exist; the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_P8_BASE64` are set; `scripts/release/testflight.sh` and the TestFlight step of `ios.yml` are written.

Still to do:

- the owner sets the repository variable `APPLE_TEAM_ID` (until then the step skips itself);
- a run that uploads, and a build that arrives in TestFlight: until then the step is unverified;
- later, when the app gains capabilities (Associated Domains, App Groups) and extensions: enable them on
  the app id and sign each extension with its own entitlements.
