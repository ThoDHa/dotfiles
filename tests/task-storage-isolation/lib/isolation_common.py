#!/usr/bin/env python3
"""Shared bwrap argv builder and fixture helpers for the isolation suite.

Python mirror of the TS wrap block that pi/extensions/
task-storage-isolation-wrap.py installs into the vendored subagent
extension. The suite's machine-side deny probes execute exactly the
argv this builder produces, and the parity test asserts the builder's
output matches the installed wrap's output for identical inputs, so
deny evidence can neither drift from nor be fabricated independently of
the production mechanism.

The builder's one non-production knob is include_agent_dir_sessions:
setting it reproduces the pre-fix trust provision (sessions/ bound back
into the child) so the transcript-leak probe can demonstrate the leak
the production shape closes. Production behavior is the default.

Usage (suite-internal):
    from isolation_common import build_isolation_argv, wrap_invocation, ...
"""

import json
import os
import socket
import subprocess
import sys
import time

ISO_FLAG = "PI_TASK_STORAGE_ISOLATION"
ISO_MASK_PATHS = "PI_TASK_STORAGE_MASK_PATHS"
ISO_SOCKET = "PI_TASK_STORAGE_SOCKET"
ISO_TRUST_FILE = "PI_TASK_STORAGE_TRUST_FILE"
ISO_AGENT_DIR = "PI_TASK_STORAGE_AGENT_DIR"
ISO_UNMASKED = "PI_TASK_STORAGE_UNMASKED"
ISO_TOKEN = "PI_TASK_STORAGE_TOKEN"

# Agent-dir entries hidden from masked children by the production wrap:
# parent session transcripts (board content), provider credentials.
# trust.json and trust.json.lock are skipped separately and the scratch
# trust file is bound from the parent-provided path.
AGENT_DIR_SKIP = ("sessions", "auth.json", "mcp-auth.json")

TRUST_FILES = ("trust.json", "trust.json.lock")


class IsoRefusal(RuntimeError):
	"""The wrap refuses to spawn: activation wiring missing or empty."""


def iso_require(env, name):
	value = env.get(name)
	if not value:
		raise IsoRefusal(
			f"{ISO_FLAG} is set but {name} is missing; refusing to spawn an unwrapped child"
		)
	return value


def agent_dir_from_env(env):
	return env.get(ISO_AGENT_DIR) or os.path.join(env.get("HOME", ""), ".pi/agent")


def build_isolation_argv(command, args, env, agent_dir=None,
                         include_agent_dir_sessions=False):
	"""Build the exact bwrap argv the production wrap spawns.

	Mirrors isoBuildIsolationArgv in the installed TS block entry for
	entry, including mount-stacking order. Raises IsoRefusal under the
	same conditions the wrap throws. include_agent_dir_sessions=True
	reproduces the pre-fix trust provision (leak-shape) for the
	transcript-leak probe; it is never used for deny evidence.
	"""
	mask_paths = [p for p in iso_require(env, ISO_MASK_PATHS).split("\n") if p]
	socket_path = iso_require(env, ISO_SOCKET)
	trust_file = iso_require(env, ISO_TRUST_FILE)
	if not mask_paths:
		raise IsoRefusal("mask path list is empty; refusing to spawn a child with nothing masked")
	if agent_dir is None:
		agent_dir = agent_dir_from_env(env)
	agent_state = ["--tmpfs", agent_dir]
	for entry in sorted(os.listdir(agent_dir)):
		if entry in TRUST_FILES:
			continue
		if not include_agent_dir_sessions and entry in AGENT_DIR_SKIP:
			continue
		agent_state += ["--ro-bind", f"{agent_dir}/{entry}", f"{agent_dir}/{entry}"]
	agent_state += ["--bind", trust_file, f"{agent_dir}/trust.json"]
	argv = [
		"--unshare-user", "--unshare-ipc", "--unshare-pid", "--die-with-parent",
		"--ro-bind", "/", "/",
		"--dev", "/dev",
		"--proc", "/proc",
		"--tmpfs", "/tmp",
	]
	for mask_path in mask_paths:
		argv += ["--ro-bind", mask_path, mask_path, "--tmpfs", mask_path]
	argv += ["--ro-bind", socket_path, socket_path]
	argv += agent_state
	return ["bwrap", *argv, command, *args]


