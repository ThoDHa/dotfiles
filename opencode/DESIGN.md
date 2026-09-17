# OpenCode Orchestration Design

This note documents the manager, worker, verifier, and reviewer agent
pipeline, the git authority model, and the task-file integration. The
agent files under the opencode config carry the normative requirements
in RFC 2119 form; this note explains the architecture and the reasoning
behind them.

## Roles

| Agent | Mode | Model | Duties |
|-------|------|-------|--------|
| manager | primary | session | Decomposition, dispatch, unit worktrees and branches, planning approval, architecture duties at coordination scale (exploration, builds, verification runs, CI/CD operation), integration and history shaping, pushes, reconciliation |
| worker | subagent | glm-5.3-flash | Implementation inside an assigned territory, checkpoint commits on the unit branch, real-time work logs, reports |
| verifier | subagent | glm-5.3-flash | Runs tests, linter, and typechecker once each, reports raw results without interpretation |
| reviewer | subagent | session | simplify-review in analysis-only mode, expectation checks, no command execution beyond read-only git |

The manager is a coordinator, not an implementer: it holds no
implementation duty (it never authors implementation content), and its
file edits are limited to `.tasks/**`. Integration commits and pushing
are coordination duties, not implementation work; unit workers commit
their own checkpoint work on the branches the manager assigned them.
The architect grant follows the same line: the manager delegates as
much work as the fleet can take, and the command freedom exists to
unblock and steer the fleet (scouting a dispatch, unblocking a worker,
checking a unit's result); any duty that grows into sustained work of
its own is dispatched to a fleet agent rather than absorbed, since
capability never reduces the delegation duty.

The verifier and reviewer split verification along the judgment line:
transcription of command results is mechanical and runs on the flash
model, while code review and result interpretation need the full model.
The verifier reports exit statuses, the runner's own counts, and
verbatim failure output; interpretation happens in the manager's
reconciliation, never inside the verifier.

## Git authority

Workers never push, in any form: the `git push*` permission is denied and
the prompt prohibition covers force variants, aliases, and `sh -c` routes.
Under the worker-commit model recorded here, the manager creates a
worktree under `.worktrees/` and a unit branch for every unit dispatched
alongside a running sibling before the dispatch goes out (a lone unit may
use the main tree), and the worker commits territory-scoped work at each
meaningful checkpoint on that branch, every commit a complete logical
change leaving the suite green (normative in the worker agent file). The
branch and its commit range give per-unit attribution, and in-flight
work survives a lost session: crash resilience and attribution are the
model's payoffs, alongside per-unit verification against the branch.

The manager owns integration and history (normative in the manager agent
file). It verifies against the unit branch, and on a pass shapes the
branch judgment-based: squash or merge the checkpoints into one commit
when they form one logical change, preserve separable commits when they
stand alone, then integrate the result into the main line. Full git
control (rebase, amend, reset, revert; fetch and pull denied per known
limits) is granted in the manager's
permission map; force-push variants stay ask-gated, and pushed history
is reshaped only on explicit user request. Staging is reserved for a
main-tree unit's output: only the files that worker changed, never
pre-existing changes. Before the first dispatch the manager confirms a
clean tree with `git status` and records the base commit with
`git rev-parse HEAD`.

The manager pushes on its own judgment once a unit is integrated and
verified, the verifier's results are clean, and the review passed,
without waiting to be asked, and pushes whenever the user asked; it
never pushes half-finished or unverified work and never when the user
forbade it. Pushed history is immutable: the manager never reshapes,
amends, or rewrites anything already on the remote; it does so only
when the user explicitly requests it, never on its own initiative, and
then via force-with-lease per the
`git-protocol` skill. A unit working in a worktree reaches the `.tasks`
board by directory walk-up (see known limits), so unit branches need no
board mirroring.

## Task-file integration

When the task-files protocol is active, each unit is a child task file,
and every `.tasks/` write has exactly one owner. The manager owns the
task files themselves: header fields, acceptance-criteria checkboxes,
status transitions, and the dashboard, rendered through the `tasks`
CLI. Dispatched workers own exactly two channels, both inside that CLI
and both attributed to them via `--from`, per the task-files skill's
Agent Write Path: interim progress as appended Work Log entries, and
the final report as a verbatim deposit under `.tasks/reports/` whose
Work Log entry carries the agent-supplied digest and a relative link.
The manager never restates
report bodies: its dispatch entry records the instructions given,
written before the call, and its analysis is an independent check on
the digest, not a retelling. A worker that finds the plan wrong flags
that in its report instead of editing the file. The single carve-out is
the planning-mode exception: a worker dispatched to plan a Triage task
may edit exactly the planning sections of that named file (Objective,
Success Criteria, Technical Approach, Risk Assessment, Testing
Strategy, Task Breakdown, Decision Log), while header fields,
checkboxes, Progress, status, and the dashboard stay manager-owned, and
no status transition, Triage → Ready included, belongs to the planning
worker.

The reports mechanism keeps bulky output out of the task files, per the
task-files skill's Reports Namespace: one directory per task file under
`.tasks/reports/`, keyed by the file's full basename including `.md`,
holding deposits named `NN-<slug>.md`. `NN` is a zero-padded sequence
number assigned in deposit order, one past the highest already on disk,
so numbers are never reused even when gaps appear. Because `current/`,
`archive/`, and `reports/` are siblings, the `../reports/...` relative
link in a task file resolves identically from both directories, so
archiving moves the task file alone and reports never move. `tasks
log`, `tasks report`, and the dashboard render they trigger each hold
the exclusive `flock` on `.tasks/.lock` for their read-modify-write
span, a process-held lock released on exit, so concurrent sessions
serialize instead of racing. `tasks show <taskfile> --tail N` prints
the header fields, the Latest Update pointer, and the last N Work Log
entries without taking the lock: the delta read for catching up on a
task. Until the subcommands exist in an environment, the manual
fallback preserves the same contract by hand: the worker writes the
next report file at the canonical path without overwriting and returns
path and digest to the manager, who makes the entry and header writes
(the task-files skill's Manual Fallback). Without task files at all,
worker reports go to `/tmp/opencode/reports/<unit-name>.md` as
artifacts.

Every completed task's Final Summary opens with a closure digest, at
most five lines naming the outcome, the key decisions, and links into
the details (report deposit paths, the Decision Log), sized
proportionally to the task; the normative text is the task-files
skill's Closure Digest section. When planning fans the work out into
parallel children with overlapping territory, a shared reconnaissance
artifact is the default: the parent deposits a `01-recon` report via
`tasks report --slug recon`, and each child references it from its
Files to Review, so exploration happens once instead of once per
child; skipping it requires a Decision Log exception naming the reason
(a single child, territory already mapped, or the unknown-contract
case where a walking skeleton precedes fan-out). The normative text is
the task-files skill's Triage to Ready Planning Phase, tied to the
manager's approval review by the delegation skill's Planning Approval
Authority. Small tasks use the lite profile defined in the task-files
skill.

## Dispatch economy

The dispatch economy requirements are normative in the
execution-standards global rule and bind every dispatcher, including
standard parallel spawns outside Manager Mode: dispatch prompts carry
pointers, not prose, with the objective and its success criteria as
the only narrative; global standards are never restated, since every
agent already receives them through the global instructions config;
verification commands are referenced via the project's AGENTS.md when
it documents them. Session resume for dependent units is the
delegation skill's context continuity rule: the manager resumes the
earlier unit's worker instead of dispatching fresh, so context stays
in the worker and reports are not retold through the manager; fresh
dispatches with the report as background remain for cross-worker
dependencies and poisoned contexts.

When work is tracked in task files, the dispatch prompt itself may be
a pointer instead of a duplicated payload, per the execution-standards
rule's Dispatch Economy and the delegation skill's Dispatch by
Reference: the manager writes the complete instructions verbatim into
the task file's Work Log (the Instructions Given entry) before making
the Task call, and that entry is the authoritative instruction record.
The call carries only a minimal bootstrap frame: the agent's role, the
task file to read, and the report-back expectation. Instructions are
written once, never restated in the call, and steering issued while
the agent runs goes through the dispatch channel, never only in the
file, since the agent cannot be assumed to re-read it mid-flight.

Dispatched agents also carry three conduct rules of their own,
normative in the same rule. Territory: stay inside the assigned files,
modules, and concerns, and flag a needed change outside them rather
than making it. Clarification routing: questions return to the
dispatcher in the reply, never to the user directly. Permission-denial
relay: a denial carrying a user message is a user question, so the
agent stops dependent work and returns the message verbatim to the
dispatcher; a bare denial is a hard no, not retried, with the blockage
routed to the dispatcher instead; the session-fatal case is covered
under known limits.

## Verification chain

Verification runs as a per-unit pipeline, not in batch (normative in
the manager agent file): when a unit's worker returns, that unit's
verifier and reviewer are dispatched in parallel. The reviewer is
path-scoped to the unit's diff against the base commit (the unit
branch's committed range, or a main-tree unit's uncommitted
working-tree changes); the verifier runs against the unit branch,
inside the unit worktree (isolated by construction), in the main tree
for a lone unit when the territories in flight are test-disjoint, or
pinned to a throwaway worktree at the unit's state (unit work
committed to a temporary branch, or the working tree copied in)
otherwise; when the shared state is a fixed external path that
pinning cannot isolate, verification runs at the integration commit
instead. Neither edits files, and only the verifier runs non-git
commands, so the two cannot contend. Four independent sources are
reconciled per unit: the worker's claims from its report, the
verifier's raw command results, the reviewer's findings, and git
ground truth (`git diff --stat` and `git log` against the base
commit). The verifier always runs; the reviewer is skipped only when
the unit was mechanical (dependency bump, rename, formatting,
documentation-only). The reviewer does not re-report simplifications
the worker's own simplify-review run already records as addressed,
only findings that remain. The verifier runs the test suite, linter,
and typechecker once each and reports exit statuses, the runners' own
counts, and verbatim failure output, gating on exit status rather than
text matches. The reviewer verifies logged work against the unit's
objective, territory, and the actual changes, and runs the
simplify-review loop (simplify pass first, then review pass) without
fixing anything; it executes nothing beyond read-only git.

