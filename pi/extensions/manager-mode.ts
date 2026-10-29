/**
 * Manager Mode extension: makes the pi-side Manager Mode posture
 * self-enforcing (the posture record is pi/DESIGN.md in the dotfiles
 * repo; the governing rules are the pinned manager body this extension
 * injects, not this file).
 *
 * Default-on: every session activates at startup, interactive and
 * headless, with no user action. Two exclusions never activate:
 * subagent child sessions (the subagent extension spawns
 * `pi --mode json -p --no-session`, so json mode is the child
 * protocol), and sessions opted out with --no-manager-mode or
 * PI_MANAGER_MODE=off.
 *
 * While active the mode:
 * - removes edit/write from the advertised tool surface (setActiveTools),
 * - denies any edit/write tool call that still arrives (tool_call
 *   backstop, defense in depth if the surface is ever re-advertised),
 * - keeps git operations open and guards force-push forms of git push
 *   behind explicit user confirmation where a UI exists, denying them
 *   in headless sessions (git protocol Force Push Protection),
 * - injects the pinned manager body (manager-body.md sidecar,
 *   sha256-checked at activation against the fleet pin carried in
 *   PINNED_BODY_DIGEST) as the governing protocol,
 * - persists the posture via appendEntry so a resume restores it.
 *
 * /manager off (synonyms: "stand down", "solo") restores the saved
 * tool surface and drops the injected posture for the rest of the
 * session; the next session reasserts the default.
 *
 * Injection mechanism: the installed extension API exposes no
 * appendSystemPrompt method, but the before_agent_start event carries
 * the mutable systemPromptOptions whose appendSystemPrompt field feeds
 * system-prompt construction; the runner normalizes those options fresh
 * for every run, so injecting here is per-run and cannot accumulate.
 */

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const COMMAND_NAME = "manager";
const ENTRY_TYPE = "manager-mode";
const STATUS_KEY = "manager-mode";
const OPT_OUT_FLAG = "no-manager-mode";
const OPT_OUT_ENV = "PI_MANAGER_MODE";
const OPT_OUT_VALUE = "off";
const WRITE_TOOLS = new Set(["edit", "write"]);
const BODY_SIDECAR = "manager-body.md";
// sha256 of the pinned fleet manager body (tests/pi-agents/
// manager-body.sha256); the sync test pins this file's embedded copy of
// the digest against that pin, and activation re-derives the sidecar's
// digest against it.
const PINNED_BODY_DIGEST = "f93208a37ad3cc03a992f6486ff933bb77ab7f427b2586d50e3cb54b92813a59";
const DEACTIVATE_ARGS = new Set(["off", "stand down", "solo"]);

interface ModeState {
	active: boolean;
	toolsBefore?: string[];
}

function isOptedOut(pi: ExtensionAPI): boolean {
	if (pi.getFlag(OPT_OUT_FLAG) === true) return true;
	return (process.env[OPT_OUT_ENV] ?? "").trim().toLowerCase() === OPT_OUT_VALUE;
}

/**
 * Detect the force-push forms of a bash command: any `git push` segment
 * carrying --force* (including --force-with-lease), a short-flag token
 * containing f, the per-refspec leading-plus form, or --mirror. Segment
 * split is on shell operators only, so quoted or nested invocations can
 * evade matching; the mode treats that residual as conduct-covered, not
 * mechanically denied.
 */
function isForcePushCommand(command: string): boolean {
	for (const segment of command.split(/&&|\|\||[;|]/)) {
		const tokens = segment.trim().split(/\s+/);
		const gitIndex = tokens.indexOf("git");
		if (gitIndex === -1) continue;
		const pushIndex = tokens.indexOf("push", gitIndex + 1);
		if (pushIndex === -1) continue;
		for (const token of tokens.slice(pushIndex + 1)) {
			if (token.startsWith("--force")) return true;
			if (token === "--mirror") return true;
			if (/^-[a-z]*f/i.test(token)) return true;
			if (token.startsWith("+") && token.length > 1) return true;
		}
	}
	return false;
}

function readPersistedState(sessionManager: { getEntries(): unknown[] }): ModeState | undefined {
	const entries = sessionManager.getEntries();
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i] as { type?: string; customType?: string; data?: ModeState };
		if (entry.type === "custom" && entry.customType === ENTRY_TYPE) return entry.data;
	}
	return undefined;
}

