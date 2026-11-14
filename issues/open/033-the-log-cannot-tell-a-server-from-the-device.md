# 033: The log cannot tell a server from the device

**Status:** open. From review round 1 (13 November 2026, `website/reviews/round-1/index.md`). **Owner:** the session that owns the vaults (`TrafficView`, `VaultActivitySection`, `VaultTrafficLog` in `SGitVault`).

Finding 5, with 12. Screens `traffic`, `vaults-end`. Found by the developer (it blocked the task: see every
request) and by the privacy user.

A request row reads "GET folder, not cached (mutable)" with a size and "0 ms". There is no host, no status, no
clock time and nothing to say which action caused it, so a request to a server and a read from the device look
the same. The totals on the Vaults screen call local reads "Requests 18" and "Downloaded 28.4 KB" for a vault
that is "On this device only", and have no figure for what was sent, which is the one a careful person wants.

To do: in each request row, where it went (the server's host, or "this device"), the status, and the time of
day; group rows under the action that caused them; in the totals, count the device and each server apart, and
add what was uploaded. Timings under a millisecond should not print as "0 ms". Sending a note to a recipient
makes requests too and they appear in no log: see issues 013 and 020.

Round 2: unchanged. "Requests 18, Downloaded 1.6 MB" on a vault that needs no network; the privacy user noticed that 1.6 MB is the size of the recording.
