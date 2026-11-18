/**
 * Task-storage guard plugin for opencode (ORCH-4-10-3).
 *
 * Closes the live .tasks tree of this repository against direct access
 * from normal fleet roles and brokers their shell execution through the
 * parent-side UDS service (tests/task-storage-isolation/lib/oc-task-service.py),
 * per the user-approved plugin-brokered socket-service mechanism. Only the
 * manager agent retains sanctioned access (every other role, primary mode
 * included, enforces restricted); every guard decision lands in the
 * runtime audit log.
 *
 * v2.3.0 runtime contract (probed live, asserted by the version gate):
 * the module default export must be { id, setup }; the setup context
 * carries hook registrars (ctx.tool.hook("execute.before"|"execute.after"),
 * ctx.permission.hook("evaluate"), ctx.session.hook("prompt")) and each
 * registration promise must be awaited; the tool execute.before callback
 * may mutate args (the command rewrite) or throw to cancel the call;
 * permission evaluate fires only for calls the permission maps did not
 * already decide, and its callback can force a denial with a message.
 *
 * Activation and rollback: the plugin enforces only inside a repository
 * that carries the broker lib (tests/task-storage-isolation/lib/), so
 * unrelated projects are untouched. Rollback is TASKS_BROKER_DISABLE=1
 * or removing this file (plus the map deny lines); no board data is
 * touched by either route. Set TASKS_BROKER_EXPECTED_VERSION to override
 * the pinned version in hermetic suite runs.
 */

import * as fs from "node:fs";
import * as net from "node:net";
import * as crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import * as path from "node:path";

const PINNED_VERSION = process.env.TASKS_BROKER_EXPECTED_VERSION ?? "2.3.0";
const BROKER_LIB_REL = "tests/task-storage-isolation/lib";
const SERVICE_SCRIPT = "oc-task-service.py";
const CLIENT_SCRIPT = "oc-broker-client.py";
const RE_ROOTS_TTL_MS = 30_000;

interface RepoLayout {
  mainRoot: string;
  cwdRoot: string;
  storagePaths: string[];
  libDir: string | null;
  stamp: number;
}

interface GuardState {
  ctx: any;
  directory: string;
  layout: RepoLayout | null;
  degraded: boolean;
  driftMessage: string;
  serviceChecked: boolean;
  runtimeDir: string;
}

const states = new Set<GuardState>();

function audit(state: GuardState, record: Record<string, unknown>): void {
  try {
    fs.mkdirSync(state.runtimeDir, { recursive: true, mode: 0o700 });
    fs.appendFileSync(
      path.join(state.runtimeDir, "guard.log"),
      JSON.stringify({ ts: new Date().toISOString(), ...record }) + "\n",
    );
  } catch {
    // audit failure must never break the guarded call; the service log
    // and the server log carry the remaining evidence
  }
}

