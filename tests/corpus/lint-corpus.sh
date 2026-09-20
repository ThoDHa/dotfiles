#!/usr/bin/env bash
#
# Corpus lint: mechanical drift checks over the tracked documentation
# corpus (corpus-review finding 16). Six checks run in order and the
# lint fails fast on the first finding, printing `FAIL: <file>:<line>:
# <what>`:
#
#   1. em-dash sweep          no U+2014 and no space-flanked U+2013 in
#                             corpus prose (Makefile included; code spans
#                             and fences excluded; the two definitional
#                             rule lines allowlisted)
#   2. link liveness          every relative file link and #anchor
#                             resolves (GitHub slug rules; external
#                             http(s) out of scope; fence contents and
#                             inline code spans excluded)
#   3. heading structure      exactly one `# ` title per file, no level
#                             jumps skipping a rung
#   4. INVENTORY counts       class heading count equals list length
#   5. INVENTORY membership   class list equals the tracked source set
#                             (directory classes: git ls-files of the
#                             heading's directory; corpus-docs class:
#                             tracked .md outside the excluded trees)
#   6. line budgets           agents 300, rules 190, SKILL.md 950,
#                             README/DESIGN under 500
#
# Reads only tracked files (git ls-files basis), so the result is
# reproducible locally and in CI. The lint's own files (this script, the
# CI workflow) stay outside lint scope, the same self-exclusion contract
# INVENTORY.md states for itself.
#
# Usage: lint-corpus.sh [--root DIR]
#   --root DIR   lint the corpus copy at DIR instead of this repo
#                (failure-fixture runs); the CORPUS_ROOT env var does
#                the same

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS_ROOT="${CORPUS_ROOT:-$REPO_ROOT}"
if [[ "${1:-}" == "--root" ]]; then
	if [[ -z "${2:-}" ]]; then
		echo "FAIL: --root requires a directory argument" >&2
		exit 1
	fi
	CORPUS_ROOT="$2"
fi
CORPUS_ROOT="$(cd "$CORPUS_ROOT" && pwd -P)"
cd "$CORPUS_ROOT"

# Corpus scope: tracked markdown under these paths feeds the content
# checks; the Makefile joins the em-dash sweep only.
SKILL_SCOPE="agents/.agents/skills"
AGENTS_SCOPE="opencode/.config/opencode/agents"
RULES_SCOPE="opencode/.config/opencode/rules"
INVENTORY="INVENTORY.md"
MAKEFILE="Makefile"
CORPUS_SCOPES=("$SKILL_SCOPE" "$AGENTS_SCOPE" "$RULES_SCOPE" "README.md" "opencode/DESIGN.md" "$INVENTORY")

# Definitional allowlist: the two rule lines that must show the very
# characters they ban (core.md names U+2014 bare in parentheses; the
# documentation-standards en-dash rule shows U+2013 in code spans).
ALLOWLIST_CORE_FILE="opencode/.config/opencode/rules/core.md"
ALLOWLIST_CORE_LINE="MUST NEVER use em dashes"
ALLOWLIST_DOCSTAND_FILE="agents/.agents/skills/documentation-standards/SKILL.md"
ALLOWLIST_DOCSTAND_LINE="An en-dash"

# The corpus-docs class names no directory in its heading; the parser
# marks it with this placeholder and the membership check switches to
# the derived tracked-markdown source set instead of git ls-files.
CORPUS_DOCS_DIR="."

# Line budgets from the corpus review; sized to the current corpus with
# headroom, binding only future drift.
BUDGET_AGENT_LINES=300
BUDGET_RULE_LINES=190
BUDGET_SKILL_LINES=950
BUDGET_CORPUS_DOC_LINES=500

EM_DASH="$(printf '\xe2\x80\x94')"
EN_DASH="$(printf '\xe2\x80\x93')"

