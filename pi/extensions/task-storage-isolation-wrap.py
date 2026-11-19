#!/usr/bin/env python3
"""Install the bwrap child-wrap into the vendored pi subagent extension.

The wrap is the ORCH-4-10-2 production form of the ORCH-4-10-1 walking
skeleton seam: getPiInvocation is renamed and a marker-delimited,
self-contained block is appended that prefixes the child invocation
with bubblewrap whenever PI_TASK_STORAGE_ISOLATION is exactly "1".
Without the flag the inserted code returns the invocation unchanged, so
rollback is flag removal. When the flag is set but the parent-side
extension wiring (mask paths, escape-channel socket, trust file) is
absent or incomplete, the wrap refuses the spawn instead of silently
producing an unmasked child.

This tool is the first-class activation mechanism, not a runtime patch:
activation happens once, against the live vendored file, and is
idempotent. Vendored-file drift is detected and refused:

- activate checks the vendored getPiInvocation seam shape before
  writing and refuses (exit 1, file untouched) when the shape no longer
  matches SEAM_ANCHOR/SEAM_CLOSER;
- an already-activated file re-verifies instead of double-inserting;
- deactivate removes the block and restores the original function name,
  leaving the file byte-identical to its pre-activation content;
- verify reports the installed state through its exit status and pins
  the installed block's content against the canonical block: an edit
  inside the block that keeps the markers fails verify (and activate),
  so a weakened wrap cannot pass as intact.

Usage:
    task-storage-isolation-wrap.py activate|deactivate|verify [agent-dir]

The agent dir defaults to PI_TASK_STORAGE_AGENT_DIR, then $HOME/.pi/agent.
"""

import os
import pathlib
import sys

SEAM_ANCHOR = "function getPiInvocation(args: string[]): { command: string; args: string[] } {"
SEAM_CLOSER = 'return { command: "pi", args };\n}'
RENAMED_ANCHOR = SEAM_ANCHOR.replace("getPiInvocation", "getPiInvocationUnwrapped")

WRAP_BEGIN = "// TASK-STORAGE-ISOLATION WRAP BEGIN"
WRAP_END = "// TASK-STORAGE-ISOLATION WRAP END"


def installed_block(text):
	"""The installed wrap block span, markers included."""
	begin = text.index(WRAP_BEGIN)
	end = text.index(WRAP_END) + len(WRAP_END)
	return text[begin:end]

