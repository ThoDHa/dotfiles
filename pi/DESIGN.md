# Pi Manager Mode Posture

This note is the pi counterpart of [opencode/DESIGN.md](../opencode/DESIGN.md),
scoped to the Manager Mode posture. The orchestration design, the role model, and the
manager's behavioral rules keep their canonical homes (the manager agent file,
opencode/DESIGN.md, and the shared skills both harnesses load); this note records
how those rules are made binding on pi: what the manager may write, where the
rules come from, when the mode is active, who is exempt, and where the
enforcement honestly ends. It is a design record, not a rule source, and it does
not restate the rules it points at.

## Writeless posture

The pi manager holds no edit/write tool use: on activation the mode removes both
tools from the advertised surface and denies any edit/write call that still
arrives, so file-content authoring is barred at two layers. The sanctioned
writes are exactly two families. The five `tasks` CLI channels (`tasks log`,
`tasks report`, `tasks edit`, `tasks set`, `tasks claim`) carry every
protocol-record write; the serialization, ownership, and channel rules are
normative in the [task-files skill](../agents/.agents/skills/task-files/SKILL.md).
Git history shaping carries integration: commit, push, and amend/fixup are
retained manager duties under the
[git-protocol skill](../agents/.agents/skills/git-protocol/SKILL.md), with force
pushes guarded by its
[Force Push Protection](../agents/.agents/skills/git-protocol/SKILL.md#force-push-protection)
requirement of explicit user confirmation. The shared mode semantics (the mode
definition, activation and deactivation phrases, and the pure-coordinator branch
of failure semantics) live in the
[delegation skill](../agents/.agents/skills/delegation/SKILL.md), which both
harnesses load; everything beyond the sanctioned writes moves through the fleet
rather than through the manager's own hands.

## Single behavioral source

The behavior of a pi manager session is defined once, in the manager agent file
([manager.md](../opencode/.config/opencode/agents/manager.md)), whose
dual-harness note maps the opencode mechanics to their pi equivalents. The
manager-mode extension injects that file's pinned body (the sha256 pin under
[tests/pi-agents/manager-body.sha256](../tests/pi-agents/manager-body.sha256))
verbatim as the session's governing protocol at activation, beside the
tool-surface enforcement. This note records the posture and its enforcement
shape; the injected body governs conduct. No pi-side document restates the
rules, and a conduct question about a pi manager session resolves to the
injected body first and this note second.

## Default-on activation

Every pi session, interactive and headless, activates Manager Mode at startup
with no user action: a fresh session is writeless and manager-governed from turn
one, making the posture the visible norm rather than an opted-in special case.
Deactivation is per-session: "/manager off" (with "stand down" and "solo"
honored as the same command's synonyms) restores the full tool surface for that
session only, and the next session reasserts the default. An off state is not
sticky across sessions, and activation never depends on the user remembering to
switch anything on.

## Child exclusion

Subagent sessions spawned by the subagent extension never activate the posture:
a worker child keeps edit/write, starts with the normal tool surface, and is not
manager-governed. The exclusion is structural, not behavioral, so no dispatch
can accidentally hand a writeless surface to the agent expected to edit code.
Without it, default-on would make every worker inherit the posture and the fleet
could not edit at all.

## Headless opt-out requirement

Headless runs cannot invoke "/manager off", so default-on would otherwise be
inescapable for scripted and automated sessions. The extension MUST ship an
explicit opt-out mechanism (an environment variable or a CLI flag, chosen
against pi's CLI surface) that starts a session with Manager Mode inactive; this
note records the requirement, and the extension's implementation picks the
mechanism and documents the choice here. Interactive users have "/manager off"; headless runs
have the opt-out; neither path weakens the default for every other session.

## Known limits

Two limits are recorded honestly. First, the mechanical denial covers the
edit/write tools; a non-commit shell write past the gate (a redirect, a `tee`,
an in-place interpreter edit) is policy-barred by the injected body, not
mechanically denied, because mechanical denial would need brittle shape-matching
over the whole bash surface, and the accepted posture is the two-layer tool gate
plus conduct. Second, the mode constrains, it does not replace: the generalist
substrate under Manager Mode is the same pi agent as always, governed by
tool-surface removal and the injected body, so the mode's boundaries are only as
strong as those two constraints. They are an enforcement shape, not a different
agent.