# Shared awk preamble: fence-state helpers for ``` and ~~~ blocks.
# Fence lines and fence contents are excluded from every content scan.
FENCE_AWK='
function fence_toggle(line) {
	if (line ~ /^[[:space:]]*```/) { bt_open = !bt_open; return 1 }
	if (line ~ /^[[:space:]]*~~~/) { td_open = !td_open; return 1 }
	return 0
}
function in_fence() { return bt_open || td_open }
BEGIN { bt_open = 0; td_open = 0 }
'

fail_at() { # file line message
	echo "FAIL: $1:$2: $3"
	exit 1
}

md_corpus_files() {
	git ls-files -- "${CORPUS_SCOPES[@]}" | grep -E '\.md$'
}

declare -A TRACKED=()
load_tracked() {
	local path
	while IFS= read -r -d '' path; do
		TRACKED["$path"]=1
	done < <(git ls-files -z)
}
is_tracked() { [[ -n "${TRACKED[$1]+x}" ]]; }

scan_em_dashes() { # file
	awk -v file="$1" -v em="$EM_DASH" -v en="$EN_DASH" \
		-v allow_core_file="$ALLOWLIST_CORE_FILE" -v allow_core_line="$ALLOWLIST_CORE_LINE" \
		-v allow_docstand_file="$ALLOWLIST_DOCSTAND_FILE" -v allow_docstand_line="$ALLOWLIST_DOCSTAND_LINE" \
		"${FENCE_AWK}"'
		{
			if (fence_toggle($0)) next
			if (in_fence()) next
			if (file == allow_core_file && index($0, allow_core_line) > 0) next
			if (file == allow_docstand_file && index($0, allow_docstand_line) > 0) next
			line = $0
			while (match(line, /`[^`]*`/))
				line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
			if (index(line, em) > 0) {
				printf "FAIL: %s:%d: em dash (U+2014) in corpus prose\n", file, NR
				exit 1
			}
			if (index(line, " " en " ") > 0) {
				printf "FAIL: %s:%d: space-flanked en dash (U+2013) in corpus prose\n", file, NR
				exit 1
			}
		}' "$1"
}

check_em_dashes() {
	local file
	while IFS= read -r file; do
		scan_em_dashes "$file"
	done < <(md_corpus_files; printf '%s\n' "$MAKEFILE")
	echo "  1/6 em-dash sweep: clean"
}

