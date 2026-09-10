#!/usr/bin/env bash
#
# Regenerates the managed Zen free pool in config.yaml from the live
# catalog. Explicit-run only (make litellm-refresh): never at container
# start, because config.yaml is a stowed symlink into a git repo, and any
# newly surfaced id must pass the V4 tool-calling gate in opencode/GATEWAY.md
# before it earns a pool slot.
#
# Semantics: entries for ids still in the catalog are preserved verbatim
# (manual model_info stanzas survive); ids gone from the catalog are
# dropped; new free ids are appended from the template. muse-spark ids are
# always excluded (Responses API only, contributor tier trains on data).

set -euo pipefail

CONFIG_PATH="${CONFIG_PATH:-$HOME/.config/litellm/config.yaml}"
ZEN_MODELS_URL="${ZEN_MODELS_URL:-https://opencode.ai/zen/v1/models}"
ASSUME_YES=0
DRY_RUN=0

usage() {
  echo "Usage: generate-models.sh [--yes] [--dry-run]"
  echo "  --yes      apply without prompting"
  echo "  --dry-run  print the diff, never write"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ -z "${ZEN_API_KEY:-}" && -f "$(dirname "$CONFIG_PATH")/env" ]]; then
  # shellcheck disable=SC1091
  . "$(dirname "$CONFIG_PATH")/env"
fi

if [[ -z "${ZEN_API_KEY:-}" ]]; then
  echo "ZEN_API_KEY not set and no env file next to config" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH" >&2
  exit 1
fi

catalog="$(mktemp)"
trap 'rm -f "$catalog"' EXIT

if ! curl -fsS -H "Authorization: Bearer ${ZEN_API_KEY}" "$ZEN_MODELS_URL" -o "$catalog"; then
  echo "Catalog fetch failed: $ZEN_MODELS_URL" >&2
  exit 1
fi

CONFIG_PATH="$CONFIG_PATH" ASSUME_YES="$ASSUME_YES" DRY_RUN="$DRY_RUN" \
python3 - "$catalog" <<'PY'
import difflib
import json
import os
import re
import sys
import tempfile

catalog_path = sys.argv[1]
# Write to the resolved target: with stow, config.yaml is a symlink into
# the dotfiles repo, and os.replace must not clobber the symlink itself.
config_path = os.path.realpath(os.environ["CONFIG_PATH"])
assume_yes = os.environ["ASSUME_YES"] == "1"
dry_run = os.environ["DRY_RUN"] == "1"

BEGIN = "# BEGIN MANAGED BLOCK"
END = "# END MANAGED BLOCK"
API_BASE = "https://opencode.ai/zen/v1"
ENTRY_TEMPLATE = """  - model_name: cascade
    litellm_params:
      model: openai/{model_id}
      api_base: {api_base}
      api_key: os.environ/ZEN_API_KEY
"""

with open(catalog_path) as f:
    catalog = json.load(f)
catalog_ids = []
for entry in catalog.get("data", []):
    model_id = entry.get("id", "")
    if "muse-spark" in model_id:
        continue
    if "free" in model_id or model_id == "big-pickle":
        catalog_ids.append(model_id)

with open(config_path) as f:
    lines = f.read().splitlines(keepends=True)

begin_idx = end_idx = None
for i, line in enumerate(lines):
    if BEGIN in line:
        begin_idx = i
    elif END in line:
        end_idx = i
if begin_idx is None or end_idx is None or end_idx < begin_idx:
    print(f"Managed markers not found in {config_path}", file=sys.stderr)
    sys.exit(1)

managed = lines[begin_idx + 1 : end_idx]

entry_starts = [i for i, line in enumerate(managed) if re.match(r"  - model_name:", line)]
existing_blocks = {}
for n, start in enumerate(entry_starts):
    stop = entry_starts[n + 1] if n + 1 < len(entry_starts) else len(managed)
    block = "".join(managed[start:stop]).rstrip("\n") + "\n"
    m = re.search(r"model: openai/(\S+)", block)
    if m:
        existing_blocks[m.group(1)] = block

new_blocks = [existing_blocks[mid] for mid in catalog_ids if mid in existing_blocks]
added = [mid for mid in catalog_ids if mid not in existing_blocks]
new_blocks += [ENTRY_TEMPLATE.format(model_id=mid, api_base=API_BASE) for mid in added]
removed = [mid for mid in existing_blocks if mid not in catalog_ids]

print(f"pool: {len(catalog_ids)} catalog ids, {len(added)} added, {len(removed)} removed")
for mid in added:
    print(f"  + {mid}  (needs the V4 gate before earning a pool slot)")
for mid in removed:
    print(f"  - {mid}")

new_managed = ["".join(new_blocks).rstrip("\n") + "\n"] if new_blocks else []
new_content = "".join(lines[: begin_idx + 1] + new_managed + lines[end_idx:])
old_content = "".join(lines)

if new_content == old_content:
    print("nothing to change")
    sys.exit(0)

diff = list(difflib.unified_diff(
    old_content.splitlines(keepends=True),
    new_content.splitlines(keepends=True),
    fromfile="config.yaml (current)",
    tofile="config.yaml (regenerated)",
))
sys.stdout.writelines(diff)

if dry_run:
    print("dry run: no write")
    sys.exit(0)

if not assume_yes:
    try:
        reply = input("Apply? [y/N] ")
    except EOFError:
        reply = ""
    if reply.strip().lower() not in ("y", "yes"):
        print("aborted")
        sys.exit(0)

config_dir = os.path.dirname(os.path.abspath(config_path))
fd, tmp_path = tempfile.mkstemp(dir=config_dir, prefix=".config.yaml.", text=True)
try:
    with os.fdopen(fd, "w") as f:
        f.write(new_content)
    os.replace(tmp_path, config_path)
except BaseException:
    os.unlink(tmp_path)
    raise
print(f"applied: {config_path}")
PY
