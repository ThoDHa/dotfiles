#!/usr/bin/env python3
"""Executable validator for the versioned metrics ledger contract.

Validates one JSONL ledger (file path argument, or "-" for stdin)
against tests/task-metrics/ledger-schema.md. Every record must carry a
known schema_version and a known record_type; every known field is
checked for type, domain, and range, and the cross-field invariants the
schema document pins (cost source marking, retry evidence, attribution
consistency, child counts, over-budget flag consistency, duplicate
invocations) are enforced here. Unknown extra fields are allowed at
every level: the schema evolves additively only.

Exit ladder: 0 the ledger is valid, 1 validation failure (each failure
printed to stderr as "FAIL: line N: <path>: <message>"), 2 usage or IO
error. On success a one-line summary naming per-type record counts is
printed to stdout.

Standard library only. python3 rather than jq because the bootstrap
container installs python3 but not jq, and the type/domain/invariant
checks need a real expression language; see ledger-schema.md for the
schema this program pins.
"""

import json
import re
import sys
from datetime import datetime

CURRENT_SCHEMA_VERSION = "1.0"
KNOWN_VERSIONS = ("1.0",)

HARNESSES = ("pi", "opencode")
COST_SOURCES = ("reported", "none")
ATTRIBUTION_METHODS = ("cwd-match", "task-file-reference", "dispatch-window", "none")
ATTRIBUTION_CONFIDENCES = ("exact", "window", "unattributed")
RETRY_EVIDENCES = ("stop-reason", "invocation-repeat", "engine-log")
CHILD_SOURCES = ("pi-subagent-details", "oc-parent-id")
SNAPSHOT_PHASES = ("before", "after")
BUDGET_DIMENSIONS = ("tokens", "cost", "wall_clock", "requests")
RECORD_TYPES = ("invocation", "unit_rollup", "batch_rollup", "ac12_snapshot")

TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")
VERSION_RE = re.compile(r"^\d+\.\d+$")


class Str:
	"""Any JSON string."""

	def check(self, value, path, errors):
		if not isinstance(value, str):
			errors.append((path, f"expected a string, got {describe(value)}"))


class NonEmptyStr(Str):
	"""A string with at least one character."""

	def check(self, value, path, errors):
		super().check(value, path, errors)
		if isinstance(value, str) and not value:
			errors.append((path, "must be non-empty"))


class Int:
	"""A JSON integer (booleans excluded)."""

	allow_negative = False
	nullable = False

	def check(self, value, path, errors):
		if value is None and self.nullable:
			return
		if isinstance(value, bool) or not isinstance(value, int):
			errors.append((path, f"expected an integer, got {describe(value)}"))
			return
		if not self.allow_negative and value < 0:
			errors.append((path, f"expected >= 0, got {value}"))


class IntNonNeg(Int):
	allow_negative = False


class IntAny(Int):
	allow_negative = True


class Num:
	"""A JSON number (int or float, booleans excluded)."""

	def __init__(self, nullable=False, nonneg=True):
		self.nullable = nullable
		self.nonneg = nonneg

	def check(self, value, path, errors):
		if value is None and self.nullable:
			return
		if isinstance(value, bool) or not isinstance(value, (int, float)):
			errors.append((path, f"expected a number, got {describe(value)}"))
			return
		if self.nonneg and value < 0:
			errors.append((path, f"expected >= 0, got {value}"))


class Timestamp(NonEmptyStr):
	"""An RFC3339 UTC timestamp (YYYY-MM-DDTHH:MM:SS[.fff]Z) that names a real calendar moment."""

	def check(self, value, path, errors):
		super().check(value, path, errors)
		if not isinstance(value, str):
			return
		if not TIMESTAMP_RE.match(value):
			errors.append((path, f"expected RFC3339 UTC (YYYY-MM-DDTHH:MM:SSZ), got {value!r}"))
			return
		pre = value[:-1].split(".")[0]
		try:
			datetime.strptime(pre, "%Y-%m-%dT%H:%M:%S")
		except ValueError:
			errors.append((path, f"not a valid calendar timestamp: {value!r}"))


class Enum(NonEmptyStr):
	"""A string restricted to a fixed member set."""

	def __init__(self, members):
		self.members = members

	def check(self, value, path, errors):
		if isinstance(value, str) and value not in self.members:
			errors.append((path, f"unknown member {value!r} (known: {', '.join(self.members)})"))
			return
		super().check(value, path, errors)


class Nullable:
	"""Wraps a spec to also accept null."""

	def __init__(self, inner):
		self.inner = inner

	def check(self, value, path, errors):
		if value is None:
			return
		self.inner.check(value, path, errors)


