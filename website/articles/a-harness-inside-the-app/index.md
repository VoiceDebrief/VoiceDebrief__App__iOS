# A harness inside the app

*A brief. From the owner's voice memo of 13 November 2026, written up by the agent. It draws on [SHarness](https://sharness.ai), the owner's design for running agents as small, single-purpose processes that reach the world only through separate, policed doors.*

## The idea

SHarness gives a process nothing by default. What it needs comes through doors, one job each: the network, the file system, keys, the model, running a command. A policy says which doors are open and how far, and a secret lives behind exactly one of them.

An app with a model in it has the same problem at a smaller scale. When the model is asked what to do next, something decides whether it may read a file, open a vault, use a key or reach the network. Today that something is scattered through the code. The brief is to make it explicit, in the same shape:

| Door | What passes through it in the app |
|---|---|
| Network | Every request, to which host, and why |
| File system | Reads and writes, as a virtual file system over notes and vaults |
| Vault | Opening a vault, reading a path, writing a commit |
| Keys | Deriving, signing, encrypting, decrypting: the key never leaves this door |
| Model | Every prompt and every answer, on the device or in Apple's cloud |
| Run | Whatever the app can execute on the model's behalf, if anything |

Each door is a small component with one job, a policy for what it will do, and a record of what it did. This need not be separate processes on iOS; the shape and the records are what matter first.

## Showing it

The reason to build it this way is to be able to watch it. On an iPad or a Mac: the thing being done on the left, the doors on the right, and each request drawn as it passes from one to the other, allowed or refused. The vault engine's "Every step" log is the first, text-only version of this for one door.

As the interface becomes something the model helps decide (see [Two decision engines](../two-decision-engines/index.md)), this view is how anyone, the developer first, understands why the app did what it did.

## First slice

Not all of it at once. One door first, the model door, with its record and its drawing, used by the first [lab](../the-lab/index.md) experiment. Then the vault door, which already has its log.

## What is not claimed

Nothing here is a security boundary in SHarness's sense: inside one iOS app there is one process. It is a way to organise and to see, and it says so.
