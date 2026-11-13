# 001: Signing and TestFlight

**Status:** open, blocked on the owner. **Milestone:** 1.

CI builds everything unsigned. To upload to TestFlight it needs, from the owner:

- the App Store Connect record and the bundle id `ai.voicedebrief.app` (the API cannot create them);
- repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `APPLE_TEAM_ID`, in a `testflight` environment.

Then: carry over the release scripts from `PrompTugal__App__iOS` (`scripts/release/`: version, signing setup,
archive unsigned then codesign, export, upload) and add a publish step to `ios.yml` for green pushes to `dev`.