On a pass the manager integrates the unit and backfills the freed slot
immediately with the next Ready task whose dependencies are Completed
and whose territory is disjoint from the running set, so the pipeline
keeps its slots full instead of serializing on verification.
Discrepancies and findings get one fix-and-re-review round per unit; a
discrepancy that resurfaces after that round is deferred to a new task
rather than being hidden or looped. Reviewer suggestions each get one
disposition: small ones (mechanical, contained in the unit's changed
files) are done now by a worker and re-verified once, big ones and any
scope creep are deferred to their own new task as maybe-later work and
proposed as the next one, and only suggestions that do not serve the
user's intent may be declined, with a recorded reason. Every
disposition is recorded (Decision Log under task files, the completion
report otherwise), and undecided or unactioned suggestions are
restated verbatim to the user when work stops; without task files the
report is the only durable record. After the queue drains, one
combined seam review covers the seams between units before the batch
closes; the per-unit reviews see each unit in isolation, so only this
pass can catch cross-unit regressions.

Failure handling parks instead of blocking (normative in the manager
agent file, with the standing-restart grant for pure coordinators in
the delegation skill's Failure Semantics): on the failure of its
single mandated retry, the task is parked with a Blocked status
whose reason carries the failure summary and the attempt count,
reported to the user without blocking the queue. At every backfill or
checkpoint event, the oldest parked task whose blocking condition may
have cleared is restarted before fresh Ready work is pulled, never
into an unchanged condition. The retry count and the escalation
bounds (the total attempt bound, the identical-recurrence bound, and
the doubling restart-backoff schedule) are normative in manager.md and
not restated here; the backoff is measured on wall-clock time taken
from the board's own timestamps, since the tasks CLI stamps task file
headers (Updated) and Work Log entries with real times and the manager
reads the current time by refreshing a header through the CLI and
reading it back. This design
is the recording the delegation skill requires: the user's
standing-restart grant is recorded here and takes effect on this
task's sign-off, putting parking and checkpoint-rule restarts in force
for this orchestration from that point.

## Worktree isolation

Under the worker-commit model recorded here, a worktree under
`.worktrees/` on a unit branch is the default dispatch vehicle, created
before dispatch and torn down after integration; a parked unit's
worktree is the one exception, persisting while the unit awaits its
restart. Setups without the model reserve worktrees for same-file
contention that would otherwise serialize independent work. In both
regimes worktrees live inside the repo (disk-backed, no RAM cost),
verified gitignored via `git check-ignore`
before first creation, pruned (`git worktree prune`) before creation, and
torn down completely after integration or reconciliation: worktree removed,
metadata pruned, throwaway branch deleted (normative in the delegation
skill's Worktree Isolation and Worktree Teardown sections).

## Permissions posture

The global config allows `/tmp/**` for external-directory access and
auto-approves `doom_loop` so unattended runs cannot halt on repeated
identical tool calls. Agent permission tiers mirror their prompts: the
manager runs an allow-all bash map whose only carve-outs are the four
force-push ask entries (pushed history is reshaped only on the user's
explicit request per the git authority section) and the `git fetch*` /
`git pull*` denies behind the known limit that the manager has no
fetch or pull; gh carries no manager entries at all, so it holds full
gh access, writes and gh api included, for CI/CD coordination (the
read-only gh set, gh api excluded because patterns cannot gate its
HTTP method, now applies below the manager only: the worker's map;
the reviewer holds no gh at all); its edit denial is the single
architectural line, confining file edits to `.tasks/**` while bash
stays open; the worker holds everything except push, history
reshaping (commit amend and rebase, including pull-with-rebase, are
denied outright, matching the prompt prohibition), gh writes (the
read-only gh set), and subagent spawning; the verifier's bash is
intentionally open so it can run tests, gated only against push, and
its edit tool and subagent spawning are denied; the reviewer holds
read-only git only.

Recurring benign commands are pre-allowed so unattended runs do not
stall on permission prompts: worker and verifier allow `make
test*`, the repo's `test` and `test-*` targets (the manager's
allow-all map subsumes them, and the reviewer is deliberately
excluded, since its charter bars running tests), and the
worker additionally allows `mktemp` with templates under
`/tmp/opencode/*`, the invocation forms observed in its workflow.
Config and agent files load once at
session start, so permission edits take effect in newly started
sessions; running sessions keep the maps they already loaded.

Prefix-based bash permissions are guardrails against uninstructed
behavior, not security boundaries: a determined `sh -c` or `git -C` route
slips past them. Hard enforcement would require hooks or credential
separation.

## LRU context plugin

Every session loads the LRU context manager as a plugin: opencode.json's
`plugin` array names `./plugin/lru-context.ts`, so the transforms below
run for the manager and every subagent alike. The plugin hooks the
message-list transform (`experimental.chat.messages.transform`) to
reshape the conversation before each model call and the system-prompt
transform (`experimental.chat.system.transform`) to deliver its hint.
Token accounting is approximate: text and tool outputs are sized
in characters and divided by four, the context budget resolves in a
fixed order (a `modelContextTokens` plugin option entry keyed
`providerID/modelID` for the session's model, then the model's
declared limit from `chat.params`, then an explicit
`defaultContextTokens` option), and eviction starts
once the estimate crosses half the budget (the watermark ratio). Map
entries must be finite positive numbers (percentage strings, zero,
negative, and non-finite values are dropped at option resolution, and
entries for model ids the session never reports are simply never
looked up). When no source exists the budget is unknown
and eviction stands down
entirely rather than running against an invented one; dedup, the
errored-input purge, and the hint line still run, and opencode's
native auto-compaction remains the overflow backstop for those
sessions.

Four transforms run in order on every turn, after stale copies of the
hint line are stripped from the message list, plus a fifth,
`userFenceEviction`, that stands down unless enabled (below). Dedup
replaces the output
of an earlier identical tool call (same tool, same input) with a
`[lru-deduped]` tombstone pointing at the newer copy, whenever the
retained copy clears the same 2048-byte floor eviction applies, and
drops the superseded copy's `state.attachments` alongside the output so
a tombstoned part carries no media. File attachments dedup in a
sibling pass (`deduplicateFileAttachments`) running beside the
tool-output dedup in the same stage: a `file` part (the
`@`-reference surface, carrying `mime`, `url`, and an optional
`filename`) whose `mime` and `url` both match a newer
occurrence is replaced by a `[lru-deduped]` text tombstone naming the
newer occurrence's message index, so the superseded payload stops
reaching the provider. The key is `mime` plus `url`, the content
identity: identical basenames in different directories must not
collapse, and the optional `filename` is display metadata that falls
back to the `mime` in the tombstone label when absent or empty. The
newest occurrence is always retained verbatim, occurrences inside the
recent window are never tombstoned, and no size floor applies because
a `file` part's payload size is not observable from its `url`; file
tombstones count in the same `deduped` metric under the same
count-only accounting. The
errored-input purge replaces the recorded input of failed tool calls
older than the recent window with `[lru-purged-input]`, so prompts,
paths, and commands from failed attempts do not linger in context.
Reasoning expiry deletes `reasoning` parts from messages strictly older
than the recent window, the same boundary the purge uses: reasoning
from earlier turns has no consumers, so expiry is plain deletion with
no stash, no tombstone, and no reload path, and it runs whether or not
a budget is known. Parts at or inside the window are untouched,
including Anthropic-style signature-carrying blocks an in-flight
tool-use continuation may still need. Expired parts are counted
separately from evictions (parts and bytes on `lru_stats` and in the
metrics log) and never added back. Eviction, the main transform, ranks
completed tool outputs by last
touch (a later call against the same file, pattern, or command counts
as a touch) and, once the estimate exceeds the watermark, replaces the
least recently active outputs with `[lru-evicted]` tombstones; outputs
last touched within the most recent four messages, the `task` and
`todowrite` tools, and outputs under 2048 bytes are exempt. The
`protectedPatterns` option adds a subject-based exemption beside those
tool names: each candidate's extracted subject paths are matched
against the configured glob list (a bash command string is a subject
whose path is the command, so the same globs guard commands), and any
match keeps the output out of eviction entirely. Glob rules: `**`
spans path separators, `*` and `?` stay within one, a pattern
containing a separator must match the whole subject string, and a
slashless pattern also matches any single separator-delimited segment,
so `.env*` guards dotenv files at any depth and `**/AGENTS.md` guards
the file however deeply it was read; subjects without an extracted
path never match, and the default empty list changes nothing. Pattern
protection guards against information loss, not redundancy: dedup
still tombstones an older identical call even when both copies match a
protected pattern, because the retained newest output keeps the
content in context. Attachments
leave with the output: a completed tool part can carry a
`state.attachments` array whose items hold a `mime` and a data-URI
`url` (observed shapes: `read` returning images), and an evicted part
loses that array entirely, so the payloads stop reaching the provider;
its tombstone gains an `attachments dropped` clause between the byte
count and the age. Every tombstone also carries a one-line digest of
the evicted output, derived at eviction time from the stashed content
with no LLM involvement: `read` outputs contribute the subject (path
with its range when the call was ranged) plus previews of the first and
last lines, `bash` outputs the command plus head and tail lines, and
every other tool a bounded excerpt of the output head. Newlines of any
shape collapse to spaces so the digest stays on one line, the whole
digest is capped at 200 characters, so content beyond the cap never
reaches the model, and the derivation is pure string work on the stashed
output, so identical content always yields an identical digest.
Tombstone bytes, digest included, are excluded from the per-eviction
reclaim credit, which counts only the evicted output's bytes against the
deficit, consistent with the approximate-accounting note above.
Eviction
does not destroy: each evicted output is stashed for its session (50
entries, oldest dropped), and the `read_evicted` tool returns a
stashed output by subject, passed exactly as the eviction notice names
it; stashes are per-session, so only output evicted during the current
session is reloadable. The stash keeps the original attachment objects
with the output, but the reload text cannot re-attach binary content:
the tool returns a string, and re-serving megabyte data URIs would
re-inflate the context eviction just reclaimed. So `read_evicted`
appends a manifest line naming each dropped attachment's mime and
data-URI character count and states that the payloads were dropped,
advising a re-run of the original tool to regenerate them; the full
originals remain in the in-memory stash until the stash bound drops
them (50 entries per session, 8 sessions retained).

Fence eviction is the one transform that edits user prose, so it ships
default-off behind the `userFenceEviction` option (`{ enabled: false,
minBlockLines: 40 }` when unset; `enabled` must be a boolean and
`minBlockLines` a non-negative integer to be honored, otherwise each
falls back to its default). When enabled it runs after reasoning expiry
and before budget-driven eviction, whether or not a budget is known,
scanning the `text` parts of user messages (messages whose info carries
`role: "user"`) that sit outside the recent window for fenced code
blocks: a line indented by at most three spaces whose remaining text
opens with at least three backticks starts a block, a later line of
nothing but backticks after the same at-most-three-space indent (at
least as many as the opener) closes it; a line indented four or more
spaces neither opens nor closes a block, since CommonMark classes it
as indented code rather than a fence; and a block that reaches the end
of the part
without a closer is never touched, so an unterminated fence is never
partially evicted however large it has grown. A closed block whose
content spans strictly more than `minBlockLines` lines (the fence
delimiter lines do not count) is replaced by a single
`[lru-evicted-fence]` tombstone line naming the first word of the
opener's info string as the language tag when the opener carried one,
the content line count, and the first non-empty
content line rendered as a subject (single line, capped at 160
characters, the same bound as every other subject); a block holding no
non-empty content line at all is never evicted, since it names nothing
and reclaiming blank lines recovers almost nothing. The reload pointer
in the tombstone names that subject, and the exact removed span (opener
through closer, terminators included) enters the session stash like a
tool output, under the same 50-entry bound and reload path (fence
insertions drop the oldest entries past that bound exactly like tool
evictions do). Prose
before, between, and after the fences is preserved byte for byte,
blocks at or under the threshold stay untouched, and assistant messages
and messages inside the recent window are never scanned. Each evicted
block counts in a distinct `fenceEvicted` counter (on `lru_stats` and
as `fenceEvictedThisRun` in the metrics log) while its removed bytes
join `bytesReclaimed`; with the option disabled the pass stands down
entirely and the transform list behaves exactly as before it existed.

The `lru_stats` tool reports the live counters (including the distinct
`fenceEvicted` fence-eviction count and the resolved
`userFenceEviction` option),
stash occupancy, the effective budget (null, with source `unknown`,
when no limit was captured and no option is set) together with the
source that produced it (`override` for a winning `modelContextTokens`
entry, `model` for a captured limit, `default` for the
`defaultContextTokens` option), and the last run's
token estimate as JSON. After each run the plugin also delivers a
`[lru-hot] recently active: ...` line into the system prompt naming up
to ten most recently touched subjects, so the model sees which files
and commands are warm without rereading them.

The plugin keeps a persistent metrics log, on by default, appended to
`~/.local/share/opencode/lru-metrics.jsonl`. Every eventful transform
run appends one JSON line: eventful means at least one eviction, dedup
tombstone, reasoning expiry, fence eviction, or post-eviction touch in
the run, or any stash read since the previous line. Each line carries
an ISO timestamp,
the session id, the budget in effect and its source (`override` for a
`modelContextTokens` entry, `model` for a
captured limit, `default` for the `defaultContextTokens` option,
`unknown` when neither exists), the run's token estimate against the
watermark (null watermark and deficit on unknown-budget runs), the
evicted entries with tool, subject, byte size, attachment byte size,
and age in messages, the dedup and post-eviction-touch counts, the
expired-reasoning count and bytes for the run (counted separately from
eviction reclaims), the fence-eviction count for the run, and stash
reads since the previous line, and the session's running totals.
`bytesReclaimed` counts every character the
transform removed from the provider-bound context: the evicted output
strings plus, for parts that carried attachments, the full character
length of each attachment's data-URI `url` as the named proxy for
attachment payload size. The proxy is exact for the serialized context
(the whole data-URI string is what a provider would receive), while
the token estimate that drives the deficit keeps sizing text parts and
output strings only, so the eviction loop converts output bytes to
tokens but never attachment bytes; a heavy attachment therefore
over-delivers its share of the deficit rather than distorting the
estimate. Dedup strips attachments from the superseded copy without
adding to `bytesReclaimed`, consistent with dedup's count-only
accounting. Subjects are rendered to a single line
capped at 160 characters (newlines flattened), the same cap that
bounds every subject in the `[lru-hot]` hint line and the eviction
notices; subjects cover file paths (with ranges), grep and glob
patterns, and bash command strings, which makes the file a
near-verbatim record of commands run, not only of context pressure.
The opt-out is the plugin's `metricsLog` option, and `metricsPath`
relocates the file, but the current config entry is the bare-string
form and the runtime extracts an options object only from the
`[path, options]` tuple form, so with a bare string every option
resolves to its default, and disabling the log requires switching the
entry to `["./plugin/lru-context.ts", { "metricsLog": false }]`. There is no
rotation: lines are appended indefinitely across sessions and the file
shrinks only when deleted by hand. A failed append never interrupts
the session; the error is held in the session's metrics and surfaces
through `lru_stats` as `logWriteError`.

## LRU sidebar panel

The `/lru` command opens the LRU context manager's panel as a TUI plugin:
`plugin/lru-context.tui.tsx` default-exports a `TuiPluginModule` (`{ id,
tui }`) whose `tui()` registers one command, `lru.panel` with slash name
`lru`, through `api.keymap.registerLayer`, and opens an x-large dialog
rendered with `@opentui/solid` primitives. The TUI does not auto-scan
the plugin directory the way the server does; a TUI plugin must be
listed in the `plugin` array of `tui.json`, which lists
`./plugin/lru-context.tui.tsx`, a path opencode resolves against the
config file that declares it. The view is thin: every line
it shows comes from `panelRows` in `plugin/lru-panel-data.ts`, the same
module the headless suite covers, so the panel's exact text is
unit-tested without a terminal.

The panel is a reader over the metrics log and adds no server-side
surface. Opening it reads `~/.local/share/opencode/lru-metrics.jsonl`
anew each time (so reopening is refreshing), filters lines to the
session the TUI route is on, and renders that session's budget with its
source (per-model limit, plugin default, or inactive), the last run's
estimate against the watermark and deficit, the cumulative counters of
the session's most recent line (evictions, bytes reclaimed, dedup,
post-eviction touches, stash reads with hits and misses, dropped stash
entries), and the most recent evictions newest first, capped at eight.
A history line mixes two time windows: sessions and runs count every
parsed line in the whole log, and since the log is append-only and
survives server restarts, those counts span the log's entire lifetime;
evictions and dedup instead sum each session's most recent cumulative
totals, which restart whenever the plugin's in-memory counters do, on
server restart or when a session falls out of the plugin's
eight-session in-memory bound and returns later, so a returning
session's newest line understates what its older lines recorded. The
panel reads the whole file on every open, since per-session totals need
each session's full line history; until the log gains rotation it grows
without bound, so that read cost grows with it.

