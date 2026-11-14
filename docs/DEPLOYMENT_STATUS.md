# Deployment checkpoint — 2026-11-15

## Boundaries
WORLD.EXE is an independent public repository: `serg-alexv/WORLD.EXE`.
No Rhea RF Spanner source, repository setting, certificate, provisioning profile or TestFlight group was modified.
Existing signing material was inspected read-only, in memory, without publishing credentials.

## Apple preflight: actual observations
- App Store Connect authentication: HTTP 200.
- Existing iOS Distribution certificate: accessible and expires 2027-11-07.
- WORLD.EXE bundle identifier `org.worldexe.prototype`: not registered at preflight.
- WORLD.EXE App Store Connect app record: not found at preflight.
- Registering the new identifier returned HTTP 403, `FORBIDDEN_ERROR`: Apple says the operation is not permitted and to contact a Team Admin.
- Registration was not bypassed. No Rhea identifier/profile was reused for WORLD.EXE.
- New WORLD.EXE provisioning and TestFlight upload are blocked until an authorized Apple team administrator enables the operation or provides the app-specific registration/profile through the protected signing workflow.

## Build evidence
The original scaffold compiled on GitHub Actions (run 43650943093). That is NOT evidence for the later playable code.
The playable branch must run its own core tests, simulator UI tests and unsigned iOS device compilation before it can be called validated. `scripts/ci.sh` writes an evidence receipt only after success.

## Release path
`.github/workflows/testflight.yml` is manual, restricted to main by job conditions, and runs validation first. `scripts/release.sh` refuses missing signing inputs, validates the app identity/profile, creates an ephemeral keychain, verifies the archive signature, exports an IPA, and uploads only when explicitly dispatched with `upload=true`.
An accepted upload is not a processed TestFlight build. App Store Connect processing and beta-group availability must be separately verified.

## Human-only checks still required
Register/authorize the separate Apple app identity, provisioning profile and app record. Then validate installation, camera permission, real LiDAR, real RoomPlan capture/export, touch controls, comfort, and thermal behavior on the target iPhone.
