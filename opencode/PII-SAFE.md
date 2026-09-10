# PII-Safe Agent Suite Plan

Status: not deployed. The four safe agent files were removed until the
LiteLLM gateway goes live; the suite is one command away whenever it is
needed (`make generate-safe-agents`, which recreates all four from the
base agents), and `make test-agents` reactivates its safe checks
automatically when the files reappear.

This note plans a parallel orchestration suite (manager, worker, reviewer,
verifier in their `-safe` variants) where every request is pinned to the
paid Z.AI coding plan through the native `zai-coding-plan` provider and
never touches the LiteLLM gateway or its free-tier pool. It exists because
the cascade in `GATEWAY.md` routes through models whose free-period terms
allow training on submitted data (big-pickle, MiMo, Ling) or trial logging
(Nemotron on NVIDIA endpoints), which disqualifies them for secrets,
credentials, customer data, and private third-party content.

## Open decisions

- **Build/Plan dispatch scope**: current lean is no hard task gating on
  `build` and `plan`; both trios stay dispatchable. The posture is
  defaults rather than gates: the default session model is paid
  (`zai-coding-plan/glm-5.3`), so interactive work rides paid unless
  explicitly switched, and free capacity becomes a conscious opt-down
  (Tab to the cascade session model, or prompt-level choice of free
  workers) for throwaway tasks. Agent descriptions should carry the
  routing signal (base trio labeled free-cascade, safe trio labeled
  paid) so the choice is visible at dispatch time. Accepted trade: the
  boundary is a habit plus a default instead of a structure, mitigated
  by the unsafe direction requiring an affirmative act. Manager-mediated
  bulk stays free always; interactive is paid by default, free on
  explicit choice. Revisit and finalize when the LiteLLM gateway goes
  live.

## What "PII safe" claims, precisely

The safe suite removes the documented free-tier data policies from the
request path. It is not a compliance certification: Z.AI's coding plan
carries its own data terms, which must be read for any real PII-handling
obligation, and this plan assumes the coding-plan endpoint is acceptable
for the user's personal sensitivity bar. If that assumption changes, the
safe suite needs a different pinned provider, and nothing else in the
design moves.

## The safe suite

| Agent | Mode | Model | Delta from base role |
|-------|------|-------|----------------------|
| `manager-safe` | primary | session (user-selected) | Full manager duties; dispatches only to `-safe` subagents |
| `worker-safe` | subagent | `zai-coding-plan/glm-5.3-flash` (pinned) | Identical duties to worker; paid pin instead of `gateway/cascade` |
| `verifier-safe` | subagent | `zai-coding-plan/glm-5.3-flash` (pinned) | Identical duties to verifier |
| `reviewer-safe` | subagent | session (user-selected) | Identical duties to reviewer |

The mechanical roles pin flash so no dispatch inside a safe task can reach
a free model regardless of context. The judgment roles (manager-safe,
reviewer-safe) deliberately follow the session model, which the user
selects: running safe work means switching to `manager-safe` with a paid
session model, and that selection is the user's responsibility, recorded
here as a design decision rather than an oversight.

## Worker inclusion

The request named manager, reviewer, and verifier. The plan includes
`worker-safe` anyway, because the worker is the role that reads and writes
the actual files: it sees more sensitive content than any other role, so a
safe suite without a safe worker protects the least exposed agents and
leaves the largest PII surface on free models. If the intent was
analysis-only safe mode (reviewing manually produced changes), drop
`worker-safe` and record that scope here; as long as implementation work
happens under safe mode, it must exist.

## Structural guarantees

1. **Pinned mechanical roles**: `worker-safe` and `verifier-safe` name
   `zai-coding-plan/glm-5.3-flash` in their frontmatter, so every
   implementation and verification dispatch inside a safe task is
   structurally paid-only. The judgment roles follow the session model by
   design (see the suite table): if the session model were ever
   `gateway/cascade`, manager-safe and reviewer-safe would ride the free
   pool, which is why safe mode requires a paid session model and why that
   selection stays with the user.
2. **No gateway hop**: safe agents reference the native provider directly.
   The gateway is a separate opencode provider entry (`gateway`), so
   pinned agents cannot produce a LiteLLM request, and every safe prompt
   forbids naming or suggesting gateway models.
3. **Bidirectional dispatch isolation**: the base `manager` allows only
   `worker`, `verifier`, and `reviewer` (deny-by-default through `"*":
   "deny"`), so it cannot dispatch any `-safe` agent; `manager-safe`
   symmetrically allows only `*-safe` subagents. A safe task cannot leak a
   dispatch to a free-model agent and vice versa. The known SDK caveat
   from `DESIGN.md` applies: on SDK versions where the `permission.task`
   key is a no-op, the prompt prohibitions in both managers are the
   backstop.