WRAP_BLOCK = """// TASK-STORAGE-ISOLATION WRAP BEGIN
// Inserted by task-storage-isolation-wrap.py (ORCH-4-10-2). The block is
// self-contained on node builtins so the suite can extract and load it
// byte-exact for parity checks. The wrap is inert unless
// PI_TASK_STORAGE_ISOLATION is exactly "1"; rollback is flag removal.
import * as isoFs from "node:fs";

const ISO_FLAG = "PI_TASK_STORAGE_ISOLATION";
const ISO_MASK_PATHS = "PI_TASK_STORAGE_MASK_PATHS";
const ISO_SOCKET = "PI_TASK_STORAGE_SOCKET";
const ISO_TRUST_FILE = "PI_TASK_STORAGE_TRUST_FILE";
const ISO_AGENT_DIR = "PI_TASK_STORAGE_AGENT_DIR";
const ISO_UNMASKED = "PI_TASK_STORAGE_UNMASKED";

interface IsoInvocation {
	command: string;
	args: string[];
}

// Agent-dir entries that must never reach a masked child: the parent's
// session transcripts carry board content (the transcript-copy bypass
// lane from the ORCH-4-10 decision log), auth files carry credentials.
// The tmpfs over the agent dir hides everything not bound back in.
const ISO_AGENT_DIR_SKIP = new Set([
	"sessions",
	"auth.json",
	"mcp-auth.json",
]);

function isoRequireWiring(env: Record<string, string | undefined>, name: string): string {
	const value = env[name];
	if (!value) {
		throw new Error(
			`task-storage-isolation: ${ISO_FLAG} is set but ${name} is missing; ` +
				"refusing to spawn an unwrapped child (load the task-storage-isolation " +
				"extension, or unset PI_TASK_STORAGE_ISOLATION to deactivate)",
		);
	}
	return value;
}

function isoAgentDir(env: Record<string, string | undefined>): string {
	return env[ISO_AGENT_DIR] || `${env.HOME ?? ""}/.pi/agent`;
}

function isoBuildIsolationArgv(
	invocation: IsoInvocation,
	env: Record<string, string | undefined>,
): IsoInvocation {
	const maskPaths = isoRequireWiring(env, ISO_MASK_PATHS)
		.split("\\n")
		.filter((entry) => entry.length > 0);
	const socketPath = isoRequireWiring(env, ISO_SOCKET);
	const trustFile = isoRequireWiring(env, ISO_TRUST_FILE);
	if (maskPaths.length === 0) {
		throw new Error(
			"task-storage-isolation: mask path list is empty; refusing to spawn a child with nothing masked",
		);
	}
	const agentDir = isoAgentDir(env);
	const agentState: string[] = ["--tmpfs", agentDir];
	for (const entry of isoFs.readdirSync(agentDir).sort()) {
		if (entry === "trust.json" || entry === "trust.json.lock") continue;
		if (ISO_AGENT_DIR_SKIP.has(entry)) continue;
		agentState.push("--ro-bind", `${agentDir}/${entry}`, `${agentDir}/${entry}`);
	}
	agentState.push("--bind", trustFile, `${agentDir}/trust.json`);
	const argv: string[] = [
		"--unshare-user",
		"--unshare-ipc",
		"--unshare-pid",
		"--die-with-parent",
		"--ro-bind",
		"/",
		"/",
		"--dev",
		"/dev",
		"--proc",
		"/proc",
		"--tmpfs",
		"/tmp",
	];
	// Mounts stack in argument order: each root is ro-bound first so its
	// view shadows the /tmp tmpfs, then the tmpfs mask lands on its
	// .tasks. The socket FILE is ro-bound: unix-socket connect is gated
	// by file mode bits, not mount rw, so the child reaches the escape
	// channel while the read-only bind stops it from unlinking the
	// socket and killing the service loop.
	for (const maskPath of maskPaths) {
		argv.push("--ro-bind", maskPath, maskPath);
		argv.push("--tmpfs", maskPath);
	}
	// Transcript-copy stores (the DC2 lane): board content also lives in
	// the same-uid session store of the other harness, reachable under
	// the root read-only bind. A tmpfs over the store hides it entirely;
	// it is skipped when absent, so machines without the other harness
	// keep the exact same argv shape minus the dead entry.
	const transcriptStore = `${env.XDG_DATA_HOME || `${env.HOME ?? ""}/.local/share`}/opencode`;
	if (isoFs.existsSync(transcriptStore)) {
		argv.push("--tmpfs", transcriptStore);
	}
	argv.push("--ro-bind", socketPath, socketPath);
	argv.push(...agentState);
	argv.push(invocation.command, ...invocation.args);
	return { command: "bwrap", args: argv };
}

function isoWrapInvocation(
	invocation: IsoInvocation,
	env: Record<string, string | undefined>,
): IsoInvocation | null {
	if (env[ISO_FLAG] !== "1") return null;
	if (env[ISO_UNMASKED] === "1") {
		process.stderr.write(
			"task-storage-isolation: explicit unmasked dispatch active " +
				"(PI_TASK_STORAGE_UNMASKED=1); this child bypasses the storage boundary " +
				"and must be recorded in the task record\\n",
		);
		return null;
	}
	return isoBuildIsolationArgv(invocation, env);
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const invocation = getPiInvocationUnwrapped(args);
	const wrapped = isoWrapInvocation(invocation, process.env);
	if (!wrapped) return invocation;
	return wrapped;
}

export const __storageIsolationProbe = {
	wrapInvocation: isoWrapInvocation,
	buildIsolationArgv: isoBuildIsolationArgv,
	agentDir: isoAgentDir,
	agentDirSkip: ISO_AGENT_DIR_SKIP,
};
// TASK-STORAGE-ISOLATION WRAP END
"""


def agent_dir_override(argv: list[str]) -> str:
	if len(argv) > 3:
		print(__doc__)
		sys.exit(2)
	if len(argv) == 3:
		return argv[2]
	return os.environ.get("PI_TASK_STORAGE_AGENT_DIR") or os.path.join(
		os.environ.get("HOME", ""), ".pi/agent"
	)


def subagent_index(agent_dir: str) -> pathlib.Path:
	return pathlib.Path(agent_dir) / "extensions" / "subagent" / "index.ts"


def check_shape(text: str) -> list[str]:
	problems = []
	if text.count(WRAP_BEGIN) != 1 or text.count(WRAP_END) != 1:
		if text.count(WRAP_BEGIN) or text.count(WRAP_END):
			problems.append("wrap markers are unbalanced")
	if text.count(SEAM_ANCHOR) != 1 or text.count(SEAM_CLOSER) != 1:
		problems.append("vendored getPiInvocation seam shape changed; "
			"update SEAM_ANCHOR/SEAM_CLOSER to match the new upstream shape")
	return problems


