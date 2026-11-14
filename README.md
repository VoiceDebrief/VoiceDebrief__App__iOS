# VoiceDebrief for iPhone and iPad

![release](https://img.shields.io/badge/release-v0.1.41-blue)

A native app that turns a voice note into a transcript and a short debrief using Apple's on-device
models only, and keeps the result in an encrypted vault the user owns, opened with a passkey.

**In development: there is nothing to install yet.** The repository holds an app that builds and
tests, the vault engine it will use, CI and the plan.

- Site: https://ios.app.voicedebrief.ai
- [What is built](website/built/index.md): the reality file
- [The plan](website/plan/index.md)
- [Build, test and release](website/develop/index.md)

```
Apps/VoiceDebrief/     the app (Xcode project, sources, tests)
Packages/SGitVault/    the sgit vault engine, copied from PrompTugal__App__iOS
website/               the site, built from markdown
issues/                open and done work
```

Part of [VoiceDebrief](https://voicedebrief.ai). Code Apache 2.0; content CC BY 4.0.
