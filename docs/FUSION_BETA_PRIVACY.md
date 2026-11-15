# WORLD.EXE Fusion beta — privacy notice

Scope: the WORLD.EXE Fusion 0.4.0 beta, bundle `org.worldexe.prototype`, distributed by the TIMELABS developer team. Updated 15 November 2026. This notice describes the reviewed source implementation; TestFlight determines which build is actually available. It is not a claim that a public invitation is already approved.

## Your choice of workspace
The app offers fictional gameplay, optional spatial sensing, optional local GGUF inference and a personal-data workspace. These are distinct modules and record types but run in the same iOS app process/container. This is not operating-system sandbox isolation between features. Personal records have no connected API into NPCs, game scoring, inference or sensor journals.

## Camera, room scans and local journals
Camera access is requested for supported AR/LiDAR/RoomPlan functions, not for the basic game. Room reconstruction is an estimate, not a certified physical measurement. Completed room captures and their geometry/metadata can be saved locally and exported by you. The app does not automatically upload room captures. In CONTACT, room geometry can be sent to the selected nearby partner only through the explicit pairing/sharing flow.

Observation, technical-telemetry and gameplay journals are separate, bounded local records with provenance. They are not a complete research archive. No camera frames, microphone recordings, personal messages, GGUF prompts or generated response bodies are automatically added to these diagnostic journals. You can clear or explicitly export them. Do not include private room information in a public bug report.

## Optional local model
Model weights are not included in the app download. You may import a GGUF file or explicitly download the pinned model from Hugging Face. That download contacts the model host and its delivery infrastructure, which receive normal request/network information such as your IP address. The installed model is checked before loading. Local generation uses the native llama.cpp runtime; the app does not silently replace it with a cloud model. Generated NPC dialogue is fictional interpretation, not a sensor measurement or an authoritative game action.

The personal feed is not connected to model inference or training. This beta does not automatically send personal records to Qwen, Apple Intelligence or a cloud AI service.

## Personal Feed
Synthetic demonstration records are fictional and held in memory. Opening the personal workspace requires device-owner authentication. User-selected CSV/JSON records are imported only after field mapping, preview and confirmation. The app uses a local AES-GCM vault, a device-only Keychain key, iOS file protection and backup exclusion. Leaving the private workspace/backgrounding locks its UI and cancels its network request. This is not a guarantee against all memory inspection, user screenshots or other code within the same process.

Manual imports do not prove a record's authenticity or that the history is complete. The app has no live Hornet/Grindr login or synchronization. It cannot read another app's private data merely because that app is installed. There is no automatic messaging or notification interception.

An optional custom source performs one confirmed HTTPS GET using the PersonalFeed Exchange v1 format. Your existing records are not included in the request. The chosen server sees normal network information. No account password, bearer-token login, stored cookies, redirects or background polling are supported in this prototype. Use only sources you trust and data you are authorized to process.

## Storage and deletion
Records remain local unless you explicitly share/export them or pair for the documented CONTACT exchange. Personal source deletion removes its imported records and dependent annotations from this client, not from the original service or the source file in Files. Local archive deletion removes the app-managed vault/key; it does not promise physical erasure of every remnant on flash storage. Model weights, room captures, game saves and personal records have distinct controls. Removing the app follows normal iOS behavior, and some Keychain items may persist; use the in-app deletion controls first when appropriate.

## Feedback, Apple and public reports
TestFlight is provided by Apple. When you choose Send Beta Feedback, Apple may send your comment, screenshots and associated device/build information to the developer. Apple also provides beta usage/crash information according to its TestFlight terms and your settings. Do not attach real account archives, private messages, faces, addresses or keys when reporting a gameplay problem; use the synthetic demo instead.

A GitHub issue is public. Never submit personal content or credentials there. Private review contacts are maintained in App Store Connect and are not published in the source repository. The TestFlight Feedback Email is the developer contact for beta issues.

This beta includes no advertising/tracking SDK, paid leaderboard, sale of personal records or background cloud synchronization. Local leaderboards are fictional game results on the device, not global rankings. No purchase is needed for the first-play test.

## Contact and changes
Use WORLD.EXE's Send Beta Feedback in TestFlight for a private beta report. Public, non-sensitive development questions can be filed at https://github.com/serg-alexv/WORLD.EXE/issues . This notice will be revised when data flows change; future live-provider or AI-on-private-record integrations are not authorized by this notice.
