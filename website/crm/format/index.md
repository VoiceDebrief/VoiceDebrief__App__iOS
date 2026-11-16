# The SGit CRM record format, version 1

How SGit CRM keeps its records in an sgit vault the user owns: `sgit.ai/crm/v1`. Written 16 November 2026 by the CRM cell (`cells/crm-ios/`, step 2 of its brief). The Swift types are `Apps/CRM/Sources/Records/`; their tests use invented people only. Status: [[unverified]] until `crm-app.yml` is green on the commit that carries it; nothing reads or writes a vault with it yet (that is step 3, import).

## One file per record

Each record is one JSON file, named by its id (a lowercase UUID), in a folder named for its kind. Two devices changing different records never touch the same file, so a merge of two copies of the vault rarely meets a clash.

| Folder | Kind | What it is |
|---|---|---|
| `people/` | person | someone we met or work with |
| `organisations/` | organisation | a company, a team, a repository |
| `interactions/` | interaction | a meeting, an email, a message, a call, a note, a message on a lane |
| `introductions/` | introduction | "you should talk to this person": who suggested it, between whom, why, and whether it happened |
| `follow-ups/` | follow-up | who owes whom what next, by when, and who it is waiting on |
| `drafts/` | draft | a message prepared for a person to send |
| `plays/` | play | a named sequence of steps the team repeats |

A record refers to another by its id, never by a copy of it.

## What every record has

| Field | Meaning |
|---|---|
| `format` | `sgit.ai/crm/v1` |
| `id` | the lowercase UUID the file is named after |
| `created`, `changed` | a stamp: `at` (ISO 8601, to the second, UTC) and `by`, an actor |
| `source` | where the record as a whole came from: `said_by` (who or what said it), `at` (when), `from` (where), and an optional `note` |

An actor has a `kind` (`person`, `agent` or `import`), a `name`, and a `key`: the fingerprint of the key that signed the change. **An agent always names its key**; a record changed by an agent without one is refused. That is how every change says which agent made it.

## A source on every value

The facts about a person or an organisation (a name, an email, a role) are each written as `{ "value": ..., "source": ... }`. A value with no `source` of its own takes the record's. So when two sources disagree, both can be kept and the screen can say why the CRM believes what it shows.

## The kinds

- **person**: `name`, `emails`, `phones`, `organisation` (an organisation's id), `role`, `links`, `notes` (all sourced values), `tags`.
- **organisation**: `name`, `website`, `notes` (sourced), `tags`.
- **interaction**: `at`, `channel` (`meeting`, `email`, `message`, `call`, `note`, `lane`), `people` (ids, at least one), `summary`, `place`, and `draft` when it logs a sent draft.
- **introduction**: `suggested_by` (sourced: a person's id or a name), `between` (two different people's ids), `why` (sourced), `status` (`suggested`, `accepted`, `made`, `happened`, `declined`), and `made_in`, the interaction in which it was made, required once it is `made` or `happened`.
- **follow-up**: `person`, `owner`, `next_step`, `due`, `status` (`open`, `waiting`, `done`, `dropped`), and `waiting_on`, required while `waiting`.
- **draft**: `to` (ids), `channel` (`email` or `message`), `subject`, `body`, `status` (`draft`, `ready`, `sent`, `dropped`), and `sent_as`, the interaction that logs it. **Only a person marks a draft sent**, and only with the interaction that logs it: the app never sends a message itself; a person sends it from the system's Mail or Messages sheet.
- **play**: `name`, `purpose`, `steps`.

## The encoding

Keys sorted, pretty-printed, slashes not escaped, a newline at the end, dates in ISO 8601 to the second. The same record is always the same bytes, so a vault's history shows only what changed. Every field is written, an empty list as `[]`.

## An example (an invented person)

```json
{
  "changed" : { "at" : "2025-11-12T09:30:00Z", "by" : { "key" : "sha256:0f1e2d3c4b5a69788796a5b4c3d2e1f0", "kind" : "agent", "name" : "crm.capture@sgit.example" } },
  "created" : { "at" : "2025-11-11T10:00:00Z", "by" : { "kind" : "person", "name" : "Owner" } },
  "emails" : [ { "value" : "ana@example.org" } ],
  "format" : "sgit.ai/crm/v1",
  "id" : "1d3e9a77-0c4b-4a3e-8f21-5b6c7d8e9f01",
  "links" : [ ],
  "name" : { "source" : { "at" : "2025-11-11T10:00:00Z", "from" : "photo IMG_0001.jpg", "said_by" : "Text read from a badge photo" }, "value" : "Ana Exemplo" },
  "notes" : [ ],
  "organisation" : { "value" : "6f0b8a52-3a1f-4c55-9e8e-2d7f0c1a9b01" },
  "phones" : [ { "value" : "+44 20 7946 0000" } ],
  "role" : { "value" : "Head of Partnerships" },
  "source" : { "at" : "2025-11-11T10:00:00Z", "from" : "Example Summit, stand B12", "said_by" : "Owner, in conversation" },
  "tags" : [ "example-summit" ]
}
```

This example is read by a test (`theDocumentedExampleReads`), so the page and the code cannot drift apart silently. It is shown on one line per field for reading; the app writes it fully pretty-printed.

## Not in version 1

Proposals (a record an agent or an import offers, for a person to accept) are step 3 and step 6: they will carry a record in this format plus who proposed it, and are not records in the vault until accepted. Signed commits per accepted batch come with step 3. The sync to Twenty is later.