4. **Selection at the top only**: safe mode is chosen by switching to
   `manager-safe` as the primary (Tab) with a paid session model.
   Everything below inherits the guarantee; there is no per-dispatch
   decision an agent can get wrong.

## Leak vectors outside the suite

- **Hidden system agents**: session titles, summaries, and compaction run
  on hidden agents whose defaults are small Zen-hosted models, and titles
  embed user prompt content. Fix globally, not per-suite: configure
  `title`, `summary`, and `compaction` agents to
  `zai-coding-plan/glm-5.3-flash` in `opencode.json`. This benefits every
  session and is a prerequisite for the safe suite's claim, since these
  agents fire during safe sessions too.
- **User-selected primary model**: pinning covers dispatched agents, not
  the model a human picks for a conversation. The safe workflow is: switch
  to `manager-safe` first, then paste sensitive content. A checklist line
  in the manager-safe prompt restates this.
- **Out of scope**: `webfetch`, MCP servers, and plugins move data by
  design and are unaffected by model pinning. Sensitive tasks should not
  use them, enforced by prompt, not structure.

## Configuration sketch

Each safe agent file is a copy of its base file with three deltas:

```yaml
---
description: Executes implementation tasks end to end (PII-safe, paid only)
mode: subagent
model: zai-coding-plan/glm-5.3-flash
permission:
  task:
    "*": "deny"
---
```

Plus a short preamble appended to the prompt body: this agent runs on the
paid provider only, must never name or select gateway models, and for
`manager-safe`, must dispatch exclusively to `worker-safe`,
`verifier-safe`, and `reviewer-safe`.

The hidden-agent pins in `opencode.json`:

```json
{
  "agent": {
    "title": { "model": "zai-coding-plan/glm-5.3-flash" },
    "summary": { "model": "zai-coding-plan/glm-5.3-flash" },
    "compaction": { "model": "zai-coding-plan/glm-5.3-flash" }
  }
}
```

## Drift control

The safe files are derived artifacts, not hand-maintained copies:
`opencode/.local/bin/generate-safe-agents` (exposed as
`make generate-safe-agents`) regenerates all four from the base agents
using one transform: frontmatter deltas, agent-name renames in the manager
body, and the safe preamble. After any base-agent edit, regenerate and
commit the twins together. `make test-agents` enforces this two ways: the
structural assertions (pinning policy, session inheritance where designed,
preamble, both isolation directions) and a derivation-parity check that
regenerates into a temp directory and diffs against the committed files,
failing with the regeneration command whenever a safe file was hand-edited
or a base change was not propagated. The only duplication that can drift
is the transform itself, which is reviewable in one place.

## Verification plan

- S1, structural: the drift-control test passes (pins, no gateway
  references, task-permission shapes, hidden-agent pins in
  `opencode.json`).
- S2, dispatch isolation: with the gateway running, dispatch a trivial
  task through `manager-safe` and confirm the LiteLLM logs record zero
  requests for the entire run.
- S3, hidden agents: create a session under safe mode, confirm the
  generated title arrives while the gateway logs stay empty.
- S4, soak: one real sensitive-flavored task through the full safe suite,
  same zero-request assertion, plus the normal verification chain.

## Rollout steps

1. Ready on demand: the transform exists as
   `opencode/.local/bin/generate-safe-agents` (`make generate-safe-agents`);
   the four `-safe` agent files are currently deleted and are recreated by
   that command (pinned flash for the mechanical roles, session
   inheritance for the judgment roles, safe preambles, renamed dispatch
   references).
2. Pin `title`, `summary`, and `compaction` in `opencode.json`.
3. Encoded in the transform: bidirectional isolation. The base `manager`
   is deny-by-default over its `worker`/`verifier`/`reviewer` allow-list;
   `manager-safe` allows only the `-safe` suite; every safe subagent has
   `task: deny`.
4. Done: `make test-agents` (wired into `make test`) asserts the base
   invariants always, and the pinning policy, session inheritance,
   preamble, isolation directions, and derivation parity whenever the
   safe files exist.
5. Run S2 through S4 after deployment.
6. Record the suite in `DESIGN.md` (roles table plus a short section) and
   link it from the `GATEWAY.md` risks bullet.

## Risks

- Prompt duplication drift (mitigated above, never fully eliminated while
  the files are hand-copied).
- Z.AI terms change: the "paid is acceptable" assumption must be rechecked
  when the subscription terms change; the plan's claim collapses if their
  retention posture shifts.
- Overtrust: the suite protects the model routing path only. PII safety
  against local threats, logs, or accidental `webfetch` use is unchanged,
  and the safe prompts say so.
