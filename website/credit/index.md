# Credit: a balance that counts down, and how a top-up will be paid for

The app keeps a credit balance. It starts at £5.00, counts down as the app is used, may go below zero, and is topped up by paying. The model is the reading meter of [newsroom.sgit.ai](https://newsroom.sgit.ai/meter/index.html): an honesty box, not a paywall.

> In test, and **no money changes hands**. The app has the ledger, the price list, the counter, the credit screen and a simulated top-up. Paying through the App Store is written and switched off: it has never run. Every price is a placeholder. [What is built](../built/index.md) is the record.

## What the app does today

| | |
|---|---|
| The unit | The **micro-credit**: one millionth of a pound, always a whole number. A penny is 10,000. Shown as pounds and pence, to a tenth of a penny (£4.962) |
| Starting credit | £5.00, written as the first entry of a new ledger. A placeholder |
| What is charged | A transcript, by the second of audio; a debrief; a clean text, by the passage. Charged when the step has produced something: a step that fails costs nothing. Running a note again is charged again |
| What is never charged | Recording. Capture without loss is the app's first rule, and credit never stops, delays or interrupts a recording |
| The counter | The balance, in the navigation bar of the Record and Library screens and as a row in Settings. It changes as things are charged. Pressing it opens the credit screen |
| The credit screen | The balance, what was used and topped up, top-up, every entry newest first with the balance after it, and the price list |
| Below zero | Nothing is blocked and nothing is held back. The balance turns a warmer colour and the credit screen says how far over it is: "Nothing is blocked, and nothing will be. Top up when it feels fair." No banner, no reminder |
| Declining | A charge can be declined with a reason (the result was not usable, I did not need it, it was a test, another reason). It is given back as a new entry; the charge stays in the ledger |
| Top-up | One pack of £5.00. In this build it is simulated: the screen says that no money is taken, and the ledger entry reads "Top-up (simulated, no money taken)" |

### The prices, all placeholders

The owner has not set the app's prices. These are in one place in the code (`PriceList` in `Model/Credit.swift`) and the credit screen says they are placeholders.

| What | Placeholder | Where the figure came from |
|---|---|---|
| A transcript | 3p a minute of audio, charged by the second | The plan's "a few pence per minute" |
| A debrief | 5p each | Newsroom's price for an article read to the end |
| A clean text | 1p a passage | Newsroom's price for a page |
| Saving a note to a vault | free, not charged | No equivalent in newsroom |
| Sending a note to a recipient | free, not charged | No equivalent in newsroom |

At these figures a 76-second note costs 3.8p to transcribe and 5p to debrief, and £5.00 is about 57 such notes.

## Where the ledger lives

One JSON file on the device, `credit-ledger.json` in the app's own storage, beside the notes. It is append-only: an entry says what was done, when, for which note, how much of it, what it cost and the balance after it. A declined charge is not removed; a refund is written after it. A top-up is credited once per payment reference.

The file is one device's log, with a random name for the device. That is the shape it needs to live in the user's vault later: two devices' logs join by taking every entry once, and the balance is the sum of the amounts, which does not depend on the order. Keeping it in the vault is [[proposed]], and waits for the account.

Deleting the app deletes the ledger, and a new install starts again at £5.00.

## How this differs from newsroom, and why

| Newsroom | The app | Why |
|---|---|---|
| Counts in pence and tenths of a penny | Counts in micro-credits | A second of audio costs less than a tenth of a penny |
| Charges for reading, by the share of a page read | Charges for work done by a model, by the minute or by the thing | There is nothing to read by degrees |
| Keeps running totals and the last 500 charges | Keeps every entry, and the balance is their sum | A ledger that will be shared between devices cannot be a pair of running totals |
| Pays through a Stripe payment link, or a simulated cart with no link | Will pay through the App Store, or a simulated payment until then | Apple's rules, below |
| A usefulness rating sets the price | Not built | The app has no rating of a result yet. Declining with a reason is built |

## What Apple requires, checked on 13 November 2026

**Credit spent inside the app must be bought by in-app purchase.** Apple's App Review Guidelines, 3.1.1: "If you want to unlock features or functionality within your app, (by way of example: subscriptions, in-game currencies, game levels, access to premium content, or unlocking a full version), you must use in-app purchase." Apple Pay is named only for the other case, 3.1.3(e), goods and services consumed outside the app. So a top-up cannot be Apple Pay, a card form or a Stripe link. The same guideline says: "Any credits or in-game currencies purchased via in-app purchase may not expire." ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase))

**A TestFlight build can make purchases that take no money.** Apple's StoreKit documentation: "Apps that you download from TestFlight always run in the sandbox environment", and "Transactions from test accounts don’t incur charges because the sandbox environment simulates successful transactions using the App Store's infrastructure without processing actual payments." ([Testing Apple In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox))

**But only once the products exist.** The same page lists what must be true first: the Apple Developer Program account is active; "Your membership Account Holder has signed the Paid Applications Agreement"; and "You set up the product information in App Store Connect for the app you’re testing. At minimum, set up a product reference name, product ID, a localized name, and a price." Until then the App Store returns no products, and the app has nothing real to offer. That is why the top-up in this build is simulated.

Not checked here: Apple's commission on each purchase, the banking and tax forms the agreement asks for, and what App Review will say about a balance that goes below zero and is paid afterwards. The last is worth asking before the first submission.

## What the owner must create to switch it on

1. In App Store Connect, under Business, sign the **Paid Applications Agreement** (the Account Holder does this), with the banking and tax details it asks for.
2. For the app `ai.voicedebrief.app`, under Monetization, In-App Purchases, create one product:

| Field | Value |
|---|---|
| Type | Consumable |
| Product ID | `ai.voicedebrief.app.credit.500` |
| Reference name | Credit, £5 |
| Display name | £5 of credit |
| Price | The tier nearest £5 (the owner's decision) |

3. Tell this repository it is done. `Payments.appStoreIsOn` in `Engine/Payments.swift` is then set to true, and the credit screen offers what the App Store returns instead of the simulated pack. A second pack is one more line in `Payments.catalogue` and one more product with the matching id.

StoreKit 2 needs no capability and no Info.plist key in the Xcode project, so nothing else changes. The App Store provider (`AppStorePayments`) is [[unverified]]: it compiles, it is covered by no test, and it has never met the App Store. It records the top-up in the ledger before it tells the App Store the purchase was delivered, and on opening the credit screen it collects any purchase that was paid for and never recorded.

## What stops someone changing their own balance

Nothing, and this page says so on purpose. The app has no server of ours, and the ledger is a file on the user's own device: someone who can edit it changes their own balance, and deleting the app wipes a negative one.

Newsroom has the same question and answers it in [its security model](https://newsroom.sgit.ai/meter/security.html): every way of cheating changes a number only the cheater can see, and costs the site a payment it was never going to get, because the meter never blocks anything. Its own line is the one that matters here: "If the balance unlocked something, it would have to be held by a server or a signed receipt."

The app is in the same position today, because nothing is held back below zero. What would make the balance trustworthy, none of it built:

- **App Store receipts for top-ups** [[proposed]]. Each StoreKit transaction is signed by Apple and verified on the device. Keeping the signed transaction with the ledger entry makes every top-up checkable by anyone, with no server. This makes the credit side honest; it does nothing for the charges.
- **A signed ledger in the vault** [[proposed]]. Each device signs its entries with the device key the [identity work](../articles/where-each-key-lives/index.md) describes, and the log is committed to the user's vault. That gives history that cannot be quietly rewritten after it has been pushed, and the same balance on every device. It still trusts the device to write its own charges.
- **Asking Apple what has been bought** [[proposed]]. By default StoreKit does not return finished consumable purchases. With the Info.plist key `SKIncludeConsumableInAppPurchaseHistory` set to true (iOS 18 and later) it does, so a new install could rebuild the top-ups from Apple instead of from the file. Apple's own note on that key asks for "a way to reconcile a customer's consumable transactions on your server, not only on the device", which this app does not have. It needs an edit to the Xcode project. ([the key](https://developer.apple.com/documentation/bundleresources/information-property-list/skincludeconsumableinapppurchasehistory))

None of these stops a determined owner of the device from not recording a charge. Only a server that does the work, or meters it, can. The plan has no such server, so the position for now is newsroom's: an honesty box, said plainly.

## Decisions that are the owner's

- The prices, and whether saving and sending are charged.
- The starting credit (£5.00 now).
- What happens below zero: nothing now. A limit, or a reminder, would be a change of position.
- The top-up amounts and their product ids (one pack of £5.00 now).
- Whether running a note again is charged again (it is now).
