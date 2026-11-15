# Signal Siege

Open **Training → Signal Siege**. This original, fictional tactical challenge extends
WORLD.EXE training. It uses a compact 7×7 board with deterministic rules, drawn with
SwiftUI shapes and system symbols. CONTACT and the existing expedition remain available.

## Rules v1

- Start at E with 8 HP and 4 AP. Reach R, secure the relay, return to E and extract.
- Movement costs 1 AP per orthogonal tile. Selecting a destination previews a shortest
  route with fixed north/east/south/west tie breaking; Move confirms it. Walls and the
  living sentry block travel. Nothing attacks during movement.
- Pulse costs 2 AP, deals exactly 2 damage, and requires clear line of sight within
  Manhattan distance 4. Walls conservatively block sight even when a ray touches their
  corner. Sight is symmetric. The sentry has 4 HP on Standard and 6 on Hardened.
- Cover tiles reduce incoming sentry fire by 1 from every direction. Brace costs 1 AP,
  cannot stack, and reduces the next enemy turn's fire by 1 and hazard damage by 1.
  Unused AP does not carry over. Brace expires after End Turn.
- End Turn moves the patrol, resolves its fire, then the predicted hazard. The patrol
  stays in place if its next tile is occupied by the operator. A living sentry fires
  for 2/3 damage on Standard/Hardened, within range 4 and clear sight. The highlighted
  hazard row deals 2 damage; the extraction pad is shielded from the hazard. The next
  actual patrol tile, hazard row and current fire exposure are visible before committing.
- Secure R and Extract each cost 1 AP on their respective tile. Extract requires the
  signal. Zero HP or ending the final allowed turn loses: Standard allows 12 turns and
  Hardened 10. Extracting during that final turn is permitted.

The layout stays fixed. The unsigned 64-bit seed sets the initial patrol offset and
hazard phase; all 30 combinations are represented by seeds 0–29. There are no random
hit rolls, real-time deadlines, sensors, generated terrain or model-generated rules.
Replay creates a fresh UUID while retaining the requested seed and difficulty.

Victory score is `1000 + HP×50 + (turnLimit−turn)×25 + remainingAP×10`, plus 80 for
disabling the sentry. Active, abandoned and defeated missions have no score.

## Local rankings and saves

`SignalSiege` saves a versioned Codable receipt: rules version, seed, difficulty,
session UUID and at most 256 accepted commands. Decoding replays those commands and
reconstructs every gameplay field; serialized health, phase or score cannot override
the rules. Impossible commands, extra commands after a terminal state, a zero session
UUID and unsupported rules versions are rejected.

`SiegeLeaderboard` is a separate version-1 Codable archive with the `signalSiege`
mode discriminator. Each retained victory has a replay receipt and checked metadata.
Top tens are partitioned by exact seed and difficulty. Order is score descending,
turn ascending, then session UUID ascending. The duplicate ledger retains IDs even
after results fall out of a top ten. A session cannot score twice after a relaunch.
The archive admits at most 4096 sessions and 16 MiB; capacity failure leaves the
previous archive intact and requires an explicit reset. These are local consistency
checks, not cryptographic anti-cheat or a global ranking service.

The app uses its local UserDefaults only, with no ranking networking or sync API.
Invalid stored rankings are retained and scoring stays blocked until the user clears
them. **Trophy → Clear all local rankings** asks for confirmation and clears every
seed/difficulty plus the duplicate ledger. Clearing a finished session also persists
its suppression ID so restarting the app does not immediately re-add that victory.
Clearing during an active session still allows its later legitimate victory to rank.
Mission progress is saved independently; clearing rankings does not reset gameplay.
UI tests use transient gameplay/rankings rather than the user's defaults.

## Fictional NPC / Qwen

Mica, the relay keeper, always has deterministic scripted offline dialogue. The
panel is labeled **AI interpretation, fictional NPC**, with a separate source label.
**GGUF / Qwen setup** opens the existing real model controls. A model must be explicitly
loaded and **Ask loaded GGUF** tapped before `OnDeviceBrain.respond(to:)` runs. The
recommended existing model is Qwen; other imported GGUF files keep their real identity.
This feature does not download, load or invoke a model automatically.

The fixed prompt contains only fictional mission turn, HP, AP, relay state and phase.
It never reads sensor observations, room geometry, CONTACT messages or journal data.
The response comes from `.response`, is displayed as bounded text and is never parsed
as a command. Failure uses the script. Session changes or leaving the panel invalidate
pending replies; the panel never displays an unrelated earlier GGUF response.

Accepted/rejected commands, replay and ranking reset append bounded game-event names
to the existing gameplay journal. They never create observation records. Raw ranking
points are not forced into EvidenceCore's differently scoped 0–100 score field.

## Verification and review gate

Added core unit tests cover movement/AP, atomic rejection, cover/brace, symmetric
line of sight, range, collision-aware patrol forecasts, hazard damage, extraction,
win/lose/replay, receipts, deterministic fairness across all 60 combinations of
hazard/patrol offset and difficulty, top-ten ordering, deduplication and corruption.
App integration tests cover local persistence/reset and journal separation. Two UI
smoke tests exercise entry from Training, movement/turn/replay, NPC gating and local
ranking reset through actual controls.

On the Windows implementation host, the existing 21 Python guard tests passed and
`git diff --check` passed. There is no installed Windows Swift compiler and WSL rejects
execution with `Wsl/E_ACCESSDENIED`. The Swift suites and UI smoke tests therefore
remain **unrun**, as do simulator compilation, real GGUF NPC inference and physical
device layout/touch/performance. An independent JavaScript transcription of the
rules found winning routes for all 60 schedule/difficulty cases (minimum 3 HP,
completion on turn 7); that is supplemental reasoning evidence, not Swift execution.

Run `swift test --package-path WorldCore` on an available Swift host and the existing
`bash scripts/build_and_test.sh` on macOS/Xcode. Require successful CI for the committed
revision and separate device checks before merge or TestFlight. Version stays 0.2.1;
signing, release, CI, privacy and dependency pins are unchanged by this extension.
