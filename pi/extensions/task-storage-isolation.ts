/**
 * Task Storage Isolation Extension
 *
 * Runtime half of the ORCH-4-10 pi enforcement slice. Everything here
 * is inert unless PI_TASK_STORAGE_ISOLATION is exactly "1"; rollback is
 * flag removal and leaves the session byte-equivalent to unextended pi.
 *
 * When active, a session gets three things:
 *
 * 1. The guard: read/edit/write tool calls whose target lands inside a
 *    .tasks tree (lexically or through symlinks, including targets that
 *    do not exist yet) are denied in json-mode child sessions. The
 *    interactive manager session is exempt (the ctx.mode !== "json"
 *    gate), because the manager is the sanctioned maintenance surface.
 *    An explicit unmasked dispatch (PI_TASK_STORAGE_UNMASKED=1 in the
 *    child environment, set by whoever launches the maintenance child)
 *    stands the guard down loudly; recording that dispatch in the task
 *    record is the launching manager's audit duty.
 *
 * 2. The escape channel: the parent hosts one per-session
 *    task-storage-isolation-service.py process on a socket under a
 *    0700 scratch dir, generates the session attribution token, and
 *    publishes the wiring (mask paths, socket, trust file, token) into
 *    the environment the vendored child-wrap consumes at spawn time.
 *    Children never host.
 *
 * 3. The drift refusal: before any subagent dispatch, the parent
 *    verifies the vendored subagent extension still carries the
 *    bwrap child-wrap installed by task-storage-isolation-wrap.py
 *    (marker presence AND a sha256 pin of the block content) and
 *    re-enumerates the mask paths. A missing wrap marker or an edited
 *    block means the vendored file drifted and children would spawn
 *    under a weakened or missing wrap, so dispatches are blocked until
 *    the wrap is reinstalled. This is the fail-closed half of the
 *    vendored-file drift problem: the wrap must never silently
 *    disappear or silently weaken.
 *
 * Failure posture: fail closed in every direction. A guard path that
 * cannot be resolved is denied, not allowed. A wrap that cannot be
 * verified blocks dispatches, not enforcement. A service that cannot
 * start blocks dispatches. bwrap failures at spawn time kill the child
 * spawn itself (the vendored wrap has no unmasked fallback), so kernel
 * or AppArmor drift over user namespaces surfaces as loud spawn
 * failures, never as silent unmasked children.
 */

