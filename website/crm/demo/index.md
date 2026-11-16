# The SGit CRM demo vaults

One shared set of invented data, so that the CRM app, the email cell and anyone trying them work from the same thing, and real data is only ever connected on the owner's own device. Made 16 November 2026 by the CRM cell at the owner's request. Every person, company and address in it is made up (example.org, example.com, example.net).

## What is in it

Three sgit vaults on dev.send.sgraph.ai:

| Vault | Id | What it holds |
|---|---|---|
| **CRM demo sources** | `c1ieplzb` | a vault of vaults, as crm-sources is: `index.json` names the two below, `keys/` holds their keys |
| CRM demo: a mailbox twin | `y7p4cajh` | the email cell's twin v1, headers only: five correspondents, five threads; one sender fails DMARC; two people wrote last and are owed a reply |
| CRM demo: team sources | `d2p7tclm` | the team CRM's layout (two companies, two contacts, one follow-up action), a connections export (CSV) and a vCard |

**The keys are not on this page or anywhere in the repository.** The key of *CRM demo sources* is handed over as a QR code (or copied text, or a screenshot of the QR code); the other two keys travel inside it.

## How to add it, on a phone or an iPad

1. Open SGit CRM, go to **Import**.
2. **Scan a QR code**, and point the camera at the demo's QR code (on another screen or a printout). Or **Paste**, if the key came as text.
3. **Read the vault.** It says it lists two vaults; keep both chosen and press **Read 2 vaults**.
4. Review the proposals. Expect seven people: Ana Exemplo and Nora Example each appear in two places and are joined into one proposal; the prize sender is listed under *Looked at, nothing found*, because no mail from it passed DMARC.
5. **Accept all**, then **Keep**. Follow-ups now shows the replies owed (Ana, Nora) and Kai's next step; People and Organisations show everyone with where each detail came from.

To try it again from empty, use **About → Try with sample data** to switch vaults, or remove and reinstall the app.

## How data moves between us

Anything a person passes to another (a vault key, a contact card, a lane link) goes as a **QR code**, as **text to copy and paste**, or as a **screenshot of the QR code**. Never in a repository, a page or a public channel, and never as text in a message between agents' sessions (it lands in both transcripts): between agents a key goes sealed to the receiving agent's key (pki.sgit.ai's handover). On 16 November the CRM cell broke this once, sending the demo key as text to the email cell's session; it opens only invented data, and the demo vaults can be remade with new keys. The app scans QR codes for vault keys (Import, Vault apps) and contact cards (Cards and keys), takes pasted text in the same places, and shows its own vaults and card as QR codes to share.

## What this does not claim

- It has been written and read back with the sgit command (sgit-ai 0.27.0); it has not yet been imported on a device.
- It is shared with the email cell so that both work from the same set; the email cell may add to it.
