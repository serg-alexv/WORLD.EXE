# Arena 0.5.0 candidate

A new native synthetic tactical-shooter mode, separate from the delivered Fusion 0.4.0 (8.1). Three deterministic enemy bots, cover, ammunition, replay-protected inputs, bounded movement, local two-player cooperation and an optional AR tabletop presentation. It is not a completed internet multiplayer product.

Open **Arena** from the Fusion hub. Start solo training, select a bot, move around cover, fire and reload. Clear the three bots. Pause, restart and exit stop or reset the appropriate session. Model-driven natural-language assistance remains in the existing optional GGUF workspace; the combat authority is deterministic, not an LLM.

For two phones: both explicitly enable sharing of synthetic state. One hosts, the other selects the host and enters its six-digit code, and the host accepts the selected teammate. The host owns state and maps every peer command to the guest actor. The separate `world-arena` service does not join a CONTACT mission. Private feeds, physical poses, real-person profiles and room scans are absent from this protocol. Disconnection pauses paired play; there is no seamless resume/host migration claim.

## Device floor

The Arena entrypoint admits iPhone 18 Pro and iPhone 18 Pro Max, iOS 27 or later. Known model identifiers are `iPhone19,2`, `iPhone19,3`, `iPhone19,7`; mapping checked against DeviceKit's maintained device table. Future identifiers fail closed pending review. The simulator exception is compile-time and explicitly labelled; it cannot admit an older physical phone. This is a runtime feature gate, not a claim that Apple's capability plist can restrict distribution to one exact marketing model. Existing Fusion modes retain their original compatibility.

## AR boundary

Place the 50 cm synthetic board on a detected horizontal tabletop while stationary. Supported local scene reconstruction contributes depth-only mesh occlusion, bounded to 48 anchors with per-anchor geometry limits. It is never uploaded or used as a social-location map. Tracking loss pauses play; reacquisition requires deliberate resume. Each phone places its own local board. Shared real-world origin alignment and physical-device occlusion/performance are **not qualified** by simulator tests.

## Acceptance

Pure Swift tests cover state invariants, rejected-input atomicity, replay, action rate, cover, friendly-fire rejection, deterministic bots, guest revocation, wire bounds and the device gate. A native UI scenario uses actual start/fire/target/pause/exit controls and retains a synthetic screenshot. Required additional evidence: complete native CI for the exact commit, exported IPA identity/signature, Apple processing, two physical supported phones, tracking interruptions, pairing/disconnection, thermal/frame-time observations and honest player feedback.

No live Hornet integration exists. A permission request is not permission, and provider permission is not participant consent. Neither is replaced by beta-community membership.