import { execFileSync, spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const ISO_FLAG = "PI_TASK_STORAGE_ISOLATION";
export const ISO_MASK_PATHS = "PI_TASK_STORAGE_MASK_PATHS";
export const ISO_SOCKET = "PI_TASK_STORAGE_SOCKET";
export const ISO_TRUST_FILE = "PI_TASK_STORAGE_TRUST_FILE";
export const ISO_AGENT_DIR = "PI_TASK_STORAGE_AGENT_DIR";
export const ISO_UNMASKED = "PI_TASK_STORAGE_UNMASKED";
export const ISO_TOKEN = "PI_TASK_STORAGE_TOKEN";

export const WRAP_MARKER = "TASK-STORAGE-ISOLATION WRAP BEGIN";

// The block span the patcher installs, comment prefixes included: the
// digest must be computed over exactly the span the patcher hashes.
const WRAP_BLOCK_BEGIN = "// TASK-STORAGE-ISOLATION WRAP BEGIN";
const WRAP_BLOCK_END = "// TASK-STORAGE-ISOLATION WRAP END";
// sha256 of the canonical WRAP_BLOCK as installed (trailing separator
// newline excluded), pinned so the drift check asks "is it the wrap?"
// rather than "does it look like the wrap?". The suite cross-checks
// this constant against the patcher's derived digest on every run.
export const WRAP_BLOCK_DIGEST =
	"6022ba6a9b75e7d8bb92ffd551da9ebffdb8ff3a3c82569fd91b8150df7deb32";

const GUARDED_TOOLS = new Set(["read", "write", "edit"]);
const SERVICE_WAIT_POLL_MS = 50;
const SERVICE_WAIT_POLLS = 100;
const GIT_TIMEOUT_MS = 5000;

export function isActive(env: NodeJS.ProcessEnv): boolean {
	return env[ISO_FLAG] === "1";
}

export function isUnmaskedOverride(env: NodeJS.ProcessEnv): boolean {
	return env[ISO_UNMASKED] === "1";
}

export function agentDirFromEnv(env: NodeJS.ProcessEnv): string {
	return env[ISO_AGENT_DIR] || path.join(env.HOME || "", ".pi/agent");
}

/**
 * Lexically resolve a raw tool-input path against the session cwd.
 * Returns null for non-string input so callers can fail closed.
 */
export function lexicalResolvePath(sessionCwd: string, raw: unknown): string | null {
	if (typeof raw !== "string" || raw.length === 0) return null;
	try {
		return path.resolve(sessionCwd, raw);
	} catch {
		return null;
	}
}

/**
 * True when any path component is exactly ".tasks", so the resolved
 * target lands inside some .tasks tree: the live board, a worktree
 * copy, or any other repo's board. ".tasks.old" or "tasks" do not
 * match; the protection class is the exact directory name.
 */
export function pathIsProtected(resolvedPath: string): boolean {
	return resolvedPath.split(path.sep).includes(".tasks");
}

/**
 * Resolve a raw path the way the kernel resolves it at open time:
 * component by component, applying ".." to the symlink-RESOLVED target
 * rather than to the raw name. This is the resolution lexical resolve
 * cannot see: a symlink followed by a dot-dot segment diverges from
 * path.resolve exactly here (raw "ln/../secret" with ln -> .tasks/x
 * opens .tasks/secret in the kernel but lexically lands outside).
 * Non-existing tails continue lexically from the deepest resolved
 * prefix, which is where an open of such a path would fail or create.
 */
export function kernelStyleResolve(sessionCwd: string, raw: unknown): string | null {
	if (typeof raw !== "string" || raw.length === 0) return null;
	let current = path.isAbsolute(raw) ? path.sep : sessionCwd;
	for (const segment of raw.split(path.sep)) {
		if (segment === "" || segment === ".") continue;
		if (segment === "..") {
			current = path.dirname(current);
			continue;
		}
		const next = path.join(current, segment);
		try {
			current = fs.realpathSync(next);
		} catch {
			current = next;
		}
	}
	return current;
}

/**
 * Full resolution verdict for one tool-input path: lexical candidate,
 * kernel-style candidate (symlinks resolved before dot-dots apply),
 * realpath when the target exists, and ancestor-realpath for targets
 * that do not exist yet (a write to .tasks/current/new.md must not
 * slip through because new.md is absent). Protected when any candidate
 * lands inside a .tasks tree. Unresolvable input is protected (fail
 * closed): a path the guard cannot prove safe is denied.
 */
export function resolveProtectedTarget(
	sessionCwd: string,
	raw: unknown,
): { path: string; protected: boolean; detail: string } {
	const lexical = lexicalResolvePath(sessionCwd, raw);
	if (lexical === null) {
		return {
			path: String(raw),
			protected: true,
			detail: "path is not a usable string; refusing to guess",
		};
	}
	const candidates: string[] = [lexical];
	const kernel = kernelStyleResolve(sessionCwd, raw);
	if (kernel !== null) candidates.push(kernel);
	try {
		candidates.push(fs.realpathSync(lexical));
	} catch {
		// Target does not exist (write-ahead) or cannot be stat'ed;
		// resolve through the deepest existing ancestor instead.
		const parts = lexical.split(path.sep);
		for (let cut = parts.length - 1; cut > 1; cut--) {
			const head = parts.slice(0, cut).join(path.sep);
			const tail = parts.slice(cut).join(path.sep);
			try {
				const realHead = fs.realpathSync(head || path.sep);
				candidates.push(path.join(realHead, tail));
				break;
			} catch {
				continue;
			}
		}
	}
	for (const candidate of candidates) {
		if (pathIsProtected(candidate)) {
			return {
				path: lexical,
				protected: true,
				detail: `${candidate} resolves inside a .tasks tree; child board access rides the sanctioned verb channel only`,
			};
		}
	}
	return { path: lexical, protected: false, detail: "outside every .tasks tree" };
}

/**
 * Enumerate every live .tasks tree the session's repo family exposes:
 * the session cwd root plus every git worktree root (the cwd's own
 * worktrees and its main checkout). Only existing directories are
 * returned; bwrap cannot mount over paths that do not exist under its
 * read-only root bind. Empty output means the flag is set somewhere
 * with no board at all, which the caller treats as a refusal.
 */
export function enumerateMaskPaths(
	sessionCwd: string,
	runGit: (cwd: string) => string = defaultRunGit,
): string[] {
	const roots = new Set<string>();
	const addRoot = (candidate: string) => {
		try {
			const real = fs.realpathSync(candidate);
			if (fs.statSync(real).isDirectory()) roots.add(real);
		} catch {
			// candidate vanished between listing and stat; skip it
		}
	};
	addRoot(sessionCwd);
	for (const line of runGit(sessionCwd).split("\n")) {
		if (line.startsWith("worktree ")) addRoot(line.slice("worktree ".length));
	}
	const maskPaths: string[] = [];
	for (const root of roots) {
		const candidate = path.join(root, ".tasks");
		try {
			if (fs.statSync(candidate).isDirectory()) maskPaths.push(fs.realpathSync(candidate));
		} catch {
			// root carries no live .tasks tree; nothing to mask there
		}
	}
	return maskPaths;
}

function defaultRunGit(cwd: string): string {
	try {
		return execFileSync("git", ["worktree", "list", "--porcelain"], {
			cwd,
			encoding: "utf8",
			timeout: GIT_TIMEOUT_MS,
		});
	} catch {
		return "";
	}
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

export default function taskStorageIsolation(pi: ExtensionAPI) {
	let refusalReason: string | null = null;
	let stickyRefusal: string | null = null;
	let service: ReturnType<typeof spawn> | null = null;
	let scratchDir: string | null = null;

	const active = () => isActive(process.env);
	const unmasked = () => isUnmaskedOverride(process.env);

	const refuse = (reason: string) => {
		refusalReason = reason;
		process.stderr.write(`task-storage-isolation: dispatches blocked: ${reason}\n`);
	};

	const stick = (reason: string) => {
		stickyRefusal = reason;
		process.stderr.write(`task-storage-isolation: dispatches blocked: ${reason}\n`);
	};

	async function hostService(): Promise<void> {
		try {
			await hostServiceInner();
		} catch (error) {
			stick(`escape-channel hosting failed unexpectedly: ${error}`);
		}
	}

	async function hostServiceInner(): Promise<void> {
		const maskPaths = enumerateMaskPaths(process.cwd());
		if (maskPaths.length === 0) {
			stick(
				"PI_TASK_STORAGE_ISOLATION is set but no live .tasks tree was found from this session; " +
					"run with the flag off or from the board repo",
			);
			return;
		}
		const dir = fs.mkdtempSync(path.join(os.tmpdir(), "task-storage-isolation-"));
		const socketPath = path.join(dir, "service.sock");
		const trustFile = path.join(dir, "trust.json");
		const logPath = path.join(dir, "service.log");
		fs.writeFileSync(trustFile, "{}\n");
		const token = randomBytes(32).toString("hex");
		const serviceScript = path.join(extensionDir(), "task-storage-isolation-service.py");
		let child: ReturnType<typeof spawn>;
		try {
			child = spawn(
				"python3",
				[serviceScript, socketPath, process.cwd(), logPath],
				{
					env: { ...process.env, [ISO_TOKEN]: token },
					stdio: "ignore",
				},
			);
		} catch (error) {
			fs.rmSync(dir, { recursive: true, force: true });
			stick(`escape-channel service could not start: ${error}`);
			return;
		}
		child.on("error", (error) => {
			stick(`escape-channel service failed: ${error}`);
		});
		let up = false;
		for (let poll = 0; poll < SERVICE_WAIT_POLLS && !up; poll++) {
			up = fs.existsSync(socketPath);
			if (!up) await sleep(SERVICE_WAIT_POLL_MS);
		}
		if (!up || child.exitCode !== null) {
			child.kill("SIGTERM");
			fs.rmSync(dir, { recursive: true, force: true });
			stick(`escape-channel service did not come up on ${socketPath}; see ${logPath}`);
			return;
		}
		service = child;
		scratchDir = dir;
		process.env[ISO_MASK_PATHS] = maskPaths.join("\n");
		process.env[ISO_SOCKET] = socketPath;
		process.env[ISO_TRUST_FILE] = trustFile;
		process.env[ISO_TOKEN] = token;
		process.stderr.write(
			`task-storage-isolation: active; masking ${maskPaths.length} .tasks tree(s); escape channel on ${socketPath}\n`,
		);
	}

	function vendoredWrapPresent(): boolean {
		const vendored = path.join(
			agentDirFromEnv(process.env),
			"extensions",
			"subagent",
			"index.ts",
		);
		try {
			const text = fs.readFileSync(vendored, "utf8");
			const begin = text.indexOf(WRAP_BLOCK_BEGIN);
			const end = text.indexOf(WRAP_BLOCK_END);
			if (begin < 0 || end < 0) return false;
			const block = text.slice(begin, end + WRAP_BLOCK_END.length);
			return createHash("sha256").update(block).digest("hex") === WRAP_BLOCK_DIGEST;
		} catch {
			return false;
		}
	}

	if (!active()) {
		return;
	}

	if (unmasked()) {
		process.stderr.write(
			"task-storage-isolation: EXPLICIT UNMASKED DISPATCH ACTIVE " +
				"(PI_TASK_STORAGE_UNMASKED=1); the guard and the child-wrap stand down " +
				"for children spawned with this environment, and this dispatch must be " +
				"recorded in the task record\n",
		);
	}

	if (process.env[ISO_SOCKET]) {
		// Inherited wiring: this session is itself a dispatched child.
		process.stderr.write("task-storage-isolation: child session; guard armed\n");
	} else {
		void hostService();
	}

	pi.on("session_shutdown", async () => {
		if (service) {
			service.kill("SIGTERM");
			service = null;
		}
		if (scratchDir) {
			fs.rmSync(scratchDir, { recursive: true, force: true });
			scratchDir = null;
		}
		delete process.env[ISO_MASK_PATHS];
		delete process.env[ISO_SOCKET];
		delete process.env[ISO_TRUST_FILE];
		delete process.env[ISO_TOKEN];
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!active()) return undefined;

		if (event.toolName === "subagent") {
			// Dispatch-time refusal checks: a json child never dispatches
			// (and is exempt from hosting), but any dispatching parent must
			// not send children out while the boundary is unverifiable. The
			// drift and mask verdicts re-evaluate on every dispatch, so a
			// repaired wrap or a newly created tree unblocks dispatches;
			// only a hosting failure is sticky, because hosting happens
			// once per session.
			if (unmasked()) {
				process.stderr.write(
					"task-storage-isolation: unmasked dispatch passes through unwrapped; " +
						"record this dispatch in the task record\n",
				);
				return undefined;
			}
			if (!vendoredWrapPresent()) {
				refuse(
					"the vendored subagent extension no longer carries the intact bwrap child-wrap " +
						`(marker or content digest mismatch in ${agentDirFromEnv(process.env)}/extensions/subagent/index.ts); ` +
						"reinstall it with task-storage-isolation-wrap.py deactivate+activate before dispatching children",
				);
				return {
					block: true,
					reason:
						"task-storage-isolation: vendored child-wrap unusable (fail-closed drift refusal); " +
						"reinstall it with task-storage-isolation-wrap.py deactivate+activate",
				};
			}
			const maskPaths = enumerateMaskPaths(process.cwd());
			if (maskPaths.length === 0) {
				refuse("no live .tasks tree found to mask from this session");
				return { block: true, reason: `task-storage-isolation: ${refusalReason}` };
			}
			refusalReason = null;
			process.env[ISO_MASK_PATHS] = maskPaths.join("\n");
			if (stickyRefusal) {
				return { block: true, reason: `task-storage-isolation: ${stickyRefusal}` };
			}
			return undefined;
		}

		if (!GUARDED_TOOLS.has(event.toolName)) return undefined;
		// The guard arms json-mode sessions only: dispatched children.
		// The interactive manager is the sanctioned maintenance surface.
		if (ctx.mode !== "json") return undefined;
		if (unmasked()) return undefined;

		const rawPath = (event.input as { path?: unknown }).path;
		const verdict = resolveProtectedTarget(process.cwd(), rawPath);
		if (verdict.protected) {
			if (ctx.hasUI) {
				ctx.ui.notify(`Blocked ${event.toolName} on protected path: ${verdict.path}`, "warning");
			}
			return {
				block: true,
				reason: `task-storage-isolation: ${event.toolName} denied for child session: ${verdict.detail}`,
			};
		}
		return undefined;
	});
}

function extensionDir(): string {
	try {
		return path.dirname(fileURLToPath(import.meta.url));
	} catch {
		// Deployed location: the extension and the service script share
		// the extensions dir by the sync-pi-extensions layout.
		return path.join(agentDirFromEnv(process.env), "extensions");
	}
}
