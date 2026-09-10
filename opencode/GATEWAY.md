# OpenCode Model Gateway: Free Cascade Plan

This note plans a self-hosted LiteLLM gateway that routes opencode traffic
through a free-first model cascade: the free OpenCode Zen models serve
everything until they are exhausted, the Z.AI flash subscription catches the
remainder, and no paid per-token tier exists beyond that. It complements
`DESIGN.md`: the orchestration pipeline, permissions, and verification chain
stay unchanged, and only the model backing the worker and verifier roles
moves behind the gateway.

## Goals

- Zero-cost default: every request starts on a free model.
- Guaranteed free exhaustion first: escalation fires only when every free
  deployment is benched at the same moment, which is the router's structural
  guarantee, not a heuristic.
- Hard stop instead of surprise billing: the terminal tier is the metered
  flash subscription, so total drain surfaces an error rather than spending
  a paid balance.
- Orchestration transparency: every agent references one stable model id
  (`gateway/cascade`) and remains unaware of switching.

## Non-goals

- No paid per-token fallback tier. This is deliberate: a paying terminal
  tier would silently convert outages into charges.
- No changes to agent prompts, permission tiers, or the verification chain.
- No multi-user serving: the gateway binds to localhost only.

## Architecture

```
opencode (manager / workers / verifier / reviewer)
    |
    |  OpenAI-compatible, http://127.0.0.1:4000/v1
    v
LiteLLM proxy  (Docker container, localhost bind, auto-restart)
    |
    |-- tier 0 "cascade": OpenCode Zen free models   (ZEN_API_KEY)
    `-- tier 1 "flash":   z.ai coding plan glm-5.3-flash (ZAI_API_KEY)
```

Failover semantics per request:

1. A healthy free deployment serves the request.
2. On a 429 or transport failure, that deployment is benched for
   `cooldown_time` and the router retries on another healthy free deployment.
3. When the entire free pool is benched, the `fallbacks` entry escalates the
   request to the `flash` group, which has the same retry and cooldown
   mechanics.
4. When flash is also benched, the error surfaces to the agent. Opencode's
   own retry behavior plus expiring cooldowns recover traffic without
   operator action, so a total drain is visible errors during a window, not
   an outage requiring intervention.

The design assumes LiteLLM's standard router guarantees: retries rotate
across healthy deployments, benched deployments are skipped entirely until
their cooldown expires, and fallback is evaluated per request, which means
traffic returns to the free tier on the first request after any free
cooldown expires.

## Gateway selection

The cascade pattern requires a gateway-class component; LiteLLM is the
chosen one, and this section records why plus what was rejected, so the
decision survives context loss.

| Option | Strength | Rejected because |
|--------|----------|------------------|
| LiteLLM (chosen) | De facto standard: largest community, first-class `cooldown_time`, `fallbacks`, and `context_window_fallbacks`, every provider quirk already hit by someone | Acceptable costs: heavy Python dependency tree, config schema churn between versions, paywalled admin UI and some routing strategies |
| Portkey Gateway (OSS) | Cleanest architecture: stateless TypeScript worker, config-driven fallbacks, load balancing, retries; very fast | The deployment-health and cooldown machinery this cascade depends on is thinner in the OSS gateway than in their hosted platform |
| glide (Go) | Single binary, YAML routing, lightweight | Small community: this setup would be an early reporter of edge-case bugs |
| Kong / Envoy AI Gateway | Enterprise-grade routing on existing infra | Overkill for a localhost single-user proxy |
| Hosted routers (OpenRouter etc.) | Zero infrastructure, native fallback chains | Cannot proxy the Zen free endpoint or the z.ai coding plan with our credentials; hosted routing is incompatible with free-tier arbitrage, where the free inventory lives behind our keys on custom endpoints |
| Custom proxy | ~200 lines for ordered failover | Correct SSE streaming passthrough (incremental tool-call deltas) is the fiddly 80%; cooldown timers and retry semantics are easy to get wrong quietly |

The tiebreaker is cooldown maturity: the "guaranteed free exhaustion first"
property rests on benched deployments being skipped and re-admitted on a
timer, which is a load-bearing, well-exercised feature in LiteLLM and the
least desirable place to be anyone's first user. The pin-version policy in
Maintenance neutralizes its main weakness, config churn.

### Native fallback status (checked 2026-09-07)

Investigated against primary sources: the installed v1.18.29 binary, the
v2 dev tree at ecbc6cc, the published config schemas, and the GitHub PR
and compare APIs. Result: OpenCode ships no model fallback chain on any
line. `fallbacks` and `cooldown_seconds` appear in no config schema; the
feature exists only as open, unmerged PR #26292 (fork branch
`j3k0:feat/llm-fallback`, +1621/−1218 across 31 files, last updated
2026-08-22, never merged into `dev`). What does ship is same-model retry
with exponential backoff (5 retries, honors `retry-after`), which layers
under the gateway without replacing it: the client retries the model, the
gateway rotates across models. The gateway plan therefore stands as
designed. Recheck triggers: PR #26292 merging, a v2 config schema
documenting `fallbacks`, or `opencode2` reaching stable; tracked as task
GW-2 on the board.

## Tiers and models

### Tier 0: OpenCode Zen free models

All five speak plain `chat/completions` at `https://opencode.ai/zen/v1` and
are excluded from every usage budget.

