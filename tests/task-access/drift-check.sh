#!/usr/bin/env bash
#
# Task-access drift check (ORCH-4-9-1, Tier A): verifies that every surface
# listed in the migrated-surfaces list is free of direct .tasks access
# patterns. The list (tests/fixtures/task-access/migrated-surfaces.txt) is
# EMPTY at the ORCH-4-9-1 landing; ORCH-4-9-2 and ORCH-4-9-3 extend it per
# migration stage, and this check must be green at every stage commit.
#
# Boundary: the check proves migration discipline over listed text surfaces.
# It is documentation drift detection, not a filesystem boundary; enforcement
# is ORCH-4-10's work.
#
# Pattern set (a listed line matching any pattern is a finding):
#   P1 map-allow    an opencode permission-map edit allow on a .tasks resource
#                   ({ action: edit, resource: ".tasks/**", ... })
#   P2 tool-path    a shell file tool (cat, grep, ls, wc, find, sed, awk,
#                   head, tail) with a `.tasks/` path in its command segment
#   P3 tool-dirarg  ls/find/du/stat/file with a bare .tasks directory argument
#   P4 uncited-mention  any other non-fenced line naming .tasks: a listed
#                   normative surface must cite a `tasks <verb>` on the same
#                   line or carry the sanctioned marker, so verb-less noun
#                   framings, stems outside the old write/read sets, and
#                   mentions beyond the old 60-character windows are all
#                   findings (strictly stronger than the write-frame and
#                   read-frame classes this rule replaces)
#   P5 fence-parity an odd fence count at EOF: the file ends inside a
#                   skipped fence region, so its tail escaped the scan
#
# Map diff (frontmatter permission stanzas): a list entry of the form
#   <path> @<role>
# declares a permission-map-bearing surface. Its frontmatter is machine
# data: text patterns do not scan it. Instead the ordered sequence of
# edit-action rules on .tasks resources in the frontmatter must equal the
# sequence in tests/fixtures/task-access/tier-b/<role>.yaml above that
# config's fixture-denial-tail marker (order matters: the maps resolve
# last-match-wins). This is the map-diff route: a retained interim allow
# (the manager's, until ORCH-4-10) is green because the target map
# retains it, and a live rule the target does not carry is a finding.
# P1 keeps catching edit-allow text in body prose, which stays scanned.
# A config with no marker line is treated as target in full; every
# tier-b config carries the marker.
#
# Evaluation order: P1-P3 are precise classes and win over P4 on a line
# matching both, so one violation line reports once under its most precise
# class. P1-P4 apply only outside fences and never to a line carrying the
# task-access-sanctioned marker; P4 is additionally satisfied by a same-line
# `tasks <verb>` citation, the sanctioned CLI route being the point.
#
# Allowances, in order:
#   - fenced regions (``` or ~~~) are skipped, so quoted examples of removed
#     patterns do not fire;
#   - a line carrying the `task-access-sanctioned` marker is skipped; the
#     marker is reserved for the retained planner research-deposit exception
#     (verb-map.md, deviation table trigger b) until a CLI research-deposit
#     path lands and the exception is removed.
#
# Exit contract: 0 green (list clean or empty), 1 findings (bad path, missing
# listed file, or pattern matches), 2 usage error.
#
# Usage: drift-check.sh [--list FILE] [--root DIR]
#   --list FILE   migrated-surfaces list (default: the repo's, relative to
#                 this script's repo root)
#   --root DIR    root the listed repo-relative paths resolve against
#                 (default: this script's repo root; failure-fixture runs
#                 override it with a temp tree)

set -uo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIST_FILE="$SCRIPT_ROOT/tests/fixtures/task-access/migrated-surfaces.txt"
SCAN_ROOT="$SCRIPT_ROOT"

usage_error() {
	printf 'usage: drift-check.sh [--list FILE] [--root DIR]\n' >&2
	exit 2
}