Degradation is deliberate: opening the panel outside a session route
renders "no active session", a session with no logged runs yet renders
"no metrics recorded for this session yet", both plus the history
line, malformed lines are skipped at parse, and an unreadable log
collapses the panel to a header and a warning row naming the error.
Two live fields are absent
by design: stash occupancy and skip-state exist only in the server
plugin's memory, and the TUI api offers no channel to them (the TUI's
kv store is local to the TUI process and the SDK client cannot invoke a
plugin tool directly), so the metrics-log-only fallback stands and the
log's stash hit and miss counts stand in for stash activity.

Deployment note: the repo's tui.json already declares the module, so
it is live rather than inert, and the facts that keep the file loadable
from the stowed plugin directory hold unconditionally: the
`@opencode-ai/plugin/tui` import is type-only (erased before the file
loads, so the stow-symlink realpath needs no node_modules up-tree), and
opencode's TUI rewrites `@opentui/solid` specifiers to
its internal runtime modules for every file outside node_modules, which
covers the JSX runtime the pragma generates. Headless verification
covers the data layer and the row model; the dialog's rendering itself
is verified only by loading the TUI.

## Known limits

- Soft rules (plan freeze, log discipline, tasks CLI restraint) depend on
  the flash worker's adherence; the reviewer's expectation check is the
  backstop, except on all-mechanical tasks where the reviewer is skipped
  and the verifier's raw results plus git reconciliation are the only
  checks.
