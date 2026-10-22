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

The pi manager holds no edit/write tool use: on activation the mode removes both tools from the advertised surface and denies any edit/write call that still arrives, so file-content authoring is barred at two layers. The sanctioned writes are exactly two families. The five `tasks` CLI channels (`tasks log`, `tasks report`, `tasks edit`, `tasks set`, `tasks claim`) carry the protocol-record writes; the serialization, ownership, and channel rules are normative in the [task-files skill](../agents/.agents/skills/task-files/SKILL.md). `tasks new` sits outside the named five and is not a sixth manager-held write channel: it stamps only the template scaffold with canonical header fields, and the body prose is delegated drafting labor dispatched to the planner under the injected body's rule 2. Git history shaping carries integration: commit, push, and amend/fixup are retained manager duties, governed by the [git-protocol skill](../agents/.agents/skills/git-protocol/SKILL.md) and granted by the injected manager body's git-authority section, with force pushes guarded by the skill's [Force Push Protection](../agents/.agents/skills/git-protocol/SKILL.md#force-push-protection) requirement of explicit user confirmation. The shared mode semantics (the mode definition, activation and deactivation phrases, and the pure-coordinator branch of failure semantics) live in the [delegation skill](../agents/.agents/skills/delegation/SKILL.md), which both harnesses load; everything beyond the sanctioned writes moves through the fleet rather than through the manager's own hands.

## Single behavioral source

The behavior of a pi manager session is defined once, in the manager agent file
([manager.md](../opencode/.config/opencode/agents/manager.md)), whose
dual-harness note maps the opencode mechanics to their pi equivalents. The
manager-mode extension injects that file's pinned body (the sha256 pin under
[tests/pi-agents/manager-body.sha256](../tests/pi-agents/manager-body.sha256))
verbatim as the session's governing protocol at activation, beside the
tool-surface enforcement. The mechanism is the system prompt's append field:
on every agent run while the mode is active, the extension appends the body
(the vendored `pi/extensions/manager-body.md` sidecar, byte-extracted from
the fleet file) to the session's system prompt through the
`before_agent_start` event's prompt options, and deactivation stops the
append. The extension re-derives the sidecar's sha256 at activation against
the pin and announces a warning instead of injecting when it mismatches; the
sync test (tests/pi-extensions/test-sync.sh) is the standing enforcement
that the deployed copy stays pinned. This note records the posture and its enforcement
shape; the injected body governs conduct. No pi-side document restates the
rules, and a conduct question about a pi manager session resolves to the
injected body first and this note second.

## Default-on activation

Every pi session, interactive and headless, activates Manager Mode at startup with no user action: a fresh session is writeless and manager-governed from turn one, making the posture the visible norm rather than an opted-in special case. Deactivation is per-session: "/manager off" (with "stand down" and "solo" honored as the same command's synonyms) restores the full tool surface for that session only, and the next session reasserts the default. The "solo" argument means only deactivate-to-normal here: it restores the surface and drops the injected body, and it is distinct from the delegation skill's Manager Mode (Solo), the direct-execution state that keeps the mode's structure, which a writeless pi manager cannot enter. Conversational Solo-class resource answers route to the off-decision: the delegation skill's resource table maps "just me" and "I'm alone" to Manager Mode (Solo), and since a writeless pi manager cannot enter that state, such an answer lands on deactivate-to-normal, exactly as the "solo" argument does. An off state is not sticky across sessions, and activation never depends on the user remembering to switch anything on.

## Child exclusion

Subagent sessions spawned by the subagent extension never activate the posture:
a worker child keeps edit/write, starts with the normal tool surface, and is not
manager-governed. The exclusion is structural, not behavioral, so no dispatch
can accidentally hand a writeless surface to the agent expected to edit code.
Without it, default-on would make every worker inherit the posture and the fleet
could not edit at all. The implemented check is a session-shape gate: sessions running pi's json output mode, the subagent extension's child spawn protocol (`pi --mode json -p --no-session`), never activate, and the same gate reads the headless opt-out environment variable, so a spawn path that marks its children explicitly can set `PI_MANAGER_MODE=off` for them. The json-mode check alone covers the subagent extension's current spawn signature; the environment variable is the general convention a changed spawn path can adopt without a new exclusion mechanism. The json-mode gate exempts every json-mode session, a user's manual `pi --mode json` run included: scripted contexts are the opt-out population, and print mode stays governed. The exclusion is belt-and-braces: the host-side subagent extension also marks every child spawn with `PI_MANAGER_MODE=off` in the spawn env.

## Headless opt-out

Headless runs cannot invoke "/manager off", so default-on would otherwise be
inescapable for scripted and automated sessions. The implemented opt-out is a
CLI flag: the extension registers `--no-manager-mode` against pi's extension
flag surface, and launching with it starts the session with Manager Mode
inactive. Because headless launch lines are often built by tooling that cannot
take extra flags, the same gate also reads the environment variable
`PI_MANAGER_MODE`: a value of `off` is equivalent to the flag, and any other
value, or its absence, leaves the default standing. Both mechanisms are
per-session: an opted-out session starts normal, and the next session launched
without the flag or the variable reasserts the default. Interactive users have
"/manager off"; headless runs have `--no-manager-mode` and
`PI_MANAGER_MODE=off`; neither path weakens the default for every other session.

## Known limits

The limits are recorded honestly. First, the mechanical denial covers the edit/write tools; a non-commit shell write past the gate (a redirect, a `tee`, an in-place interpreter edit) is policy-barred by the injected body, not mechanically denied, because mechanical denial would need brittle shape-matching over the whole bash surface, and the accepted posture is the two-layer tool gate plus conduct. The force-push guard shares that shape-based character: its matcher matches command tokens exactly, so quoting or nested invocations (`bash -c "git push -f"`, `$(git push -f)`) can evade matching, and that residual is conduct-covered, not mechanically denied. Second, a pin mismatch or an unreadable sidecar yields a session that stays writeless and force-guarded but carries no injected governing body: the posture fails open on conduct and fails closed on tools, deliberately, because the fail-closed alternatives are worse (denying activation bricks sessions on a stale pin, and deactivating to the full surface re-arms edit and write). Third, write-shaped MCP tools (qhaway `remember`, the playwright suite) remain on the surface under the mode; they are conduct-governed by the injected body and the corpus rules, never mechanically denied. Fourth, the mode constrains, it does not replace: the generalist substrate under Manager Mode is the same pi agent as always, governed by tool-surface removal and the injected body, so the mode's boundaries are only as strong as those two constraints; they are an enforcement shape, not a different agent. Fifth, no headless force-push override exists: `--force-with-lease` is denied headless and confirmed in the TUI, so a scripted flow that needs a user-approved lease push must use the mode opt-out until a narrow override is warranted.