class Obj:
	"""A JSON object with named fields; unknown fields pass (additive-only)."""

	def __init__(self, fields):
		self.fields = fields

	def check(self, value, path, errors):
		if not isinstance(value, dict):
			errors.append((path, f"expected an object, got {describe(value)}"))
			return
		for name, (spec, required) in self.fields.items():
			if name not in value:
				if required:
					errors.append((f"{path}.{name}", "missing required field"))
				continue
			spec.check(value[name], f"{path}.{name}", errors)


class Arr:
	"""A JSON array whose elements all match one spec."""

	def __init__(self, inner, min_length=0):
		self.inner = inner
		self.min_length = min_length

	def check(self, value, path, errors):
		if not isinstance(value, list):
			errors.append((path, f"expected an array, got {describe(value)}"))
			return
		if len(value) < self.min_length:
			errors.append((path, f"expected at least {self.min_length} entries, got {len(value)}"))
		for i, item in enumerate(value):
			self.inner.check(item, f"{path}[{i}]", errors)


class Map:
	"""A JSON object whose keys are free strings and values match one spec."""

	def __init__(self, inner):
		self.inner = inner

	def check(self, value, path, errors):
		if not isinstance(value, dict):
			errors.append((path, f"expected an object, got {describe(value)}"))
			return
		for key, item in value.items():
			self.inner.check(item, f"{path}.{key}", errors)


def req(spec):
	return (spec, True)


def opt(spec):
	return (spec, False)


def describe(value):
	if isinstance(value, str):
		return f"string ({value!r})"
	if isinstance(value, bool):
		return "boolean"
	if isinstance(value, (int, float)):
		return f"number ({value})"
	if value is None:
		return "null"
	if isinstance(value, list):
		return "array"
	if isinstance(value, dict):
		return "object"
	return type(value).__name__


TOKEN_CHILD_FIELDS = Obj({
	"input": req(IntNonNeg()),
	"output": req(IntNonNeg()),
	"cache_read": req(IntNonNeg()),
	"cache_write": req(IntNonNeg()),
})

FAMILY_SPEC = Obj({
	"method": req(NonEmptyStr()),
	"source": req(NonEmptyStr()),
	"values": req(Map(Nullable(Num()))),
	"notes": req(Nullable(Str())),
})

COST = Obj({
	"amount": req(Num(nullable=True)),
	"source": req(Enum(COST_SOURCES)),
})

CHILD = Obj({
	"agent": req(NonEmptyStr()),
	"agent_role": req(Nullable(NonEmptyStr())),
	"model": req(Nullable(NonEmptyStr())),
	"exit_code": req(Nullable(IntAny())),
	"stop_reason": req(Nullable(NonEmptyStr())),
	"tokens": req(TOKEN_CHILD_FIELDS),
	"cost": req(COST),
	"turns": req(Nullable(IntNonNeg())),
	"source": req(Enum(CHILD_SOURCES)),
})

