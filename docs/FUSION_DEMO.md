# WORLD.EXE Fusion — 0.4.0 candidate

One update to existing `org.worldexe.prototype`, signed only through its reviewed TIMELABS release path. No second Apple registration is required for this combined app. This document describes source intent; Apple processing and the final release receipt determine TestFlight availability.

## Included
- A real workspace launcher: Expeditions, spatial sensors, Personal Feed.
- Training and two-device CONTACT, existing real LiDAR/RoomPlan and AR capsule handling.
- Signal Siege from PR #13: deterministic AP/cover/line-of-sight/patrol/hazard mission, relay retrieval/extraction, local seed/difficulty Top 10, original Kira NPC with neutral/sarcastic/black humor.
- Existing optional local GGUF/llama.cpp inference and explicit model import/download. Weights are not bundled and scripted fallback is labeled. No cloud substitution for GGUF.
- Personal Feed from PR #14: synthetic demo, owner-authenticated encrypted vault, explicit mapped CSV/JSON import, search, independent notes, local deletion and explicit own HTTPS Exchange v1 requests.

## Fusion is navigation, not mixing evidence
Personal feed UI/storage/network code is compiled as the separate static module `PersonalFeedFeature`. Its only host-facing entry point is a SwiftUI view; the host receives no records, session or vault. Its dependencies are FeedDomain/FeedAdapters/FeedStore, not WorldCore/EvidenceCore/LocalLlama. The standalone PersonalFeed target remains buildable from the same source.

The combined version necessarily runs in ONE app process/container. This is NOT an OS-level isolation guarantee. The UI says so. Each app has its own Keychain service derived from its bundle identity. The combined app does not migrate the standalone app's inaccessible vault or grant an App Group. Game NPCs, scores and observations have no record API into the feed. No personal-text inference or training is connected. Do not import sensitive production histories until physical-device privacy acceptance.

The root renders only one workspace at a time. Leaving personal view locks its session and cancels requests. Leaving the game pauses spatial capture/session, requires native work to be idle, unloads the model, and flushes factual evidence before reaching the hub. Saved missions/room archives/model files are retained. A new game workspace may require model reload; an archived room is not a live AR alignment.

Hornet/Grindr are NOT live-connected. File mapping is user-directed and native provider schemas remain unverified. HTTPS Exchange v1 is our own protocol, not an invented vendor API. No automatic messaging, scraping, notification interception or actual private data in test artifacts.

## Verification
Retain all existing core, GGUF (network denied), app and UI checks. Register the existing real encrypted-storage/Keychain/network tests against the actual integrated feature module. Add hub→game→hub, synthetic feed→close→locked, real Keychain-backed synthetic source persistence across workspace switching UI acceptance. The auth navigation shortcut remains DEBUG Simulator-only.

PR #13 failed on ambiguous XCTest confirmation labels. Confirmation actions now have unique labels and scoped selectors, while post-replay/reset assertions are retained. The known post-XCTest Simulator reinstall race is fixed by not reinstalling a just-tested app; launch retries are strictly bounded and only match the installation Busy error. Crashes and other errors still fail. These are not weakened gameplay tests.

Hardware AR/LiDAR alignment, Face ID, background interruption, real-file imports, two-phone networking and thermals require the user's iPhone acceptance. Release archive and exported IPA identities must both be verified as 0.4.0 and the actual run build number before upload; Apple VALID and IN_BETA_TESTING must be checked separately.

## First play
WORLD.EXE → Expeditions → Signal Siege. Select a tile and Move; watch the next hazard row, secure R, return to E and Extract. Trophy opens local rankings; NPC panel selects humor and offers explicit GGUF generation after model loading. CONTACT remains the separate paired mission.

Personal Feed → Open demonstration works with fictional records. Private space requires owner authentication; imports remain local and cannot be used as game/NPC context.

Rhea RF Spanner is out of scope and unchanged.
