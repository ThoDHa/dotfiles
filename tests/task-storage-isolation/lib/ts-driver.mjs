// Node driver for the TS-side unit checks of the task-storage-isolation
// enforcement surface (the guard extension and the installed wrap
// block). The bash suite owns fixtures, machine-side bwrap probes, and
// the pass/fail counters; this driver prints one "ok <name>" or
// "bad <name>" line per check for the suite to count, and exits
// non-zero when any check fails. Node 24 strips types natively, so the
// real TS sources load directly: the suite tests the shipped code, not
// a copy.
//
// Usage:
//   ts-driver.mjs guard <repo-root> <scratch-dir>
//   ts-driver.mjs wrap <repo-root> <scratch-dir> <activated-index.ts> <expected-argv.json>
//   ts-driver.mjs extension <repo-root> <scratch-dir> <fixture-repo> <taskfile-basename>
//
// The wrap and extension sections expect <scratch-dir>/agent-activated
// to exist (the suite stages the pristine and wrap-activated vendored
// copies there before calling the driver).

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

let failures = 0;

function ok(name) {
	console.log(`ok ${name}`);
}

function bad(name, detail) {
	failures++;
	console.log(`bad ${name}${detail ? ` (${detail})` : ""}`);
}

function check(name, condition, detail) {
	if (condition) ok(name);
	else bad(name, detail);
}

function assertThrows(name, fn, needle) {
	try {
		fn();
		bad(name, "did not throw");
	} catch (error) {
		check(name, String(error).includes(needle), `unexpected: ${error}`);
	}
}

const ISO = {
	FLAG: "PI_TASK_STORAGE_ISOLATION",
	MASK: "PI_TASK_STORAGE_MASK_PATHS",
	SOCKET: "PI_TASK_STORAGE_SOCKET",
	TRUST: "PI_TASK_STORAGE_TRUST_FILE",
	AGENT: "PI_TASK_STORAGE_AGENT_DIR",
	UNMASKED: "PI_TASK_STORAGE_UNMASKED",
	TOKEN: "PI_TASK_STORAGE_TOKEN",
};

const ENV_KEYS = Object.values(ISO);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function stubPi() {
	const handlers = {};
	return {
		api: {
			on: (name, handler) => {
				(handlers[name] ??= []).push(handler);
			},
		},
		handlers,
	};
}

function makeProbeTree(scratch) {
	const probe = path.join(scratch, "probe");
	fs.mkdirSync(path.join(probe, ".tasks", "current"), { recursive: true });
	fs.mkdirSync(path.join(probe, "sub", "deeper"), { recursive: true });
	fs.mkdirSync(path.join(probe, "outside-dir"), { recursive: true });
	fs.writeFileSync(path.join(probe, ".tasks", "current", "secret.md"), "secret\n");
	fs.writeFileSync(path.join(probe, "outside.md"), "fine\n");
	fs.writeFileSync(path.join(probe, "outside-dir", "note.txt"), "fine\n");
	fs.symlinkSync(path.join(probe, ".tasks", "current", "secret.md"), path.join(probe, "link-into"));
	fs.symlinkSync("/etc/passwd", path.join(probe, ".tasks", "link-out"));
	// Symlink-then-dotdot divergence class: the kernel applies ".." to the
	// symlink's RESOLVED target, lexical resolve applies it to the name.
	fs.symlinkSync(".tasks/current", path.join(probe, "tasks-link"));
	fs.symlinkSync("../.tasks/current", path.join(probe, "sub", "link-cur"));
	fs.symlinkSync("outside-dir", path.join(probe, "out-link"));
	fs.symlinkSync("outside-dir", path.join(probe, "hop"));
	return probe;
}