RECORD_SPECS = {
	"invocation": Obj({
		"timestamp": req(Timestamp()),
		"harness": req(Enum(HARNESSES)),
		"session_id": req(NonEmptyStr()),
		"message_id": req(NonEmptyStr()),
		"agent_role": req(Nullable(NonEmptyStr())),
		"model": req(NonEmptyStr()),
		"provider": req(NonEmptyStr()),
		"tokens": req(Obj({
			"input": req(IntNonNeg()),
			"output": req(IntNonNeg()),
			"cache_read": req(IntNonNeg()),
			"cache_write": req(IntNonNeg()),
			"reasoning": req(Nullable(IntNonNeg())),
		})),
		"cost": req(COST),
		"duration_ms": req(Nullable(IntNonNeg())),
		"stop_reason": req(NonEmptyStr()),
		"retry": req(Obj({
			"count": req(IntNonNeg()),
			"evidence": req(Nullable(Enum(RETRY_EVIDENCES))),
		})),
		"restart": req(Obj({
			"of_session_id": req(Nullable(NonEmptyStr())),
			"engine_log": req(Nullable(NonEmptyStr())),
		})),
		"nested": req(Obj({
			"child_count": req(IntNonNeg()),
			"children": req(Arr(CHILD)),
		})),
		"attribution": req(Obj({
			"method": req(Enum(ATTRIBUTION_METHODS)),
			"confidence": req(Enum(ATTRIBUTION_CONFIDENCES)),
			"unit_id": req(Nullable(NonEmptyStr())),
			"batch_id": req(Nullable(NonEmptyStr())),
		})),
	}),
	"unit_rollup": Obj({
		"unit_id": req(NonEmptyStr()),
		"batch_id": req(Nullable(NonEmptyStr())),
		"generated_at": req(Timestamp()),
		"invocation_count": req(IntNonNeg()),
		"retry_count": req(IntNonNeg()),
		"restart_count": req(IntNonNeg()),
		"stop_reason_histogram": req(Map(IntNonNeg())),
		"tokens": req(Obj({
			"input": req(IntNonNeg()),
			"output": req(IntNonNeg()),
			"cache_read": req(IntNonNeg()),
			"cache_write": req(IntNonNeg()),
			"reasoning": req(IntNonNeg()),
		})),
		"nested_tokens": req(TOKEN_CHILD_FIELDS),
		"cost": req(Obj({
			"amount_sum": req(Nullable(Num())),
			"reported_count": req(IntNonNeg()),
			"unreported_count": req(IntNonNeg()),
		})),
		"duration_ms_total": req(IntNonNeg()),
		"attribution_confidence_histogram": req(Obj({
			"exact": req(IntNonNeg()),
			"window": req(IntNonNeg()),
			"unattributed": req(IntNonNeg()),
		})),
	}),
	"batch_rollup": Obj({
		"batch_id": req(NonEmptyStr()),
		"generated_at": req(Timestamp()),
		"unit_count": req(IntNonNeg()),
		"invocation_count": req(IntNonNeg()),
		"stop_reason_histogram": req(Map(IntNonNeg())),
		"tokens": req(Obj({
			"input": req(IntNonNeg()),
			"output": req(IntNonNeg()),
			"cache_read": req(IntNonNeg()),
			"cache_write": req(IntNonNeg()),
			"reasoning": req(IntNonNeg()),
		})),
		"nested_tokens": req(TOKEN_CHILD_FIELDS),
		"cost": req(Obj({
			"amount_sum": req(Nullable(Num())),
			"reported_count": req(IntNonNeg()),
			"unreported_count": req(IntNonNeg()),
		})),
		"duration_ms_total": req(IntNonNeg()),
		"budget": req(Obj({
			"declared": req(Obj({
				"tokens": req(Nullable(Num())),
				"cost": req(Nullable(Num())),
				"wall_clock_ms": req(Nullable(IntNonNeg())),
				"requests": req(Nullable(IntNonNeg())),
			})),
			"over_budget": req(Arr(Enum(BUDGET_DIMENSIONS))),
		})),
		"yield_tally": opt(Obj({
			"verifier_findings_by_severity": req(Map(IntNonNeg())),
			"verifier_caught_defects": req(IntNonNeg()),
			"reviewer_blocker": req(IntNonNeg()),
			"reviewer_major": req(IntNonNeg()),
			"reviewer_minor": req(IntNonNeg()),
			"escaped_defects": req(IntNonNeg()),
			"false_positives": req(IntNonNeg()),
			"time_to_close_ms": req(Nullable(IntNonNeg())),
			"batch_cost_total": req(Nullable(Num())),
			"source_links": req(Arr(NonEmptyStr(), min_length=1)),
		})),
	}),
	"ac12_snapshot": Obj({
		"generated_at": req(Timestamp()),
		"phase": req(Enum(SNAPSHOT_PHASES)),
		"harness": req(Enum(HARNESSES)),
		"families": req(Obj({
			"read_latency": req(FAMILY_SPEC),
			"context_token_cost": req(FAMILY_SPEC),
			"command_failures": req(FAMILY_SPEC),
			"retrieval_completeness": req(FAMILY_SPEC),
			"permission_denials": req(FAMILY_SPEC),
		})),
	}),
}


def check_invariants(rec, errors):
	"""Cross-field invariants shared by all record types."""
	kind = rec["record_type"]
	if kind == "invocation":
		if rec["cost"]["source"] == "reported" and rec["cost"]["amount"] is None:
			errors.append(("cost.amount", "source reported requires a numeric amount"))
		if rec["cost"]["source"] == "none" and rec["cost"]["amount"] is not None \
				and rec["cost"]["amount"] != 0:
			errors.append(("cost.amount",
				"source none requires amount null or the harness's reported zero"))
		if rec["retry"]["count"] > 0 and rec["retry"]["evidence"] is None:
			errors.append(("retry.evidence", "count > 0 requires an evidence class"))
		if rec["retry"]["count"] == 0 and rec["retry"]["evidence"] is not None:
			errors.append(("retry.evidence", "count 0 must not carry evidence"))
		if rec["nested"]["child_count"] != len(rec["nested"]["children"]):
			errors.append(("nested.child_count",
				f"child_count {rec['nested']['child_count']} does not match "
				f"{len(rec['nested']['children'])} children"))
		confidence = rec["attribution"]["confidence"]
		method = rec["attribution"]["method"]
		if confidence == "unattributed" and method != "none":
			errors.append(("attribution.method",
				"confidence unattributed requires method none"))
		if confidence != "unattributed" and method == "none":
			errors.append(("attribution.method",
				"method none requires confidence unattributed"))
	if kind == "unit_rollup":
		reported = rec["cost"]["reported_count"]
		unreported = rec["cost"]["unreported_count"]
		if reported + unreported != rec["invocation_count"]:
			errors.append(("cost",
				f"reported ({reported}) + unreported ({unreported}) != invocation_count "
				f"({rec['invocation_count']})"))
	if kind == "batch_rollup":
		declared = rec["budget"]["declared"]
		declared_key = {"tokens": "tokens", "cost": "cost",
			"wall_clock": "wall_clock_ms", "requests": "requests"}
		flags = rec["budget"]["over_budget"]
		if len(flags) != len(set(flags)):
			errors.append(("budget.over_budget", "a flagged dimension appears more than once"))
		actuals = {
			"tokens": rec["tokens"]["input"] + rec["tokens"]["output"],
			"cost": rec["cost"]["amount_sum"],
			"wall_clock": rec["duration_ms_total"],
			"requests": rec["invocation_count"],
		}
		for flag in flags:
			if flag not in declared_key:
				continue
			if declared.get(declared_key[flag]) is None:
				errors.append(("budget.over_budget",
					f"dimension {flag} flagged over budget but its declared value is null"))
			elif actuals[flag] is not None and actuals[flag] <= declared[declared_key[flag]]:
				errors.append(("budget.over_budget",
					f"dimension {flag} flagged over budget but actual {actuals[flag]} "
					f"does not exceed declared {declared[declared_key[flag]]}"))


