#!/usr/bin/env python3
"""Smoke-harness library: scenario parsing, the scenario registry, and the
mechanical grader for the manager routing smoke set.

The harness is the ORCH-4-6 entry-criterion instrument (consolidation-5
Criterion 1): no removal evaluation starts before it exists and is green.
Two consumers share this single parser so the shape contract cannot drift
between the hermetic validate mode and the live runner:

  run-smoke.sh --validate   shape checks + grader self-test, no model calls
  run-smoke.sh [--scenario] live fixture-bounded dispatches, graded here

Scenario file grammar (no YAML dependency):

  id: S1                  header lines until the prompt marker; `id`,
  title: ...              `ro-key`, `flash`, and `timeout` are required;
  ro-key: RO-170          `fixture:` may repeat (files copied into the
  flash: FL-01            live run's scratch working directory)
  timeout: 900
  fixture: s1-thing.md
  --- prompt ---
  ...multi-line dispatch the manager receives verbatim...
  --- rubric ---
  require: LITERAL                reply must contain LITERAL (case-insensitive)
  forbid: LITERAL                 reply must not contain LITERAL
  require-if: A=>B                reply containing A must also contain B
  require-any: A|B|C              reply must contain at least one of A|B|C
  tool-require: AGENT             transcript must dispatch subagent AGENT
  tool-forbid: AGENT              transcript must not dispatch subagent AGENT
  tool-max: AGENT N               transcript dispatches AGENT at most N times
  tool-min: AGENT N               transcript dispatches AGENT at least N times
  reply-max-lines: N              final reply at most N non-empty lines

Grading is literal and case-insensitive throughout: the rubric grades the
routing DECISION the reply states, never clause quoting, so a pass says the
behavior survived and a fail says it did not.
"""

import json
import re
import sys

REGISTRY = {
    # id -> (matrix row key, flash-era candidate key): the initial
    # scenario registry per the locked contract section 4 plus the
    # per-touched-row scenarios this subset added (S8 second memo,
    # S9 dispatch discipline, S10 git integration plan); names are the
    # pins (DC-3), file positions are never load-bearing. A "-" flash
    # key marks a row with no flash-era candidate.
    "S1": ("RO-170", "FL-01"),
    "S2": ("RO-170", "FL-01"),
    "S3": ("RO-170", "FL-01"),
    "S4": ("RO-171", "FL-02"),
    "S5": ("RO-173", "FL-04"),
    "S6": ("RO-168", "FL-06"),
    "S7": ("RO-267", "FL-05"),
    "S8": ("RO-172", "FL-03"),
    "S9": ("RO-115", "FL-07"),
    "S10": ("RO-063", "-"),
}

# The seven-class routing pin (08-consolidation-6 section 5, the corpus's
# class names verbatim; load-bearing names, not the L-range). The S6
# scenario must carry every name across its prompt and fixtures.
SEVEN_CLASS_NAMES = [
    "initial nontrivial request triage, scope interpretation, and decomposition strategy",
    "evaluation of significant plans and architecture choices",
    "risky tradeoffs, competing approaches, and reviewer design challenges",
    "reconciliation of inconsistent worker, verifier, reviewer, or Git evidence",
    "recovery strategy after meaningful failures or blocked work",
    "integration-readiness decisions on ambiguous evidence",
    "substantive final synthesis and recommendations",
]

PROMPT_MARKER = "--- prompt ---"
RUBRIC_MARKER = "--- rubric ---"
HEADER_KEYS = ("id", "title", "ro-key", "flash", "timeout", "fixture")

RUBRIC_KINDS = ("require", "forbid", "require-if", "require-any",
                "tool-require", "tool-forbid", "tool-max", "tool-min",
                "reply-max-lines")

# Dispatch counting is per subagent toolCall event, so a parallel or chain
# dispatch naming an agent twice in one call counts once per named slot;
# the prior-memo bar's mechanical leg needs total call events, not slots,
# and the transcript records one toolCall per dispatch act either way.

# The live run injects the manager body under test as pi's appended system
# prompt, which lands in the transcript's system message "addendum"
# section. The instrument check bounds its size instead of matching body
# prose, so the check survives corpus rewraps (the manager body is tens of
# KB; a missing injection leaves the pi default addendum far below this).
MIN_INJECTED_ADDENDUM_CHARS = 15000


