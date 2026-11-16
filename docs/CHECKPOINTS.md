# Five-minute source recovery on WD

The user requested source saves every five minutes. A native Windows Task Scheduler task, `WORLD.EXE-GitHub-saveups-5min`, runs a reviewed copy of `scripts/github_checkpoint.py` on WD using the current Windows user's existing GitHub authorization. This is not an unattended AI development loop.

## Recovery branches

- `checkpoints/wd/main`: canonical checkout.
- `checkpoints/wd/contact-testbed`: CONTACT implementation worktree.
- `checkpoints/wd/contact-release`: release identity repair worktree.

Each snapshot contains source files and `CHECKPOINT.json` recording the source commit and branch. Snapshot commits are explicitly unvalidated; they are not releases or CI passes. New snapshots are pushed only when approved source changes. Every task run records its timestamp and result locally. Offline failures are visible in the next status file and retried by the next scheduled iteration; no force pushes are used.

## Scope and safeguards

The snapshot uses an alternate temporary Git index and commit-tree. It never stages, resets, stashes, switches or commits on an active working branch. It covers allowlisted source, documentation, workflow and dependency-manifest paths, including new text source files. Only already tracked app-icon PNGs are included as binary assets. Files must remain within an approved WORLD.EXE worktree. File/total size limits, UTF-8 checks and conservative credential-pattern checks reject suspicious snapshots. These checks reduce risk; they are not a guarantee that arbitrary secrets embedded in source can be recognized.

Private operational files, Git configuration, credentials, model weights, native frameworks, caches, archives and generated binaries are excluded. No other repository, including Rhea RF Spanner, is modified.

## Operation

WD must be awake, the configured Windows user must be signed in, and GitHub must be reachable. The task does not wake the machine. Overlapping instances are ignored and an OS lock prevents simultaneous index work. Log/status: `WORLD.EXE-ops/checkpoints/latest.json` and `history.jsonl`. Configuration: `WORLD.EXE-ops/checkpoint-config.json`.

One iteration: `python github_checkpoint.py --config checkpoint-config.json`.
Preflight without upload: add `--dry-run`.
To pause: `Disable-ScheduledTask -TaskName 'WORLD.EXE-GitHub-saveups-5min'`.
To resume: `Enable-ScheduledTask -TaskName 'WORLD.EXE-GitHub-saveups-5min'`.

The installed task runs a reviewed operational copy, not a mutable script from the worktree. Updating the public source alone does not change the scheduled executable. Inspect before deploying a newer script.
