# Build, test and release

How this repository works. The short version: **CI is the compiler.** Most of the work here is done by agents in Linux containers that cannot build Swift, so every change is compiled and tested on a Mac by GitHub Actions, and a failure is read from the job summary.

## Layout

```
Apps/VoiceDebrief/            the app: a hand-written Xcode project, sources, resources, tests, UI tests
Packages/SGitVault/           the vault engine (copied; see its SOURCE.md)
Config/                       Local.xcconfig.example, for building on your own device
.github/workflows/            ios.yml, ios-vault.yml, screens.yml, site.yml
.github/scripts/              select Xcode, pick a simulator, copy errors into the job summary, export screenshots
website/                      this site: markdown sources, the builder and the gate
issues/                       open and done work, one file each
version                       the version, one line, written by CI only
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
| `screens.yml` | By hand, or a push to `dev` or a `work/` branch that touches the screens | A screenshot of every screen on an iPhone and an iPad simulator, light and dark, from invented sample data: see below |
| `site.yml` | Every push and pull request | The gate, then (on `dev`) the next version, its tag, and the site |

Builds and tests are unsigned. The last step of `ios.yml` uploads to TestFlight on a green push to `dev`: `scripts/release/testflight.sh` archives unsigned, signs the app with its entitlements, and exports with automatic signing through the App Store Connect API key. It needs the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and the variable `APPLE_TEAM_ID`, and skips itself while any is missing.

**Reading a failure without a Mac.** Each build and test step runs through `.github/scripts/run-and-summarize.sh`, which copies compiler errors and failed tests into the job summary and repeats them as the last lines of the step, so they can be read through the Actions API. Full logs are kept as the `ios-logs` artifact.

## Seeing the screens

Nobody who writes this app from a Linux container can run it, so CI takes a picture of every screen. `screens.yml` runs by hand, and on a push to `dev` or a `work/` branch that touches the app's `UI/` or `App/` sources, the UI tests or the project file.

**How a picture is made.** `Apps/VoiceDebrief/UITests/ScreensTests.swift` has one test per picture. Each launches the app with two launch arguments, read by `Sources/App/LaunchOptions.swift` in debug builds only:

| Argument | What it does |
|---|---|
| `-VDSampleData full` | The app is given invented notes in a temporary folder (one finished, one transcript only, one interrupted, and where the screen needs it one being worked on or recorded), a vault book in memory, and one invented vault that the real engine writes into the same temporary folder. Never the real library or Keychain. The recipients and the glossary are not replaced: they are the app's own stores, empty on a simulator |
| `-VDSampleData empty` | The same, with nothing in them: the empty states |
| `-VDScreen <id>` | Opens that screen directly. Ignored without `-VDSampleData` |

In a sample launch the network is off: every request fails as if the device were offline. The sample vault is made on the device by the app's own vault book, with one invented server beside it that is never reached. Every invented note says in its own words that it is invented. A simulator has no speech model, no Apple Intelligence, no microphone and no passkeys, so a recording in progress, a transcript and a debrief are sample values, not results; the tests also pass `-vd.localeId en-GB`, because a simulator's speech model reports no language. None of this is compiled into a release build.

**What a run leaves.** One artifact, `screens-<commit sha>`, kept 30 days:

```
iphone-light-<id>.png   iphone-dark-<id>.png     one iPhone, portrait
ipad-light-<id>.png     ipad-dark-<id>.png       one iPad, landscape
contact-<device>-<appearance>.png                every screen of one set in a single picture
index.md                                         the table that is also the job summary
```

The longest side is 1600 px. The ids: `record`, `record-empty`, `record.recording`, `record.working`, `library`, `library-empty`, `note.finished`, `note.transcript`, `note.interrupted`, `note.working`, `vaults`, `vaults-empty`, `vault.detail`, `settings`, `recipients`, `words`, `diagnostics`, `traffic`, `about`; and six long screens again, scrolled to their end: `note.finished-end`, `vaults-end`, `vault.detail-end`, `settings-end`, `diagnostics-end`, `about-end`.

**Adding a screen.** Add a case to `LaunchScreen`, show it in `LaunchedScreen` if it is reached by a tap, add a test method and its id to `ScreensTests.shots`, and add the id to `SHOTS` in `screens.yml`. The run fails if a picture is missing.

**Looking at them from a Linux container.** With the GitHub Actions tools an agent session has (the GitHub MCP server):

1. `actions_list` with `list_workflow_runs` and `screens.yml` lists the runs; take the newest successful one for the commit or branch.
2. `actions_list` with `list_workflow_run_artifacts` and that run's id lists its artifacts; take the id of `screens-<sha>` (about 26 MB).
3. `actions_get` with `download_workflow_run_artifact` and that artifact id returns a `download_url` for a zip. The address is on GitHub's blob store (`*.blob.core.windows.net`), needs no token, and expires within minutes.
4. `curl -sSL -o screens.zip '<download_url>'`, unzip into an empty folder, and open the PNGs with the tool that reads images. Start with the four `contact-*.png` files, then open a single screen at full size where a detail matters.

Where the `gh` command is set up, one line does steps 3 and 4: `gh api repos/VoiceDebrief/VoiceDebrief__App__iOS/actions/artifacts/<artifact id>/zip > screens.zip`.

Both ways were followed from a Linux container on 13 November 2026 (`work/screens`: 68 pictures from the first run, 100 from the fourth). A person can download the same artifact from the run's page on GitHub.

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

Every push to `dev` is one. Nobody sets a version.

1. Add a row headed `next` to [the release history](../versions/index.md) and update [What is built](../built/index.md) for anything that changed.
2. Push to `dev`.

CI (`site.yml`) takes the latest tag, adds one to its last number, writes the `version` file and the badge in the README, tags that commit, and publishes the site with the number stamped into every page. The pages committed to the repository say `dev` where the number goes. `ios.yml` gives the app the same number: the tag this push was given, with the run number as the build.

Because CI adds a commit to `dev` after every push, pull before pushing.

## Rules that are easy to break

- **Nothing that decrypts what is committed may be committed.** No vault key, access key, API key or private key in the repository. The only exceptions are the throwaway fixture vaults under `Packages/SGitVault/Tests/`, which exist on no server.
- **Apple SDK only.** No third-party packages without a written reason.
- **If it is not on [What is built](../built/index.md), it does not exist.** Mark anything else as proposed.
