# The SGit CRM record format, version 1

How SGit CRM keeps its records in an sgit vault the user owns: `sgit.ai/crm/v1`. Written 16 November 2026 by the CRM cell (`cells/crm-ios/`, step 2 of its brief). The Swift types are `Apps/CRM/Sources/Records/`; their tests use invented people only. Status: [[unverified]] until `crm-app.yml` is green on the commit that carries it, and until it has been used on a device. The import (step 3) writes it.

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
- **follow-up**: `person`, `owner`, `next_step`, `due`, `status` (`open`, `waiting`, `done`, `dropped`), `waiting_on`, required while `waiting`, and `stage`, the pipeline stage as its source wrote it (the team's stages are free text: to contact, to follow up, in conversation, call booked, proposal, won, parked; won reads as done, parked as dropped, the rest as open).
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

## Reading it from a vault app

Everything the native screens show can be rebuilt from the files alone, so a vault app (HTML and JavaScript in a vault, the explorer layer of [explorers and villagers](../explorers/index.md)) can show the same thing. The Swift readers are kept apart from the screens for this reason: `Records/` (the format), `Model/FollowUpBoard.swift` (who needs what), `Agents/AgentsBoard.swift` (the agents).

- **Records**: list the vault's files; a record is `<folder>/<lowercase uuid>.json` in one of the seven folders; parse it as JSON; refuse one whose `id` is not its file name, or whose `format` is not `sgit.ai/crm/v1`. Keep files that do not read, and say so; never drop them silently.
- **Names**: a follow-up, an interaction or an introduction names people by id; look them up in `people/`, and a person's organisation in `organisations/`. A value's source is its own `source`, or else its record's.
- **Who needs what** (W3): each follow-up goes in one bucket. `done` and `dropped` are *done or dropped*; `waiting` is *waiting on someone else*; an `open` one with no `due` is *no date*; otherwise compare its due day with today, in the reader's own time zone: before today *overdue*, today *due today*, within the next seven days *in the next seven days*, later *later*. Within a bucket, by due date, then by the person's name. A filter by `owner` is the only other choice.
- **What the agents are doing** (W11): read `agents/agents.json` from the agents vault (the conductor's report: `agents`, `links`, `messages`, `decisions`, `nextSteps`). Group agents by `group` (else "Other"); within a group `blocked`, `waiting`, `working`, `idle`, `done`, then by name; groups with someone waiting first. Read it again every 30 seconds while it is on screen.
- **Writing** is one commit per batch of changed records, each with its `changed` stamp; only a person marks a draft sent. A vault app that cannot sign commits proposes instead, on a lane, and the app shows its proposals for a person to accept.

## How records arrive

An import (step 3) reads another vault and offers each contact it finds as a proposal; a proposal is not a record. Only what a person accepts is written, as one signed commit per batch: new people, values added to people who matched (each with the import as its source), the organisations they name, and, if asked, a note interaction and a follow-up for each new person. Proposals from agents on an append lane come with step 6. The sync to Twenty is later.