heading_slugs() { # file; prints GitHub-style anchor slugs for its headings
	awk "${FENCE_AWK}"'
	{
		if (fence_toggle($0)) next
		if (in_fence()) next
		if ($0 !~ /^#{1,6}[[:space:]]/) next
		text = $0
		sub(/^#{1,6}[[:space:]]+/, "", text)
		sub(/[[:space:]]*#+[[:space:]]*$/, "", text)
		gsub(/`/, "", text)
		text = tolower(text)
		slug = ""
		for (i = 1; i <= length(text); i++) {
			c = substr(text, i, 1)
			if (c ~ /^[a-z0-9_-]$/) slug = slug c
			else if (c == " ") slug = slug "-"
		}
		if (slug != "") print slug
	}' "$1"
}

declare -A ANCHORS=()
ANCHORS_FILE=""
load_anchors() { # file; rebuilds the ANCHORS slug set for one file
	local file="$1" slug n
	[[ "$ANCHORS_FILE" == "$file" ]] && return 0
	ANCHORS_FILE="$file"
	ANCHORS=()
	while IFS= read -r slug; do
		if [[ -n "${ANCHORS[$slug]+x}" ]]; then
			n=1
			while [[ -n "${ANCHORS["$slug-$n"]+x}" ]]; do
				n=$((n + 1))
			done
			slug="$slug-$n"
		fi
		ANCHORS["$slug"]=1
	done < <(heading_slugs "$file")
}

extract_links() { # file; prints "line<TAB>target" per markdown link
	awk "${FENCE_AWK}"'
	{
		if (fence_toggle($0)) next
		if (in_fence()) next
		line = $0
		while (match(line, /`[^`]*`/))
			line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
		while (match(line, /\[[^][]*\]\([^()]*\)/)) {
			link = substr(line, RSTART, RLENGTH)
			line = substr(line, RSTART + RLENGTH)
			target = link
			sub(/^.*\]\(/, "", target)
			sub(/\)$/, "", target)
			sub(/[[:space:]]+"[^"]*"$/, "", target)
			printf "%d\t%s\n", NR, target
		}
	}' "$1"
}

resolve_link_path() { # src_file link_target; prints the repo-relative path
	local src="$1" rel="$2" abs
	abs="$(realpath -m "$CORPUS_ROOT/$(dirname "$src")/$rel")"
	printf '%s' "${abs#"$CORPUS_ROOT"/}"
}

check_links() {
	local file ln target path_part anchor resolved
	while IFS= read -r file; do
		while IFS=$'\t' read -r ln target; do
			case "$target" in
				*"://"* | mailto:* | "<"*) continue ;;
			esac
			path_part="$target"
			anchor=""
			if [[ "$target" == *"#"* ]]; then
				path_part="${target%%#*}"
				anchor="${target#*#}"
			fi
			if [[ -z "$path_part" ]]; then
				load_anchors "$file"
				[[ -n "${ANCHORS[$anchor]+x}" ]] \
					|| fail_at "$file" "$ln" "dead anchor '#$anchor' (no such heading in this file)"
				continue
			fi
			resolved="$(resolve_link_path "$file" "$path_part")"
			if ! is_tracked "$resolved"; then
				fail_at "$file" "$ln" "dead link target '$target' (no tracked file at '$resolved')"
			fi
			if [[ -n "$anchor" ]]; then
				load_anchors "$resolved"
				[[ -n "${ANCHORS[$anchor]+x}" ]] \
					|| fail_at "$file" "$ln" "dead anchor '#$anchor' (not a heading of '$resolved')"
			fi
		done < <(extract_links "$file")
	done < <(md_corpus_files)
	echo "  2/6 link liveness: clean"
}

scan_headings() { # file
	awk -v file="$1" "${FENCE_AWK}"'
	BEGIN { in_frontmatter = 0 }
	{
		if (fence_toggle($0)) next
		if (in_fence()) next
		if (NR == 1 && $0 == "---") { in_frontmatter = 1; next }
		if (in_frontmatter) {
			if ($0 == "---") in_frontmatter = 0
			next
		}
		if ($0 !~ /^#{1,6}[[:space:]]/) next
		match($0, /^#+/)
		level = RLENGTH
		if (!saw_any) {
			if (level != 1) {
				printf "FAIL: %s:%d: first heading is level %d; expected the single # title\n", file, NR, level
				exit 1
			}
			saw_any = 1
			saw_title = 1
			prev = 1
			next
		}
		if (level == 1) {
			printf "FAIL: %s:%d: second # title; exactly one allowed\n", file, NR
			exit 1
		}
		if (level > prev + 1) {
			printf "FAIL: %s:%d: heading level jump from %d to %d\n", file, NR, prev, level
			exit 1
		}
		prev = level
	}
	END {
		if (saw_title) exit 0
	}' "$1"
}

check_headings() {
	local file
	while IFS= read -r file; do
		scan_headings "$file"
	done < <(md_corpus_files)
	echo "  3/6 heading structure: clean"
}

parse_inventory() { # emits C<class> and E<entry> records
	awk -v inv="$INVENTORY" '
	function flush_class() {
		if (have_class) printf "C\t%s\t%s\t%d\t%s\n", class_name, class_count, class_line, class_dir
	}
	function parse_heading(heading, line_no,    head, matched, inner, comma_at) {
		head = heading
		sub(/^##[[:space:]]+/, "", head)
		if (match(head, /[[:space:]]\([0-9]+\)$/)) {
			class_count = substr(head, RSTART + 2, RLENGTH - 3)
			class_dir = "."
			class_name = substr(head, 1, RSTART - 1)
		} else if (match(head, /[[:space:]]\([^()]+, [0-9]+\)$/)) {
			matched = substr(head, RSTART, RLENGTH)
			inner = substr(matched, 3, length(matched) - 3)
			comma_at = match(inner, /, [0-9]+$/)
			if (comma_at == 0) {
				printf "FAIL: %s:%d: malformed class heading: %s\n", FILENAME, line_no, heading
				exit 1
			}
			class_count = substr(inner, comma_at + 2, length(inner) - comma_at - 1)
			class_dir = substr(inner, 1, comma_at - 1)
			class_name = substr(head, 1, length(head) - length(matched))
		} else {
			printf "FAIL: %s:%d: class heading not in \x27<Name> (<dir>/, N)\x27 or \x27<Name> (N)\x27 form: %s\n", FILENAME, line_no, heading
			exit 1
		}
		sub(/[[:space:]]+$/, "", class_name)
		have_class = 1
		class_line = line_no
	}
	/^## / {
		parse_heading($0, NR)
		flush_class()
		next
	}
	/^[[:space:]]*$/ { next }
	/^#/ { next }
	{
		if (!have_class) next
		line = $0
		sub(/[[:space:]]+$/, "", line)
		printf "E\t%s\n", line
	}' "$INVENTORY"
}

declare -A INV_DIR=() INV_COUNT=() INV_LINE=() INV_ENTRIES=() INV_ENTRY_TOTAL=()
INV_CLASS_ORDER=()
read_inventory() {
	local stream tag name count head_line dir last
	INV_CLASS_ORDER=()
	stream="$(parse_inventory)"
	while IFS=$'\t' read -r tag name count head_line dir; do
		case "$tag" in
			C)
				INV_CLASS_ORDER+=("$name")
				INV_DIR["$name"]="$dir"
				INV_COUNT["$name"]="$count"
				INV_LINE["$name"]="$head_line"
				INV_ENTRIES["$name"]=""
				INV_ENTRY_TOTAL["$name"]=0
				;;
			E)
				last="${INV_CLASS_ORDER[${#INV_CLASS_ORDER[@]} - 1]}"
				INV_ENTRIES["$last"]+="${INV_ENTRIES["$last"]:+$'\n'}$name"
				INV_ENTRY_TOTAL["$last"]=$((INV_ENTRY_TOTAL["$last"] + 1))
				;;
		esac
	done <<<"$stream"
}

check_inventory_counts() {
	local name i
	for i in "${!INV_CLASS_ORDER[@]}"; do
		name="${INV_CLASS_ORDER[$i]}"
		if [[ "${INV_COUNT[$name]}" -ne "${INV_ENTRY_TOTAL[$name]}" ]]; then
			fail_at "$INVENTORY" "${INV_LINE[$name]}" \
				"class '<$name>' heading count ${INV_COUNT[$name]} != list length ${INV_ENTRY_TOTAL[$name]}"
		fi
	done
	echo "  4/6 INVENTORY heading counts: clean"
}

inventory_corpus_docs_members() {
	# Corpus-docs derivation (task contract): tracked .md outside the
	# stowed config and non-corpus trees, minus the manifest itself.
	git ls-files '*.md' | awk \
		'$0 != inv && $0 !~ /^(agents\/|opencode\/\.config\/|bootstrap\/|reference\/|tests\/|\.github\/)/' \
		inv="$INVENTORY" - | sort
}

check_inventory_membership() {
	local name i expected actual missing extra source_desc
	for i in "${!INV_CLASS_ORDER[@]}"; do
		name="${INV_CLASS_ORDER[$i]}"
		if [[ "${INV_DIR[$name]}" == "$CORPUS_DOCS_DIR" ]]; then
			expected="$(inventory_corpus_docs_members)"
			source_desc="tracked .md outside the excluded trees, minus $INVENTORY itself"
		else
			expected="$(git ls-files -- "${INV_DIR[$name]}" | sort)"
			source_desc="git ls-files ${INV_DIR[$name]}"
		fi
		if [[ "${INV_ENTRY_TOTAL[$name]}" -eq 0 ]]; then
			actual=""
		else
			actual="$(printf '%s\n' "${INV_ENTRIES[$name]}" | sort)"
		fi
		if [[ "$expected" != "$actual" ]]; then
			missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd ' ' -)"
			extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | paste -sd ' ' -)"
			fail_at "$INVENTORY" "${INV_LINE[$name]}" \
				"membership drift in class '<$name>' vs $source_desc: missing [$missing] extra [$extra]"
		fi
	done
	echo "  5/6 INVENTORY membership: clean"
}

