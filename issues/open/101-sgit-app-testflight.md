# 101: TestFlight for the sgit app

**Status:** open. Blocked on the owner.

`sgit-app.yml` archives and uploads on a green push to `dev` only when the repository variable `SGIT_APP_TESTFLIGHT` is `1`. Before that: an App Store Connect record for the bundle id `ai.sgit.app` (register the bundle id under Identifiers, then New App, platform iOS, name of the owner's choosing, SKU of any kind). The signing secrets are the ones `ios.yml` already uses. Then set the variable.
