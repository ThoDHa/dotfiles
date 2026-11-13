# Batch task: five components

1. Extract the retry loop in notify.py into a shared helper at backoff.py and update both call sites in scheduler.py.
2. Add unit tests for the new backoff.py helper in a new test_backoff.py, covering the success path and the give-up path.
3. Migrate the three deployment settings in deploy-config.yaml to the key names documented in MIGRATION.md, removing the old keys.
4. Update the REQUIRED_KEYS validation in validate.py so it checks the migrated key names, then rerun the validation.
5. Regenerate integration.md from the current module docstrings and fix stale cross-references in runbook.md.

Constraints: components 3 and 4 both rewrite deploy-config.yaml, so they contend on the same file.
