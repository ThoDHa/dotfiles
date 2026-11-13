#!/usr/bin/env bash
#
# Transcript audit for the Tier-B fixture harness (ORCH-4-9-1): scans agent
# execution transcripts for direct .tasks access and exits nonzero when any
# is found. ORCH-4-9-4 runs one audited transcript per role's representative
# execution.
#
# Violation classes:
#   V1 shell-adjacency   a shell file tool (cat, grep, ls, wc, find, sed,
#                        awk, head, tail, cp, mv, rm, touch, mkdir, tee)
#                        or an interpreter (python3, python, perl, node,
#                        ruby, dd) reaching a .tasks path within one
#                        command segment
#   V2 file-path-field   a structured tool record naming a .tasks path in
#                        its file_path field (JSON double-quoted form and
#                        the key=value form)
#
# Not violations: `tasks <verb>` invocations (the CLI resolves .tasks
# internally; that is the sanctioned surface), and prose or paths that
# mention .tasks with no file-tool adjacency and no file_path field.
#
# The interpreter stems close the allow-first hole: worker and manager
# carry blanket shell allows, so their fixture configs deny the write
# tools and interpreters explicitly (tier-b/worker.yaml,
# tier-b/manager.yaml), and this audit detects the same routes in
# transcripts, including under configs whose catch-all deny is absent.
# Future alternative to the enumeration: a path-token model (any .tasks
# argument token on a command line whose leading token is not tasks)
# would be one pattern instead of a stem list, at the cost of a
# prose-tolerance story for transcripts that legitimately mention
# .tasks in prose; ORCH-4-10 may adopt it when it owns enforcement.
#
# Boundary: the audit is detection, not denial. opencode permission maps
# have no read action, so the native read tool cannot be denied
# mechanically; the audit covers that gap for the representative
# executions. This is role-discipline evidence, not enforcement;
# enforcement is ORCH-4-10's work.
#
# Exit contract: 0 clean, 1 violations found, 2 usage error.
#
# Usage: audit-transcript.sh <transcript-file> [<transcript-file>...]

set -uo pipefail

if (($# == 0)); then
	printf 'usage: audit-transcript.sh <transcript-file> [<transcript-file>...]\n' >&2
	exit 2
fi

for f in "$@"; do
	if [[ ! -f "$f" ]]; then
		printf 'audit-transcript: no such transcript: %s\n' "$f" >&2
		exit 2
	fi
done

# Word boundaries are explicit character classes (the bash =~ regex \b is a
# GNU libc extension, not portable to the verify container's libc).
V1='(^|[^[:alnum:]_-])(cat|grep|ls|wc|find|sed|awk|head|tail|cp|mv|rm|touch|mkdir|tee|python3|python|perl|node|ruby|dd)([^[:alnum:]_-]|$)[^;|&]{0,80}\.tasks(/|[^/[:alnum:]-]|$)'
V2A='"file_path"[[:space:]]*:[[:space:]]*"[^"]*\.tasks'
V2B="file_path[[:space:]]*[=:][[:space:]]*['\"]?[^'\"]*\.tasks"

violations=0
for f in "$@"; do
	line_no=0
	# The `|| [[ -n $line ]]` tail keeps a final line that lacks its newline
	# in scope: a bare while-read drops it, and a violation there would
	# escape the scan.
	while IFS= read -r line || [[ -n "$line" ]]; do
		line_no=$((line_no + 1))
		vid=""
		if [[ "$line" =~ $V1 ]]; then
			vid="V1"
		elif [[ "$line" =~ $V2A ]]; then
			vid="V2"
		elif [[ "$line" =~ $V2B ]]; then
			vid="V2"
		fi
		if [[ -n "$vid" ]]; then
			# violations go to stderr: they accompany exit 1, and the clean
			# run's summary stays the only stdout output
			printf 'VIOLATION: %s:%s: %s: %s\n' "$f" "$line_no" "$vid" "$line" >&2
			violations=$((violations + 1))
		fi
	done < "$f"
done

if ((violations > 0)); then
	echo "audit-transcript: $violations direct .tasks access violation(s)" >&2
	exit 1
fi
echo "audit-transcript: clean ($# transcript(s), zero direct .tasks access)"
exit 0
