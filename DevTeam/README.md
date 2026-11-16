# WORLD.EXE single-developer team

A bounded **proposal broker**, not an unattended release agent. Gemini, Copilot, DeepSeek and llama.cpp have invocation adapters. Trae receives an interactive handoff; no undocumented headless API is invented. Hugging Face owns model provenance, not a fictitious LLM identity. Installed, authenticated, invoked, responded, tested and accepted are separate states.

## One entrypoint on Windows

Open `WORLD.EXE.code-workspace` in Trae or a compatible editor. From PowerShell:

```powershell
.\world.ps1 doctor
.\world.ps1 test
.\world.ps1 github
.\world.ps1 queue --provider copilot --task "Review replay protection. Propose tests; no execution." --source WorldCore/Sources/WorldCore/ArenaMission.swift
.\world.ps1 run --job <the-returned-job-id> --allow-remote
```

`--allow-remote` authorizes that specific foreground provider request; it is not stored as standing authority. DeepSeek additionally requires `DEEPSEEK_API_KEY` and an explicitly chosen `WORLD_DEEPSEEK_MODEL` in the invoking process. Never place credentials in source or command arguments. Normal provider login remains interactive when needed. A missing login is a blocker, not a simulated agent response.

Local model execution requires a private `WORLD.EXE-ops/local-gguf.json` containing verified binary/model paths and SHA-256 hashes. The adapter verifies both hashes, uses two CPU threads, 2,048 context tokens and at most 192 output tokens. The model must be below 1 GiB. No weights, runtime output, private feeds or player reviews enter Git.

## Bounded improvement loop

1. Select a concrete defect and immutable source commit; queue an explicit task with a small source allowlist.
2. Run one proposal agent. Its response is untrusted and cannot execute commands or mutate files.
3. Give the proposed change to a separate reviewer; preserve the source/job identity. Review does not substitute for execution.
4. Apply an inspected patch in a dedicated worktree. Run fixed regression cases and add a reviewed reproducer for the defect. Do not change the acceptance criteria to make the candidate pass.
5. Compare executed results against the incumbent, then deliberately accept or reject. Human approval owns merge, release, provider integration, permissions and spending.

This is controlled iterative improvement of code and working instructions. It does **not** train model weights, guarantee autonomous self-improvement, or give agents permission to change their own guards. Candidate responses are private proposals, never PASS receipts.

## Events

The Windows `WORLD.EXE-DevTeam-1h` observer detects source changes and reports readiness/queue depth. It does not call paid APIs, execute generated code, fetch/merge Git branches or publish a release. `tick` is idempotent with a single-run lock. A stale lock requires inspection; it is not automatically broken.

GitHub `devteam.yml` runs deterministic contract tests on relevant source events and daily at 05:17 UTC once the workflow is on the default branch. No model tokens or Apple environment are available to it. Existing five-minute source recovery and hourly first-player review remain separate.

## Limits

One provider invocation at a time, 120-second deadline, 48 KB context and response budgets, immutable source hashes, no shell interpolation of model output, no automatic candidate application or release. The broker is a policy boundary, not an OS sandbox: compromised CLIs still run as the user. A separate low-privilege Windows account or sandbox is a further hardening gate before unattended tool-using agents.
