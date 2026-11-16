# CONTACT / agreed testbed — 0.2.0

## Product contract
Two complementary roles explore one room: the researcher sees AR glyphs, the operator sees an isometric room estimate and the symbol/channel manual. Neither LLM nor a remote command is authoritative: the host's validated reducer owns mission state.

First complete loop: inspect a node → tell partner its glyph → operator powers it and selects the matching channel → researcher stabilizes it. Repeat for three nodes → operator arms extraction → researcher selects and extracts the capsule. Wrong tuning loses score but never makes the scenario unsolvable. Replay creates a new session ID. No movement timer, running, lifting furniture or reaching behind obstacles is required.

## Try it on one phone
Open **КОНТАКТ · вдвоём → Демонстрация / один экран**. The tabletop is explicitly fictional. Switch between researcher/operator roles to learn the information split. This is NOT evidence of a real network session or physical AR alignment.

## Two phones nearby
Researcher: finish a NEW Room scan during this app launch, then open CONTACT and consent to sharing processed geometry. Create a pair and tell the chosen operator your displayed peer name and six-digit code. Operator: open CONTACT, choose Operator, find that peer and enter the code. Researcher explicitly accepts the invitation. Both tap Continue. Researcher points at a clear horizontal surface at least 62×62 cm, 0.55–2 m ahead, and taps to place the capsule.

Only the processed room geometry and game state are transmitted locally. No camera image, microphone audio, account or cloud server is needed. A code and display name are not cryptographic proof of identity; confirm your physical partner. Transport requires MultipeerConnectivity encryption. One remote peer, bounded packets and command rate, session/revision checks and host-authorized roles. Disconnect/background/tracking loss freezes paired actions. Resume is explicit. Reconnection is through the lobby; a new mission starts there.

## Spatial contract
The AR view reuses the live ARSession from the successful RoomPlan capture WITHOUT resetting its coordinate origin. The operator map uses the same captured element transforms and game anchor transform. Archived JSON alone does not establish AR alignment: after relaunch a new scan is required. Real room geometry remains an estimate; the capsule/nodes/energy links are fictional. Depth-only AR mesh geometry provides occlusion on supported hardware. Placement bounds are convenience checks, not a safety certification.

## Actual local GGUF
Open **GGUF · интеллект**. Import a full `.gguf` from Files, or explicitly download the pinned official Qwen3 0.6B Q8_0 (~640 MB, Wi-Fi only, Apache-2.0). Then Load into memory and ask a question with internet disabled. The app calls the linked llama.cpp C bridge; it does not silently substitute Apple Foundation Models or a remote server. The existing Training advisor is a separately labeled legacy Apple/rules feature.

One loaded model, context 2048, generation max160 tokens, two CPU threads, optional Metal offload, bounded native request, Stop/Unload/Delete controls. Local import is not an endorsement of an arbitrary file; use trusted model sources. The full file is hashed before loading. Imported files must be valid-header GGUF ≤1.3 GB; decoder models >2B parameters are rejected. Unsupported architecture/template errors are visible. Native parser compatibility is not guaranteed for every third-party GGUF.

LLM hints use role/public progress only. They cannot execute commands, alter score, select channels, fabricate sensor measurements or access raw camera input. Weights are not in the app, repository or CI artifacts. No distillation has been performed.

## Reproducibility
Runtime: llama.cpp b12398, commit d8f30a5b6db907110b6f8d67c2f84c1443b871ef, MIT. Official iPhone/macOS framework digest and source-built simulator slice are recorded by scripts/prepare_llama.sh. Default-model revision/digest/license are in Dependencies/models.json. CI compiles the SAME C bridge and generates text with the real model under a macOS network-denial sandbox, then checks cancellation and unloading. That verifies native offline inference, not iPhone Metal speed.

## Acceptance
Core role/revision/session/range/duplicate/privacy tests; complete hot-seat mission UI test; existing training tests; native offline GGUF smoke; iOS simulator+device build. Physical acceptance remains: two-phone discovery/consent/reconnection, AR origin continuity after RoomPlan, hit testing and occlusion, GGUF import and generation on the target iPhone, latency/memory/temperature, background and camera permission behavior. No simulator result is evidence of those hardware outcomes.

Rhea RF Spanner is independent and is not modified by this work.
