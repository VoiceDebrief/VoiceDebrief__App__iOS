# 101: TestFlight for the sgit app

**Status:** done, 13 November 2026. The owner made the App Store Connect record ("SGit Vaults") and set the switch; `sgit-app.yml` run 7 uploaded 0.1.19 (7). The switch was added as a secret, which the workflow also reads; because its value is `1`, GitHub masks every `1` in that job's log. Moving it to a repository variable would stop that.

`sgit-app.yml` archives and uploads on a green push to `dev` only when the repository variable `SGIT_APP_TESTFLIGHT` is `1`. Before that: an App Store Connect record for the bundle id `ai.sgit.vaults.app` (register the bundle id under Identifiers, then New App, platform iOS, name of the owner's choosing, SKU of any kind). The signing secrets are the ones `ios.yml` already uses. Then set the variable.
