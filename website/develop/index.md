# Build, test and release

How this repository works. The short version: **CI is the compiler.** Most of the work here is done by agents in Linux containers that cannot build Swift, so every change is compiled and tested on a Mac by GitHub Actions, and a failure is read from the job summary.

## Layout

```
Apps/VoiceDebrief/            the app: a hand-written Xcode project, sources, resources, tests
Packages/SGitVault/           the vault engine (copied; see its SOURCE.md)
Config/                       Local.xcconfig.example, for building on your own device
.github/workflows/            ios.yml, ios-vault.yml, site.yml
.github/scripts/              select Xcode, pick a simulator, copy errors into the job summary
website/                      this site: markdown sources, the builder and the gate
issues/                       open and done work, one file each
version                       the version, one line
```

The Xcode project uses folder-synchronised groups: a Swift file added under `Apps/VoiceDebrief/Sources/` is part of the app without editing the project file. Resources are copied flat into the bundle, so two resource files with the same name break the build.

## On a Mac

Xcode 26 or later. Open `Apps/VoiceDebrief/VoiceDebrief.xcodeproj` and run the `VoiceDebrief` scheme on a simulator. To run on your own device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team.

```
cd Packages/SGitVault && swift test          # the vault engine, on the Mac itself
```

## What CI does

| Workflow | When | What |
|---|---|---|
| `ios.yml` | A push to `dev` or to a `work/` branch, or a pull request, that touches `Apps/`, `Packages/` or the workflow. Only `dev` uploads to TestFlight | One Mac job: the vault engine's tests, a simulator build, a Release device build (unsigned), then the app's unit tests on an iPhone and an iPad simulator |
| `ios-vault.yml` | A change to the vault write path, every Monday, or by hand | Swift writes vaults on a Mac; `sgit-ai` on Linux clones them, verifies every signature and compares every file |
| `site.yml` | Every push and pull request | The gate, then (on `dev`) the release tag and the site |

Builds and tests are unsigned. The last step of `ios.yml` uploads to TestFlight on a green push to `dev`: `scripts/release/testflight.sh` archives unsigned, signs the app with its entitlements, and exports with automatic signing through the App Store Connect API key. It needs the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and the variable `APPLE_TEAM_ID`, and skips itself while any is missing.

**Reading a failure without a Mac.** Each build and test step runs through `.github/scripts/run-and-summarize.sh`, which copies compiler errors and failed tests into the job summary and repeats them as the last lines of the step, so they can be read through the Actions API. Full logs are kept as the `ios-logs` artifact.

## What CI cannot do

No simulator has Apple Intelligence's models, a real microphone, or a passkey in iCloud Keychain. Speech, the debrief, the passkey and the share sheet will have to be tested on a device by a person, against a written checklist. None of that exists yet.

## The site

Each page is an `index.md`; `index.html` beside it is generated and committed.

```
node website/admin/build.mjs        # regenerate the pages, sitemap.xml and robots.txt
node website/admin/validate.mjs     # the gate CI runs
```

The gate fails on a page that is out of date, a broken link or anchor, a key-shaped string anywhere in the repository, an em-dash, or a script on a page. A page added, moved or removed updates [llms.txt](../llms.txt) in the same commit.

## A release

1. Set the next version in the `version` file (a push to `dev` is the next patch number: `v0.1.0` then `v0.1.1`).
2. Add a row to [the release history](../versions/index.md) and update [What is built](../built/index.md) for anything that changed.
3. Run the builder and the gate, commit, push to `dev`.

CI tags the commit with the version if that tag does not exist yet, and publishes the site. A push that does not change the version is not a release: it is built, tested and published, but not tagged.

## Rules that are easy to break

- **Nothing that decrypts what is committed may be committed.** No vault key, access key, API key or private key in the repository. The only exceptions are the throwaway fixture vaults under `Packages/SGitVault/Tests/`, which exist on no server.
- **Apple SDK only.** No third-party packages without a written reason.
- **If it is not on [What is built](../built/index.md), it does not exist.** Mark anything else as proposed.