export default function managerModeExtension(pi: ExtensionAPI): void {
	let active = false;
	let savedTools: string[] | undefined;
	let bodyText: string | undefined;
	let bodyProblem: string | undefined;

	pi.registerFlag(OPT_OUT_FLAG, {
		description: "Start with Manager Mode inactive (default-on opt-out)",
		type: "boolean",
		default: false,
	});

	function loadBody(): void {
		const bodyPath = path.join(path.dirname(fileURLToPath(import.meta.url)), BODY_SIDECAR);
		try {
			const text = readFileSync(bodyPath, "utf8");
			const digest = createHash("sha256").update(text).digest("hex");
			if (digest !== PINNED_BODY_DIGEST) {
				bodyProblem = `manager body digest ${digest} does not match the fleet pin; resync (make sync-pi-extensions)`;
				return;
			}
			bodyText = text;
		} catch (error) {
			bodyProblem = `manager body unreadable: ${error instanceof Error ? error.message : String(error)}`;
		}
	}

	function persist(): void {
		pi.appendEntry<ModeState>(ENTRY_TYPE, { active, toolsBefore: savedTools });
	}

	function updateStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		ctx.ui.setStatus(STATUS_KEY, active ? ctx.ui.theme.fg("warning", "Ⓜ manager") : undefined);
	}

	function captureSurface(): string[] {
		const surface = [...pi.getActiveTools()];
		for (const name of WRITE_TOOLS) {
			if (!surface.includes(name) && pi.getAllTools().some((tool) => tool.name === name)) {
				surface.push(name);
			}
		}
		return surface;
	}

	function activate(persisted?: ModeState): void {
		savedTools = persisted?.toolsBefore?.length ? [...persisted.toolsBefore] : captureSurface();
		pi.setActiveTools(savedTools.filter((name) => !WRITE_TOOLS.has(name)));
		active = true;
		persist();
	}

	function deactivate(): void {
		if (savedTools) pi.setActiveTools(savedTools);
		savedTools = undefined;
		active = false;
		persist();
	}

	function restoreSurfaceOnly(): void {
		if (savedTools) pi.setActiveTools(savedTools);
		savedTools = undefined;
		active = false;
	}

	loadBody();

	pi.registerCommand(COMMAND_NAME, {
		description: "Toggle Manager Mode (writeless delegated posture, on by default)",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (DEACTIVATE_ARGS.has(arg)) {
				if (!active) {
					ctx.ui.notify("Manager Mode is not active.");
					return;
				}
				deactivate();
				updateStatus(ctx);
				ctx.ui.notify("Manager Mode off: edit/write restored for this session.");
				return;
			}
			if (arg === "" || arg === "on") {
				if (active) {
					ctx.ui.notify("Manager Mode is already active.");
					return;
				}
				activate();
				updateStatus(ctx);
				ctx.ui.notify(
					bodyProblem
						? `Manager Mode active (surface enforcement only: ${bodyProblem})`
						: "Manager Mode active: writeless posture and the manager protocol are in force.",
					bodyProblem ? "warning" : "info",
				);
				return;
			}
			ctx.ui.notify(`Usage: /${COMMAND_NAME} [off|stand down|solo]`);
		},
	});

	// Default-on activation and resume restore. Fresh sessions carry no
	// mode entry and activate; sessions resumed from an entry restore its
	// state, so /manager off survives a resume while a fresh session
	// reasserts the default. Gated sessions (child protocol, opt-out)
	// never activate, and a session switch out of an active session hands
	// the full surface back before the gate applies.
	pi.on("session_start", async (_event, ctx) => {
		const persisted = readPersistedState(ctx.sessionManager);
		const shouldActivate = !isOptedOut(pi) && ctx.mode !== "json" && persisted?.active !== false;
		if (shouldActivate) {
			activate(persisted);
		} else if (active) {
			restoreSurfaceOnly();
		} else if (persisted) {
			// A fresh process resuming a session this extension previously
			// governed, with the mode resolving inactive: pi rebuilds the
			// active set from the transcript, whose last declaration can be
			// the reduced one from an active stretch that ended between
			// turns, so the write tools must be handed back for off to mean
			// the full surface.
			pi.setActiveTools(captureSurface());
		}
		if (active && bodyProblem) {
			ctx.ui.notify(`Manager Mode: ${bodyProblem}`, "warning");
		}
		updateStatus(ctx);
	});

	// The governing protocol rides the system prompt: appended after the
	// base prompt content for every run while active, dropped by doing
	// nothing once inactive.
	pi.on("before_agent_start", async (event) => {
		if (!active || !bodyText) return;
		const options = event.systemPromptOptions;
		options.appendSystemPrompt = options.appendSystemPrompt
			? `${options.appendSystemPrompt}\n\n${bodyText}`
			: bodyText;
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!active) return;
		if (WRITE_TOOLS.has(event.toolName)) {
			return {
				block: true,
				reason: `Manager Mode bars ${event.toolName}: the pi manager is writeless and delegates file work to a worker. Run /${COMMAND_NAME} off to leave the mode for this session.`,
			};
		}
		if (event.toolName !== "bash") return;
		const command = (event.input as { command?: unknown }).command;
		if (typeof command !== "string" || !isForcePushCommand(command)) return;
		const warning = "WARNING: Force push will overwrite remote history. This action cannot be undone.";
		if (!ctx.hasUI) {
			return {
				block: true,
				reason: `Manager Mode force-push guard: ${warning} Explicit user confirmation is required and this headless session has no confirmation UI; rerun interactively to confirm.`,
			};
		}
		const confirmed = await ctx.ui.confirm(`Manager Mode: force push`, `${warning}\n\nContinue with force push?`);
		if (!confirmed) {
			return { block: true, reason: "Manager Mode force-push guard: declined without explicit confirmation." };
		}
	});
}
