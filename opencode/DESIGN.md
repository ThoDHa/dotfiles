# OpenCode Orchestration Design

This note documents the manager, worker, verifier, reviewer, planner,
and advisor agent pipeline, the git authority model, the task-file
integration, and the verification chain. The agent files under the
opencode config carry the normative requirements in RFC 2119 form; this
note explains the architecture and the reasoning, pointing at each
requirement's canonical home (file plus section heading or rule number).

## Roles

| Agent | Mode | Model | Duties |
|-------|------|-------|--------|
| manager | primary | glm-5.3-flash | Decomposition, dispatch, unit worktrees and branches, planning approval, user plan sign-off, architecture duties at coordination scale (exploration, builds, verification runs, CI/CD operation), integration and history shaping, pushes, reconciliation |
| worker | subagent | glm-5.3-flash | Code writing: implementation inside an assigned territory, commit checkpoints on the unit branch, real-time work logs, reports |
| verifier | subagent | glm-5.3-flash | Runs tests, linter, and typechecker once each, reports raw results without interpretation |
| reviewer | subagent | glm-5.3 | Dual mandate: compliance (simplify-review in Analysis-Only Mode, advisory plan critiques between drafting and approval, expectation checks, verdict failing only on correctness, security, or contradiction) and advisory adversarial design critique aimed at a better design, not a defeated one (every challenge carrying an alternative, tradeoffs, and a falsifiable claim, one-exchange debate through the report deposits), no command execution beyond its deny-first read-only map plus exactly one findings-deposit write per dispatch (the `tasks report` channel under task files, a `/tmp/opencode/reports/` artifact otherwise) |
| planner | subagent | glm-5.3 | Planning and research labor: dedicated research dispatches (territory reconnaissance, codebase investigation, findings reports through the `tasks report` channel for task-file dispatches or the reserved `research/` deposit path for task-file-less ones), drafting the Triage task file's planning sections ahead of the manager's Triage → Ready approval, shared recon deposits, no implementation |
| advisor | subagent | glm-5.3 | Judgment labor behind the manager's decisions: evaluation memos for plan approvals, discrepancy reconciliation analysis, design-challenge position drafts, reviewer-finding disposition drafts, incoming-request triage, closing-report synthesis, git-reshape design; read-only repos and logs, evidence stated with anchors, one memo deposit per dispatch, never authoring what it judges |

The manager is a coordinator, not an implementer: it holds no implementation
duty (it never authors implementation content), and its file edits are
limited to `.tasks/**`. Integration commits and pushing are coordination
duties, not implementation work; unit workers make their own commit
checkpoints on the branches the manager assigned them. The division of
labor between the dispatch targets is explicit: the worker is the
code-writing agent, the planner is the destination for research and
planning dispatches (planning labor, dedicated exploration,
investigation, and findings reports), and the advisor is the
destination for judgment dispatches (evaluation memos, reconciliation
analysis, disposition and position drafts, request triage, synthesis
drafting), so research-grade context building and judgment work
concentrate in full-model agents instead of eroding the flash worker's
focus. The architect grant
follows the same line: the manager delegates as much work as the fleet can
take, and the command freedom exists to unblock and steer the fleet
(scouting a dispatch, unblocking a worker, checking a unit's result); any
duty that grows into sustained work of its own is dispatched to a fleet
agent rather than absorbed (research-grade exploration to the planner,
judgment memos to the advisor, code writing to the worker), since
capability never reduces the delegation
duty.

The verifier and reviewer split verification along the judgment line:
transcription of command results is mechanical and runs on the flash model,
while code review and result interpretation need the full model. The model
pins follow the same line: an unpinned subagent inherits the parent
session's model, and the manager session itself runs flash, so the
judgment roles (reviewer, planner, advisor) carry explicit glm-5.3 pins
while the mechanical roles (worker, verifier) keep their flash pins. The
verifier reports exit statuses, the runner's own counts, and verbatim
failure output; interpretation happens in the reconciliation chain
(advisor memo, manager decision), never inside the verifier.

## Git authority

Under the worker-commit model recorded here, a unit dispatched alongside a
running sibling works in a worktree under `.worktrees/` on its own unit
branch (a lone unit may use the main tree), and the worker makes
territory-scoped commit checkpoints there, every commit a complete logical
change, the suite green at the branch head and at every commit except the
red first commit of the sanctioned ordered pair from the coding-standards
rule's "Separation of Code and Test Changes" section; per-unit attribution
and crash resilience are the payoffs, and the commit rules are normative in
the worker agent file's commits paragraph and the delegation skill's
Worktree Isolation section. Integration, history shaping, staging, and
pushing are the manager's alone, keeping the main line coherent while units
run in parallel: it shapes a passed unit's branch judgment-based (squash or
merge the commit checkpoints as the change warrants), stages only the files
that worker changed, and reshapes pushed history only on explicit user
request. A sanctioned ordered pair per the coding-standards rule's
"Separation of Code and Test Changes" section (a production fix and its
test-expectation commit) MUST NOT be squashed into one commit: the pair's
commits stay separable. Rule 4 of the manager agent file is normative for
the worktree default and the pre-dispatch tree and base-commit checks, and
its closing git-authority section for staging, history shaping, and push
rules.