| Model id | Notes |
|----------|-------|
| `big-pickle` | Stealth model; free period; data may be used for training |
| `mimo-v2.5-free` | Free period; data may be used for training |
| `ling-3.0-flash-fin-free` | Free period; data may be used for training |
| `nemotron-3-ultra-free` | NVIDIA trial terms apply to data handling |
| `nemotron-3.5-lightning-free` | NVIDIA trial terms apply to data handling |

`muse-spark-1.3-contributor-free` is excluded on purpose: it only serves the
Responses API (which does not fit a chat pool) and its contributor tier
trains on prompts and completions.

### Tier 0 expansion: Groq (deferred)

Groq is deliberately excluded from the initial pool. Its marginal value over
five independent Zen free models is provider diversity (an outage of Zen
itself), while its costs are ongoing: another key and terms surface, the
fastest-rotating model catalog of any provider (constant generator-script
maintenance), more candidates to gate in V4, and a wider pool diluting
prompt-cache locality under `least-busy` routing. Escalation lands on the
flat, already-paid flash subscription, so free-pool exhaustion is cheap
rather than costly, which further lowers the value of extra redundancy.

Add Groq only on evidence, after the V6 soak:

- flash served requests regularly on healthy free-pool days (the pool
  drains in normal operation), or
- the LiteLLM logs show the entire Zen free pool benched simultaneously
  (a shared ceiling or provider-level outage).

The reintroduction recipe: create a Groq key, verify candidate ids against
`GET https://api.groq.com/openai/v1/models`, gate each through the V4
tool-calling smoke test, then add survivors as `cascade` deployments with
LiteLLM's native `groq/` prefix and `GROQ_API_KEY` in the env file.
Preference order favors tool-calling competence over raw speed:
`moonshotai/kimi-k2-instruct-0905`, `openai/gpt-oss-120b`,
`qwen/qwen3-32b`, `llama-3.3-70b-versatile`.

### Tier 1: Z.AI flash

`glm-5.3-flash` through the coding plan endpoint
`https://api.z.ai/api/coding/paas/v4`, the same subscription that backs the
worker and verifier roles today (provider `zai-coding-plan` in opencode
auth). The plan's quota is prompts per five hours; exhaustion surfaces as
429s, which the cooldown absorbs.

### Context window ledger