def wrap_invocation(command, args, env, agent_dir=None):
	"""Mirror of isoWrapInvocation: None when inert, else the wrapped argv."""
	if env.get(ISO_FLAG) != "1":
		return None
	if env.get(ISO_UNMASKED) == "1":
		return None
	return build_isolation_argv(command, args, env, agent_dir)


def make_fixture_agent_dir(root):
	"""Create a minimal agent dir under <root>/agent with marked entries.

	Returns (agent_dir, markers) where markers maps each sensitive entry
	to the secret marker string planted inside it. The suite asserts the
	markers are invisible inside a production-shape namespace.
	"""
	agent_dir = os.path.join(root, "agent")
	os.makedirs(os.path.join(agent_dir, "extensions", "subagent"), exist_ok=True)
	os.makedirs(os.path.join(agent_dir, "prompts"), exist_ok=True)
	os.makedirs(os.path.join(agent_dir, "sessions", "--fixture-cwd--"), exist_ok=True)
	markers = {
		"auth.json": "AUTH-MARKER-4f21",
		"mcp-auth.json": "MCPAUTH-MARKER-9c07",
		"trust.json": "TRUST-MARKER-5e33",
		"transcript": "TRANSCRIPT-MARKER-8ab2",
	}
	with open(os.path.join(agent_dir, "auth.json"), "w") as handle:
		handle.write(json.dumps({"secret": markers["auth.json"]}))
	with open(os.path.join(agent_dir, "mcp-auth.json"), "w") as handle:
		handle.write(json.dumps({"secret": markers["mcp-auth.json"]}))
	with open(os.path.join(agent_dir, "trust.json"), "w") as handle:
		handle.write(json.dumps({"secret": markers["trust.json"]}))
	with open(
		os.path.join(agent_dir, "sessions", "--fixture-cwd--", "transcript.jsonl"), "w"
	) as handle:
		handle.write(json.dumps({"role": "assistant", "content": markers["transcript"]}) + "\n")
	for name in ("settings.json", "models-store.json", "mcp.json"):
		with open(os.path.join(agent_dir, name), "w") as handle:
			handle.write("{}\n")
	with open(os.path.join(agent_dir, "extensions", "subagent", "index.ts"), "w") as handle:
		handle.write("// fixture vendored extension\n")
	with open(os.path.join(agent_dir, "prompts", "default.md"), "w") as handle:
		handle.write("fixture prompt\n")
	return agent_dir, markers


def seed_transcript(agent_dir, slug, marker):
	"""Write a parent-session transcript carrying marker under sessions/."""
	session_dir = os.path.join(agent_dir, "sessions", slug)
	os.makedirs(session_dir, exist_ok=True)
	path = os.path.join(session_dir, "2026-11-17T00-00-00-seeded.jsonl")
	with open(path, "w") as handle:
		handle.write(json.dumps({"role": "assistant", "content": marker}) + "\n")
	return path


def make_fixture_repo(root):
	"""Create a git repo with a gitignored .tasks tree under <root>/repo.

	Returns (repo, secret_marker). The repo is a real git repo (init,
	commit) with .tasks/ gitignored, mirroring the live-board shape the
	mask targets.
	"""
	repo = os.path.join(root, "repo")
	os.makedirs(os.path.join(repo, ".tasks", "current"), exist_ok=True)
	subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
	subprocess.run(["git", "-C", repo, "config", "user.email", "suite@fixture"], check=True)
	subprocess.run(["git", "-C", repo, "config", "user.name", "suite"], check=True)
	with open(os.path.join(repo, ".gitignore"), "w") as handle:
		handle.write(".tasks/\n")
	with open(os.path.join(repo, "README.md"), "w") as handle:
		handle.write("fixture readme\n")
	secret_marker = "SUITE-SECRET-2d97-masked"
	with open(os.path.join(repo, ".tasks", "current", "secret.md"), "w") as handle:
		handle.write(f"secret: {secret_marker}\n")
	os.symlink(".tasks/current/secret.md", os.path.join(repo, "link-rel"))
	os.symlink(os.path.join(repo, ".tasks/current/secret.md"), os.path.join(repo, "link-abs"))
	os.makedirs(os.path.join(repo, "sub", "deeper"), exist_ok=True)
	os.symlink("../../.tasks/current/secret.md",
	           os.path.join(repo, "sub", "deeper", "link-updown"))
	# Points outside the board repo entirely: the service-side path-policy
	# pins use it to prove kernel-walk candidates are checked (a positional
	# through it escapes the sanctioned surface and must be refused).
	os.symlink("/etc", os.path.join(repo, "esc-etc"))
	subprocess.run(["git", "-C", repo, "add", ".gitignore", "README.md"], check=True)
	subprocess.run(["git", "-C", repo, "commit", "-qm", "fixture repo"], check=True)
	return repo, secret_marker


