# 008: Credit, charging per use, top-up

**Status:** open. A first version is in the app with a simulated top-up; no money changes hands. Waits on
the owner for the prices and for the products in App Store Connect. Everything is on the
[credit page](../../website/credit/index.md).

On the pattern of newsroom.sgit.ai's SG Meter: £5.00 of starting credit, a balance allowed below zero,
nothing blocked, a charge can be declined with a reason.

## Done (in test, not yet seen on a device)

- A ledger in micro-credits (a millionth of a pound), append-only, one JSON file on the device.
- A price list in one place (`PriceList` in `Model/Prices.swift`), every figure a placeholder, whole pence,
  nothing free: a transcript 3p a started minute, a debrief 5p, creating a vault 10p, and 1p each for a
  clean passage, opening a file, adding a word, adding a vault, a file saved to a vault, sending, adding
  a recipient.
- Takings by feature on the credit screen: uses, charged, declined, given back, by period.
- A counter on Record and Library, a row in Settings, and the credit screen: balance, top-up, entries
  newest first, prices.
- Below zero: nothing is held back; a warmer colour and one sentence on the credit screen.
- `PaymentProvider`, with a simulated payment that says no money is taken.
- `AppStorePayments` (StoreKit 2 consumables) written behind `Payments.appStoreIsOn`, which is false.

## The owner's decisions

1. The prices, and what else should have one (looking inside a vault, reading, deleting are not charged).
2. The starting credit (£5.00 now).
3. What happens below zero (nothing now).
4. The top-up amounts and product ids (one pack, `ai.voicedebrief.app.credit.500`, £5.00 now).
5. Whether running a note again is charged again (it is now).

## Still to do

- The owner: sign the Paid Applications Agreement and create the consumable product. Then switch
  `Payments.appStoreIsOn` on and try a sandbox purchase from a TestFlight build.
- The other half of a profit and loss by feature: a cost per feature, and an opt-in summary (feature
  keys and totals, no note content) sent to the owner over a lane. Proposed on the credit page.
- The same ledger in the sgit app (`Apps/SGit`), with its own price list.
- The ledger in the user's vault, one log per device, after the account (011, 014, 018).
- Ask App Review, before the first submission, about a balance that is paid after it goes negative.

## Enforcement, said plainly

The ledger is a file on the user's device and nothing checks it: its owner can edit it, and deleting the
app starts again at £5.00. Newsroom accepts the same thing because its meter unlocks nothing; so does
the app, for now. Proposed and not built: keep Apple's signed transaction with each top-up; sign each
entry with the device key and commit the log to the vault; rebuild top-ups from the App Store's history.
None of these stops a device from not recording a charge: only a server could.
