# 400: SGit CRM, a third app for iPhone and iPad

Opened 16 November 2026, at the owner's request. Status: open, being built by the cell in `cells/crm-ios/`.

A CRM of our own, on vaults, first used to follow up every contact and action from Web Summit 2026 (design:
[A CRM for us and for our agents](https://newsroom.sgit.ai/articles/a-crm-for-us-and-our-agents.html)).
App Store name SGit CRM, bundle id `ai.sgit.crm.app`, code in `Apps/CRM`. The brief is `cells/crm-ios/brief.md`.

## Needs from the owner

- Register the bundle id `ai.sgit.crm.app` and create the SGit CRM app in App Store Connect, so CI can upload to TestFlight.

## Done when

The app imports contacts from a vault as proposals, keeps them in the user's CRM vault, lists who needs a follow-up,
and lets a person send a draft themselves, on a device, from TestFlight.