Pool models tokenize and window differently, so this table is filled during
verification step V2 and drives two later values: the smallest pool window
(used for opencode's `limit.context`) and per-deployment `model_info` limits
in LiteLLM.

| Model | Context window | Source |
|-------|----------------|--------|
| `big-pickle` | TBD (V2) | `GET https://opencode.ai/zen/v1/models` |
| `mimo-v2.5-free` | TBD (V2) | same |
| `ling-3.0-flash-fin-free` | TBD (V2) | same |
| `nemotron-3-ultra-free` | TBD (V2) | same |
| `nemotron-3.5-lightning-free` | TBD (V2) | same |
| `glm-5.3-flash` | TBD (V2) | Z.AI coding plan docs |

## Configuration

### Files in this dotfiles repo

A new `litellm/` stow package, following the existing package layout:

```
litellm/
  .config/litellm/config.yaml        # gateway configuration (committed)
  .config/litellm/env                # API keys (never committed; gitignored)
  .config/litellm/env.example        # committed template for env
  .config/litellm/docker-compose.yaml# container definition (committed)
  .config/litellm/generate-models.sh # refreshes model_list from live endpoints
```

The package is wired into the Makefile: stow lists, `make litellm-refresh`
(explicit generator invocation), and `make test-litellm` (config structure,
compose posture, and generator merge semantics, including stow-symlink
safety and idempotence).

### LiteLLM config.yaml

```yaml
model_list:
  # tier 0: OpenCode Zen free
  - model_name: cascade
    litellm_params:
      model: openai/big-pickle
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  - model_name: cascade
    litellm_params:
      model: openai/mimo-v2.5-free
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  - model_name: cascade
    litellm_params:
      model: openai/ling-3.0-flash-fin-free
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  - model_name: cascade
    litellm_params:
      model: openai/nemotron-3-ultra-free
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  - model_name: cascade
    litellm_params:
      model: openai/nemotron-3.5-lightning-free
      api_base: https://opencode.ai/zen/v1
      api_key: os.environ/ZEN_API_KEY
  # tier 1: Z.AI coding plan flash
  - model_name: flash
    litellm_params:
      model: openai/glm-5.3-flash
      api_base: https://api.z.ai/api/coding/paas/v4
      api_key: os.environ/ZAI_API_KEY

# after V2: add model_info.max_input_tokens / max_output_tokens per
# deployment, sized from the context window ledger

router_settings:
  routing_strategy: least-busy        # spreads parallel workers across the pool
  num_retries: 4
  timeout: 300
  cooldown_time: 300                  # long bench: fewer wasted probes on
                                      # daily-cap models; Retry-After wins
                                      # when the provider sends it
  context_window_fallbacks:
    - cascade: ["flash"]              # escalate on context overflow (400)
                                      # instead of failing the request

litellm_settings:
  fallbacks:
    - cascade: ["flash"]              # escalate only when the free pool is
                                      # fully benched

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY   # localhost guard; any random
                                              # string, stored in env
```

Groq deployments, if the deferred expansion adds them, use LiteLLM's native
`groq/` prefix, which supplies the correct base URL and expects
`GROQ_API_KEY` in the environment. Zen and
Z.AI deployments use the `openai/` prefix with explicit `api_base` because
both are OpenAI-compatible but not in LiteLLM's provider registry under
these endpoints.

### Environment file

`~/.config/litellm/env`, mode 600, loaded by the Docker container:

```
ZEN_API_KEY=...        # from https://opencode.ai/auth (already in opencode auth.json)
ZAI_API_KEY=...        # existing z.ai coding plan key
LITELLM_MASTER_KEY=... # random string, e.g. openssl rand -hex 24
```

`GROQ_API_KEY` joins this file only if the deferred Groq expansion happens.

### Docker container

```yaml
# ~/.config/litellm/docker-compose.yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-stable   # pin a concrete tag in V3
    container_name: litellm-gateway
    command: --config /app/config.yaml --host 0.0.0.0 --port 4000
    volumes:
      - ./config.yaml:/app/config.yaml:ro
    env_file: env
    ports:
      - "127.0.0.1:4000:4000"   # localhost-only publish: the security boundary
    restart: unless-stopped
    mem_limit: 512m             # bounded footprint on a 7GB, swap-using host
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health/liveliness"]
      interval: 30s
      timeout: 5s
      retries: 3
```

Run with `docker compose -f ~/.config/litellm/docker-compose.yaml up -d`;
the container reads keys from the env file and the gateway publishes only
to loopback, so the master key note from the opencode integration section
still applies unchanged. Docker restarts the container on crash or reboot
(when the daemon runs), replacing the systemd restart guarantee.

Tradeoffs versus the pipx/systemd variant: the image costs roughly 2GB of
disk instead of 200MB, the footprint stays containerized (no Python
dependency tree on the host), and config changes are a `docker compose
restart` away. On-demand use is `docker compose stop` / `up -d`, which is
the memory-frugal mode for this host.

### opencode integration

Add to `opencode.json`:

```json
{
  "provider": {
    "gateway": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM cascade",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "see note below"
      },
      "models": {
        "cascade": {
          "name": "Free cascade -> flash",
          "limit": {
            "context": <smallest pool window from V2, minus ~25% headroom>,
            "output": <smallest output limit from V2>
          }
        }
      }
    }
  }
}
```

Then change `model:` in `agents/worker.md` and `agents/verifier.md` from
`zai-coding-plan/glm-5.3-flash` to `gateway/cascade`. The manager and
reviewer keep the session model: coordination and judgment are the wrong
place to spend free-model variance. Session-title generation
(`small_model`) also stays on its current default so titles never depend on
gateway availability.

Decision recorded: workers go on the cascade, not flash-direct. This
knowingly relaxes the `DESIGN.md` assumption that soft-rule adherence
(plan freeze, log discipline) rides on a flash-grade worker: the free pool
varies in instruction-following strength. The accepted mitigations are the
V4 tool-calling gate (models that cannot follow tool protocol cleanly are
removed, which also proxies for instruction adherence) and the V6 soak,
which doubles as the check that worker discipline survives pool variance.
If soak shows discipline failures, the fallback position is verifier-only
cascade, recorded here so the retreat path is explicit.

Note on the gateway key: `opencode.json` is committed to this repo, so the
`apiKey` value must be treated as non-secret configuration, not a
credential. Set `LITELLM_MASTER_KEY` in the env file and the `apiKey` field
to the same value only if this repo stays private; otherwise use any fixed
placeholder in both, since the actual boundary is the `127.0.0.1` bind plus
the env file's 600 permissions, not this value's secrecy.

## Context management interaction

The gateway is stateless: it forwards payloads and prunes nothing. Opencode
keeps sole ownership of conversation state, compaction, and the
`lru-context` plugin, all of which behave identically through the cascade.
Three pool-specific effects remain:

1. Window mismatch: a session that outgrows a smaller-window pool model
   receives a 400, which `context_window_fallbacks` converts into
   escalation to flash rather than a failed request. The conservative
   `limit.context` (smallest window minus headroom) makes opencode compact
   before overflow is reachable in the normal case.
2. Cache locality: prompt caching is per model and provider, so a
   mid-task cascade switch re-prefills the whole conversation on the new
   model: slower steps, and on flash, metered prompts. Mitigation is
   long cooldowns (no flapping) and session pinning where the installed
   LiteLLM version supports it; the router API changes frequently, so
   verify the exact session-affinity key against the installed version
   during V4 and record it here.
3. Tokenizer drift: opencode's token accounting approximates every pool
   model differently, which the ~25% compaction headroom absorbs.

## Verification plan

Each step gates the next.

- V1, keys and catalogs: fetch
  `curl -H "Authorization: Bearer $ZEN_API_KEY" https://opencode.ai/zen/v1/models`
  and confirm every Zen free candidate id exists. Drop missing ones from
  the pool before proceeding.
- V2, ledger: fill the context window table above from the V1 responses
  and the Z.AI docs, then compute `limit.context` and the `model_info`
  values. This is the step that makes the numbers in committed config
  real rather than assumed.
- V3, gateway health: `docker compose -f ~/.config/litellm/docker-compose.yaml up -d`,
  wait for `docker ps` to report the container healthy, then
  `curl http://127.0.0.1:4000/health/liveliness` and
  `curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://127.0.0.1:4000/health`
  to confirm every deployment registers healthy.
- V4, per-model smoke test: send one chat request per cascade deployment
  (LiteLLM logs and the response `model` field identify the deployment
  that served each), then one tool-calling round trip per model from
  opencode by temporarily exposing per-model aliases. Drop any model that
  fails tool calls from the pool: free but tool-broken models poison
  agent loops. Also verify session affinity behavior here if pursuing it.
- V5, escalation drill: temporarily point all `cascade` deployments at an
  unreachable `api_base` in a scratch copy of the config, confirm a
  request still succeeds served by flash (proving the fallback chain),
  then restore the real config. Watch `/health` show the free pool benched
  during the drill.
- V6, orchestration soak: run one real manager-dispatched task with
  worker and verifier on `gateway/cascade`, then confirm in the LiteLLM
  logs that requests spread across free deployments and that flash served
  zero requests.

## Maintenance

- `generate-models.sh` (wired as `make litellm-refresh`) refetches the Zen
  `/v1/models` endpoint, filters to the free subset (ids containing `free`
  plus `big-pickle`, always excluding muse-spark), and rewrites only the
  managed block of `config.yaml`: kept entries survive verbatim (manual
  `model_info` stanzas included), decommissioned ids drop, new ids append
  from the template after confirmation. It runs explicitly, monthly or
  whenever logs show a permanently benched id: never at container start,
  because config.yaml is a stowed symlink into this repo (start-time
  rewrites leave a dirty tree every boot), an automatic refresh would
  admit unvetted models past the V4 gate, and a dead id is merely benched,
  not boot-critical. New ids the script surfaces still go through V4
  before earning a pool slot. If the Groq expansion happens, extend the
  script to that catalog under the same rules.
- Pin the LiteLLM image tag in the compose file after V3. The router
  config surface moves between versions, and this plan's keys are
  verified against the pinned one.
- Container logs flow through Docker's json-file driver, capped by the
  compose `logging` block; no extra rotation setup is needed.

## Risks

- Data policy: the Zen free models and NVIDIA trial endpoints may log or
  train on submitted data. The cascade therefore must not route secrets,
  credentials, or private third-party content; dotfiles and tooling work
  is the intended workload.
- Tool-calling variance across free models is the main quality risk, and
  V4 is the gate that keeps weak models out of the pool.
- Daily-cap models interact with cooldown by repeatedly probing a dead
  quota; `cooldown_time: 300` and honored `Retry-After` headers bound the
  waste, and soak results (V6) decide whether per-model tuning is needed.
- The gateway is a single point of failure for workers and verifier.
  Docker's `restart: unless-stopped` covers crashes, and the manual bypass
  is flipping those two agent files back to
  `zai-coding-plan/glm-5.3-flash`, which remains configured and
  authenticated.
- Metered exposure is bounded by design: the only spendable tier is the
  flat coding-plan subscription, already paid, with no balance-based
  billing path configured.

## Rollout steps

1. Write `~/.config/litellm/env` with the three values (V1).
2. Verify candidate ids and fill the context ledger (V1, V2).
3. Done: the `litellm/` stow package exists (config.yaml, env.example,
   docker-compose.yaml, generate-models.sh) with Makefile registration
   (stow lists, `litellm-refresh`, `test-litellm`). Remaining here: copy
   `env.example` to `env`, fill the three values, `chmod 600 env`.
4. Pull the LiteLLM image, pin its tag in the compose file, start the
   container, pass health checks (V3).
5. Run per-model smoke tests, prune the pool, finalize `model_info`
   limits and session-affinity findings (V4).
6. Run the escalation drill on the scratch config (V5).
7. Add the `gateway` provider to `opencode.json` and switch
   `agents/worker.md` and `agents/verifier.md` to `gateway/cascade`.
8. Run the orchestration soak and confirm flash served zero requests on a
   healthy free pool (V6).
9. First live `make litellm-refresh` run to validate the generator against
   the real catalog, then set the monthly reminder mechanism.
10. Update `DESIGN.md`: reference `gateway/cascade` for worker and
    verifier in the roles table, and amend the known-limits line about
    flash worker adherence to reflect the cascade decision and its
    mitigations.
