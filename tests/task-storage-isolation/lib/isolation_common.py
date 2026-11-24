#!/usr/bin/env python3
"""Fixture builders for the task-storage adversarial suite (opencode column).

Builds the hermetic git repos the suite's bypass classes run against: a
fixture repo with a gitignored .tasks tree shaped like a live board
(the mask/enforcement target), and a sibling worktree carrying its own
board so multi-root coverage is provable. The pi-column machinery that
shared this module's bwrap argv builder moved with the extensions to
ThoDHa/pi (PIRELOC-1); this copy keeps only the fixture builders the
opencode column consumes.

Usage (suite-internal):
    from isolation_common import make_fixture_repo, add_fixture_worktree
"""

import os
import subprocess


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