class ScenarioError(Exception):
    pass


def parse_scenario(path):
    """Parse one scenario file into a dict; raise ScenarioError on any
    grammar violation so a malformed instrument fails loudly."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        raise ScenarioError(f"{path}: unreadable: {exc}") from exc
    scenario = {"path": path, "fixtures": [], "rubric": []}
    section = "header"
    header_done = False
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if section == "header":
            if line == PROMPT_MARKER:
                section = "prompt"
                header_done = True
                continue
            if not line or line.startswith("#"):
                continue
            key, sep, value = line.partition(":")
            key = key.strip()
            if not sep or key not in HEADER_KEYS:
                raise ScenarioError(
                    f"{path}:{lineno}: header line not `key: value` "
                    f"with key in {HEADER_KEYS}: {raw!r}")
            value = value.strip()
            if key == "fixture":
                if not value:
                    raise ScenarioError(f"{path}:{lineno}: empty fixture name")
                scenario["fixtures"].append(value)
            else:
                scenario[key] = value
        elif section == "prompt":
            if line == RUBRIC_MARKER:
                section = "rubric"
                continue
            scenario["prompt"] = scenario.get("prompt", "") + raw + "\n"
        elif section == "rubric":
            if not line or line.startswith("#"):
                continue
            scenario["rubric"].append((lineno, line))
    if not header_done:
        raise ScenarioError(f"{path}: missing {PROMPT_MARKER} marker")
    if section != "rubric":
        raise ScenarioError(f"{path}: missing {RUBRIC_MARKER} marker")
    for key in ("id", "title", "ro-key", "flash", "timeout"):
        if not scenario.get(key):
            raise ScenarioError(f"{path}: missing required header field `{key}`")
    if scenario["id"] not in REGISTRY:
        raise ScenarioError(
            f"{path}: id {scenario['id']} not in the registry {sorted(REGISTRY)}")
    expected_ro, expected_flash = REGISTRY[scenario["id"]]
    if scenario["ro-key"] != expected_ro or scenario["flash"] != expected_flash:
        raise ScenarioError(
            f"{path}: registry mismatch for {scenario['id']}: expected "
            f"{expected_ro}/{expected_flash}, got {scenario['ro-key']}/{scenario['flash']}")
    if not scenario.get("timeout", "").isdigit() or int(scenario["timeout"]) <= 0:
        raise ScenarioError(f"{path}: timeout must be a positive integer")
    if not scenario.get("prompt", "").strip():
        raise ScenarioError(f"{path}: empty prompt")
    if len(scenario["rubric"]) < 2:
        raise ScenarioError(f"{path}: rubric needs at least two checks")
    for lineno, line in scenario["rubric"]:
        check_rubric_line(path, lineno, line)
    return scenario


def check_rubric_line(path, lineno, line):
    """Validate one rubric line's grammar; raise ScenarioError on garbage."""
    kind, sep, rest = line.partition(":")
    kind = kind.strip()
    rest = rest.strip()
    if not sep or kind not in RUBRIC_KINDS or not rest:
        raise ScenarioError(
            f"{path}:{lineno}: rubric line must be one of {RUBRIC_KINDS} "
            f"with a non-empty value: {line!r}")
    if kind == "require-if":
        trigger, sep2, needed = rest.partition("=>")
        if not sep2 or not trigger.strip() or not needed.strip():
            raise ScenarioError(
                f"{path}:{lineno}: require-if needs `TRIGGER=>NEEDED`: {line!r}")
    if kind == "require-any" and "|" not in rest:
        raise ScenarioError(
            f"{path}:{lineno}: require-any needs |-separated options: {line!r}")
    if kind == "reply-max-lines" and not rest.isdigit():
        raise ScenarioError(
            f"{path}:{lineno}: reply-max-lines needs an integer: {line!r}")
    if kind == "tool-max":
        parts = rest.split()
        if (len(parts) != 2 or not parts[1].isdigit()
                or int(parts[1]) < 1):
            raise ScenarioError(
                f"{path}:{lineno}: tool-max needs `AGENT N` with N >= 1: {line!r}")
    if kind == "tool-min":
        parts = rest.split()
        if len(parts) != 2 or not parts[1].isdigit():
            raise ScenarioError(
                f"{path}:{lineno}: tool-min needs `AGENT N` with N >= 0: {line!r}")