## Task-file integration

Under the task-files protocol every `.tasks/` write has exactly one owner:
the manager owns the task files and the dashboard, dispatched agents own the
two `tasks` CLI channels (Work Log entries and report deposits, attributed
via `--from`; the reviewer's findings deposit rides the report channel the
same way, no third exception), and the two agent-owned write exceptions are
the planner's planning-section carve-out and the research deposit, a
task-file-less agent's direct file write into the reserved `research/`
namespace (the task-files skill's Agent Write Path, Serialized Task-File
Body Edits, and Reports Namespace sections). Bulky output lives under
`.tasks/reports/` (the skill's Reports Namespace and Manual Fallback
sections); closure work opens with a short digest and planning fan-out
shares one reconnaissance artifact (the skill's Closure Digest and Triage to
Ready Planning Phase sections, the latter tied to the delegation skill's
Planning Approval Authority). Between the manager's Triage → Ready approval
and the first worker dispatch sits the delegation skill's execution sign-off
gate: the manager presents the plan to the user (objective reading, unit
breakdown with territories, execution order, verification approach, plus
alternatives when multiple viable approaches exist) and waits for explicit
go-ahead, a wait enforced as a turn boundary: the presenting response
carries no dispatch or unit worktree creation, and only an explicit user
reply after the presentation unlocks execution; one sign-off covers the
plan's lifecycle (units, fix, verification, and review rounds, retries,
restarts, backfills), and new work or material deviations return to the gate
(rule 3 of the manager agent file; the delegation skill's Execution Sign-off
Gate section).
High-cost plans (parallel fan-out, checkpoint slicing with a contract seam,
user-flagged stakes) pass an advisory plan-review gate whose verdict never
binds (rule 2 of the manager agent file; the reviewer agent file's
plan-review dispatch type); small tasks use the skill's Documentation Scale:
Lite Profile.

## Dispatch economy

The dispatch economy requirements and the dispatched-agent conduct rules
(territory, clarification routing, permission-denial relay) are normative in
the execution-standards rule's Dispatch Economy section, and the delegation
skill's Dispatch by Reference section sanctions the pointer-form dispatch
through a task file's Instructions Given entry.

Dependent units resume the earlier worker's session (the delegation skill's
Context Continuity section, extended batch-wide by rule 5 of the manager
agent file): every fresh dispatch re-pays the prior session's exploration,
file reads, and skill loads. Two exclusions stand: the reviewer is never
resumed across units (accumulated verdicts erode its independence), and the
verifier stays stateless by design; the session-fatal denial case sits under
known limits.

## Verification chain

Verification runs as a per-unit pipeline, not in batch: when a unit's worker
returns, its verifier and reviewer are dispatched in parallel and four
independent sources are reconciled per unit (worker claims, verifier
results, reviewer findings, git ground truth). The verifier reports raw
results without interpretation, the reviewer runs the simplify-review loop
in Analysis-Only Mode and nothing beyond its deny-first read-only map plus
exactly one findings-deposit write per dispatch, with the reviewer's reply
to the manager carrying only the deposit path and digest (normative in
rule 7 of the manager agent file and the verifier and reviewer agent
files). On a pass
the manager backfills the freed slot immediately and gives every
discrepancy, finding, and suggestion exactly one recorded disposition (fix,
defer, or decline), because unbounded loops hide failures and unactioned
suggestions get lost (rules 7 through 9 of the manager agent file; one
combined seam review closes the batch). The reconciliation analysis
behind rule 8's discrepancy handling and the position and disposition
drafts behind rule 9 route to the advisor under the class-based
consultation routing, where advisor consultation is the default before
every other consequential judgment; the manager keeps the dispositions
and the decisions.

