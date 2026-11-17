# Task Storage Isolation: Feasibility Probes and Walking Skeleton

Worker artifacts for ORCH-4-10-1 (feasibility probes and walking skeleton, design-bearing tier) under the ORCH-4-10 parent (enforce raw task storage isolation). Nothing in this subtree touches live pi or opencode enforcement configuration; the mask, the guard seam, and the escape channel here all operate on a hermetic fixture repo built per run under `/tmp`.

## Contents

- `probes/bwrap-probes.md` - deliverable 1 evidence: bwrap unprivileged user-namespace viability, tmpfs masking of a gitignored `.tasks` tree inside a git repo, symlink traversal through the mask, AF_UNIX escape viability, and the net-shared namespace shape. All green.
- `probes/opencode-surface.md` - deliverable 2 evidence: the installed opencode (v2.3.0, superseding the recon's v2.1.4) exposes a `read` permission action and an ordered `permissions` ruleset at schema level; no `sandbox` key exists in the opencode config schema; plugin load paths and the guard hook surface. Includes the embedded Claude-Code-style sandbox runtime finding flagged for the ORCH-4-10-3 mechanism decision.
- `run-skeleton.sh` - deliverable 3: the walking skeleton runner. One run dispatches a pi child through the vendored subagent extension's own spawn path under bwrap with the fixture `.tasks` masked, and demonstrates one denied direct read (plus symlink traversal) and one passed sanctioned `tasks` verb through the parent-side AF_UNIX whitelist service.
- `lib/patch-subagent.py` - runtime copy + patch of the vendored subagent extension. The patch renames `getPiInvocation` and appends a wrapper that prefixes the resolved child invocation with bwrap when `SKELETON_BWRAP_MASK` and `SKELETON_BWRAP_SOCKET` are set. This is the exact seam ORCH-4-10-2 will productionize behind explicit activation; the live extension is never modified, and the patch script fails loudly on upstream seam drift.
- `lib/task-service.py` - the G3-approved escape shape in skeleton form: parent-side AF_UNIX service executing exactly one sanctioned verb shape (`tasks show <fixture-task> --json` against the fixture board), refusing everything else with a logged non-zero response.
- `lib/uds-client.py` - child-side client; sends one argv request over the bind-mounted socket file and relays the service response unchanged.

## Running the skeleton

```
bash tests/task-storage-isolation/run-skeleton.sh
```

Requires: bwrap, pi, the tasks CLI on PATH, the vendored subagent extension at `~/.pi/agent/extensions/subagent`, and a reachable model gateway (the run makes two LLM calls: parent dispatcher and worker child, both on the fleet worker model by default; override with `run-skeleton.sh <model>`).

Success output is the acceptance evidence:

```
SKELETON-VERDICT: DENY-VERIFIED (direct and symlink reads denied under mask)
SKELETON-VERDICT: PASS-VERIFIED (sanctioned tasks verb round-tripped through the UDS service)
```

On failure the runner keeps its scratch directory and prints its path for inspection.

## What the skeleton establishes

The bash-boundary mechanism contract the per-harness enforcement slices (ORCH-4-10-2, ORCH-4-10-3) build on:

1. The vendored extension's child spawn (`getPiInvocation` resolution feeding `spawn` with json-mode argv, inherited env, ignore/pipe/pipe stdio) functions unchanged under a bwrap prefix that ro-binds the host, tmpfs-masks the fixture `.tasks`, and shares the network namespace (model-bound children need the gateway).
2. The mask denies every read class probed (direct, relative, absolute, parent-traversal symlink, realpath-normalized) with no lexical path guard involved.
3. Sanctioned board verbs pass through a parent-side whitelist service over a bind-mounted socket file while the child keeps no other view of the masked tree.

## Verdict memo

Recorded in the ORCH-4-10-1 task Work Log and the worker's final report: pi lands on G3 (conditional mechanism: bwrap child-wrap plus parent-side task service, approved and demonstrated at skeleton scope); opencode lands on G2-plus (structured-tool `read` denial now schema-expressible on v2.3.0; the bash boundary remains G3-conditional via the socket-service shape, with the newly discovered embedded sandbox runtime as an additional design-review candidate). Neither harness lands on G5: no probe failure or blocker was found.