function runGit(directory: string, args: string[]): string | null {
  const result = spawnSync("git", args, { cwd: directory, encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : null;
}

function computeLayout(directory: string): RepoLayout {
  const cwdRoot = runGit(directory, ["rev-parse", "--show-toplevel"]) ?? directory;
  const commonDir = runGit(directory, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const mainRoot = commonDir ? path.dirname(commonDir) : cwdRoot;
  const roots = new Set<string>([mainRoot, cwdRoot]);
  const listed = runGit(mainRoot, ["worktree", "list", "--porcelain"]);
  if (listed) {
    for (const line of listed.split("\n")) {
      if (line.startsWith("worktree ")) roots.add(line.slice("worktree ".length).trim());
    }
  }
  const libDir = path.join(mainRoot, BROKER_LIB_REL);
  return {
    mainRoot,
    cwdRoot,
    storagePaths: [...roots].map((root) => path.join(root, ".tasks")),
    libDir: fs.existsSync(path.join(libDir, SERVICE_SCRIPT)) ? libDir : null,
    stamp: 0,
  };
}

function repoLayout(state: GuardState): RepoLayout | null {
  const now = Date.now();
  if (state.layout && now - state.layout.stamp < RE_ROOTS_TTL_MS) {
    return state.layout;
  }
  state.layout = computeLayout(state.directory);
  return state.layout;
}

function lexicalRealPath(candidate: string, directory: string): string {
  return path.isAbsolute(candidate) ? candidate : path.resolve(directory, candidate);
}

function resolveCandidate(candidate: string): string | null {
  try {
    return fs.realpathSync(candidate);
  } catch (error: any) {
    if (error?.code === "ENOENT") return null; // nothing exists; lexical check decides
    throw error;
  }
}

function matchesStorage(real: string, storagePaths: string[]): boolean {
  return storagePaths.some(
    (storage) => real === storage || real.startsWith(storage + path.sep),
  );
}

function isStorageAccess(state: GuardState, candidate: string): boolean {
  const layout = repoLayout(state);
  if (!layout) return false;
  const lexical = lexicalRealPath(candidate, state.directory);
  if (matchesStorage(lexical, layout.storagePaths)) return true;
  try {
    const real = resolveCandidate(candidate);
    if (real === null) return false; // ENOENT: no inode to smuggle through
    return matchesStorage(real, layout.storagePaths);
  } catch {
    // resolution failed for a non-ENOENT reason (EACCES, ELOOP): the
    // real target cannot be proven outside storage, so fail closed
    return true;
  }
}

function pathArgs(tool: string, input: Record<string, unknown>): string[] {
  const candidates: string[] = [];
  for (const key of ["path", "filePath", "file", "directory"]) {
    const value = input?.[key];
    if (typeof value === "string" && value.length > 0) candidates.push(value);
  }
  return candidates;
}

function quoteSingle(value: string): string {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

function pingSocket(socketPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect(socketPath);
    const settle = (outcome: boolean) => {
      socket.destroy();
      resolve(outcome);
    };
    socket.setTimeout(1000);
    socket.once("connect", () => settle(true));
    socket.once("error", () => settle(false));
    socket.once("timeout", () => settle(false));
  });
}

async function ensureService(state: GuardState, layout: RepoLayout): Promise<void> {
  if (state.serviceChecked) return;
  state.serviceChecked = true;
  const socketPath = path.join(state.runtimeDir, "broker.sock");
  if (await pingSocket(socketPath)) return;
  fs.mkdirSync(state.runtimeDir, { recursive: true, mode: 0o700 });
  const child = spawn(
    "python3",
    [
      path.join(layout.libDir!, SERVICE_SCRIPT),
      "--socket", socketPath,
      "--repo", layout.mainRoot,
      "--audit-log", path.join(state.runtimeDir, "service.log"),
    ],
    { detached: true, stdio: "ignore" },
  );
  child.unref();
  // a concurrent instance may spawn too; the loser re-reads the same
  // token file and its bind fails, leaving one serving process, so the
  // race is harmless for requests
  audit(state, { decision: "service-spawn", socket: socketPath });
}

function controlRequest(state: GuardState, payload: Record<string, unknown>,
                        attempts = 3): Promise<string> {
  return new Promise((resolve) => {
    const socketPath = path.join(state.runtimeDir, "broker.sock");
    const socket = net.connect(socketPath);
    let settled = false;
    const finish = (outcome: string) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(outcome);
    };
    socket.setTimeout(2000);
    socket.once("connect", () => {
      socket.write(JSON.stringify(payload));
      // the service reads until EOF before parsing, so the request side
      // must send its FIN or both ends wait on the read timeout
      socket.end();
    });
    let data = "";
    socket.on("data", (chunk) => {
      data += chunk.toString();
      try {
        const response = JSON.parse(data);
        finish(response?.exit === 0 ? "registered" : `refused: ${response?.stderr ?? "?"}`);
      } catch {
        // response not complete yet
      }
    });
    socket.once("error", (error) => finish(`unreachable: ${error}`));
    socket.once("timeout", () => finish("timeout"));
  }).then(async (outcome) => {
    if (outcome === "registered" || attempts <= 1) return outcome;
    await new Promise((resolve) => setTimeout(resolve, 300));
    return controlRequest(state, payload, attempts - 1);
  });
}

async function registerSession(state: GuardState, session: string, agent: string): Promise<string> {
  return controlRequest(state, { control: "register", session, agent });
}

async function sessionAgent(state: GuardState, sessionID: string): Promise<string> {
  try {
    const record = await state.ctx.session.get({ sessionID });
    return typeof record?.agent === "string" ? record.agent : "";
  } catch {
    return "";
  }
}

function isExempt(agent: string): boolean {
  return agent === "manager";
}

function reportedVersion(): string {
  // `opencode --version` prints a banner line ("opencode v2.3.0"), so the
  // comparison key is the trailing version token with its leading "v"
  // stripped, not the raw line.
  const normalize = (line: string): string => {
    const token = line.trim().split(/\s+/).pop() ?? "";
    return token.startsWith("v") ? token.slice(1) : token;
  };
  const banner = (() => {
    try {
      const result = spawnSync("opencode", ["--version"], { encoding: "utf8" });
      if (result.status === 0) return normalize(result.stdout);
    } catch {
      // fall through to the binary-at-execPath form
    }
    return "";
  })();
  if (banner) return banner;
  try {
    const result = spawnSync(process.execPath, ["--version"], { encoding: "utf8" });
    if (result.status === 0) return normalize(result.stdout);
  } catch {
    // unreachable binary: reported as unknown below
  }
  return "";
}

function checkVersion(state: GuardState): void {
  const version = reportedVersion();
  if (version !== PINNED_VERSION) {
    state.degraded = true;
    state.driftMessage =
      `opencode version drift: enforcement pinned to ${PINNED_VERSION}, ` +
      `installed surface reports '${version || "unknown"}'. Re-probe the pinned ` +
      "v2.3.0 facts (plugin module shape {id,setup}, tool execute.before mutation " +
      "and cancel-by-throw, permission evaluate force-deny, permissions.read map " +
      "action, shell tool arg command, read tool arg path) and re-pin before " +
      "restoring full enforcement. Until then storage reads and non-manager " +
      "shell execution are denied (fail closed).";
    audit(state, { decision: "version-drift", expected: PINNED_VERSION, installed: version });
    try {
      fs.writeFileSync(path.join(state.runtimeDir, "VERSION_DRIFT"), state.driftMessage + "\n");
    } catch {
      // marker is best-effort; the audit line is the durable record
    }
  } else {
    audit(state, { decision: "version-ok", version });
  }
}

const guard = {
  id: "task-storage-guard",
  setup: async (ctx: any) => {
    if (process.env.TASKS_BROKER_DISABLE === "1") return undefined;
    const directory: string = ctx?.location?.directory ?? process.cwd();
    const xdg = process.env.XDG_STATE_HOME || path.join(process.env.HOME || "/tmp", ".local/state");
    const repoKey = crypto.createHash("sha256").update(computeLayout(directory).mainRoot).digest("hex").slice(0, 16);
    const state: GuardState = {
      ctx,
      directory,
      layout: null,
      degraded: false,
      driftMessage: "",
      serviceChecked: false,
      runtimeDir: path.join(xdg, "task-storage-broker", repoKey),
    };
    states.add(state);
    checkVersion(state);
    const layout = repoLayout(state)!;
    if (!layout.libDir) {
      audit(state, { decision: "inert", reason: "repository carries no broker lib" });
      states.delete(state);
      return () => states.delete(state);
    }

    await ctx.permission.hook("evaluate", (decision: any) => {
      const action: string = decision?.action ?? "";
      if (!["read", "edit", "write", "glob", "grep", "list"].includes(action)) return;
      const resources: unknown[] = Array.isArray(decision?.resources) ? decision.resources : [];
      for (const resource of resources) {
        if (typeof resource !== "string") continue;
        if (isStorageAccess(state, resource)) {
          decision.effect = "deny";
          decision.message = state.degraded
            ? "task-storage guard: denied under version-drift fail-closed mode"
            : `task-storage guard: '${resource}' resolves into the live .tasks tree; ` +
              "board access is CLI-only for this role (tasks show/list/reports)";
          audit(state, {
            decision: "deny", layer: "permission-evaluate",
            action, resource,
          });
          return;
        }
      }
    });

    await ctx.tool.hook("execute.before", async (call: any) => {
      const tool: string = call?.tool ?? "";
      const input: Record<string, unknown> = call?.input ?? {};
      const agent = await sessionAgent(state, call?.sessionID ?? "");
      if (isExempt(agent)) {
        audit(state, { decision: "exempt", role: agent, tool, session: call?.sessionID });
        return;
      }
      if (agent === "") {
        audit(state, { decision: "deny", tool, reason: "session role unresolved (fail closed)" });
        throw new Error(
          "task-storage guard: session role could not be resolved; " +
          "allowed roles are enforced as restricted (fail closed)",
        );
      }

      if (["read", "edit", "write", "glob", "grep", "list"].includes(tool)) {
        for (const candidate of pathArgs(tool, input)) {
          if (isStorageAccess(state, candidate)) {
            audit(state, {
              decision: "deny", layer: "tool-execute-before",
              tool, path: candidate, agent,
            });
            throw new Error(
              `task-storage guard: '${candidate}' resolves into the live .tasks ` +
              "tree; board access is CLI-only for this role (tasks show/list/reports)",
            );
          }
        }
        return;
      }

      if ((tool === "shell" || tool === "bash") && typeof input.command === "string") {
        const layoutNow = repoLayout(state)!;
        const bridgePrefix = layoutNow.libDir
          ? `python3 ${path.join(layoutNow.libDir, CLIENT_SCRIPT)} --registry ${state.runtimeDir}`
          : "\u0000never";
        if (input.command.startsWith(bridgePrefix)) return;
        if (state.degraded) {
          audit(state, { decision: "deny", tool, reason: "version-drift fail-closed", agent });
          throw new Error(state.driftMessage);
        }
        if (!layoutNow.libDir) {
          // the broker lib vanished after setup; without it no sanctioned
          // channel exists, so non-exempt shell fails closed rather than
          // falling back to unbrokered execution
          audit(state, { decision: "deny", tool, reason: "broker lib missing", agent });
          throw new Error(
            "task-storage guard: broker lib is missing; refusing unbrokered " +
            "shell execution (fail closed)",
          );
        }
        await ensureService(state, layoutNow);
        const registration = await registerSession(state, String(call?.sessionID ?? ""), agent);
        if (registration !== "registered") {
          audit(state, { decision: "deny", tool, reason: `registration failed: ${registration}`, agent });
          throw new Error(
            "task-storage guard: broker registration failed; refusing to run " +
            "unbrokered shell (fail closed). Check the broker service at " +
            state.runtimeDir,
          );
        }
        const client = path.join(layoutNow.libDir, CLIENT_SCRIPT);
        input.command =
          `python3 ${client}` +
          ` --registry ${state.runtimeDir}` +
          ` --session ${String(call?.sessionID ?? "")}` +
          ` --agent ${agent}` +
          ` exec ${quoteSingle(input.command)}`;
        audit(state, { decision: "broker", tool, agent, session: call?.sessionID });
        return;
      }
    });

    return () => states.delete(state);
  },
};

export default guard;