Verified findings get fixed or dispatched; design arguments get answered
or debated in search of the better design (taste-only findings labeled
and not debatable): the manager answers before declining, drafting its
position papers through the advisor, the reviewer
concedes promptly or strengthens with new argument only, exactly one
exchange ends the debate, and a disagreement still unresolved after that
exchange escalates verbatim to the user rather than dropping silently; a
declined challenge requires the recorded concession or that escalation
record (normative in rule 9 of the manager agent file and the reviewer
agent file's debate paragraph).

Failure handling parks instead of blocking: on the failure of the single
mandated retry, the task is parked with a Blocked status whose reason
carries the failure summary and the attempt count, reported to the user
without blocking the queue, and parked tasks are reconsidered at every
backfill or checkpoint event. Rule 6 of the manager agent file is normative
for the escalation bounds, and the backoff measurement procedure lives in
the delegation skill's Failure Semantics section. This design is the
recording that section's standing-restart grant clause requires: the user's
standing-restart grant is recorded here and takes effect on this task's
sign-off, putting parking and the checkpoint-event rule in force for this
orchestration from that point.

## Worktree isolation

Under the worker-commit model recorded here, a worktree under `.worktrees/`
on a unit branch is the default dispatch vehicle for a unit with a running
sibling (a lone unit works in the main tree; a parked unit's worktree is the
one teardown exception); this recording switches the delegation skill's
worktree regime, whose mechanics are normative in its Worktree Isolation and
Worktree Teardown sections.

## Permissions posture

Agent permission tiers mirror their prompts, defined in each agent file's
frontmatter and the global opencode.json; under opencode v2 each map
translates into an ordered rule list where the last matching rule wins
and agent rules append after the global ones. An action matching no rule
falls to that permission's default (allow for most, ask for a few like
`external_directory`), and a headless subagent session auto-rejects
anything that asks. The watching background service refreshes config
mid-run (the shared service log records the events; grep
`event.type=config.updated` and `event.type=agent.updated`), so
permission-map edits no longer wait for a newly started session. The
manager's edit denial is the single architectural line, confining its
edits to `.tasks/**` while bash stays open; the worker holds everything
except push, history reshaping, gh writes, and subagent spawning; those
two are the only allow-first maps. The verifier, reviewer, planner, and
advisor run deny-first maps: the verifier's bash denies by default and
allows only `make verify`, `tasks render`, the read-only git set
(status, diff, log, show, rev-parse), `ls`, `cat`, and `grep`, with its
edit, task, webfetch, and websearch channels denied outright; the
reviewer's bash allows read-only git
(status, diff, log, show, rev-parse, worktree list, plus the `git -C`
forms for all but rev-parse), file inspection (`ls`, `cat`, `grep`, `wc`,
head and tail withdrawn, the native read tool covering their case and
the base deny governing their shapes), and the single `tasks report`
deposit channel, with its edit map opening only
`/tmp/opencode/reports/**`; the planner
pairs the same git set minus the `git -C` worktree-list form with the
same inspection core and adds the two `tasks` channels, the
containerized `make verify` and the docker-free `make lint-corpus`
rung, `sqlite3 -readonly`, the opencode help and version probes, and the
exact `opencode debug config` and `opencode debug agents` entries,
with its edit map opening only `.tasks/**` for the planning carve-out
and the direct `research/` deposit write; and the advisor copies the
planner's bash map rule for rule (its `grep` allow already covers the
service-log reading its reconciliation memos need), with its edit map
opening `/tmp/opencode/reports/**` for the memo deposits instead of
`.tasks/**`. The maps are guardrails
against uninstructed behavior, not security boundaries, and the failure
mode now splits by map shape: on the two allow-first maps (manager,
worker) a determined `sh -c` or `git -C` route slips past the prefixed
denies, while the deny-first maps fail closed, an unrouted command
denied outright, so the residual surface there is only the shapes that
legitimately match an allow, recorded in the accepted-risk register
below; hard enforcement everywhere would still require policies or
credential separation. Dispatchers MUST address each agent's report
deposit to its own charter path: the planner to the reserved
`research/` path under `.tasks/reports/` (task-file-less research), the
reviewer and advisor to `/tmp/opencode/reports/`, task-file agents
through the `tasks report` channel; the edit maps enforce these paths
mechanically and a headless session auto-rejects anything that would
ask, so a cross-addressed deposit fails as `Permission denied: edit`
with no user message (observed 2026-10-20: planner denied at `/tmp`,
reviewer denied at `.tasks/reports/research`, both correct denials).

### Accepted-risk register