check_line_budgets() {
	local file lines budget
	while IFS= read -r file; do
		budget=""
		case "$file" in
			"$AGENTS_SCOPE"/*.md) budget=$BUDGET_AGENT_LINES ;;
			"$RULES_SCOPE"/*.md) budget=$BUDGET_RULE_LINES ;;
			"$SKILL_SCOPE"/*/SKILL.md) budget=$BUDGET_SKILL_LINES ;;
			README.md | opencode/DESIGN.md) budget=$BUDGET_CORPUS_DOC_LINES ;;
		esac
		[[ -n "$budget" ]] || continue
		lines="$(wc -l < "$file")"
		case "$file" in
			README.md | opencode/DESIGN.md)
				((lines < budget)) || fail_at "$file" "$lines" \
					"file has $lines lines; corpus docs must stay under $budget"
				;;
			*)
				((lines <= budget)) || fail_at "$file" "$lines" \
					"file has $lines lines; budget is $budget"
				;;
		esac
	done < <(md_corpus_files)
	echo "  6/6 line budgets: clean"
}

main() {
	git rev-parse --show-toplevel >/dev/null 2>&1 \
		|| fail_at "$CORPUS_ROOT" 1 "not a git work tree; the lint reads tracked files only"
	load_tracked
	echo "Linting the corpus at $CORPUS_ROOT"
	check_em_dashes
	check_links
	check_headings
	read_inventory
	check_inventory_counts
	check_inventory_membership
	check_line_budgets
	echo "Corpus lint passed: 6 checks clean"
}

main "$@"