def write_atomically(target: pathlib.Path, text: str) -> None:
	staged = target.with_suffix(".ts.isolation-staging")
	staged.write_text(text)
	staged.replace(target)


def cmd_activate(agent_dir: str) -> int:
	index = subagent_index(agent_dir)
	try:
		text = index.read_text()
	except OSError as error:
		print(f"ACTIVATE REFUSED: cannot read {index}: {error}")
		return 1
	if WRAP_BEGIN in text or WRAP_END in text:
		problems = check_shape(text)
		if WRAP_BEGIN in text and WRAP_END in text and not problems:
			if installed_block(text) == WRAP_BLOCK[:-1]:
				print(f"already activated: wrap block present in {index} (verified, no change)")
				return 0
			print("ACTIVATE REFUSED: wrap block content drifted from the canonical block "
				"(markers intact); deactivate and re-activate to reinstall it")
			return 1
		print("ACTIVATE REFUSED: " + "; ".join(problems or ["wrap markers are unbalanced"]))
		return 1
	if text.count(RENAMED_ANCHOR) != 0:
		print("ACTIVATE REFUSED: renamed seam anchor already present without wrap block; "
			"the vendored file is in an unknown half-patched state")
		return 1
	problems = check_shape(text)
	if problems:
		print("ACTIVATE REFUSED: " + "; ".join(problems))
		return 1
	patched = text.replace(SEAM_ANCHOR, RENAMED_ANCHOR) + "\n" + WRAP_BLOCK
	write_atomically(index, patched)
	print(f"activated: wrap block installed in {index}")
	return 0


def cmd_deactivate(agent_dir: str) -> int:
	index = subagent_index(agent_dir)
	try:
		text = index.read_text()
	except OSError as error:
		print(f"DEACTIVATE REFUSED: cannot read {index}: {error}")
		return 1
	if WRAP_BEGIN not in text:
		if text.count(RENAMED_ANCHOR) != 0:
			print("DEACTIVATE REFUSED: renamed seam anchor present without wrap block; "
				"restore the vendored file from its upstream source instead")
			return 1
		print(f"already inactive: no wrap block in {index} (no change)")
		return 0
	if WRAP_END not in text:
		print("DEACTIVATE REFUSED: wrap markers are unbalanced; restore the vendored file from its upstream source instead")
		return 1
	# Inverse of activate: the inserted fragment was "\n" + WRAP_BLOCK,
	# so its separator newline is dropped from both ends of the removed
	# span, leaving the pre-activation bytes exactly.
	begin = text.index(WRAP_BEGIN)
	end = text.index(WRAP_END) + len(WRAP_END)
	prefix = text[:begin]
	suffix = text[end:]
	if prefix.endswith("\n") and suffix.startswith("\n"):
		prefix = prefix[:-1]
		suffix = suffix[1:]
	restored = prefix + suffix
	restored = restored.replace(RENAMED_ANCHOR, SEAM_ANCHOR, 1)
	problems = check_shape(restored)
	if problems:
		print("DEACTIVATE REFUSED: restoring would leave " + "; ".join(problems))
		return 1
	write_atomically(index, restored)
	print(f"deactivated: wrap block removed from {index}")
	return 0


def cmd_verify(agent_dir: str) -> int:
	index = subagent_index(agent_dir)
	try:
		text = index.read_text()
	except OSError as error:
		print(f"VERIFY FAIL: cannot read {index}: {error}")
		return 1
	if WRAP_BEGIN not in text:
		problems = check_shape(text)
		if problems:
			print(f"VERIFY FAIL: not activated and " + "; ".join(problems))
			return 1
		print(f"not activated: {index} is pristine (seam shape intact)")
		return 0
	problems = check_shape(text)
	if problems:
		print("VERIFY FAIL: " + "; ".join(problems))
		return 1
	if installed_block(text) != WRAP_BLOCK[:-1]:
		print("VERIFY FAIL: wrap block content drifted from the canonical block "
			"(markers intact); deactivate and re-activate to reinstall it")
		return 1
	print(f"activated and intact: wrap block present in {index}")
	return 0


def main() -> int:
	if len(sys.argv) < 2 or sys.argv[1] not in {"activate", "deactivate", "verify"}:
		print(__doc__)
		return 2
	command = sys.argv[1]
	agent_dir = agent_dir_override(sys.argv)
	return {"activate": cmd_activate, "deactivate": cmd_deactivate, "verify": cmd_verify}[command](agent_dir)


if __name__ == "__main__":
	sys.exit(main())
