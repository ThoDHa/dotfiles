# Probe: opencode v2.3.0 permission and plugin surface

**Task:** ORCH-4-10-1-20261106-1716-feasibility-probes-and-walking-skeleton.md
**Date:** 2026-11-17
**Operator:** worker-orch4-10-1
**Version drift:** the dispatch and the parent recon name opencode v2.1.4; the installed binary is **v2.3.0** (`~/.opencode/bin/opencode --version`). Probes ran against the installed surface; findings supersede the v2.1.4-era inventory where they differ.

## Read permission action: present at schema level

The config's own `$schema` (`https://opencode.ai/config.json`, fetched live) defines:

- `permissions`: ordered ruleset (`Permission.Ruleset`) of `{action, resource, effect}` rules where `effect` is `allow | deny | ask` (`Permission.Effect`); the `permission` singular key is deprecated.
- `PermissionConfig` (object form) exposes the action keys: **`read`**, `edit`, `glob`, `grep`, `list`, **`bash`**, `task`, `external_directory`, `todowrite`, `question`, `webfetch`, `websearch`, `lsp`, `doom_loop`, `skill`. Each key takes `PermissionRuleConfig`: either a plain action or a resource-pattern-to-action object.
- `plugin` (deprecated) and `plugins`: arrays of `string | [string, options]` module entries.

Functional acceptance check: a fixture project (`/tmp/llm/orch4-10-1-scratch/oc-fixture/.opencode/opencode.json`) carrying

```json
{ "permissions": [
  { "action": "read", "resource": "**/.tasks/**", "effect": "deny" },
  { "action": "edit", "resource": "**/.tasks/**", "effect": "deny" } ] }
```

was accepted without schema error: `opencode serve --print-logs` booted (`server listening on http://127.0.0.1:4699`), and `opencode debug config` lists the fixture document as a config source. The v2.1.4-era conclusion "no map expresses a read-path deny" is superseded: the schema now has a `read` action and the ordered ruleset accepts path-scoped deny rules. Functional enforcement evidence (a live read tool denial) is 10-3's implementation slice, not this probe.

## Bash sandbox key in opencode config: absent

No `sandbox` key exists in the opencode config schema (verified against the fetched schema's top-level properties and `$defs`).

Significant adjacent finding: the installed binary embeds a full Claude-Code-style sandbox runtime (string-level evidence: `sandbox.enabled` default false, `sandbox.filesystem` with `denyRead` / `denyWrite` / `allowRead` path lists and `mask` mode, `sandbox.network.allowedDomains` with wildcard allow/deny lists, `sandbox.credentials` file/env masking with sentinel-substitution proxy, `bwrapPath` / `socatPath` Linux overrides, managed-settings precedence rules). That runtime is driven by `.claude/settings.json`-style managed settings, not by `opencode.json`. Wiring it to opencode sessions is unproven by this probe and is a manager decision input for ORCH-4-10-3: it is a second G3-shaped mechanism candidate on opencode (bwrap-based filesystem masking) that the v2.1.4-era recon could not see.

## Plugin load path for a path-guard plugin

Evidence: fetched config schema, installed `@opencode-ai/plugin` type definitions (`~/.config/opencode/node_modules/@opencode-ai/plugin/dist/index.d.ts`), plugin reconciliation code visible in the binary strings, and this machine's own plugin state (`~/.local/state/opencode/plugin-meta.json`).

1. **Convention directories**: global `~/.config/opencode/plugin/` and per-project `.opencode/plugin/` (singular; a fixture probe with `.opencode/plugins/` plural loaded nothing). Machine proof: `lru-context` was loaded from `~/.config/opencode/plugin/lru-context.tui.tsx` with `load_count: 71` recorded in plugin-meta.json.
2. **Config declarations**: the `plugins` config array declares external packages and enablement directives (`string` or `[specifier, options]`; `-` prefix disables, `*` / `opencode.*` wildcards enable; the deprecated `plugin` key has the same shape). Reconciliation merges: discovered directory entries, active package/local plugins, and config `plugins` entries.
3. **Initialization timing**: reconciliation runs per location/TUI session context, not at bare `opencode serve` boot (a serve-only run logs no `plugin reconciliation started` line; real sessions log `plugin reconciliation completed ... plugins=13/14`).
4. **Guard surface** (installed type definitions): `permission.ask` hook returns `status: "ask" | "deny" | "allow"` (force-deny), and `tool.execute.before` receives `{tool, input}` with mutable `output.args` (throwing cancels the call). A path-guard plugin with realpath normalization is implementable through either hook. No executor-replacement hook exists: a plugin still cannot itself sandbox a bash execution except by rewriting `args.command` or cancelling.

## Probe conclusions for the verdict

- opencode structured-tool layer: `read` denial is now expressible at the config-schema level (ordered ruleset, path-scoped deny), so the G2 structured-tool enforcement for `read` no longer needs a plugin on v2.3.0; a plugin remains the fallback and the realpath-normalization hardening layer.
- opencode bash boundary: unchanged from the recon (no opencode.json sandbox key; prefix-glob shell resources are not a boundary). New candidate for the G3 design review: the embedded bwrap-based sandbox runtime, gated on proven schema/session wiring, which is unprobed here.
