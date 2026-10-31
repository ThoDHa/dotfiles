# Sync comparator for the repo's artifact-sync suites, sourced by
# tests/agents-md/test-sync.sh and tests/pi-agents/test-sync.sh. A sibling
# of harness.sh, not a member:
# only suites that compare regenerated artifacts against host state load
# these functions, so non-sync suites sourcing the harness stay free of
# sync-specific comparators. The sourcing suite must source harness.sh
# first (compare_fresh reports through its ok/bad counters) and define
# the per-suite globals the stale line is built from; the guards below
# enforce that contract at source time, failing with the missing global
# named when a suite sources the lib with one unset:
#   ARTIFACT_NOUN     - artifact name in the stale line ("AGENTS.md",
#                       "pi agents")
#   PROVENANCE_PHRASE - provenance sentence ("does not match a fresh
#                       generation of the rules.", "does not match a
#                       fresh compilation of the fleet.")
#   REMEDIATION       - the sync command that repairs the drift
# The diff summary length comes from the suite's DIFF_SUMMARY_LINES.

: "${ARTIFACT_NOUN:?sync-comparator requires ARTIFACT_NOUN before sourcing}"
: "${PROVENANCE_PHRASE:?sync-comparator requires PROVENANCE_PHRASE before sourcing}"
: "${REMEDIATION:?sync-comparator requires REMEDIATION before sourcing}"
: "${DIFF_SUMMARY_LINES:?sync-comparator requires DIFF_SUMMARY_LINES before sourcing}"

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