def contains_fold(haystack, needle):
    """Case-insensitive literal containment; whitespace-run tolerant so a
    rubric literal spanning a wrapped reply line still matches."""
    pattern = r"\s+".join(re.escape(tok) for tok in needle.split())
    return re.search(pattern, haystack, re.IGNORECASE) is not None


def extract_transcript(transcript_path):
    """Pull (addendum_chars, final_reply_text, dispatched_agents,
    per_agent_call_counts, errors) out of a pi --mode json transcript."""
    addendum_chars = 0
    reply = ""
    agents = set()
    agent_calls = {}
    errors = []
    saw_session = False
    try:
        with open(transcript_path, encoding="utf-8", errors="replace") as fh:
            lines = fh.readlines()
    except OSError as exc:
        return 0, "", set(), [f"transcript unreadable: {exc}"]
    for lineno, line in enumerate(lines, 1):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            errors.append(f"{transcript_path}:{lineno}: non-JSON line")
            continue
        etype = event.get("type")
        if etype == "session":
            saw_session = True
        elif etype == "message_start":
            message = event.get("message", {})
            if message.get("role") == "system":
                addendum = message.get("sections", {}).get("addendum", "")
                addendum_chars = max(addendum_chars, len(addendum))
        elif etype == "message_end":
            message = event.get("message", {})
            if message.get("role") != "assistant":
                continue
            blocks = message.get("content", [])
            texts = [block.get("text", "") for block in blocks
                     if block.get("type") == "text"]
            if texts:
                reply = "\n".join(texts)
            for block in blocks:
                if block.get("type") != "toolCall":
                    continue
                if block.get("name") != "subagent":
                    continue
                args = block.get("arguments") or block.get("args") or {}
                named = []
                if args.get("agent"):
                    named.append(str(args["agent"]))
                for task in args.get("tasks") or []:
                    if isinstance(task, dict) and task.get("agent"):
                        named.append(str(task["agent"]))
                for step in args.get("chain") or []:
                    if isinstance(step, dict) and step.get("agent"):
                        named.append(str(step["agent"]))
                for agent_name in named:
                    agents.add(agent_name)
                    agent_calls[agent_name] = agent_calls.get(agent_name, 0) + 1
    if not saw_session:
        errors.append("transcript has no session event (dispatch did not start)")
    return addendum_chars, reply, agents, agent_calls, errors


def grade_scenario(scenario, transcript_path):
    """Grade one live transcript against the scenario rubric; returns
    (verdict, checks) where checks is a list of (label, ok, detail)."""
    addendum_chars, reply, agents, agent_calls, errors = extract_transcript(transcript_path)
    checks = []
    checks.append(("instrument: session started", not errors, "; ".join(errors)))
    checks.append((
        "instrument: manager body injected into the system addendum",
        addendum_chars >= MIN_INJECTED_ADDENDUM_CHARS,
        f"addendum {addendum_chars} chars (minimum {MIN_INJECTED_ADDENDUM_CHARS})"))
    checks.append(("instrument: non-empty final reply", bool(reply.strip()),
                   f"{len(reply.strip())} chars"))
    for lineno, line in scenario["rubric"]:
        kind, _, rest = line.partition(":")
        kind = kind.strip()
        rest = rest.strip()
        label = f"rubric L{lineno}: {line}"
        if kind == "require":
            ok = contains_fold(reply, rest)
            detail = "present" if ok else "absent from the reply"
        elif kind == "forbid":
            ok = not contains_fold(reply, rest)
            detail = "absent" if ok else "unexpectedly present in the reply"
        elif kind == "require-if":
            trigger, needed = rest.split("=>", 1)
            trigger, needed = trigger.strip(), needed.strip()
            if contains_fold(reply, trigger):
                ok = contains_fold(reply, needed)
                detail = (f"trigger present, needed literal "
                          f"{'present' if ok else 'MISSING'}")
            else:
                ok = True
                detail = "trigger absent, check vacuous"
        elif kind == "require-any":
            options = [opt.strip() for opt in rest.split("|")]
            hits = [opt for opt in options if contains_fold(reply, opt)]
            ok = bool(hits)
            detail = f"matched {hits}" if hits else "no option matched"
        elif kind == "tool-require":
            ok = rest in agents
            detail = (f"dispatched agents: {sorted(agents) or 'none'}")
        elif kind == "tool-forbid":
            ok = rest not in agents
            detail = (f"dispatched agents: {sorted(agents) or 'none'}")
        elif kind == "tool-max":
            agent_name, cap = rest.split()
            calls = agent_calls.get(agent_name, 0)
            ok = calls <= int(cap)
            detail = f"{agent_name} dispatched {calls} time(s), cap {cap}"
        elif kind == "tool-min":
            agent_name, floor = rest.split()
            calls = agent_calls.get(agent_name, 0)
            ok = calls >= int(floor)
            detail = f"{agent_name} dispatched {calls} time(s), floor {floor}"
        elif kind == "reply-max-lines":
            nonempty = len([l for l in reply.splitlines() if l.strip()])
            ok = nonempty <= int(rest)
            detail = f"{nonempty} non-empty reply lines (max {rest})"
        else:  # parse_scenario already rejected anything else
            ok = False
            detail = "unreachable"
        checks.append((label, ok, detail))
    verdict = "PASS" if all(ok for _, ok, _ in checks) else "FAIL"
    return verdict, checks


