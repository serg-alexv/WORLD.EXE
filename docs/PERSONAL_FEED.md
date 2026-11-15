# Personal Feed — isolated personal client demo

## Product / refactor boundary
This is a separate native iOS application target in the WORLD.EXE monorepo, not a new game tab and not a replacement for the published WORLD.EXE app. Bundle: `org.worldexe.personalfeed`. Working display name: «Личная лента».

```
WORLD.EXE: App → WorldCore + EvidenceCore + LocalLlama (unchanged)
PersonalFeed: App → FeedDomain / FeedAdapters / FeedStore
FeedAdapters → FeedDomain
FeedStore → FeedDomain
```

No dependency from the game, sensor journals, NPCs or leaderboards into personal records. No shared container or App Group. No legacy Rhea/Rheknel modification. Source/test/build graphs are isolated; wholesale relocation of the existing game is deliberately deferred while its separate PR is open. This is an additive architectural refactor, not a claim that all legacy code has been rewritten.

## What works in this slice
- Native demo feed with unmistakably synthetic records, separate from the encrypted personal vault.
- Explicit CSV/JSON file selection, structure inspection, manual field mapping, preview and confirmation. UTF-8/RFC4180-style CSV; JSON top-level array or user-specified top-level array key. Nested values are not guessed or flattened.
- Source-specific stable IDs, idempotent reimport, revision updates and atomic rejection on conflicting IDs/invalid input.
- Unknown source time remains nil, distinct from import time. Coverage is unknown/partial/outgoing-only, never automatically complete.
- Search, source filtering and personal notes stored independently from the original record. A changed/deleted record invalidates annotations referring to its old revision. Delete source cascades to its local records and notes; does not mutate the external service.
- One explicit HTTPS GET to the user's own `personal-feed-exchange/v1` endpoint. No credentials, cookies, query secrets, redirects or background polling. This is NOT a Hornet or Grindr API connector.
- Separate typed contract for model interpretations with engine/reference/revision requirements. No model is connected to personal texts yet; no claim of Qwen inference in this app.

## Hornet / Grindr integration status
Hornet officially documents requesting personal data through Profile → Settings → Privacy → Request my Personal Data, and web Account → Personal Data & GDPR → Request Data. Its public beta-tester description does not establish API access. No native export fixture or approved partner API specification was provided in this task. Consequently **we do not invent an export schema or call an undocumented endpoint**. The generic importer works only on a CSV/JSON selected and mapped by the user; real provider export compatibility remains an explicit acceptance item.

Grindr's personal-data export documentation says received messages are excluded. Do not label an imported archive as the complete conversation. A provider label is user attribution, not cryptographic proof of origin.

Official references checked 2026-11-15:
- https://hornetnetworks.zendesk.com/hc/en-us/articles/31333277569810-How-do-I-request-a-copy-of-my-personal-data
- https://hornetapp.com/contributors/programs/beta-tester
- https://help.grindr.com/hc/en-us/articles/1500005257961-Accessing-your-personal-data
- https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)

## Privacy / storage
Personal records use an AES-GCM vault with a random 256-bit key stored as a Keychain item accessible while unlocked on this device only. The vault also uses full iOS file protection and is excluded from backup. It is loaded only after system device-owner authentication. The view is shielded when inactive and locked on background; locking drops the session's visible data and cancels its HTTP request. This is not a guarantee against all memory forensics or screenshots.

No imports or archives are uploaded to CI/GitHub; fixtures and screenshots are synthetic only. No raw content/paths/errors/tokens in diagnostic logs. No tracking SDK, notification interception, automated messaging, account linking, facial matching or silent model training. Deletion removes app-managed files/keys and references, not provider data or guaranteed physical remnants on flash.

Resource limits: 4 MiB input, 2,000 records, 32 sources, 16 KiB body, 12 MiB serialized vault. Bounds reject excess input rather than silently truncating history. Whole-batch operations are atomic. This small-vault demo is not an unbounded production message database.

## Own endpoint contract
Serve `Content-Type: application/json` over HTTPS, without redirects:
```json
{"format":"personal-feed-exchange/v1","records":[{"id":"synthetic-1","text":"Synthetic example only","timestamp":"2026-11-15T12:00:00Z","direction":"unspecified"}]}
```
Optional fields: title, author, timestamp (ISO8601 with timezone), direction (incoming/outgoing/unspecified). Missing records in subsequent responses are NOT interpreted as provider deletions. No real endpoint is preconfigured or fetched by the demo.

## Build and verification
`swift test --package-path PersonalClient/Core`
`xcodegen generate --spec PersonalClient/project.yml --project PersonalClient`
`bash scripts/personal_feed_ci.sh` on the pinned macOS/Xcode runner.

The independent CI produces a simulator app, an unsigned iOS device app, test logs, `.xcresult` and synthetic screenshots. The workflow does NOT publish TestFlight. A new app-specific App ID, provisioning profile and App Store Connect record are required; do not reuse the WORLD.EXE profile or mislabel an unsigned build as installable.

## Next release gates
1. Full new core, native encrypted-storage/HTTP and UI tests pass; inspect synthetic screenshots.
2. Test device-owner auth, background locking, user file permissions and real networking on the phone.
3. Inspect a user-authorized, ideally redacted Hornet export outside the repository to write/test the exact adapter. Do not upload it automatically.
4. Ask Hornet for documented read-only scopes, auth, retention/deletion and rate limits before live synchronization.
5. Only then consider optional local Qwen annotation with per-request record consent and a dedicated instance/context that cannot reach game NPCs.