- The manager cannot resolve merge conflicts, since it edits nothing
  outside `.tasks`: it dispatches a worker to resolve, then commits the
  merge.
- Concurrent per-unit verification is safe because suites run on
  temp-isolated fixtures: each verifier works inside its unit's
  worktree against isolated state, so parallel suites share no
  verdict-relevant mutable state (fixed scratch paths outside the
  repo, like the rules test's `/tmp` output file, do not affect
  verdicts). A suite that violates the assumption (shared paths,
  ports, caches that change outcomes) makes the territories not
  test-disjoint and forces the integration-commit path below.
- A unit's commits are verified against its branch with the siblings'
  edits absent; under disjoint territories this is equivalent to
  verifying them with the siblings' edits present, so the per-task
  verdicts hold without an integration build. When territories are not
  disjoint, verification runs at the integration commit instead, after
  the branches are combined.
- Parking replaces blocking escalation only under the standing-restart
  grant: with the grant recorded in this design, a failed-and-retried
  task waits in Blocked with its failure summary and attempt count
  while the queue continues, and restarts ride backfill and checkpoint
  events within the escalation bounds; without the grant, the
  delegation skill's default (stop, report, ask) stands.
- A rejected push escalates to the user; the manager has no fetch or pull.
- Without task files, a retried worker overwrites its
  `/tmp/opencode/reports/` artifact, the unit name fixing the path;
  under task files each deposit takes the next `NN` sequence number and
  `tasks report` refuses to overwrite an existing file, so the reports
  directory preserves failure history.
- Subagent permission denials do not propagate to the parent or the
  main thread: the denial and any user message attached to it surface
  only inside the subagent's session. The relay rule covers the
  survivable cases; a session-fatal denial cannot be relayed at all,
  an upstream platform gap declined for now.
- Children working in unit worktrees reach the main board by default:
  `.tasks/` is gitignored, so a checkout under `.worktrees/` contains
  no board of its own, but worktrees live inside the repo, and the
  `tasks` CLI's directory walk-up from the child's working directory
  finds the main repo root's `.tasks/`, so logs and reports land on
  the main board. `--dir` (or `TASKS_DIR`) are explicit overrides,
  needed only for working directories outside the repo tree.
- Subagent gating through the `permission.task` key depends on SDK
  support: on some SDK versions (for example 1.18.5) the key may be a
  no-op, so the agents' task permission blocks may not be enforced; the
  prompt prohibitions are the backstop until the running binary confirms
  the key.