def run_selftest():
    """Exercise the parser and grader over synthetic inputs; prints
    `SELFTEST ok|FAIL <label>` lines consumed by run-smoke.sh --validate."""
    results = []

    def record(label, ok):
        results.append((label, bool(ok)))

    base = (
        "id: S1\ntitle: t\nro-key: RO-170\nflash: FL-01\ntimeout: 600\n"
        "--- prompt ---\nDo the thing.\n--- rubric ---\n"
        "require: ROUTE advisor\nforbid: ADVANCE: yes\n"
        "require-if: ITEM 1=>retry\nrequire-any: lane-a|lane-b\n"
        "tool-require: advisor\ntool-forbid: scout\ntool-max: advisor 1\n"
            "reply-max-lines: 12\n")

    # Parser: happy path.
    import tempfile
    import os
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "s1.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(base)
        try:
            scenario = parse_scenario(path)
            record("parse: valid scenario parses", scenario["id"] == "S1"
                   and len(scenario["rubric"]) == 8
                   and scenario["prompt"].strip() == "Do the thing.")
        except ScenarioError as exc:
            record(f"parse: valid scenario parses ({exc})", False)

        # Parser: registry mismatch fails.
        bad = base.replace("flash: FL-01", "flash: FL-99")
        path_bad = os.path.join(tmp, "bad.md")
        with open(path_bad, "w", encoding="utf-8") as fh:
            fh.write(bad)
        try:
            parse_scenario(path_bad)
            record("parse: registry mismatch rejected", False)
        except ScenarioError:
            record("parse: registry mismatch rejected", True)

        # Parser: garbage rubric line fails.
        ugly = base.replace("forbid: ADVANCE: yes",
                            "sometimes: ADVANCE: yes")
        path_ugly = os.path.join(tmp, "ugly.md")
        with open(path_ugly, "w", encoding="utf-8") as fh:
            fh.write(ugly)
        try:
            parse_scenario(path_ugly)
            record("parse: unknown rubric kind rejected", False)
        except ScenarioError:
            record("parse: unknown rubric kind rejected", True)

        fixture_dir = os.path.join(tmp, "fixtures")
        os.makedirs(fixture_dir, exist_ok=True)
        with open(os.path.join(fixture_dir, "f.txt"), "w") as fh:
            fh.write("x")

        # Grader: synthetic passing transcript.
        sysmsg = {"type": "message_start",
                  "message": {"role": "system",
                              "sections": {"addendum": "x" * 20000}}}
        assistant = {"type": "message_end", "message": {"role": "assistant",
                     "content": [
                         {"type": "toolCall", "name": "subagent",
                          "arguments": {"agent": "advisor", "task": "t"}},
                         {"type": "text",
                          "text": "ITEM 1: retry once\nROUTE advisor\n"
                                  "lane-a\nADVANCE: no"}]}}
        session = {"type": "session", "id": "t"}
        good = os.path.join(tmp, "good.jsonl")
        with open(good, "w", encoding="utf-8") as fh:
            for event in (session, sysmsg, assistant):
                fh.write(json.dumps(event) + "\n")
        verdict, checks = grade_scenario(scenario, good)
        record("grade: passing transcript passes",
               verdict == "PASS" and all(ok for _, ok, _ in checks))

        # Grader: a second dispatch to the capped agent trips tool-max.
        assistant_twice = {"type": "message_end", "message": {"role": "assistant",
                           "content": [
                               {"type": "toolCall", "name": "subagent",
                                "arguments": {"agent": "advisor", "task": "t"}},
                               {"type": "toolCall", "name": "subagent",
                                "arguments": {"agent": "advisor", "task": "t2"}},
                               {"type": "text",
                                "text": "ITEM 1: retry once\nROUTE advisor\n"
                                        "lane-a\nADVANCE: no"}]}}
        twice = os.path.join(tmp, "twice.jsonl")
        with open(twice, "w", encoding="utf-8") as fh:
            for event in (session, sysmsg, assistant_twice):
                fh.write(json.dumps(event) + "\n")
        verdict, checks = grade_scenario(scenario, twice)
        record("grade: tool-max cap trip caught",
               any("tool-max:" in label and not ok for label, ok, _ in checks))

        # Grader: each violation class trips exactly its check. The reply
        # carries none of the require/require-any options, breaks the
        # require-if implication, dispatches the forbidden agent, and
        # exceeds the line cap.
        bad_lines = ["ITEM 1: advance", "ADVANCE: yes"] \
            + [f"filler line {n}" for n in range(1, 15)]
        assistant_bad = {"type": "message_end", "message": {"role": "assistant",
                         "content": [
                             {"type": "toolCall", "name": "subagent",
                              "arguments": {"agent": "scout", "task": "t"}},
                             {"type": "text", "text": "\n".join(bad_lines)}]}}
        badout = os.path.join(tmp, "bad.jsonl")
        with open(badout, "w", encoding="utf-8") as fh:
            for event in (session, sysmsg, assistant_bad):
                fh.write(json.dumps(event) + "\n")
        verdict, checks = grade_scenario(scenario, badout)
        failed = [label for label, ok, _ in checks if not ok]
        record("grade: violating transcript fails", verdict == "FAIL")
        record("grade: require violation caught",
               any("require: ROUTE advisor" in label for label in failed))
        record("grade: forbid violation caught",
               any("forbid:" in label for label in failed))
        record("grade: require-if violation caught",
               any("require-if:" in label for label in failed))
        record("grade: require-any violation caught",
               any("require-any:" in label for label in failed))
        record("grade: tool-require violation caught",
               any("tool-require:" in label for label in failed))
        record("grade: tool-forbid violation caught",
               any("tool-forbid:" in label for label in failed))
        record("grade: reply-max-lines violation caught",
               any("reply-max-lines:" in label for label in failed))

        # Grader: missing injection and empty transcript are instrument errors.
        thin = {"type": "message_start",
                "message": {"role": "system", "sections": {"addendum": "tiny"}}}
        noinj = os.path.join(tmp, "noinj.jsonl")
        with open(noinj, "w", encoding="utf-8") as fh:
            for event in (session, thin, assistant):
                fh.write(json.dumps(event) + "\n")
        verdict, checks = grade_scenario(scenario, noinj)
        record("grade: missing body injection trips the instrument check",
               verdict == "FAIL"
               and any("instrument" in label for label, ok, _ in checks if not ok))

        # Case-insensitivity and wrap tolerance of the literal matcher.
        record("match: case-insensitive",
               contains_fold("Route ADVISOR now", "route advisor"))
        record("match: wrapped-line literal",
               contains_fold("route to the\nadvisor channel", "the advisor"))

    for label, ok in results:
        print(f"SELFTEST {'ok' if ok else 'FAIL'} {label}")
    return 0 if all(ok for _, ok in results) else 1


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(run_selftest())
    usage = "usage: smoke_lib.py --selftest"
    print(usage, file=sys.stderr)
    sys.exit(2)
