---
name: browser-testing
description: Use when a task involves browser automation or browser test suites: Playwright, Puppeteer, scraping, verifying a running web UI, running browser tests locally or in Docker, or before installing any browser automation tooling. Covers the Playwright MCP versus Docker versus local-install selection rules and the Docker execution requirements. Do not use for non-browser Docker or testing work.
---

# Skill: Browser Testing

> Tool-selection and execution requirements for browser automation and local runs of browser test suites (Playwright and equivalents).

## Tool Selection Requirements

| Scenario | Required Tool | Rationale |
|----------|---------------|-----------|
| Interactive agent-driven browsing: verifying a running UI, scraping, smoke-checking a flow | Playwright MCP server (configured as `playwright` under `mcp` in `opencode.json`) | Provides navigate/click/fill/snapshot tools with token-efficient accessibility-tree snapshots; no per-task browser downloads |
| Reproducible suite runs: verifying completed work, matching CI | Docker container from the official Playwright image | Locks browser versions and OS dependencies together; keeps roughly 2 GB of browsers off the host; runs the exact environment CI uses |
| Tight-loop test authoring: writing or debugging tests with rapid re-runs | Local install (`@playwright/test` as a repo devDependency) | Fastest feedback loop; host-side trace viewer and debugger |

Selection rules:

- Implementations MUST use the Playwright MCP server for one-off interactive browsing when it is available, and MUST NOT ad-hoc install Playwright packages or browsers for that purpose.
- Implementations MUST NOT download browsers onto the host (`npx playwright install`) when the suite will be verified in Docker or CI. The authoring loop is the only permitted exception.
- Final verification of test work MUST use the Docker path, not a host-local run left over from the authoring loop.

## Docker Execution Requirements

- **Image pinning:** MUST use the official image with the tag pinned to the repo's Playwright version (for example `mcr.microsoft.com/playwright:v1.49.0-noble`). Floating tags (`latest`, `v1.49-noble` without the patch) MUST NOT be used because the image's bundled browsers and its Playwright version drift from the repo's pin.
- **Workspace mounting:** MUST mount the repository into the container and run the repo's own test command; test code MUST NOT be baked into ad-hoc images.
- **Container hygiene:** `--rm` and `--init` MUST be used so containers and zombie processes never accumulate; `--privileged` MUST NOT be used. Resource cleanup follows the `coding-standards` rule.
- **Host service access:** when tests target a dev server on the host, on Linux the invocation MUST add `--add-host=host.docker.internal:host-gateway` and tests MUST address the host as `host.docker.internal` (container-local `localhost` does not reach the host).
- **Reference invocation:**

```
docker run --rm --init \
  -v "$PWD:/work" -w /work \
  --add-host=host.docker.internal:host-gateway \
  mcr.microsoft.com/playwright:v<repo-version>-noble \
  npx playwright test
```

## Local Install Constraints

- Local Playwright MUST exist only as a repository devDependency locked by the repo's lockfile. Global host installs (`npm i -g playwright`) MUST NOT be created.
- Environments without Docker fall back to the local-install leg for every scenario above.

## Conformance

Violations of MUST or MUST NOT requirements constitute conformance failures, notably: ad-hoc Playwright installs for interactive browsing while the MCP server is available; unpinned or floating Playwright image tags; host browser downloads outside the authoring loop; missing `--rm`/`--init` or use of `--privileged`; global Playwright installs.