def add_fixture_worktree(repo, path):
	"""Add a git worktree at path and create its own gitignored .tasks tree.

	Returns (worktree_path, sibling_secret_marker). The sibling tree
	carries a distinct secret, proving the multi-root mask covers
	worktree copies, not just the session cwd's tree.
	"""
	subprocess.run(["git", "-C", repo, "worktree", "add", "-q", path], check=True)
	os.makedirs(os.path.join(path, ".tasks", "current"), exist_ok=True)
	sibling_marker = "SIBLING-SECRET-71ce-masked"
	with open(os.path.join(path, ".tasks", "current", "sibling.md"), "w") as handle:
		handle.write(f"secret: {sibling_marker}\n")
	return path, sibling_marker


def make_fixture_vendored_extension(path):
	"""Write a minimal vendored-extension source carrying the seam shape.

	Hermetic stand-in for ~/.pi/agent/extensions/subagent/index.ts: it
	carries exactly the getPiInvocation seam the wrap patcher anchors on,
	plus enough surrounding body that activate/deactivate/verify and the
	wrap-block extraction behave as they do against the real file. The
	suite never reads the live host extension.
	"""
	seam_anchor = 'function getPiInvocation(args: string[]): { command: string; args: string[] } {'
	seam_closer = 'return { command: "pi", args };\n}'
	body = (
		'import * as fs from "node:fs";\n'
		'import * as path from "node:path";\n'
		'\n'
		'function helper(args: string[]): string[] {\n'
		'\treturn ["--flag", ...args];\n'
		'}\n'
		'\n'
		f'{seam_anchor}\n'
		'\tconst argv = helper([]);\n'
		'\tif (argv.length === 0) {\n'
		'\t\treturn { command: "fallback", args: argv };\n'
		'\t}\n'
		f'\t{seam_closer}\n'
		'\n'
		'export default function register() {}\n'
	)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with open(path, "w") as handle:
		handle.write(body)
	return path


def wait_for_socket(socket_path, timeout_seconds=5.0):
	"""Poll until socket_path exists as a socket, up to timeout."""
	deadline = time.monotonic() + timeout_seconds
	while time.monotonic() < deadline:
		if os.path.exists(socket_path):
			return True
		time.sleep(0.05)
	return False


def service_request(socket_path, payload, read_cap=64 * 1024 * 1024):
	"""Send one JSON payload to the service and return (exit, stdout, stderr).

	The client-side twin of the production client protocol: one JSON
	object, half-shutdown, response relayed verbatim.
	"""
	client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	try:
		client.connect(socket_path)
		client.sendall(json.dumps(payload).encode())
		client.shutdown(socket.SHUT_WR)
		chunks = []
		total = 0
		while True:
			chunk = client.recv(65536)
			if not chunk:
				break
			total += len(chunk)
			if total > read_cap:
				raise RuntimeError("service response exceeded read cap")
			chunks.append(chunk)
		response = json.loads(b"".join(chunks).decode())
		return int(response["exit"]), response["stdout"], response["stderr"]
	finally:
		client.close()


if __name__ == "__main__":
	print(__doc__)
	sys.exit(2)