async function runGuard(repoRoot, scratch) {
	const guardPath = path.join(repoRoot, "pi", "extensions", "task-storage-isolation.ts");
	const probe = makeProbeTree(scratch);
	let tag = 0;
	const load = async (env) => {
		const saved = {};
		for (const key of ENV_KEYS) saved[key] = process.env[key];
		for (const key of ENV_KEYS) delete process.env[key];
		Object.assign(process.env, env);
		const mod = await import(pathToFileURL(guardPath).href + `?case=${tag++}`);
		return {
			mod,
			restore: () => {
				for (const key of ENV_KEYS) {
					if (saved[key] === undefined) delete process.env[key];
					else process.env[key] = saved[key];
				}
			},
		};
	};

	const cases = [
		["guard allows a plain path outside .tasks", path.join(probe, "outside.md"), false],
		["guard denies a relative .tasks read (lexical)", ".tasks/current/secret.md", true],
		["guard denies an absolute .tasks read (lexical)", path.join(probe, ".tasks/current/secret.md"), true],
		["guard denies parent traversal into .tasks (lexical)", "sub/deeper/../../.tasks/current/secret.md", true],
		["guard denies a symlink resolving into .tasks (realpath)", "link-into", true],
		["guard denies a path inside .tasks pointing outward (lexical)", ".tasks/link-out", true],
		["guard denies a not-yet-existing write target under .tasks (ancestor realpath)", ".tasks/current/new.md", true],
		["guard denies the .tasks directory itself", ".tasks", true],
		["guard matches the exact .tasks component only", ".tasksx/secret", false],
		// Symlink-then-dotdot divergence: lexical and ancestor candidates
		// both miss these; only the kernel-style walk sees the .tasks hit.
		["guard denies symlink-then-dotdot through a .tasks symlink (kernel walks the target)", "tasks-link/../current/secret.md", true],
		["guard denies symlink-then-dotdot through a nested .tasks symlink", "sub/link-cur/../current/secret.md", true],
		["guard denies a symlink pointing outside then dotdot back into .tasks", "hop/../.tasks/current/secret.md", true],
		// No over-block: the same class staying outside .tasks must pass.
		["guard allows symlink-then-dotdot that stays outside .tasks", "out-link/../outside-dir/note.txt", false],
	];
	for (const [name, raw, expectedProtected] of cases) {
		const { mod, restore } = await load({});
		try {
			const verdict = mod.resolveProtectedTarget(probe, raw);
			check(name, verdict.protected === expectedProtected, JSON.stringify(verdict));
		} finally {
			restore();
		}
	}
	{
		const { mod, restore } = await load({});
		try {
			check("guard fails closed on a non-string path (null)", mod.resolveProtectedTarget(probe, null).protected);
			check("guard fails closed on an object path", mod.resolveProtectedTarget(probe, { evil: true }).protected);
		} finally {
			restore();
		}
	}

	const wiring = {
		[ISO.FLAG]: "1",
		[ISO.SOCKET]: "/tmp/isolation-driver-unused-socket",
		[ISO.TRUST]: "/tmp/isolation-driver-unused-trust",
		[ISO.MASK]: probe,
		[ISO.AGENT]: scratch,
	};
	{
		const { mod, restore } = await load(wiring);
		try {
			const stub = stubPi();
			mod.default(stub.api);
			const handler = stub.handlers.tool_call[0];
			const child = { mode: "json", hasUI: false };
			const blocked = await handler(
				{ toolName: "read", input: { path: path.join(probe, ".tasks/current/secret.md") } }, child);
			check("factory denies a child (json) read of .tasks", Boolean(blocked?.block), JSON.stringify(blocked));
			const allowed = await handler(
				{ toolName: "read", input: { path: path.join(probe, "outside.md") } }, child);
			check("factory allows a child read outside .tasks", !allowed?.block, JSON.stringify(allowed));
			const manager = await handler(
				{ toolName: "read", input: { path: path.join(probe, ".tasks/current/secret.md") } },
				{ mode: "default", hasUI: false });
			check("factory exempts the interactive manager (non-json ctx)", !manager?.block, JSON.stringify(manager));
			for (const toolName of ["write", "edit"]) {
				const denied = await handler(
					{ toolName, input: { path: path.join(probe, ".tasks/current/secret.md") } }, child);
				check(`factory denies a child ${toolName} on .tasks`, Boolean(denied?.block), JSON.stringify(denied));
			}
			const bash = await handler(
				{ toolName: "bash", input: { command: "cat .tasks/current/secret.md" } }, child);
			check("factory leaves bash to the child-wrap layer (no guard denial)", !bash?.block, JSON.stringify(bash));
		} finally {
			restore();
		}
	}
	{
		const { mod, restore } = await load({ ...wiring, [ISO.UNMASKED]: "1" });
		try {
			const stub = stubPi();
			mod.default(stub.api);
			const handler = stub.handlers.tool_call[0];
			const passed = await handler(
				{ toolName: "read", input: { path: path.join(probe, ".tasks/current/secret.md") } },
				{ mode: "json", hasUI: false });
			check("factory stands down under the explicit unmasked override", !passed?.block, JSON.stringify(passed));
		} finally {
			restore();
		}
	}
	{
		const { mod, restore } = await load({});
		try {
			const stub = stubPi();
			mod.default(stub.api);
			check("factory registers nothing when the flag is off (rollback)",
				Object.keys(stub.handlers).length === 0, JSON.stringify(Object.keys(stub.handlers)));
		} finally {
			restore();
		}
	}
}

