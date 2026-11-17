#!/usr/bin/env python3
"""Copy the vendored pi subagent extension and insert the bwrap seam.

Walking-skeleton artifact (ORCH-4-10-1). Copies the live extension
directory into a scratch location, then patches the copy, never the
live extension: getPiInvocation is renamed to getPiInvocationUnwrapped
and a wrapper of the same name is appended that prefixes the resolved
invocation with a bubblewrap command when the SKELETON_BWRAP_MASK,
SKELETON_BWRAP_SOCKET, and SKELETON_BWRAP_TRUST_FILE environment
variables are all set. The wrapper is the exact seam ORCH-4-10-2 will
productionize behind explicit activation; without the variables the
copy behaves byte-equivalently to the vendored original.

Usage:
    patch-subagent.py <live-extension-dir> <destination-dir>

Exits non-zero without writing anything when the vendored source no
longer matches the expected seam shape, so upstream drift surfaces
instead of silently patching the wrong function.
"""

import pathlib
import shutil
import sys

SEAM_ANCHOR = "function getPiInvocation(args: string[]): { command: string; args: string[] } {"
SEAM_CLOSER = 'return { command: "pi", args };\n}'

WRAPPER_LINES = [
    "function getPiInvocation(args: string[]): { command: string; args: string[] } {",
    "\tconst invocation = getPiInvocationUnwrapped(args);",
    "\tconst mask = process.env.SKELETON_BWRAP_MASK;",
    "\tconst socketPath = process.env.SKELETON_BWRAP_SOCKET;",
    "\tconst trustFile = process.env.SKELETON_BWRAP_TRUST_FILE;",
    "\tif (!mask || !socketPath || !trustFile) return invocation;",
    "\t// The child needs a writable ~/.pi/agent for its trust state (pi",
    "\t// mkdirs trust.json.lock at startup) and bwrap cannot create missing",
    "\t// bind destinations under a read-only mount, so the agent dir becomes",
    "\t// a tmpfs with every real entry ro-bound back in and a writable",
    "\t// trust.json bound from scratch.",
    "\tconst agentDir = `${process.env.HOME}/.pi/agent`;",
    '\tconst agentState: string[] = ["--tmpfs", agentDir];',
    "\tfor (const entry of fs.readdirSync(agentDir)) {",
    '\t\tif (entry === "trust.json" || entry === "trust.json.lock") continue;',
    '\t\tagentState.push("--ro-bind", `${agentDir}/${entry}`, `${agentDir}/${entry}`);',
    "\t}",
    '\tagentState.push("--bind", trustFile, `${agentDir}/trust.json`);',
    "\treturn {",
    '\t\tcommand: "bwrap",',
    "\t\targs: [",
    '\t\t\t"--unshare-user", "--unshare-ipc", "--unshare-pid", "--die-with-parent",',
    '\t\t\t"--ro-bind", "/", "/",',
    '\t\t\t"--dev", "/dev",',
    '\t\t\t"--proc", "/proc",',
    '\t\t\t"--tmpfs", "/tmp",',
    '\t\t\t"--ro-bind", mask, mask,',
    '\t\t\t"--tmpfs", mask + "/.tasks",',
    '\t\t\t"--bind", socketPath, socketPath,',
    "\t\t\t...agentState,",
    "\t\t\tinvocation.command, ...invocation.args,",
    "\t\t],",
    "\t};",
    "}",
]

WRAPPER = "\n".join([""] + WRAPPER_LINES) + "\n"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    source = pathlib.Path(sys.argv[1]).resolve()
    destination = pathlib.Path(sys.argv[2])
    index = source / "index.ts"
    text = index.read_text()
    if text.count(SEAM_ANCHOR) != 1 or text.count(SEAM_CLOSER) != 1:
        print("SEAM DRIFT: the vendored getPiInvocation shape changed; "
              "update SEAM_ANCHOR/SEAM_CLOSER before re-running the skeleton")
        return 1
    shutil.copytree(source, destination)
    patched = destination / "index.ts"
    body = patched.read_text()
    body = body.replace(SEAM_ANCHOR,
                        SEAM_ANCHOR.replace("getPiInvocation", "getPiInvocationUnwrapped"))
    body = body + WRAPPER
    patched.write_text(body)
    print(f"patched copy at {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