The deny-first verifier, reviewer, planner, and advisor maps carry the accepted residual classes below, accepted because withdrawing them would gut the read-only charters (diff inspection is the reviewer's core duty, cat and grep the standard inspection path). Since the FLEET-1-7 wiring, verifier dispatches run through the containerized `make verify` gate: the recipe mounts the repo read-only, runs with the network off, and bounds writes to a designated per-run scratch, with the permission-layer allowlist kept as defense-in-depth; planner and advisor verify runs ride the same gate, closing the live-model spawn and host deployment checks neither charter names. Single-command redirects are a pattern-level match: `cat file > /target` matches `cat *`, the same class for the other inspection commands and the git prefixes, a residual now shared by the verifier map; the docs specify no redirect rule and any platform defense is unrecorded, so the claim states the conservative ceiling, able only to overstate the risk. Argument-level writes ride the diff, log, and show prefixes: `git diff --output=/path` needs no metacharacters. The former `.env` read class is closed: the contains-form `"* *.env*"` deny placed last in all four maps was live-probed on 2026-10-20 and denied every probed form before execution: final position (`cat .env`), padding (`cat .env README`), subdirectory (`cat config/.env`), grep (`grep x .env`), the `git show HEAD:.env` blob form, and the redirect target (`cat README.md > .env`); quoted forms match because the scanner strips quoting before matching (live-observed in the final seam re-review). The entry's boundary, also probed live: a command carrying no literal space before the `.env` text (`cat$IFS.env`) matches nothing in the entry, so in these four maps the `"*": "deny"` fallback takes it, while the allow-first manager and worker maps, which carry no env entry, take it by fallback allow. The probe table lives in the FLEET-1 env-semantics-fix report. Piped compounds reject in headless sessions even when every segment individually matches an allow (observed live); the docs do not specify the compound rule. Two residuals sit outside the maps: the launcher exposure, the whole verify recipe plus Makefile parse-time shell executing host-side with the payload alone container-bounded, parked as the out-of-repo wrapper user decision under Blocks (b) of the FLEET-1-7 wiring fix; and the docker daemon as the verification single point of failure. The hardening shape is deny entries placed after the allows, which win by position; asks are the wrong tool in headless sessions because they auto-reject, and the structural option for the cat class, dropping `cat *` for named reads, stays recorded if the threat model changes. The acceptance guard is the read-only charters plus transcript visibility: every residual is a read or a redirect visible in the session transcript, and pattern syntax is no barrier to later narrowing, since literals like `>` and `=` are expressible in deny entries.

## LRU context plugin

The LRU context plugin and its `/lru` sidebar panel live in their own
repository, [opencode-lru-context](https://github.com/ThoDHa/opencode-lru-context),
whose DESIGN.md carries the full design note for the eviction pipeline, the
tools, the metrics log, and the panel. Under opencode v2 the plugin does
not load: v2 requires a configured plugin path to be a directory and
warned on every config load of the single-file `plugin` array in
opencode.json (grep the service log for `configured plugin path must be
a directory`), so that stanza came out, and tui.json's `plugin` stanza
pointing at the `.tsx` twin, inert under v2, followed in the same batch;
each stanza is preserved verbatim in its removal commit's diff for the
plugin-port task to restore deliberately. tui.json keeps only
its keybinds; the `sidebarSubagents: true` option that listed the fleet's
child sessions (worker, verifier, reviewer, planner, advisor) in the
sidebar's LRU group rode the removed entry and returns with the port. The
tripwire for the `.tsx` twin lives here: after any future v2 upgrade,
grep the shared service log for a WARN line naming `tui.tsx` (baseline
zero; echoes are INFO `spawning process` lines, so the `level=WARN`
requirement disarms them) the same day, because the `.ts` stanza's
rejection warned on every load and a resurfacing plugin-parse warning on
the `.tsx` path would surface as just such a WARN line.

## Known limits

- Soft rules (the worker's task-file write restraint, its real-time work
  logging duty, and the tasks CLI's two-channel write path) depend on
  the flash worker's adherence; the reviewer's expectation check is the
  backstop, except on all-mechanical tasks where the reviewer is skipped
  and the verifier's raw results plus git reconciliation are the only
  checks. The planner's restraint inside its planning-section carve-out
  is likewise prompt-soft, and the planner runs pinned to glm-5.3, not
  flash: the manager's planning review of the filled-out task file
  is its backstop. The no-implementation and territory-scoping
  restraints on research dispatches routed to the same planner are
  likewise prompt-soft, and the manager's review of the findings is
  their backstop. The advisor's no-authorship and evidence-anchoring
  restraints are prompt-soft the same way: the manager's review of each
  memo, and its final yes/no on everything the memo informs, are the
  backstop. The plan-review gate on high-cost plans is advisory
  by construction: the reviewer's critique is one more input to that
  planning review, and it enforces nothing.
- The manager cannot resolve merge conflicts, since it edits nothing
  outside `.tasks`: it dispatches a worker to resolve, then commits the
  merge.
- Concurrent per-unit verification is safe because suites run on
  temp-isolated fixtures: each verifier works inside its unit's
  worktree against isolated state, so parallel suites share no
  verdict-relevant mutable state (fixed scratch resources outside
  the repo, like the rules test's `/tmp` output file, do not affect
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
- Subagent gating through the `permission.task` key is enforced on the
  running binary (v2.0.32): the shared service log records the translated
  per-agent task rules evaluating on spawns without an ask (grep
  `message=evaluated permission=task`), closing the v1-era concern that
  the key could be a no-op on some SDK versions (1.18.5 among them); the
  manager's named-agent allows plus catch-all deny and the subagents'
  blanket `task: deny` hold at the permission layer, and the prompt
  prohibitions remain the conduct backstop, not the enforcement.
