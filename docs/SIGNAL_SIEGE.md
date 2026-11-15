# Signal Siege — candidate 0.3.0

Original deterministic tactical training inspired by the genre's action-point / cover conventions. No copied characters, art, dialogue or proprietary game code. This is a separate single-player challenge opened from Training. Existing two-phone CONTACT is preserved; Signal Siege does not claim multiplayer.

## Play
Select a tile, inspect the route and confirm Move. Each turn grants 4 AP. Walls block movement and line of sight. Cover and Brace reduce the predicted sentry damage. Pulse costs 2 AP, deals deterministic damage and requires clear range/line of sight. The patrol and next hazard row are visible. Secure relay R, return to extraction E and extract before health or turns expire. Standard: 12 turns; Hardened: 10. Replay with the same seed reproduces the challenge in a fresh session.

## Local rankings
Only extracted victories rank. Scores are reconstructed from bounded command receipts, not accepted from a text field, model, or arbitrary score packet. Top 10 is partitioned by exact seed and difficulty. Duplicate session IDs are retained in a bounded ledger, even after falling out of the top 10. The archive rejects invalid receipts and requires explicit clearing on corruption/capacity exhaustion. Clearing rankings does not reset the current mission. These checks prevent accidental inconsistent local results; they are not a global anti-cheat service or tamper-proof attestation. No server or Game Center leaderboard is configured.

## KIRA: fictional NPC, three tones
The tone selector offers neutral, sarcasm and black humor. The requested default is black humor. This applies only to fictional mission commentary and rankings, not numerical rules, sensor observations, technical statuses or errors. Copy satirizes an imaginary employer, expendable crews and bureaucracy; it contains non-graphic references to fictional death. Neutral mode removes scripted jokes. Unknown persisted tone values fail to neutral.

The bounded scenario catalogue responds to deployment, movement, firing, brace, enemy turns, damage, sentry defeat, relay recovery, victory/defeat, replay, rejected actions and leaderboard events. Exact action/error messages remain separate and factual. No quip or model response is written into EvidenceCore.

GGUF narration uses the existing local llama.cpp engine only after explicit loading and tapping Ask. Its prompt contains public fictional state and the selected tone; no scan, camera, private identity or hidden seed. Response text is capped in the UI, labeled as local model interpretation, and never parsed as a command or used to score. Model prose is nondeterministic and may not always follow the requested humor style; scripted copy is the reliable fallback and clearly labeled, not impersonated as inference.

A move, replay, tone change, background transition or leaving the panel cancels its request and invalidates stale results. Stop is exposed during inference. Cancelling this panel never intentionally cancels an unrelated model import/download. Actual native errors remain visible beside the fallback, without humorous rewriting.

## Verification contract
New portable tests cover movement, AP, conservative symmetric line of sight, damage/cover, hazard forecast, terminal gating, replay, deterministic receipts, score partitions, corruption rejection, duplicate ledger, all voice events/tones, bounded text and prompt isolation. App tests exercise real stores, persistence, ranking resets, neutral errors and evidence isolation. UI tests exercise movement/replay, NPC readiness, local ranking visibility and tone changes without changing mission state.

Run the complete existing CI, including real GGUF with networking denied, before merging/releasing. A successful simulator test is not a physical-device performance or sensor-accuracy measurement. Human review of the generated dialogue, small-screen layout, and gameplay fun remains necessary. Rhea RF Spanner is out of scope and unchanged.
