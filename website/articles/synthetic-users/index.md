# Synthetic users

*A brief. From the owner's voice memo of 13 November 2026, written up by the agent.*

## The problem

The app is built by an agent that cannot see it. Continuous integration compiles and tests it; the owner sees it on a device. Between the two there is nobody checking whether a person arriving for the first time can find the record button, understand what a vault is, or get back from the place a tap took them.

## The idea

Invented users, each with a purpose and a level of knowledge, who walk the screens and report where they hesitated, guessed wrong or got lost. The newsroom at sgit.ai does this for a website, one screenshot at a time. The same applies here.

For example:

- someone who wants to record a memo while driving and has never heard of a vault;
- someone careful about privacy who wants to know exactly what leaves the phone;
- a developer who wants to see every request the app makes;
- someone who lost a recording in another app and does not trust this one.

## How it would work

1. **Pictures of every screen.** A workflow in continuous integration runs the app in a simulator, one launch per screen with sample data, and keeps a screenshot of each on an iPhone and an iPad. The sibling repository has this already; it is to be carried over. It also gives the agent its first sight of its own work.
2. **A walk.** A synthetic user is given a task and the screenshots, and says at each step what it would tap and what it expects. Where its expectation and the next screen disagree is a finding.
3. **A record.** Findings are kept as files, each with the screen, the user and what went wrong, and a status as review findings have elsewhere in this family.

## Limits

A synthetic user reads a picture. It does not feel a button that is too small for a thumb, hear nothing, or drive a car. Simulators have no speech model and no Apple Intelligence, so screens that depend on them are shown with sample data. The owner on a device remains the test that counts.