def validate_ledger(lines):
	"""Validate raw ledger lines; returns (errors, type_counts)."""
	errors = []
	type_counts = {}
	seen_invocations = {}
	if not any(line.strip() for line in lines):
		errors.append((0, "", "no records in ledger"))
		return errors, type_counts
	for number, raw in enumerate(lines, start=1):
		if not raw.strip():
			errors.append((number, "", "blank line in ledger (one JSON object per line)"))
			continue
		try:
			rec = json.loads(raw)
		except json.JSONDecodeError as exc:
			errors.append((number, "", f"invalid JSON: {exc.msg}"))
			continue
		if not isinstance(rec, dict):
			errors.append((number, "", f"record is not a JSON object (got {describe(rec)})"))
			continue
		rec_errors = []
		version = rec.get("schema_version")
		if version is None:
			rec_errors.append(("schema_version", "missing required field"))
		elif not isinstance(version, str) or not VERSION_RE.match(version):
			rec_errors.append(("schema_version", f"expected MAJOR.MINOR, got {version!r}"))
		elif version not in KNOWN_VERSIONS:
			known = ", ".join(KNOWN_VERSIONS)
			rec_errors.append(("schema_version", f"unknown version {version!r} "
				f"(validator knows: {known}); extend validate-ledger.py before writing it"))
		kind = rec.get("record_type")
		if kind not in RECORD_SPECS:
			rec_errors.append(("record_type", f"unknown record type {kind!r} "
				f"(known: {', '.join(RECORD_TYPES)})"))
		else:
			RECORD_SPECS[kind].check(rec, "record", rec_errors)
			if len(rec_errors) == 0:
				check_invariants(rec, rec_errors)
				type_counts[kind] = type_counts.get(kind, 0) + 1
				if kind == "invocation":
					key = (rec["harness"], rec["session_id"], rec["message_id"])
					if key in seen_invocations:
						first_line = seen_invocations[key]
						rec_errors.append(("", f"duplicate invocation: harness {key[0]} "
							f"session {key[1]} message {key[2]} already recorded at line {first_line}"))
					else:
						seen_invocations[key] = number
		for path, message in rec_errors:
			errors.append((number, path, message))
	return errors, type_counts


def main(argv):
	if len(argv) != 2:
		print("USAGE: validate-ledger.py LEDGER.jsonl|-", file=sys.stderr)
		return 2
	source_name = argv[1]
	try:
		if argv[1] == "-":
			lines = sys.stdin.read().splitlines()
			source_name = "<stdin>"
		else:
			with open(argv[1], encoding="utf-8") as ledger:
				lines = ledger.read().splitlines()
	except OSError as exc:
		print(f"ERROR: cannot read {argv[1]}: {exc}", file=sys.stderr)
		return 2

	errors, type_counts = validate_ledger(lines)
	if errors:
		for number, path, message in errors:
			loc = f"line {number}" if number else "ledger"
			if path:
				print(f"FAIL: {loc}: {path}: {message}", file=sys.stderr)
			else:
				print(f"FAIL: {loc}: {message}", file=sys.stderr)
		return 1

	total = sum(type_counts.values())
	counts = ", ".join(f"{kind}: {type_counts[kind]}"
		for kind in sorted(type_counts))
	print(f"OK ledger {source_name}: {total} records validated ({counts}) "
		f"against schema {CURRENT_SCHEMA_VERSION}")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))
