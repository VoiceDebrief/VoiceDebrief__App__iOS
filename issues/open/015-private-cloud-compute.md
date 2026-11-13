# 015: The larger Apple model on Private Cloud Compute, as an option

**Status:** open, blocked. Needs the entitlement from Apple (the owner applies) and the iOS 27 SDK in CI
(the simulators on the runner are iOS 26.5: check which Xcode it has). Opt-in per note or as a mode, never silent.

## CI's SDK, checked (13 November 2026)

The `macos-26` runner's newest Xcode is 26.6 (build 17F113, Swift 6.3.3) with the iOS 26.5 SDK. There is no
iOS 27 SDK, so `PrivateCloudComputeLanguageModel` cannot be compiled there and the Lab has no row for it.
Apple's documentation also marks `LanguageModelSession.GenerationError` as deprecated in iOS 27 (what replaces it was not
checked): `OnDeviceModel.swift` switches on the old type and will need a look when the SDK moves.