async function runWrap(repoRoot, scratch, activatedPath, expectedArgvPath) {
	const text = fs.readFileSync(activatedPath, "utf8");
	const markerBegin = "// TASK-STORAGE-ISOLATION WRAP BEGIN";
	const markerEnd = "// TASK-STORAGE-ISOLATION WRAP END";
	const begin = text.indexOf(markerBegin);
	const end = text.indexOf(markerEnd);
	if (begin < 0 || end < 0) {
		bad("wrap block extraction", "markers not found in activated copy");
		return;
	}
	const blockPath = path.join(scratch, "wrap-block.ts");
	fs.writeFileSync(blockPath, text.slice(begin, end + markerEnd.length) + "\n");
	const mod = await import(pathToFileURL(blockPath).href);
	const probe = mod.__storageIsolationProbe;
	const expected = JSON.parse(fs.readFileSync(expectedArgvPath, "utf8"));
	const invocation = { command: "node", args: ["child.js"] };

	check("wrap is inert without the flag (identity)",
		probe.wrapInvocation(invocation, {}) === null);
	check("wrap is inert with a non-1 flag value",
		probe.wrapInvocation(invocation, { [ISO.FLAG]: "0" }) === null);
	check("wrap stands down under the explicit unmasked override",
		probe.wrapInvocation(invocation, { [ISO.FLAG]: "1", [ISO.UNMASKED]: "1" }) === null);
	assertThrows("wrap refuses when mask wiring is missing",
		() => probe.wrapInvocation(invocation, { [ISO.FLAG]: "1" }), "PI_TASK_STORAGE_MASK_PATHS");
	assertThrows("wrap refuses when socket wiring is missing",
		() => probe.wrapInvocation(invocation, {
			[ISO.FLAG]: "1", [ISO.MASK]: expected.mask_paths.join("\n"),
		}), "PI_TASK_STORAGE_SOCKET");
	assertThrows("wrap refuses when trust wiring is missing",
		() => probe.wrapInvocation(invocation, {
			[ISO.FLAG]: "1", [ISO.MASK]: expected.mask_paths.join("\n"),
			[ISO.SOCKET]: expected.socket,
		}), "PI_TASK_STORAGE_TRUST_FILE");
	assertThrows("wrap refuses an empty mask list", () => probe.wrapInvocation(invocation, {
		[ISO.FLAG]: "1", [ISO.MASK]: "\n", [ISO.SOCKET]: expected.socket,
		[ISO.TRUST]: expected.trust, [ISO.AGENT]: expected.agent_dir,
	}), "empty");

	const wired = {
		[ISO.FLAG]: "1",
		[ISO.MASK]: expected.mask_paths.join("\n"),
		[ISO.SOCKET]: expected.socket,
		[ISO.TRUST]: expected.trust,
		[ISO.AGENT]: expected.agent_dir,
		XDG_DATA_HOME: expected.xdg_data_home,
	};
	const built = probe.wrapInvocation(invocation, wired);
	check("wrap argv matches the suite builder for identical inputs (parity)",
		JSON.stringify(built) === JSON.stringify({ command: expected.command, args: expected.argv }),
		`wrap=${JSON.stringify(built)} builder=${JSON.stringify(expected.argv)}`);
	const socketIndex = built ? built.args.indexOf(expected.socket) : -1;
	check("wrap binds the socket FILE read-only (connect allowed, unlink refused)",
		socketIndex > 0 && built.args[socketIndex - 1] === "--ro-bind",
		JSON.stringify(built));
	const transcriptStore = `${expected.xdg_data_home}/opencode`;
	const storeIndex = built ? built.args.indexOf(transcriptStore) : -1;
	check("wrap tmpfs-masks the other harness's transcript-copy store (DC2)",
		storeIndex > 0 && built.args[storeIndex - 1] === "--tmpfs",
		JSON.stringify(built));
	for (const maskPath of expected.mask_paths) {
		check(`wrap stacks a ro-bind and tmpfs mask over ${maskPath}`,
			Boolean(built) && built.args.includes(maskPath) && built.args.includes("--tmpfs"),
			JSON.stringify(built));
	}
	const skip = probe.agentDirSkip;
	check("wrap hides sessions and credentials from children",
		skip.has("sessions") && skip.has("auth.json") && skip.has("mcp-auth.json"),
		JSON.stringify([...skip]));
}

