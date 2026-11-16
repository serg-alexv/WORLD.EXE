# Acceptance gates — evidence must match the claim

| Gate | Required evidence | Current boundary |
|---|---|---|
| Source isolation | Correct repository/worktree and Apple identity; no Rhea changes | Checked in interactive reconciliation; config rejects scope drift |
| Local behavior | Complete Node test log for exact tree, including HTTP and SSE | Execute `npm test`; record version and exit code |
| Signal privacy | Extra-field/source/TTL/replay rejection; no private feed path | Covered by contract tests; only synthetic source implemented |
| Consent/auth | One-use admission, cross-room isolation, expiry, revocation | Covered by unit + HTTP tests; not external OIDC identity |
| Operator control | Atomic revisioned pause/drain state, repeat/conflict tests | Covered locally; not HA or power-loss certification |
| Native integration | Next candidate builds and native contract tests pass | NOT IMPLEMENTED for Gamebox; existing Fusion baseline remains separate |
| Physical AR multiplayer | Two real iPhones, same-frame placement, interruption and loss recovery, movement safety | NOT EXECUTED for this slice |
| Live provider | Documented permitted API, purpose/consent review, revocation tests, actual API evidence | BLOCKED; no live Hornet/Grindr connector |
| Online pilot | Real gateway/identity, authenticated sessions, latency/jitter/loss/adversarial tests, consent UX | NOT IMPLEMENTED |
| Production operations | Managed secrets, persistent state, rollback, backup/restore, moderation, alert routing, spend controls | DESIGN ONLY beyond local controls |
| Scale | Measured regional CCU, p95/p99 frame/network latency, soak and failure tests, resource/cost receipt | NOT QUALIFIED; synthetic benchmark is not this gate |
| First genuine outside review | Exact released build, external provenance, nonempty human gameplay opinion, independent content assessment | Existing private read-only monitor owns this; CI/installations never satisfy it |

Suggested ONLINE PILOT targets, not measurements: 20 Hz authoritative simulation; p95 simulation work below 25 ms per 50 ms tick budget; agreed regional end-to-end latency and loss targets after physical testing. Capacity admission must use measured resources with headroom, not the arithmetic MAU scenario.

A green backend workflow proves only backend/source-boundary tests. It does not promote the iOS build, activate a public beta link, license provider data, prove scale or count as a player's review. A failed, skipped, timed-out or inaccessible check must retain that status.
