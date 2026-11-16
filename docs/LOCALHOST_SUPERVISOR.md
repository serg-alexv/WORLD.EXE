# WORLD.EXE native localhost supervisor

This is source recovery and development-environment supervision, not an unattended coding or release agent. Only serg-alexv/WORLD.EXE is in scope. Rhea applications and unrelated tasks are excluded.

## Operating model

Windows ReadDirectoryChangesW notifications mark only affected approved workspaces dirty. Three-second debounce coalesces writes; a thirty-second maximum prevents indefinite delay during continuous editing. An allowlisted, content-addressed snapshot is frozen locally before network publication. Unchanged content never starts GitHub activity. Local snapshots survive network outages and worker restarts. Startup, wake, notification overflow and an explicit reconcile trigger inventories; a thirty-minute missed-notification safety inventory does not publish unchanged source.

A separate guardian checks coordinator heartbeats and owns a Windows kill-on-close Job Object for the worker and descendants, with a 512 MiB job-memory ceiling. Three recoveries within ten minutes open a circuit. Windows Task Scheduler starts the guardian at user logon. Restart-on-failure is configured but was insufficient in a forced-termination test; a second at-logon task waits on the guardian's native process-exit handle and performs bounded recovery. There is no recurring five-minute execution trigger. Explicit pause/stop is preserved, never undone as a supposed repair.

Only immutable refs/heads/checkpoints/wd/<approved-workspace> may be pushed. Source HEAD/index are not changed. Publication verifies the remote commit. A lost receipt after a successful push reconciles the existing tree instead of duplicating a commit. Network retries use increasing delays and stop after five attempts; authentication/integrity failures require explicit operator retry. One capture/publication job runs at a time. Each capture is at most24MiB; the private local outbox has a512MiB quota and a1GiB disk reserve. Quota exhaustion blocks rather than deleting unpublished recovery data.

## Local controls

The installed private world-local.ps1 command exposes status, pause, resume, reconcile, retry, stop and start. The loopback health route is GET /healthz. Full status and control require a per-install token, sent only as an Authorization header. Non-loopback Host values, browser Origin headers, query-string tokens and arbitrary commands are refused. No public tunnel, firewall exception or remote control surface is installed.

Machine binding checks a salted digest of Windows machine GUID, hardware UUID, current user SID and hostname. This is an operational machine/user pin, not TPM attestation or protection against the same fully privileged user. Runtime code and configuration are hash-pinned outside the mutable worktree. Software/policy upgrades require an explicit reviewed installation; agents cannot change their own guards.

## Boundaries and recovery

The guardian repairs process liveness, directory notification subscriptions and transient publication failures. It does not fix application code, bypass failed tests, invoke AI providers, approve releases, send email, alter Apple resources or obtain Hornet permissions. Agent queue/receipt counts are observed without executing queued tasks. Installation/autostart requires the user's interactive Windows logon; it cannot operate while the laptop is powered off. No sleep settings are changed.

Private state, machine binding, access token, captured archives and operational receipts remain in WORLD.EXE-ops/local-supervisor. Previous project timer definitions are exported before cutover; rollback disables/stops only the new supervisor and restores the prior enablement of the two replaced WORLD.EXE tasks. The independent first-player review remains separate and exact-build scoped.

## Tests

python -m unittest discover -s DevTeam/tests -p test_localops.py -v

The suite covers offline local capture, immutable publication, unchanged-tree network suppression, duplicate-push recovery, index/HEAD preservation, secret/path gates, HTTP authorization/Host/Origin rules, retry limits, crash-released locking, subprocess timeout cleanup, native directory notifications and Windows child-job termination. Deployment receipts separately establish live liveness recovery; unit success is not deployment evidence or an iOS acceptance result.

## Guardian-exit fallback

The initial forced guardian termination was not automatically recovered by Task Scheduler within100seconds; the failed receipt is retained privately. The native fallback waits on a Windows process handle, validates the exact project task/action before starting it, respects intentional stop, disabled tasks and recovery circuits, and caps recovery at three attempts per ten minutes. It does not enable Windows event logging, request administrator access, install a system service, or introduce a periodic source/job runner. The recovery observer is also launched at the user's logon. Simultaneous loss of both supervisors or of Windows itself is outside the tested recovery envelope.