function makeMinimalAgentDir(where) {
	fs.mkdirSync(path.join(where, "extensions", "subagent"), { recursive: true });
	fs.mkdirSync(path.join(where, "prompts"), { recursive: true });
	fs.mkdirSync(path.join(where, "sessions", "--fixture-cwd--"), { recursive: true });
	for (const name of ["auth.json", "mcp-auth.json", "trust.json", "settings.json", "models-store.json", "mcp.json"]) {
		fs.writeFileSync(path.join(where, name), "{}\n");
	}
	fs.writeFileSync(path.join(where, "extensions", "subagent", "index.ts"), "// fixture\n");
	fs.writeFileSync(path.join(where, "prompts", "default.md"), "prompt\n");
	fs.writeFileSync(path.join(where, "sessions", "--fixture-cwd--", "t.jsonl"), "{}\n");
}

async function runExtension(repoRoot, scratch, fixtureRepo, taskfile) {
	const guardPath = path.join(repoRoot, "pi", "extensions", "task-storage-isolation.ts");
	const pristineDir = path.join(scratch, "agent-pristine");
	const activatedDir = path.join(scratch, "agent-activated");
	makeMinimalAgentDir(pristineDir);
	makeMinimalAgentDir(activatedDir);
	fs.copyFileSync(path.join(scratch, "vendored-activated.ts"),
		path.join(activatedDir, "extensions", "subagent", "index.ts"));

	let tag = 1000;
	const load = async (env) => {
		const saved = {};
		for (const key of ENV_KEYS) saved[key] = process.env[key];
		for (const key of ENV_KEYS) delete process.env[key];
		Object.assign(process.env, env);
		const mod = await import(pathToFileURL(guardPath).href + `?case=${tag++}`);
		return {
			mod,
			restore: () => {
				for (const key of ENV_KEYS) {
					if (saved[key] === undefined) delete process.env[key];
					else process.env[key] = saved[key];
				}
			},
		};
	};

	// Drift refusal: pristine vendored copy (no wrap marker) blocks dispatch.
	{
		const { mod, restore } = await load({
			[ISO.FLAG]: "1",
			[ISO.SOCKET]: "/tmp/isolation-driver-unused-socket",
			[ISO.TRUST]: "/tmp/isolation-driver-unused-trust",
			[ISO.AGENT]: pristineDir,
		});
		try {
			const stub = stubPi();
			mod.default(stub.api);
			const handler = stub.handlers.tool_call[0];
			const blocked = await handler(
				{ toolName: "subagent", input: { agent: "worker", task: "x" } },
				{ mode: "default", hasUI: false });
			check("drift refusal blocks dispatch when the vendored wrap marker is missing",
				Boolean(blocked?.block) && String(blocked.reason).includes("fail-closed"),
				JSON.stringify(blocked));
		} finally {
			restore();
		}
	}

	// S-drift: an in-block edit keeping the markers must fail the digest
	// pin and block dispatch, not pass as a healthy wrap.
	{
		const driftedDir = path.join(scratch, "agent-drifted");
		makeMinimalAgentDir(driftedDir);
		const activatedText = fs.readFileSync(path.join(scratch, "vendored-activated.ts"), "utf8");
		const driftedText = activatedText.replace('"--die-with-parent",', '"--die-with-parent-drifted",');
		if (driftedText === activatedText) {
			bad("drifted vendored copy could not be prepared", "anchor line missing");
		} else {
			fs.writeFileSync(path.join(driftedDir, "extensions", "subagent", "index.ts"), driftedText);
			const { mod, restore } = await load({
				[ISO.FLAG]: "1",
				[ISO.SOCKET]: "/tmp/isolation-driver-unused-socket",
				[ISO.TRUST]: "/tmp/isolation-driver-unused-trust",
				[ISO.AGENT]: driftedDir,
			});
			try {
				const stub = stubPi();
				mod.default(stub.api);
				const handler = stub.handlers.tool_call[0];
				const blocked = await handler(
					{ toolName: "subagent", input: { agent: "worker", task: "x" } },
					{ mode: "default", hasUI: false });
				check("drift refusal blocks dispatch when the installed block content drifts (digest mismatch)",
					Boolean(blocked?.block) && String(blocked.reason).includes("fail-closed"),
					JSON.stringify(blocked));
			} finally {
				restore();
			}
		}
	}

	// Drift pass + mask refresh: activated copy, dispatch allowed, env refreshed.
	{
		const { mod, restore } = await load({
			[ISO.FLAG]: "1",
			[ISO.SOCKET]: "/tmp/isolation-driver-unused-socket",
			[ISO.TRUST]: "/tmp/isolation-driver-unused-trust",
			[ISO.AGENT]: activatedDir,
		});
		try {
			const previousCwd = process.cwd();
			process.chdir(fixtureRepo);
			try {
				const stub = stubPi();
				mod.default(stub.api);
				const handler = stub.handlers.tool_call[0];
				const passed = await handler(
					{ toolName: "subagent", input: { agent: "worker", task: "x" } },
					{ mode: "default", hasUI: false });
				check("dispatch passes when the vendored wrap marker is present", !passed?.block, JSON.stringify(passed));
				const maskPaths = (process.env[ISO.MASK] || "").split("\n").filter(Boolean);
				const repoTasks = path.join(fs.realpathSync(fixtureRepo), ".tasks");
				check("dispatch refreshes the mask list to the live .tasks trees",
					maskPaths.length >= 1 && maskPaths.includes(repoTasks)
						&& maskPaths.every((entry) => fs.existsSync(entry)),
					JSON.stringify(maskPaths));
			} finally {
				process.chdir(previousCwd);
			}
		} finally {
			restore();
		}
	}

	// Hosting: parent session starts the service, a child round-trips the
	// sanctioned verb through the real client, shutdown cleans up.
	{
		const { mod, restore } = await load({ [ISO.FLAG]: "1", [ISO.AGENT]: activatedDir });
		try {
			const previousCwd = process.cwd();
			process.chdir(fixtureRepo);
			let shutdownHandler = null;
			try {
				const stub = stubPi();
				mod.default(stub.api);
				shutdownHandler = stub.handlers.session_shutdown?.[0];
				const repoReal = fs.realpathSync(fixtureRepo);
				let socketPath = null;
				for (let poll = 0; poll < 120 && !socketPath; poll++) {
					socketPath = process.env[ISO.SOCKET] || null;
					if (!socketPath) await sleep(50);
				}
				check("parent session hosts the escape-channel service", Boolean(socketPath), "socket never appeared");
				check("hosting publishes the mask list for the child-wrap",
					(process.env[ISO.MASK] || "").includes(path.join(repoReal, ".tasks")),
					process.env[ISO.MASK]);
				check("hosting publishes the attribution token",
					(process.env[ISO.TOKEN] || "").length >= 32, String((process.env[ISO.TOKEN] || "").length));
				if (socketPath) {
					const client = path.join(repoRoot, "pi", "extensions", "task-storage-isolation-client.py");
					const roundTrip = spawnSync("python3", [client, "tasks", "show", taskfile, "--json"], {
						encoding: "utf8",
						env: {
							...process.env,
							PI_TASK_STORAGE_SOCKET: socketPath,
							PI_TASK_STORAGE_TOKEN: process.env[ISO.TOKEN],
							TASKS_SESSION: "driver-child",
						},
					});
					check("sanctioned read round-trips through the hosted channel",
						roundTrip.status === 0 && roundTrip.stdout.includes("schema_version"),
						`status=${roundTrip.status} out=${roundTrip.stdout.slice(0, 120)} err=${roundTrip.stderr.slice(0, 200)}`);
				}
			} finally {
				process.chdir(previousCwd);
				if (shutdownHandler) await shutdownHandler({}, { mode: "default", hasUI: false });
			}
			check("session shutdown stops the channel and clears its wiring",
				!process.env[ISO.SOCKET] && !process.env[ISO.TOKEN],
				"wiring still present after shutdown");
		} finally {
			restore();
		}
	}

	// Empty-mask refusal: flag on, no .tasks anywhere under the cwd.
	{
		const bare = path.join(scratch, "bare");
		fs.mkdirSync(bare, { recursive: true });
		const { mod, restore } = await load({ [ISO.FLAG]: "1", [ISO.AGENT]: activatedDir });
		try {
			const previousCwd = process.cwd();
			process.chdir(bare);
			try {
				const stub = stubPi();
				mod.default(stub.api);
				for (let poll = 0; poll < 60; poll++) {
					if (process.env[ISO.SOCKET]) break;
					await sleep(50);
				}
				check("hosting refuses when no live .tasks tree exists", !process.env[ISO.SOCKET],
					String(process.env[ISO.SOCKET]));
				const handler = stub.handlers.tool_call?.[0];
				const blocked = handler
					? await handler({ toolName: "subagent", input: { agent: "w", task: "x" } }, { mode: "default", hasUI: false })
					: null;
				check("dispatch is blocked under the empty-mask refusal", Boolean(blocked?.block), JSON.stringify(blocked));
			} finally {
				process.chdir(previousCwd);
			}
		} finally {
			restore();
		}
	}
}

async function main() {
	const [section, repoRoot, scratch, arg4, arg5] = process.argv.slice(2);
	if (!section || !repoRoot || !scratch) {
		console.error(
			"usage: ts-driver.mjs <guard|wrap|extension> <repo-root> <scratch-dir> [wrap/extension args]",
		);
		process.exit(2);
	}
	fs.mkdirSync(scratch, { recursive: true });
	if (section === "guard") {
		await runGuard(repoRoot, scratch);
	} else if (section === "wrap") {
		if (!arg4 || !arg5) {
			console.error("wrap section needs <activated-index.ts> <expected-argv.json>");
			process.exit(2);
		}
		await runWrap(repoRoot, scratch, arg4, arg5);
	} else if (section === "extension") {
		if (!arg4 || !arg5) {
			console.error("extension section needs <fixture-repo> <taskfile-basename>");
			process.exit(2);
		}
		await runExtension(repoRoot, scratch, arg4, arg5);
	} else {
		console.error(`unknown section ${section}`);
		process.exit(2);
	}
	if (failures > 0) {
		console.error(`ts-driver: ${failures} check(s) failed`);
		process.exit(1);
	}
}

main().catch((error) => {
	console.error(`ts-driver crashed: ${error}`);
	process.exit(1);
});
