# Sync comparator for the repo's artifact-sync suites, sourced by
# tests/agents-md/test-sync.sh, tests/claudecode/test-sync.sh, and
# tests/pi-agents/test-sync.sh. A sibling of harness.sh, not a member:
# only suites that compare regenerated artifacts against host state load
# these functions, so non-sync suites sourcing the harness stay free of
# sync-specific comparators. The sourcing suite must source harness.sh
# first (compare_fresh reports through its ok/bad counters) and define
# the per-suite globals the stale line is built from:
#   ARTIFACT_NOUN     - artifact name in the stale line ("AGENTS.md",
#                       "CLAUDE.md", "pi agents")
#   PROVENANCE_PHRASE - provenance sentence ("does not match a fresh
#                       generation of the rules.", "does not match a
#                       fresh compilation of the fleet.")
#   REMEDIATION       - the sync command that repairs the drift
# The diff summary length comes from the suite's DIFF_SUMMARY_LINES.

report_stale() { # fresh actual; prints the stale line, the diff summary, and the remediation
	echo "  Stale $ARTIFACT_NOUN: $2 $PROVENANCE_PHRASE"
	echo "  Diff summary (first $DIFF_SUMMARY_LINES lines, fresh vs host):"
	diff -u "$1" "$2" | sed -n "1,${DIFF_SUMMARY_LINES}p" | sed 's/^/    /' || true
	echo "  Remediation: $REMEDIATION"
}

compare_fresh() { # label fresh actual; ok on byte-identity, bad plus summary otherwise
	if cmp -s "$2" "$3"; then
		ok "$1"
		return 0
	fi
	bad "$1"
	report_stale "$2" "$3"
	return 1
}