while (($# > 0)); do
	case "$1" in
	--list)
		(($# >= 2)) || usage_error
		LIST_FILE="$2"
		shift 2
		;;
	--root)
		(($# >= 2)) || usage_error
		SCAN_ROOT="$2"
		shift 2
		;;
	*) usage_error ;;
	esac
done

if [[ ! -f "$LIST_FILE" ]]; then
	printf 'FAIL: migrated-surfaces list not found: %s\n' "$LIST_FILE" >&2
	exit 1
fi

# Word boundaries are written as explicit non-word character classes, not \b:
# bash's =~ regex support for \b is a GNU libc extension the verify container's
# libc does not guarantee. Each pattern's leading group consumes one boundary
# character; matching (not capturing) semantics keep this transparent.
patterns=(
	"P1	map-allow	\{[[:space:]]*action:[[:space:]]*edit,[[:space:]]*resource:[[:space:]]*[\"']?\.tasks[^}]*effect:[[:space:]]*allow"
	"P2	tool-path	(^|[^[:alnum:]_-])(cat|grep|ls|wc|find|sed|awk|head|tail)[^;|&]{0,60}\.tasks/"
	"P3	tool-dirarg	(^|[^[:alnum:]_-])(ls|find|du|stat|file)[[:space:]]+[^[:space:]]*\.tasks([^/[:alnum:]-]|$)"
)
# The mention rule and fence parity stay out of the pattern array: P4 needs
# a negated condition (a same-line citation defeats it), which the bash =~
# regex dialect cannot express, and P5 is a per-file property, not a line
# match. Word boundaries stay explicit character classes (the bash =~ regex
# \b is a GNU libc extension, not portable to the verify container's libc).
mention_re='\.tasks(/|$|[^/[:alnum:]-])'
# The citation alternation pins the landed verb stems, so noun framings
# ("the tasks CLI", "the tasks board") satisfy nothing: P4's documented
# teeth. A verb that lands updates this alternation in the same change.
cite_re='(^|[^[:alnum:]_-])tasks[[:space:]]+(show|list|reports|export|lint|doctor|frontier|claims|events|help|init|render|new|set|report|log|edit|claim|release|reclaim|archive|close|stamp)'

# Marker line that ends a tier-b config's target map; everything below it
# is fixture-only denial tail. Matched as a fixed whole line (grep -xF):
# the configs' header comments mention the tail in prose and must not
# read as markers.
tail_marker='# fixture denial tail (fixture-only rules; not part of the target map)'

# One opencode rule line: { action: A, resource: R, effect: E }
rules_re='\{[[:space:]]*action:[[:space:]]*([^,]+),[[:space:]]*resource:[[:space:]]*("[^"]*"|[^,]+),[[:space:]]*effect:[[:space:]]*([^}]+)\}$'

# edit_tasks_rules FILE [END-LINE]: canonical "action|resource|effect"
# lines for the edit-action rules whose resource names .tasks, in file
# order, from lines 1..END-LINE (or the whole file when END-LINE is
# empty). Quotes and rule-internal spacing are normalized so the live
# charter and the tier-b config compare byte-for-byte on meaning.
edit_tasks_rules() { # file [end-line] -> canonical rules on stdout
	local file="$1" endline="$2" rule act res eff lead trail
	if [[ -n "$endline" ]]; then
		head -n "$endline" "$file"
	else
		cat "$file"
	fi | while IFS= read -r rule; do
		[[ "$rule" =~ $rules_re ]] || continue
		act="${BASH_REMATCH[1]}"; act="${act//[[:space:]]/}"
		res="${BASH_REMATCH[2]}"
		lead="${res%%[![:space:]]*}"; trail="${res##*[![:space:]]}"
		res="${res#"$lead"}"; res="${res%"$trail"}"
		eff="${BASH_REMATCH[3]}"; eff="${eff//[[:space:]]/}"
		res="${res%\"}"; res="${res#\"}"
		[[ "$act" == "edit" && "$res" == *.tasks* ]] || continue
		printf '%s|%s|%s\n' "$act" "$res" "$eff"
	done
}

# frontmatter_end FILE: line number of the closing --- of a YAML
# frontmatter that opens at line 1, empty when there is none.
frontmatter_end() { # file -> line number on stdout
	awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$1"
}

findings=0
finding() { # path line-number pattern-id pattern-name line-text; findings go to
	# stderr: they accompany exit 1, and the success line stays the only
	# stdout output a clean run produces
	printf 'FAIL: %s:%s: %s (%s): %s\n' "$1" "$2" "$3" "$4" "$5" >&2
	findings=$((findings + 1))
}

# Effective entries only: blank lines and # comments carry no surface.
mapfile -t surfaces < <(grep -v '^[[:space:]]*\(#\|$\)' "$LIST_FILE")

if ((${#surfaces[@]} == 0)); then
	echo "drift-check: migrated-surfaces list is empty; nothing to scan (green)"
	exit 0
fi

fence_re='^[[:space:]]*(```|~~~)'
for entry in "${surfaces[@]}"; do
	rel="$entry"
	role=""
	if [[ "$entry" =~ ^(.+)[[:space:]]+@([[:alnum:]-]+)$ ]]; then
		rel="${BASH_REMATCH[1]}"; role="${BASH_REMATCH[2]}"
	fi
	path="$SCAN_ROOT/$rel"
	if [[ ! -f "$path" ]]; then
		finding "$rel" "?" "P0" "listed-file-missing" "no file at $path"
		continue
	fi
	fm_end=0
	if [[ -n "$role" ]]; then
		if [[ "$(head -n 1 "$path")" == ---* ]]; then
			fm_end="$(frontmatter_end "$path")"
			[[ -n "$fm_end" ]] || fm_end=0
		fi
		if ((fm_end == 0)); then
			finding "$rel" "1" "MD" "map-diff" "@$role entry carries no YAML frontmatter permission stanza"
		fi
	fi
	in_fence=0
	line_no=0
	# The `|| [[ -n $line ]]` tail keeps a final line that lacks its newline
	# in scope: a bare while-read drops it, and a violation there would
	# escape the scan.
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_no=$((line_no + 1))
		# Frontmatter of an @role entry is machine data: the map-diff owns
		# it, and the text patterns never see it.
		if ((fm_end > 0 && line_no <= fm_end)); then continue; fi
		# Fence toggle: ``` or ~~~ opening/closing lines (with optional
		# trailing info string) end and start skipped regions.
		if [[ "$line" =~ $fence_re ]]; then
			if ((in_fence == 1)); then in_fence=0; else in_fence=1; fi
			continue
		fi
		if ((in_fence == 1)); then continue; fi
		if [[ "$line" == *"task-access-sanctioned"* ]]; then continue; fi
		hit_pid=""; hit_pname=""
		for spec in "${patterns[@]}"; do
			pid="${spec%%$'\t'*}"
			rest="${spec#*$'\t'}"
			pname="${rest%%$'\t'*}"
			regex="${rest#*$'\t'}"
			if [[ "$line" =~ $regex ]]; then
				hit_pid="$pid"; hit_pname="$pname"
				break
			fi
		done
		if [[ -z "$hit_pid" && "$line" =~ $mention_re && ! "$line" =~ $cite_re ]]; then
			hit_pid="P4"; hit_pname="uncited-mention"
		fi
		if [[ -n "$hit_pid" ]]; then
			finding "$rel" "$line_no" "$hit_pid" "$hit_pname" "$line"
		fi
	done < "$path"
	# Fence parity: an odd fence count means the file ends inside a skipped
	# region, so everything below the last stray fence escaped the scan.
	if ((in_fence == 1)); then
		finding "$rel" "$line_no" "P5" "fence-parity" "odd fence count; file ends inside a skipped fence region"
	fi
	if [[ -n "$role" && "$fm_end" -gt 0 ]]; then
		cfg="$SCRIPT_ROOT/tests/fixtures/task-access/tier-b/$role.yaml"
		if [[ ! -f "$cfg" ]]; then
			finding "$rel" "frontmatter" "MD" "map-diff" "no tier-b config for @$role: $cfg"
		else
			marker_line="$(grep -nxF "$tail_marker" "$cfg" | head -n 1 | cut -d: -f1)"
			target_end=""
			[[ -n "$marker_line" ]] && target_end=$((marker_line - 1))
			live_rules="$(edit_tasks_rules "$path" "$fm_end")"
			target_rules="$(edit_tasks_rules "$cfg" "$target_end")"
			if [[ "$live_rules" != "$target_rules" ]]; then
				finding "$rel" "frontmatter" "MD" "map-diff" "live .tasks edit rules [$(printf '%s' "$live_rules" | tr '\n' ' ')] differ from the tier-b target for @$role [$(printf '%s' "$target_rules" | tr '\n' ' ')]"
			fi
		fi
	fi
done

if ((findings > 0)); then
	echo "drift-check: $findings finding(s); migrated surfaces must be CLI-only" >&2
	exit 1
fi
echo "drift-check: ${#surfaces[@]} migrated surface(s) clean (green)"
exit 0
