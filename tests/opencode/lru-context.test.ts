import assert from "node:assert/strict"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import lruContextFactory from "../../opencode/.config/opencode/plugin/lru-context.ts"

const TRANSFORM_HOOK = "experimental.chat.messages.transform"
const CHAT_PARAMS_HOOK = "chat.params"
const SESSION_ID = "lru-harness-session"
const SESSION_ID_B = "lru-harness-session-b"
const BASH_TOOL = "bash"
const READ_TOOL = "read"
const TOMBSTONE_MARKER = "[lru-evicted]"
const TOMBSTONE_SUFFIX = " was evicted to reclaim context; re-run the tool to reload its output."
const SMALL_TEXT_CHARS = 60
const SMALL_TOOL_OUTPUT_CHARS = 256
const CHARS_PER_TOKEN = 4
const WATERMARK_RATIO = 0.5
const DEFAULT_CONTEXT_TOKENS = 100000
const MIN_EVICTABLE_BYTES = 2048
const RECENT_WINDOW_MESSAGES = 4
const FILLER_TEXT_CHARS = 10
const RECENT_WINDOW_FILLER_MESSAGES = 4
const PATH_INPUT_KEY = "filePath"
const SECONDARY_PATH_INPUT_KEY = "path"
const WATERMARK_PROBE_CONTEXT_LIMIT = 200
const HEADROOM_TOKENS = 100
const OVER_BY_ONE_TOKENS = 1
const THREE_ENTRY_OUTPUT_BYTES = 3000
const THREE_ENTRY_COUNT = 3
const PARTIAL_DEFICIT_TOKENS = 700
const TWO_ENTRY_DEFICIT_TOKENS = 800
const COLD_OUTPUT_BYTES = 2048
const NEW_OUTPUT_BYTES = 3000
const REFRESHED_PATH = "/data/refresh.txt"
const APPEARANCE_ONLY_OUTPUT_BYTES = 10
const BASH_ENTRY_COMMAND = "rm -rf /tmp/build"
const SUBSTRING_ENTRY_COMMAND = "abcd"
const SUBSTRING_APPEARANCE_COMMAND = "echo abcd done"
const SHORT_SUBSTRING_ENTRY_COMMAND = "abc"
const SHORT_SUBSTRING_APPEARANCE_COMMAND = "abc def"
const MARKER_PADDED_CHARS = 4000
const DEFAULT_WATERMARK_CHARS = DEFAULT_CONTEXT_TOKENS * WATERMARK_RATIO * CHARS_PER_TOKEN
const FALLBACK_TRAILING_FILLER_MESSAGES = 3
const FALLBACK_EXTRA_CHARS = 1
const SMALL_CONTEXT_LIMIT = 600
const ZERO_CONTEXT_LIMIT = 0
const TEXT_BUDGET_CONTEXT_LIMIT = 1060
const EXTRA_TEXT_CHARS = 64
const UNCOMPLETED_OUTPUT_BYTES = 5000
const OVER_WATERMARK_FILLER_TEXT_CHARS = 800
const OVER_WATERMARK_FILLER_MESSAGES = 4
const SINGLE_MESSAGE_OUTPUT_BYTES = 4000
const ISOLATION_CONTEXT_LIMIT_A = 200
const ISOLATION_CONTEXT_LIMIT_B = 20000
const STANDARD_BUNDLE_CHARS = MIN_EVICTABLE_BYTES + RECENT_WINDOW_FILLER_MESSAGES * FILLER_TEXT_CHARS
const THREE_ENTRY_BUNDLE_CHARS = THREE_ENTRY_COUNT * THREE_ENTRY_OUTPUT_BYTES + RECENT_WINDOW_FILLER_MESSAGES * FILLER_TEXT_CHARS
const COLD_NEW_BUNDLE_CHARS = COLD_OUTPUT_BYTES + NEW_OUTPUT_BYTES + RECENT_WINDOW_FILLER_MESSAGES * FILLER_TEXT_CHARS
const GREP_TOOL = "grep"
const RANGE_PATH = "/data/range.txt"
const READ_OFFSET_LINES = 100
const READ_LIMIT_LINES = 50
const PATTERN_QUERY = "parseConfig"
const INCLUDE_GLOB = "*.ts"
const INCLUDE_NUMERIC = 42
const RANGED_ENTRY_OFFSET = 10
const RANGED_ENTRY_LIMIT = 20
const PATTERN_INPUT_KEY = "pattern"
const INCLUDE_INPUT_KEY = "include"
const OFFSET_INPUT_KEY = "offset"
const LIMIT_INPUT_KEY = "limit"
const HINT_MARKER = "[lru-hot]"
const HINT_LABEL = "recently active:"
const HINT_SUBJECT_SEPARATOR = ", "
const HINT_TEST_SUBJECT_CAP = 2
const HINT_DEFAULT_ENTRY_COUNT = 11
const DEFAULT_HINT_SUBJECT_COUNT = 10
const REPEAT_TRANSFORM_COUNT = 3
const NEGATIVE_HINT_SUBJECTS = -1
const SYSTEM_HOOK = "experimental.chat.system.transform"
const BASE_SYSTEM_BLOCK = "base system prompt block"
const SYSTEM_BLOCK_COUNT_WITH_HINT = 2
const LEGACY_HINT_SUBJECT = "/data/legacy.txt"
const HINT_SESSION_BOUND = 8
const HINT_SESSION_OVERFLOW_COUNT = 9
const FOREIGN_HINT_BLOCK_TAIL = "foreign config block"
const USER_TEXT_AFTER_BARE_MARKER = "plain user note"
const NO_SESSION_HINT_PATH = "/data/no-session-hint.txt"
const SYSTEM_GUARD_HINT_PATH = "/data/system-guard.txt"
const SYSTEM_GUARD_NON_ARRAY_VALUE = "not a block array"
const RELOAD_TOOL_NAME = "read_evicted"
const RELOAD_TOOL_MAP_KEY = "tool"
const RELOAD_POINTER_LEAD = " Evicted output stashed; reload it with"
const STASH_MARKER = "[lru-stash]"
const STASH_OLDER_LEAD = "older matches for subject"
const STASH_MESSAGE_LABEL = "at message"
const STASH_MATCH_SEPARATOR = "; "
const STASH_MISS_LEAD = "no stashed output for subject"
const STASH_MISS_HINT = "only outputs evicted during this session are stashed"
const STASH_INVALID_SUBJECT_LEAD = "requires a non-empty subject string"
const RECEIVED_LABEL = "received"
const UNKNOWN_TARGET_LABEL = "unknown target"
const STASH_LIMIT = 50
const STASH_OVERFLOW_COUNT = 51
const INVALID_SUBJECT_VALUE = 42
const STASH_ISOLATION_SUBJECT = "/data/shared-stash.txt"
const STASH_ISOLATION_SESSION_C = "lru-harness-session-c"
const DEDUP_MARKER = "[lru-deduped]"
const DEDUP_SUPERSEDED_LEAD = "identical call superseded by the newer output at message"
const DEDUP_PATH = "/data/dedup.txt"
const DEDUP_ENCODING_KEY = "encoding"
const DEDUP_ENCODING_VALUE = "utf-8"
const DEDUP_NESTED_TOP_KEY = "opts"
const DEDUP_NESTED_KEY_LATE = "z"
const DEDUP_NESTED_KEY_EARLY = "a"
const DEDUP_LEAF_KEY_LATE = "y"
const DEDUP_LEAF_KEY_EARLY = "b"
const DEDUP_NESTED_TOP_VALUE = 1
const DEDUP_LEAF_VALUE_LATE = 2
const DEDUP_LEAF_VALUE_EARLY = 3
const PURGE_MARKER = "[lru-purged-input]"
const PURGE_ERROR_PATH = "/data/errored-purge.txt"
const PURGE_BOUNDARY_PATH = "/data/boundary-purge.txt"
const PURGE_PENDING_PATH = "/data/pending-purge.txt"
const PURGE_COMPLETED_PATH = "/data/completed-purge.txt"
const TASK_TOOL = "task"
const TODOWRITE_TOOL = "todowrite"
const PROTECTED_OUTPUT_BYTES = 3000
const PROTECTED_PRESSURE_SIBLING_PATH = "/data/pressure-sibling.txt"
const OVERRIDE_PROTECTED_PATH = "/data/override-protected.txt"
const INVALID_PROTECTED_TOOLS_VALUE = "todowrite"
const INVALID_PROTECTED_TOOLS_ENTRY = 42
const EMPTY_PROTECTED_TOOLS_ENTRY = ""
const STASH_PROTECTED_PATTERN = "protectedStashQuery"
const STASH_PROTECTED_VICTIM_PATH = "/data/stash-protected-victim.txt"
const PROTECTED_TASK_PROMPT = "summarize subagent findings"
const HINT_PROTECTED_COMMAND = "deploy --target staging"
const PROTECTED_PRESSURE_BUNDLE_CHARS =
  PROTECTED_OUTPUT_BYTES * 2 + RECENT_WINDOW_FILLER_MESSAGES * FILLER_TEXT_CHARS
const PROTECTED_PRESSURE_DEFICIT_TOKENS = PROTECTED_OUTPUT_BYTES / CHARS_PER_TOKEN
const STASH_SESSION_BOUND = 8
const STASH_SESSION_OVERFLOW_COUNT = 9
const STASH_MISS_PROBE_SUBJECT = "/data/stash-probe-miss.txt"
const LIMIT_SESSION_BOUND = 8
const LIMIT_SESSION_OVERFLOW_COUNT = 9
const RENDERED_SUBJECT_CAP = 160
const ELLIPSIS_MARKER = "…"
const HEREDOC_LINE = "printf segment\n"
const HEREDOC_LINE_REPEAT = 200
const HEREDOC_COMMAND = HEREDOC_LINE.repeat(HEREDOC_LINE_REPEAT)

const hintLineFor = (subjects: string[]): string =>
  `${HINT_MARKER} ${HINT_LABEL} ${subjects.join(HINT_SUBJECT_SEPARATOR)}`

type TextPart = { type: "text"; text: string }

type CompletedToolPart = {
  type: "tool"
  tool: string
  state: { status: "completed"; input: Record<string, unknown>; output: string }
}

type PendingToolPart = {
  type: "tool"
  tool: string
  state: { status: "pending"; input: Record<string, unknown>; output: string }
}

type ErrorToolPart = {
  type: "tool"
  tool: string
  state: { status: "error"; input: Record<string, unknown>; output: string }
}

type MessagePart = TextPart | CompletedToolPart | PendingToolPart | ErrorToolPart

type StatefulToolPart = { state: { input: unknown } }

type Message = {
  info: { sessionID?: string }
  parts: Array<Record<string, unknown>>
}

type MessageBundle = { messages: Message[] }

type StrictMessage = { info: { sessionID?: string }; parts: MessagePart[] }

type StrictBundle = { messages: StrictMessage[] }

type HookMap = Record<string, (input: unknown, output: unknown) => Promise<unknown>>

type ReloadToolDefinition = { execute: (args: unknown, context: unknown) => Promise<unknown> }

const textPart = (text: string): TextPart => ({ type: "text", text })

const completedToolPart = (tool: string, input: Record<string, unknown>, output: string): CompletedToolPart => ({
  type: "tool",
  tool,
  state: { status: "completed", input, output },
})

const syntheticMessage = (parts: MessagePart[]): Message => ({
  info: { sessionID: SESSION_ID },
  parts,
})

const buildSmallBundle = (): MessageBundle => ({
  messages: [
    syntheticMessage([textPart("m".repeat(SMALL_TEXT_CHARS))]),
    syntheticMessage([completedToolPart(BASH_TOOL, { command: "echo ok" }, "o".repeat(SMALL_TOOL_OUTPUT_CHARS))]),
  ],
})

const loadPluginHooks = async (): Promise<HookMap> => (await lruContextFactory({}, { metricsLog: false })) as HookMap

const loadPluginHooksWith = async (options: Record<string, unknown>): Promise<HookMap> =>
  (await lruContextFactory({}, { metricsLog: false, ...options })) as HookMap

type HintPartRef = { messageIndex: number; partIndex: number; text: string }

const hintPartsIn = (bundle: StrictBundle): HintPartRef[] => {
  const found: HintPartRef[] = []
  bundle.messages.forEach((message, messageIndex) => {
    message.parts.forEach((part, partIndex) => {
      const text = part["text"]
      if (part["type"] === "text" && typeof text === "string" && text.startsWith(HINT_MARKER)) {
        found.push({ messageIndex, partIndex, text })
      }
    })
  })
  return found
}

const runSystemTransform = async (
  hooks: HookMap,
  sessionID: string | undefined,
  blocks: string[] = [],
): Promise<string[]> => {
  const output: { system: string[] } = { system: blocks }
  await hooks[SYSTEM_HOOK]({ sessionID }, output)
  return blocks
}

const hintBlocksIn = (blocks: string[]): string[] => blocks.filter((block) => block.startsWith(HINT_MARKER))

const totalPartCount = (bundle: StrictBundle): number =>
  bundle.messages.reduce((count, message) => count + message.parts.length, 0)

const outputOfBytes = (bytes: number): string => "x".repeat(bytes)

const textOfChars = (chars: number): string => "t".repeat(chars)

const pendingToolPart = (tool: string, input: Record<string, unknown>, output: string): PendingToolPart => ({
  type: "tool",
  tool,
  state: { status: "pending", input, output },
})

const errorToolPart = (tool: string, input: Record<string, unknown>, output: string): ErrorToolPart => ({
  type: "tool",
  tool,
  state: { status: "error", input, output },
})

const pathToolPart = (path: string, outputBytes: number): CompletedToolPart =>
  completedToolPart(READ_TOOL, { [PATH_INPUT_KEY]: path }, outputOfBytes(outputBytes))

const bashToolPart = (command: string, outputBytes: number): CompletedToolPart =>
  completedToolPart(BASH_TOOL, { command }, outputOfBytes(outputBytes))

const textMessages = (count: number, chars: number): MessagePart[][] =>
  Array.from({ length: count }, () => [textPart(textOfChars(chars))])

const fillerMessages = (count: number = RECENT_WINDOW_FILLER_MESSAGES): MessagePart[][] =>
  textMessages(count, FILLER_TEXT_CHARS)

const syntheticMessageFor = (sessionID: string, parts: MessagePart[]): StrictMessage => ({
  info: { sessionID },
  parts,
})

const buildBundle = (partsPerMessage: MessagePart[][], sessionID: string = SESSION_ID): StrictBundle => ({
  messages: partsPerMessage.map((parts) => syntheticMessageFor(sessionID, parts)),
})

const buildStandardBundle = (sessionID: string, path: string): StrictBundle =>
  buildBundle([[pathToolPart(path, MIN_EVICTABLE_BYTES)], ...fillerMessages()], sessionID)

const buildOverWatermarkProtectedBundle = (tool: string): StrictBundle =>
  buildBundle([[completedToolPart(tool, {}, outputOfBytes(MIN_EVICTABLE_BYTES))], ...fillerMessages()])

const FALLBACK_BUNDLE_LARGE_TEXT_CHARS =
  DEFAULT_WATERMARK_CHARS - MIN_EVICTABLE_BYTES - FALLBACK_TRAILING_FILLER_MESSAGES * FILLER_TEXT_CHARS

const buildFallbackBudgetBundle = (largeTextChars: number): StrictBundle =>
  buildBundle([
    [pathToolPart("/data/default.txt", MIN_EVICTABLE_BYTES)],
    [textPart(textOfChars(largeTextChars))],
    ...fillerMessages(FALLBACK_TRAILING_FILLER_MESSAGES),
  ])

const toolPartAt = (message: StrictMessage, partIndex: number): CompletedToolPart =>
  message.parts[partIndex] as CompletedToolPart

const inputAt = (message: StrictMessage): unknown => (message.parts[0] as StatefulToolPart).state.input

const tokensForChars = (chars: number): number => Math.ceil(chars / CHARS_PER_TOKEN)

const contextForWatermarkTokens = (watermarkTokens: number): number => watermarkTokens / WATERMARK_RATIO

const contextForDeficit = (bundleChars: number, deficitTokens: number): number =>
  contextForWatermarkTokens(tokensForChars(bundleChars) - deficitTokens)

const setContextLimit = async (hooks: HookMap, sessionID: string, contextTokens: number): Promise<void> => {
  await hooks[CHAT_PARAMS_HOOK]({ sessionID, model: { limit: { context: contextTokens } } }, {})
}

const setChatParamsWithoutContext = async (hooks: HookMap, sessionID: string): Promise<void> => {
  await hooks[CHAT_PARAMS_HOOK]({ sessionID }, {})
}

const setChatParamsWithZeroContext = async (hooks: HookMap, sessionID: string): Promise<void> => {
  await hooks[CHAT_PARAMS_HOOK]({ sessionID, model: { limit: { context: ZERO_CONTEXT_LIMIT } } }, {})
}

const runTransform = async (hooks: HookMap, bundle: StrictBundle): Promise<void> => {
  await hooks[TRANSFORM_HOOK]({}, bundle)
}

const reloadPointerFor = (subject: string): string =>
  `${RELOAD_POINTER_LEAD} ${RELOAD_TOOL_NAME} (subject "${subject}").`

const stashMissFor = (subject: string): string =>
  `${STASH_MARKER} ${STASH_MISS_LEAD} "${subject}"; ${STASH_MISS_HINT}.`

const invalidSubjectMissFor = (received: string): string =>
  `${STASH_MARKER} ${RELOAD_TOOL_NAME} ${STASH_INVALID_SUBJECT_LEAD} (${RECEIVED_LABEL} ${received}).`

const olderMatchesLineFor = (subject: string, pointers: string[]): string =>
  `${STASH_MARKER} ${STASH_OLDER_LEAD} "${subject}": ${pointers.join(STASH_MATCH_SEPARATOR)}`

const pointerFor = (tool: string, msgIndex: number): string => `${tool} ${STASH_MESSAGE_LABEL} ${msgIndex}`

const dedupTombstoneFor = (tool: string, msgIndex: number): string =>
  `${DEDUP_MARKER} ${tool} ${DEDUP_SUPERSEDED_LEAD} ${msgIndex}`

const readEvicted = async (hooks: HookMap, subject: unknown, sessionID: string): Promise<unknown> =>
  (hooks as Record<string, Record<string, ReloadToolDefinition>>)[RELOAD_TOOL_MAP_KEY][RELOAD_TOOL_NAME].execute(
    { subject },
    { sessionID },
  )

test("experimental.chat.messages.transform accepts a small synthetic bundle without error and leaves it untouched", async () => {
  const hooks = await loadPluginHooks()
  const transform = hooks[TRANSFORM_HOOK]
  assert.equal(typeof transform, "function")

  const bundle = buildSmallBundle()
  const snapshot = structuredClone(bundle)
  await transform({}, bundle)

  assert.deepEqual(bundle, snapshot)
})

test("transform leaves every output untouched when the estimate equals the watermark exactly", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, 0))

  const bundle = buildStandardBundle(SESSION_ID, "/data/a.txt")
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform leaves every output untouched when the estimate sits under the watermark", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(
    hooks,
    SESSION_ID,
    contextForWatermarkTokens(tokensForChars(STANDARD_BUNDLE_CHARS) + HEADROOM_TOKENS),
  )

  const bundle = buildStandardBundle(SESSION_ID, "/data/a.txt")
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform evicts the coldest output when the estimate exceeds the watermark by one token", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const bundle = buildStandardBundle(SESSION_ID, "/data/a.txt")
  await runTransform(hooks, bundle)

  const evicted = toolPartAt(bundle.messages[0], 0).state.output
  assert.ok(evicted.startsWith(TOMBSTONE_MARKER))
  assert.ok(evicted.includes("(2048 bytes,"))
})

test("transform evicts only the coldest entry when one eviction covers the deficit", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(THREE_ENTRY_BUNDLE_CHARS, PARTIAL_DEFICIT_TOKENS))

  const bundle = buildBundle([
    [pathToolPart("/data/a.txt", THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/b.txt", THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/c.txt", THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(bundle.messages[1], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.equal(toolPartAt(bundle.messages[2], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform evicts multiple entries until the deficit is covered and keeps the newest entry", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(THREE_ENTRY_BUNDLE_CHARS, TWO_ENTRY_DEFICIT_TOKENS))

  const bundle = buildBundle([
    [pathToolPart("/data/a.txt", THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/b.txt", THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/c.txt", THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.ok(toolPartAt(bundle.messages[1], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(bundle.messages[2], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform evicts the coldest entry first when over watermark regardless of output size", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(
    hooks,
    SESSION_ID,
    contextForDeficit(COLD_NEW_BUNDLE_CHARS, tokensForChars(COLD_OUTPUT_BYTES)),
  )

  const bundle = buildBundle([
    [pathToolPart("/data/cold.txt", COLD_OUTPUT_BYTES)],
    [pathToolPart("/data/new.txt", NEW_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(bundle.messages[1], 0).state.output, outputOfBytes(NEW_OUTPUT_BYTES))
})

test("transform evicts the larger output first when entries share the same last touch", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(
    hooks,
    SESSION_ID,
    contextForDeficit(COLD_NEW_BUNDLE_CHARS, tokensForChars(COLD_OUTPUT_BYTES)),
  )

  const bundle = buildBundle([
    [pathToolPart("/data/small.txt", COLD_OUTPUT_BYTES), pathToolPart("/data/large.txt", NEW_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(COLD_OUTPUT_BYTES))
  assert.ok(toolPartAt(bundle.messages[0], 1).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform protects a path output refreshed by a later tool call on the same path", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart(REFRESHED_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(1),
    [pathToolPart(REFRESHED_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(bundle.messages[2], 0).state.output, outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES))
})

test("transform refreshes a path output last touch to the message index of the later call", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart(REFRESHED_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(1),
    [pathToolPart(REFRESHED_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(4),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read ${REFRESHED_PATH} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(REFRESHED_PATH)}`,
  )
})

test("transform refreshes a bash entry last touch on exact command match", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [bashToolPart(BASH_ENTRY_COMMAND, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
    [bashToolPart(BASH_ENTRY_COMMAND, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(4),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} bash ${BASH_ENTRY_COMMAND} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(BASH_ENTRY_COMMAND)}`,
  )
})

test("transform refreshes a bash entry via substring match when the entry subject exceeds three characters", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [bashToolPart(SUBSTRING_ENTRY_COMMAND, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
    [bashToolPart(SUBSTRING_APPEARANCE_COMMAND, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(1),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES))
})

test("transform evicts a bash entry when the substring match is blocked at exactly three characters", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [bashToolPart(SHORT_SUBSTRING_ENTRY_COMMAND, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
    [bashToolPart(SHORT_SUBSTRING_APPEARANCE_COMMAND, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(1),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} bash ${SHORT_SUBSTRING_ENTRY_COMMAND} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(SHORT_SUBSTRING_ENTRY_COMMAND)}`,
  )
})

test("transform never evicts an entry whose last touch sits at the recent window boundary", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
    [pathToolPart("/data/old.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/hot.txt", MIN_EVICTABLE_BYTES)],
    ...fillerMessages(RECENT_WINDOW_MESSAGES - 1),
  ])
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[RECENT_WINDOW_MESSAGES + 1], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(
    toolPartAt(bundle.messages[RECENT_WINDOW_MESSAGES + 2], 0).state.output,
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
})

test("transform never evicts outputs one byte below the size floor", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([[pathToolPart("/data/floor.txt", MIN_EVICTABLE_BYTES - 1)], ...fillerMessages()])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES - 1))
})

test("transform evicts outputs exactly at the size floor", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildStandardBundle(SESSION_ID, "/data/floor.txt")
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read /data/floor.txt (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor("/data/floor.txt")}`,
  )
})

test("transform writes a tombstone naming the tool first subject byte count and message age", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        { [PATH_INPUT_KEY]: "/data/first.txt", [SECONDARY_PATH_INPUT_KEY]: "/data/second.txt" },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  const output = toolPartAt(bundle.messages[0], 0).state.output
  assert.equal(output, `${TOMBSTONE_MARKER} read /data/first.txt (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor("/data/first.txt")}`)
  assert.ok(!output.includes("/data/second.txt"))
})

test("transform writes unknown target into the tombstone for an entry without subjects", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [completedToolPart(READ_TOOL, {}, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read unknown target (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(UNKNOWN_TARGET_LABEL)}`,
  )
})

test("transform skips outputs already starting with the eviction marker", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const markedOutput = `${TOMBSTONE_MARKER}${"z".repeat(MARKER_PADDED_CHARS)}`
  const bundle = buildBundle([
    [completedToolPart(READ_TOOL, { [PATH_INPUT_KEY]: "/data/already.txt" }, markedOutput)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, markedOutput)
})

test("transform leaves tombstones unchanged on a second transform pass", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart("/data/a.txt", THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/b.txt", THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)
  const afterFirstPass = structuredClone(bundle)
  await runTransform(hooks, bundle)

  assert.deepEqual(bundle, afterFirstPass)
  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.ok(toolPartAt(bundle.messages[1], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform applies the chat params context limit instead of the default budget", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, SMALL_CONTEXT_LIMIT)

  const limited = buildStandardBundle(SESSION_ID, "/data/limited.txt")
  const fallback = buildStandardBundle(SESSION_ID_B, "/data/fallback.txt")
  await runTransform(hooks, fallback)
  await runTransform(hooks, limited)

  assert.ok(toolPartAt(limited.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(fallback.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform keeps an unregistered session bundle intact at exactly the default watermark", async () => {
  const hooks = await loadPluginHooks()
  const bundle = buildFallbackBudgetBundle(FALLBACK_BUNDLE_LARGE_TEXT_CHARS)
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform evicts an unregistered session bundle one token over the default watermark", async () => {
  const hooks = await loadPluginHooks()
  const bundle = buildFallbackBudgetBundle(FALLBACK_BUNDLE_LARGE_TEXT_CHARS + FALLBACK_EXTRA_CHARS)
  await runTransform(hooks, bundle)

  const evicted = toolPartAt(bundle.messages[0], 0).state.output
  assert.ok(evicted.startsWith(TOMBSTONE_MARKER))
  assert.ok(evicted.includes("(2048 bytes,"))
})

test("transform falls back to the default budget when chat params carry no context limit", async () => {
  const hooks = await loadPluginHooks()
  await setChatParamsWithoutContext(hooks, SESSION_ID)

  const bundle = buildFallbackBudgetBundle(FALLBACK_BUNDLE_LARGE_TEXT_CHARS + FALLBACK_EXTRA_CHARS)
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform keeps a stored real context limit when a later chat params event carries none", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)
  await setChatParamsWithoutContext(hooks, SESSION_ID)

  const bundle = buildStandardBundle(SESSION_ID, "/data/retained-limit.txt")
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform keeps a stored real context limit when a later chat params event carries a zero limit", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)
  await setChatParamsWithZeroContext(hooks, SESSION_ID)

  const bundle = buildStandardBundle(SESSION_ID, "/data/retained-limit-zero.txt")
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform keeps session budgets isolated across repeated transforms with no cross talk", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, ISOLATION_CONTEXT_LIMIT_A)
  await setContextLimit(hooks, SESSION_ID_B, ISOLATION_CONTEXT_LIMIT_B)

  const sessionB = buildStandardBundle(SESSION_ID_B, "/data/shared.txt")
  const sessionA = buildStandardBundle(SESSION_ID, "/data/shared.txt")
  await runTransform(hooks, sessionB)
  await runTransform(hooks, sessionA)
  await runTransform(hooks, sessionB)

  assert.ok(toolPartAt(sessionA.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(sessionB.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform counts text parts toward the token estimate", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, TEXT_BUDGET_CONTEXT_LIMIT)

  const withoutExtraText = buildStandardBundle(SESSION_ID, "/data/counted.txt")
  const withExtraText = buildBundle([
    [pathToolPart("/data/counted.txt", MIN_EVICTABLE_BYTES), textPart(textOfChars(EXTRA_TEXT_CHARS))],
    ...fillerMessages(),
  ])
  await runTransform(hooks, withoutExtraText)
  await runTransform(hooks, withExtraText)

  assert.equal(toolPartAt(withoutExtraText.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.ok(toolPartAt(withExtraText.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform ignores pending and error tool outputs in the token estimate", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, TEXT_BUDGET_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart("/data/completed.txt", MIN_EVICTABLE_BYTES)],
    [pendingToolPart(READ_TOOL, { [PATH_INPUT_KEY]: "/data/pending.txt" }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: "/data/error.txt" }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal((bundle.messages[1].parts[0] as PendingToolPart).state.output, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))
  assert.equal((bundle.messages[2].parts[0] as ErrorToolPart).state.output, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))
})

test("transform never rewrites pending or error tool outputs", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pendingToolPart(READ_TOOL, { [PATH_INPUT_KEY]: "/data/pending.txt" }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: "/data/error.txt" }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...textMessages(OVER_WATERMARK_FILLER_MESSAGES, OVER_WATERMARK_FILLER_TEXT_CHARS),
  ])
  await runTransform(hooks, bundle)

  assert.equal((bundle.messages[0].parts[0] as PendingToolPart).state.output, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))
  assert.equal((bundle.messages[1].parts[0] as ErrorToolPart).state.output, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))
})

test("transform accepts an empty messages array without mutation", async () => {
  const hooks = await loadPluginHooks()
  const bundle: StrictBundle = { messages: [] }
  await runTransform(hooks, bundle)

  assert.equal(bundle.messages.length, 0)
})

test("transform leaves a single message bundle untouched despite being over watermark", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([[pathToolPart("/data/solo.txt", SINGLE_MESSAGE_OUTPUT_BYTES)]])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(SINGLE_MESSAGE_OUTPUT_BYTES))
})

test("transform renders a read range subject as path start end in the tombstone", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        { [PATH_INPUT_KEY]: RANGE_PATH, [OFFSET_INPUT_KEY]: READ_OFFSET_LINES, [LIMIT_INPUT_KEY]: READ_LIMIT_LINES },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read ${RANGE_PATH}:${READ_OFFSET_LINES}-${READ_OFFSET_LINES + READ_LIMIT_LINES} (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(`${RANGE_PATH}:${READ_OFFSET_LINES}-${READ_OFFSET_LINES + READ_LIMIT_LINES}`)}`,
  )
})

test("transform renders a grep pattern subject in the tombstone", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        GREP_TOOL,
        { [PATTERN_INPUT_KEY]: PATTERN_QUERY, [INCLUDE_INPUT_KEY]: INCLUDE_GLOB },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} grep ${PATTERN_QUERY} (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(PATTERN_QUERY)}`,
  )
})

test("transform still extracts a pattern subject when include is not a string", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        GREP_TOOL,
        { [PATTERN_INPUT_KEY]: PATTERN_QUERY, [INCLUDE_INPUT_KEY]: INCLUDE_NUMERIC },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} grep ${PATTERN_QUERY} (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(PATTERN_QUERY)}`,
  )
})

test("transform refreshes a ranged entry when a whole path call hits the same path later", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        {
          [PATH_INPUT_KEY]: REFRESHED_PATH,
          [OFFSET_INPUT_KEY]: RANGED_ENTRY_OFFSET,
          [LIMIT_INPUT_KEY]: RANGED_ENTRY_LIMIT,
        },
        outputOfBytes(MIN_EVICTABLE_BYTES),
      ),
    ],
    ...fillerMessages(1),
    [pathToolPart(REFRESHED_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(4),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read ${REFRESHED_PATH}:${RANGED_ENTRY_OFFSET}-${RANGED_ENTRY_OFFSET + RANGED_ENTRY_LIMIT} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(`${REFRESHED_PATH}:${RANGED_ENTRY_OFFSET}-${RANGED_ENTRY_OFFSET + RANGED_ENTRY_LIMIT}`)}`,
  )
})

test("transform refreshes a whole path entry when a ranged call hits the same path later", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart(REFRESHED_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(1),
    [
      completedToolPart(
        READ_TOOL,
        {
          [PATH_INPUT_KEY]: REFRESHED_PATH,
          [OFFSET_INPUT_KEY]: RANGED_ENTRY_OFFSET,
          [LIMIT_INPUT_KEY]: RANGED_ENTRY_LIMIT,
        },
        outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(4),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read ${REFRESHED_PATH} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(REFRESHED_PATH)}`,
  )
})

test("transform refreshes a pattern entry regardless of its include qualifier", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        GREP_TOOL,
        { [PATTERN_INPUT_KEY]: PATTERN_QUERY, [INCLUDE_INPUT_KEY]: INCLUDE_GLOB },
        outputOfBytes(MIN_EVICTABLE_BYTES),
      ),
    ],
    ...fillerMessages(1),
    [completedToolPart(GREP_TOOL, { [PATTERN_INPUT_KEY]: PATTERN_QUERY }, outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES))],
    ...fillerMessages(4),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} grep ${PATTERN_QUERY} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(PATTERN_QUERY)}`,
  )
})

test("transform keeps every message part byte-identical while the hint reaches the system prompt", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart("/data/older.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/newer.txt", MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
  ])
  const snapshot = structuredClone(bundle)
  await runTransform(hooks, bundle)

  assert.deepEqual(bundle, snapshot)
  assert.equal(hintPartsIn(bundle).length, 0)
  const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
  assert.equal(hintBlocksIn(blocks).length, 1)
})

test("chat system transform appends a single hint block listing live subjects most recent first", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart("/data/older.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/newer.txt", MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
  assert.equal(blocks.length, SYSTEM_BLOCK_COUNT_WITH_HINT)
  assert.equal(blocks[0], BASE_SYSTEM_BLOCK)
  assert.equal(blocks[1], hintLineFor(["/data/newer.txt", "/data/older.txt"]))
  assert.ok(!blocks[1].includes("\n"))
})

test("chat system transform replaces a prior hint block in place keeping one block", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[pathToolPart("/data/a.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const blocks = await runSystemTransform(hooks, SESSION_ID, [hintLineFor([LEGACY_HINT_SUBJECT]), BASE_SYSTEM_BLOCK])
  assert.equal(blocks.length, SYSTEM_BLOCK_COUNT_WITH_HINT)
  assert.equal(blocks[0], hintLineFor(["/data/a.txt"]))
  assert.equal(blocks[1], BASE_SYSTEM_BLOCK)
})

test("chat system transform keeps a foreign block that starts with the bare hint marker and appends the stored hint separately", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[pathToolPart("/data/a.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const foreignBlock = `${HINT_MARKER} ${FOREIGN_HINT_BLOCK_TAIL}`
  const blocks = await runSystemTransform(hooks, SESSION_ID, [foreignBlock, BASE_SYSTEM_BLOCK])

  assert.equal(blocks.length, SYSTEM_BLOCK_COUNT_WITH_HINT + 1)
  assert.equal(blocks[0], foreignBlock)
  assert.equal(blocks[1], BASE_SYSTEM_BLOCK)
  assert.equal(blocks[2], hintLineFor(["/data/a.txt"]))
})

test("chat system transform leaves the system blocks untouched for a session without a stored hint", async () => {
  const hooks = await loadPluginHooks()

  const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])

  assert.deepEqual(blocks, [BASE_SYSTEM_BLOCK])
})

test("transform strips a legacy hint text part recorded inside a message by earlier delivery", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart("/data/older.txt", MIN_EVICTABLE_BYTES)],
    [textPart(hintLineFor([LEGACY_HINT_SUBJECT]))],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(hintPartsIn(bundle).length, 0)
  const blocks = await runSystemTransform(hooks, SESSION_ID)
  assert.equal(hintBlocksIn(blocks).length, 1)
  assert.equal(blocks[0], hintLineFor(["/data/older.txt"]))
})

test("transform preserves a user text part that starts with the bare hint marker without the hint label", async () => {
  const hooks = await loadPluginHooks()
  const userText = `${HINT_MARKER} ${USER_TEXT_AFTER_BARE_MARKER}`

  const bundle = buildBundle([
    [pathToolPart("/data/older.txt", MIN_EVICTABLE_BYTES)],
    [textPart(userText)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.deepEqual(
    bundle.messages[1].parts.map((part) => part["text"]),
    [userText],
  )
})

const buildNoSessionBundle = (partsPerMessage: MessagePart[][]): StrictBundle => ({
  messages: partsPerMessage.map((parts) => ({ info: {}, parts })),
})

test("chat system transform delivers the hint stored under the no-session fallback when the system hook carries no session id", async () => {
  const hooks = await loadPluginHooks()
  await runTransform(
    hooks,
    buildNoSessionBundle([[pathToolPart(NO_SESSION_HINT_PATH, MIN_EVICTABLE_BYTES)], ...fillerMessages(2)]),
  )

  const blocks = await runSystemTransform(hooks, undefined)

  assert.equal(hintBlocksIn(blocks).length, 1)
  assert.equal(blocks[0], hintLineFor([NO_SESSION_HINT_PATH]))
})

test("chat system transform is a no-op without throwing when the system output is not an array", async () => {
  const hooks = await loadPluginHooks()
  const bundle = buildBundle([[pathToolPart(SYSTEM_GUARD_HINT_PATH, MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const output = { system: SYSTEM_GUARD_NON_ARRAY_VALUE } as unknown as { system: string[] }
  await hooks[SYSTEM_HOOK]({ sessionID: SESSION_ID }, output)

  assert.equal(output.system, SYSTEM_GUARD_NON_ARRAY_VALUE)
})

test("chat system transform caps the hint at the configured subject count keeping the most recent", async () => {
  const hooks = await loadPluginHooksWith({ hintSubjects: HINT_TEST_SUBJECT_CAP })

  const bundle = buildBundle([
    [pathToolPart("/data/a.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/b.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/c.txt", MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  const blocks = await runSystemTransform(hooks, SESSION_ID)
  const hintBlocks = hintBlocksIn(blocks)
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor(["/data/c.txt", "/data/b.txt"]))
  assert.ok(!hintBlocks[0].includes("/data/a.txt"))
})

test("chat system transform defaults the hint to ten subjects dropping older ones", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle(
    Array.from({ length: HINT_DEFAULT_ENTRY_COUNT }, (_, entryIndex) => [
      pathToolPart(`/data/hint${entryIndex}.txt`, MIN_EVICTABLE_BYTES),
    ]),
  )
  await runTransform(hooks, bundle)

  const expectedSubjects = Array.from(
    { length: DEFAULT_HINT_SUBJECT_COUNT },
    (_, offset) => `/data/hint${HINT_DEFAULT_ENTRY_COUNT - 1 - offset}.txt`,
  )
  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor(expectedSubjects))
  assert.ok(!hintBlocks[0].includes("/data/hint0.txt"))
})

test("chat system transform emits no hint block when hintSubjects is zero", async () => {
  const hooks = await loadPluginHooksWith({ hintSubjects: 0 })

  const bundle = buildBundle([[pathToolPart("/data/live.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
  assert.equal(hintBlocksIn(blocks).length, 0)
  assert.equal(blocks.length, 1)
  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("chat system transform emits no hint block when every entry is tombstoned before any hint was stored", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildStandardBundle(SESSION_ID, "/data/doomed.txt")
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
  assert.equal(hintBlocksIn(blocks).length, 0)
  assert.equal(blocks.length, 1)
})

test("transform serves the refreshed hint when the working set grows without adding message parts", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[pathToolPart("/data/a.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const firstBlocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
  assert.equal(hintBlocksIn(firstBlocks).length, 1)
  assert.equal(firstBlocks[1], hintLineFor(["/data/a.txt"]))
  const partCountAfterFirst = totalPartCount(bundle)

  bundle.messages.push(syntheticMessageFor(SESSION_ID, [pathToolPart("/data/b.txt", MIN_EVICTABLE_BYTES)]))
  await runTransform(hooks, bundle)
  const secondBlocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])

  assert.equal(hintBlocksIn(secondBlocks).length, 1)
  assert.equal(secondBlocks[1], hintLineFor(["/data/b.txt", "/data/a.txt"]))
  assert.equal(totalPartCount(bundle), partCountAfterFirst + 1)
  assert.equal(hintPartsIn(bundle).length, 0)
})

test("chat system transform keeps the last stored hint when no live subjects remain", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[pathToolPart("/data/fading.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)
  const firstHint = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(firstHint.length, 1)

  bundle.messages.push(syntheticMessageFor(SESSION_ID, [textPart(textOfChars(OVER_WATERMARK_FILLER_TEXT_CHARS))]))
  bundle.messages.push(syntheticMessageFor(SESSION_ID, [textPart(textOfChars(OVER_WATERMARK_FILLER_TEXT_CHARS))]))
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  const secondHint = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(secondHint.length, 1)
  assert.equal(secondHint[0], firstHint[0])
})

test("transform never adds message parts across repeated transforms and system deliveries", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[pathToolPart("/data/stable.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  const partCountBefore = totalPartCount(bundle)
  for (let run = 0; run < REPEAT_TRANSFORM_COUNT; run += 1) {
    await runTransform(hooks, bundle)
    const blocks = await runSystemTransform(hooks, SESSION_ID, [BASE_SYSTEM_BLOCK])
    assert.equal(hintBlocksIn(blocks).length, 1)
  }
  assert.equal(totalPartCount(bundle), partCountBefore)
  assert.equal(hintPartsIn(bundle).length, 0)
})

test("chat system transform keeps hint subjects isolated between sessions", async () => {
  const hooks = await loadPluginHooks()

  const sessionA = buildBundle([[pathToolPart("/data/from-a.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)], SESSION_ID)
  const sessionB = buildBundle([[pathToolPart("/data/from-b.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)], SESSION_ID_B)
  await runTransform(hooks, sessionA)
  await runTransform(hooks, sessionB)
  await runTransform(hooks, sessionA)

  const hintA = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintA.length, 1)
  assert.equal(hintA[0], hintLineFor(["/data/from-a.txt"]))
  const hintB = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID_B))
  assert.equal(hintB.length, 1)
  assert.equal(hintB[0], hintLineFor(["/data/from-b.txt"]))
})

test("chat system transform falls back to the default hint count when hintSubjects is negative", async () => {
  const hooks = await loadPluginHooksWith({ hintSubjects: NEGATIVE_HINT_SUBJECTS })

  const bundle = buildBundle([[pathToolPart("/data/fallback.txt", MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor(["/data/fallback.txt"]))
})

test("chat system transform renders ranged subjects with start and end in the hint block", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        { [PATH_INPUT_KEY]: RANGE_PATH, [OFFSET_INPUT_KEY]: READ_OFFSET_LINES, [LIMIT_INPUT_KEY]: READ_LIMIT_LINES },
        outputOfBytes(MIN_EVICTABLE_BYTES),
      ),
    ],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(
    hintBlocks[0],
    hintLineFor([`${RANGE_PATH}:${READ_OFFSET_LINES}-${READ_OFFSET_LINES + READ_LIMIT_LINES}`]),
  )
})

test("chat system transform lists one hint entry from the retained copy when identical calls repeat a subject", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart("/data/dup.txt", MIN_EVICTABLE_BYTES)],
    [pathToolPart("/data/dup.txt", MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor(["/data/dup.txt"]))
  assert.equal(hintBlocks[0].split("/data/dup.txt").length - 1, 1)
})

test("read_evicted returns the full original output named by the tombstone after eviction", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const original = outputOfBytes(THREE_ENTRY_OUTPUT_BYTES)
  const bundle = buildBundle([[pathToolPart("/data/stashed.txt", THREE_ENTRY_OUTPUT_BYTES)], ...fillerMessages()])
  await runTransform(hooks, bundle)

  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} read /data/stashed.txt (3000 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor("/data/stashed.txt")}`,
  )
  assert.equal(await readEvicted(hooks, "/data/stashed.txt", SESSION_ID), original)
})

test("read_evicted returns the newest match in full and one-line pointers to older matches", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([[pathToolPart("/data/dup.txt", THREE_ENTRY_OUTPUT_BYTES)], ...fillerMessages()])
  await runTransform(hooks, bundle)
  bundle.messages.push(syntheticMessageFor(SESSION_ID, [pathToolPart("/data/dup.txt", COLD_OUTPUT_BYTES)]))
  fillerMessages().forEach((parts) => bundle.messages.push(syntheticMessageFor(SESSION_ID, parts)))
  await runTransform(hooks, bundle)

  assert.equal(
    await readEvicted(hooks, "/data/dup.txt", SESSION_ID),
    `${outputOfBytes(COLD_OUTPUT_BYTES)}\n${olderMatchesLineFor("/data/dup.txt", [pointerFor(READ_TOOL, 0)])}`,
  )
})

test("read_evicted returns an error-style miss naming the subject when nothing was stashed for it", async () => {
  const hooks = await loadPluginHooks()

  assert.equal(await readEvicted(hooks, "/data/never-evicted.txt", SESSION_ID), stashMissFor("/data/never-evicted.txt"))
})

test("read_evicted evicts the oldest stashed entry when a session stash exceeds the fifty entry bound", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const stashSubjects = Array.from({ length: STASH_OVERFLOW_COUNT }, (_, index) => `/data/stash${index}.txt`)
  const bundle = buildBundle([
    ...stashSubjects.map((subject) => [pathToolPart(subject, MIN_EVICTABLE_BYTES)]),
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(await readEvicted(hooks, stashSubjects[0], SESSION_ID), stashMissFor(stashSubjects[0]))
  assert.equal(await readEvicted(hooks, stashSubjects[1], SESSION_ID), outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(await readEvicted(hooks, stashSubjects[STASH_LIMIT], SESSION_ID), outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("read_evicted keeps stashes isolated between sessions", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)
  await setContextLimit(hooks, SESSION_ID_B, WATERMARK_PROBE_CONTEXT_LIMIT)

  const sessionA = buildBundle(
    [[pathToolPart(STASH_ISOLATION_SUBJECT, COLD_OUTPUT_BYTES)], ...fillerMessages()],
    SESSION_ID,
  )
  const sessionB = buildBundle(
    [[pathToolPart(STASH_ISOLATION_SUBJECT, THREE_ENTRY_OUTPUT_BYTES)], ...fillerMessages()],
    SESSION_ID_B,
  )
  await runTransform(hooks, sessionA)
  await runTransform(hooks, sessionB)

  assert.equal(await readEvicted(hooks, STASH_ISOLATION_SUBJECT, SESSION_ID), outputOfBytes(COLD_OUTPUT_BYTES))
  assert.equal(await readEvicted(hooks, STASH_ISOLATION_SUBJECT, SESSION_ID_B), outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.equal(
    await readEvicted(hooks, STASH_ISOLATION_SUBJECT, STASH_ISOLATION_SESSION_C),
    stashMissFor(STASH_ISOLATION_SUBJECT),
  )
})

test("transform leaves no stash behind when the estimate sits under the watermark", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForWatermarkTokens(tokensForChars(STANDARD_BUNDLE_CHARS) + HEADROOM_TOKENS))

  const bundle = buildStandardBundle(SESSION_ID, "/data/kept.txt")
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(await readEvicted(hooks, "/data/kept.txt", SESSION_ID), stashMissFor("/data/kept.txt"))
})

test("read_evicted returns an error-style miss when the subject is not a non-empty string", async () => {
  const hooks = await loadPluginHooks()

  assert.equal(await readEvicted(hooks, INVALID_SUBJECT_VALUE, SESSION_ID), invalidSubjectMissFor("number"))
  assert.equal(await readEvicted(hooks, "", SESSION_ID), invalidSubjectMissFor("string"))
})

test("transform tombstones an older identical call with the dedup marker and keeps the newest output verbatim", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.ok(!toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform never re-evicts a dedup tombstone and leaves it byte-identical under eviction pressure", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart("/data/cold-dedup.txt", THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(RECENT_WINDOW_MESSAGES),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 1))
  assert.ok(toolPartAt(bundle.messages[2], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform dedups an older identical call with the estimate under the watermark and no eviction", async () => {
  const hooks = await loadPluginHooks()

  const postDedupChars =
    dedupTombstoneFor(READ_TOOL, 1).length + THREE_ENTRY_OUTPUT_BYTES + RECENT_WINDOW_FILLER_MESSAGES * FILLER_TEXT_CHARS
  await setContextLimit(hooks, SESSION_ID, contextForWatermarkTokens(tokensForChars(postDedupChars) + HEADROOM_TOKENS))

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 1))
  assert.equal(toolPartAt(bundle.messages[1], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.ok(!toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform never stashes a dedup tombstoned output so read_evicted misses it", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(3),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 1))
  assert.equal(toolPartAt(bundle.messages[1], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.equal(await readEvicted(hooks, DEDUP_PATH, SESSION_ID), stashMissFor(DEDUP_PATH))
})

test("transform lists a deduped subject once from the retained copy and never from the tombstone", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(1),
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(DEDUP_MARKER))
  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor([DEDUP_PATH]))
})

test("transform dedups identical inputs whose object keys appear in a different order", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        { [PATH_INPUT_KEY]: DEDUP_PATH, [DEDUP_ENCODING_KEY]: DEDUP_ENCODING_VALUE },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(2),
    [
      completedToolPart(
        READ_TOOL,
        { [DEDUP_ENCODING_KEY]: DEDUP_ENCODING_VALUE, [PATH_INPUT_KEY]: DEDUP_PATH },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
    ],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform dedups identical inputs with recursively reordered nested objects", async () => {
  const hooks = await loadPluginHooks()

  const nestedFirst = {
    [PATH_INPUT_KEY]: DEDUP_PATH,
    [DEDUP_NESTED_TOP_KEY]: {
      [DEDUP_NESTED_KEY_LATE]: DEDUP_NESTED_TOP_VALUE,
      [DEDUP_NESTED_KEY_EARLY]: { [DEDUP_LEAF_KEY_LATE]: DEDUP_LEAF_VALUE_LATE, [DEDUP_LEAF_KEY_EARLY]: DEDUP_LEAF_VALUE_EARLY },
    },
  }
  const nestedSecond = {
    [DEDUP_NESTED_TOP_KEY]: {
      [DEDUP_NESTED_KEY_EARLY]: { [DEDUP_LEAF_KEY_EARLY]: DEDUP_LEAF_VALUE_EARLY, [DEDUP_LEAF_KEY_LATE]: DEDUP_LEAF_VALUE_LATE },
      [DEDUP_NESTED_KEY_LATE]: DEDUP_NESTED_TOP_VALUE,
    },
    [PATH_INPUT_KEY]: DEDUP_PATH,
  }
  const bundle = buildBundle([
    [completedToolPart(READ_TOOL, nestedFirst, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    ...fillerMessages(2),
    [completedToolPart(READ_TOOL, nestedSecond, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform leaves dedup results unchanged on a second transform pass", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)
  const afterFirstPass = structuredClone(bundle)
  await runTransform(hooks, bundle)

  assert.deepEqual(bundle, afterFirstPass)
  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
})

test("transform never treats pending or error parts as dedup targets or superseders", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pendingToolPart(READ_TOOL, { [PATH_INPUT_KEY]: DEDUP_PATH }, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: DEDUP_PATH }, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal((bundle.messages[0].parts[0] as PendingToolPart).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.equal(toolPartAt(bundle.messages[1], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
  assert.equal((bundle.messages[2].parts[0] as ErrorToolPart).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform never dedups a substantial older output when the newest identical output sits below the size floor", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(1),
    [pathToolPart(DEDUP_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(bundle.messages[2], 0).state.output, outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES))
  assert.ok(!toolPartAt(bundle.messages[0], 0).state.output.startsWith(DEDUP_MARKER))
})

test("transform dedups an older duplicate when the newest identical output sits exactly at the size floor", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
    [pathToolPart(DEDUP_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(READ_TOOL, 3))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform purges the input of an errored tool part one message outside the recent window while keeping its error output", async () => {
  const hooks = await loadPluginHooks()
  const errorOutput = outputOfBytes(UNCOMPLETED_OUTPUT_BYTES)

  const bundle = buildBundle([
    ...fillerMessages(RECENT_WINDOW_MESSAGES - 1),
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_ERROR_PATH }, errorOutput)],
    ...fillerMessages(RECENT_WINDOW_MESSAGES),
  ])
  await runTransform(hooks, bundle)

  assert.equal(inputAt(bundle.messages[RECENT_WINDOW_MESSAGES - 1]), PURGE_MARKER)
  assert.equal((bundle.messages[RECENT_WINDOW_MESSAGES - 1].parts[0] as ErrorToolPart).state.output, errorOutput)
})

test("transform keeps the input of an errored tool part sitting exactly at the recent window boundary", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    ...fillerMessages(RECENT_WINDOW_MESSAGES),
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_BOUNDARY_PATH }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(RECENT_WINDOW_MESSAGES - 1),
  ])
  await runTransform(hooks, bundle)

  assert.deepEqual(inputAt(bundle.messages[RECENT_WINDOW_MESSAGES]), { [PATH_INPUT_KEY]: PURGE_BOUNDARY_PATH })
})

test("transform leaves purge results unchanged on a second transform pass", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_ERROR_PATH }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
  ])
  await runTransform(hooks, bundle)
  const afterFirstPass = structuredClone(bundle)
  await runTransform(hooks, bundle)

  assert.deepEqual(bundle, afterFirstPass)
  assert.equal(inputAt(bundle.messages[0]), PURGE_MARKER)
})

test("transform purges errored tool inputs even when the bundle sits below the watermark with no eviction pressure", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_ERROR_PATH }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
  ])
  await runTransform(hooks, bundle)

  assert.equal(inputAt(bundle.messages[0]), PURGE_MARKER)
})

test("transform never purges the input of a pending tool part outside the recent window", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pendingToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_PENDING_PATH }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
  ])
  await runTransform(hooks, bundle)

  assert.deepEqual(inputAt(bundle.messages[0]), { [PATH_INPUT_KEY]: PURGE_PENDING_PATH })
})

test("transform never purges the input of a completed tool part outside the recent window", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(PURGE_COMPLETED_PATH, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
  ])
  await runTransform(hooks, bundle)

  assert.deepEqual(toolPartAt(bundle.messages[0], 0).state.input, { [PATH_INPUT_KEY]: PURGE_COMPLETED_PATH })
  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform purges errored tool inputs identically in both sessions with no cross-session coupling", async () => {
  const hooks = await loadPluginHooks()

  const buildPurgeBundle = (sessionID: string): StrictBundle =>
    buildBundle(
      [
        [errorToolPart(READ_TOOL, { [PATH_INPUT_KEY]: PURGE_ERROR_PATH }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
        ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
      ],
      sessionID,
    )
  const sessionA = buildPurgeBundle(SESSION_ID)
  const sessionB = buildPurgeBundle(SESSION_ID_B)
  await runTransform(hooks, sessionA)
  await runTransform(hooks, sessionB)
  await runTransform(hooks, sessionA)

  assert.equal(inputAt(sessionA.messages[0]), PURGE_MARKER)
  assert.equal(inputAt(sessionB.messages[0]), PURGE_MARKER)
})

test("transform never tombstones a default protected task output under watermark pressure that evicts an unprotected sibling", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(
    hooks,
    SESSION_ID,
    contextForDeficit(PROTECTED_PRESSURE_BUNDLE_CHARS, PROTECTED_PRESSURE_DEFICIT_TOKENS),
  )

  const bundle = buildBundle([
    [completedToolPart(TASK_TOOL, {}, outputOfBytes(PROTECTED_OUTPUT_BYTES))],
    [pathToolPart(PROTECTED_PRESSURE_SIBLING_PATH, PROTECTED_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(PROTECTED_OUTPUT_BYTES))
  assert.ok(toolPartAt(bundle.messages[1], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

test("transform protects a task output from eviction by default when the estimate exceeds the watermark by one token", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const bundle = buildOverWatermarkProtectedBundle(TASK_TOOL)
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform protects a todowrite output from eviction by default when the estimate exceeds the watermark by one token", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const bundle = buildOverWatermarkProtectedBundle(TODOWRITE_TOOL)
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform honors a custom protectedTools override protecting read outputs by name", async () => {
  const hooks = await loadPluginHooksWith({ protectedTools: [READ_TOOL] })
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const bundle = buildStandardBundle(SESSION_ID, OVERRIDE_PROTECTED_PATH)
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform falls back to the default protected tools when protectedTools is invalid", async () => {
  const invalidValueHooks = await loadPluginHooksWith({ protectedTools: INVALID_PROTECTED_TOOLS_VALUE })
  const nonStringEntryHooks = await loadPluginHooksWith({
    protectedTools: [TASK_TOOL, INVALID_PROTECTED_TOOLS_ENTRY],
  })
  const emptyEntryHooks = await loadPluginHooksWith({ protectedTools: [EMPTY_PROTECTED_TOOLS_ENTRY] })
  await setContextLimit(invalidValueHooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))
  await setContextLimit(nonStringEntryHooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))
  await setContextLimit(emptyEntryHooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const invalidValueBundle = buildOverWatermarkProtectedBundle(TODOWRITE_TOOL)
  const nonStringEntryBundle = buildOverWatermarkProtectedBundle(TODOWRITE_TOOL)
  const emptyEntryBundle = buildOverWatermarkProtectedBundle(TODOWRITE_TOOL)
  await runTransform(invalidValueHooks, invalidValueBundle)
  await runTransform(nonStringEntryHooks, nonStringEntryBundle)
  await runTransform(emptyEntryHooks, emptyEntryBundle)

  assert.equal(toolPartAt(invalidValueBundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(nonStringEntryBundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(emptyEntryBundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("transform never stashes a protected output so read_evicted misses it after an eviction run under pressure", async () => {
  const hooks = await loadPluginHooksWith({ protectedTools: [GREP_TOOL] })
  await setContextLimit(
    hooks,
    SESSION_ID,
    contextForDeficit(PROTECTED_PRESSURE_BUNDLE_CHARS, PROTECTED_PRESSURE_DEFICIT_TOKENS),
  )

  const bundle = buildBundle([
    [
      completedToolPart(
        GREP_TOOL,
        { [PATTERN_INPUT_KEY]: STASH_PROTECTED_PATTERN, [INCLUDE_INPUT_KEY]: INCLUDE_GLOB },
        outputOfBytes(PROTECTED_OUTPUT_BYTES),
      ),
    ],
    [pathToolPart(STASH_PROTECTED_VICTIM_PATH, PROTECTED_OUTPUT_BYTES)],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(PROTECTED_OUTPUT_BYTES))
  assert.ok(toolPartAt(bundle.messages[1], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(await readEvicted(hooks, STASH_PROTECTED_PATTERN, SESSION_ID), stashMissFor(STASH_PROTECTED_PATTERN))
  assert.equal(await readEvicted(hooks, STASH_PROTECTED_VICTIM_PATH, SESSION_ID), outputOfBytes(PROTECTED_OUTPUT_BYTES))
})

test("transform dedups protected tool duplicates with the newest substantial output superseding the older", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [completedToolPart(TASK_TOOL, {}, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    ...fillerMessages(2),
    [completedToolPart(TASK_TOOL, {}, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, dedupTombstoneFor(TASK_TOOL, 3))
  assert.equal(toolPartAt(bundle.messages[3], 0).state.output, outputOfBytes(THREE_ENTRY_OUTPUT_BYTES))
})

test("transform purges the input of an errored protected tool part outside the recent window", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [errorToolPart(TASK_TOOL, { prompt: PROTECTED_TASK_PROMPT }, outputOfBytes(UNCOMPLETED_OUTPUT_BYTES))],
    ...fillerMessages(RECENT_WINDOW_MESSAGES + 1),
  ])
  await runTransform(hooks, bundle)

  assert.equal(inputAt(bundle.messages[0]), PURGE_MARKER)
})

test("transform lists a protected live subject in the hint line like any live subject", async () => {
  const hooks = await loadPluginHooksWith({ protectedTools: [BASH_TOOL] })

  const bundle = buildBundle([[bashToolPart(HINT_PROTECTED_COMMAND, MIN_EVICTABLE_BYTES)], ...fillerMessages(2)])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor([HINT_PROTECTED_COMMAND]))
})

const stashSessionId = (index: number): string => `lru-stash-session-${index}`

const stashSessionSubject = (index: number): string => `/data/stash-session-${index}.txt`

const stashOverflowSessionBundle = (index: number): StrictBundle =>
  buildStandardBundle(stashSessionId(index), stashSessionSubject(index))

const evictStashSession = async (hooks: HookMap, index: number): Promise<void> => {
  await setContextLimit(hooks, stashSessionId(index), WATERMARK_PROBE_CONTEXT_LIMIT)
  await runTransform(hooks, stashOverflowSessionBundle(index))
}

test("read_evicted drops the least recently active session stash when a ninth session stashes an eviction", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < STASH_SESSION_BOUND; index += 1) await evictStashSession(hooks, index)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_BOUND - 1), stashSessionId(STASH_SESSION_BOUND - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )

  await evictStashSession(hooks, STASH_SESSION_OVERFLOW_COUNT - 1)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(1), stashSessionId(1)),
    stashMissFor(stashSessionSubject(1)),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_BOUND - 1), stashSessionId(STASH_SESSION_BOUND - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_OVERFLOW_COUNT - 1), stashSessionId(STASH_SESSION_OVERFLOW_COUNT - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
})

test("read_evicted protects a refreshed hot session stash when a ninth session stashes an eviction", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < STASH_SESSION_BOUND; index += 1) await evictStashSession(hooks, index)

  await runTransform(hooks, stashOverflowSessionBundle(0))
  await evictStashSession(hooks, STASH_SESSION_OVERFLOW_COUNT - 1)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(1), stashSessionId(1)),
    stashMissFor(stashSessionSubject(1)),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_OVERFLOW_COUNT - 1), stashSessionId(STASH_SESSION_OVERFLOW_COUNT - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
})

test("read_evicted refreshes a reloading session stash so it survives when a ninth session stashes an eviction", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < STASH_SESSION_BOUND; index += 1) await evictStashSession(hooks, index)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )

  await evictStashSession(hooks, STASH_SESSION_OVERFLOW_COUNT - 1)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(1), stashSessionId(1)),
    stashMissFor(stashSessionSubject(1)),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_OVERFLOW_COUNT - 1), stashSessionId(STASH_SESSION_OVERFLOW_COUNT - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
})

test("read_evicted does not refresh a session stash on a miss probe so the probing session drops when a ninth session stashes an eviction", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < STASH_SESSION_BOUND; index += 1) await evictStashSession(hooks, index)

  assert.equal(
    await readEvicted(hooks, STASH_MISS_PROBE_SUBJECT, stashSessionId(0)),
    stashMissFor(STASH_MISS_PROBE_SUBJECT),
  )

  await evictStashSession(hooks, STASH_SESSION_OVERFLOW_COUNT - 1)

  assert.equal(
    await readEvicted(hooks, stashSessionSubject(0), stashSessionId(0)),
    stashMissFor(stashSessionSubject(0)),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(1), stashSessionId(1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
  assert.equal(
    await readEvicted(hooks, stashSessionSubject(STASH_SESSION_OVERFLOW_COUNT - 1), stashSessionId(STASH_SESSION_OVERFLOW_COUNT - 1)),
    outputOfBytes(MIN_EVICTABLE_BYTES),
  )
})

const limitSessionId = (index: number): string => `lru-limit-session-${index}`

test("chat params drops the least recently informed session limit when a ninth session stores a context limit", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < LIMIT_SESSION_BOUND; index += 1) {
    await setContextLimit(hooks, limitSessionId(index), WATERMARK_PROBE_CONTEXT_LIMIT)
  }
  await setContextLimit(hooks, limitSessionId(0), WATERMARK_PROBE_CONTEXT_LIMIT)
  await setContextLimit(hooks, limitSessionId(LIMIT_SESSION_OVERFLOW_COUNT - 1), WATERMARK_PROBE_CONTEXT_LIMIT)

  const refreshed = buildStandardBundle(limitSessionId(0), "/data/limit-refreshed.txt")
  const evicted = buildStandardBundle(limitSessionId(1), "/data/limit-evicted.txt")
  const newest = buildStandardBundle(limitSessionId(LIMIT_SESSION_OVERFLOW_COUNT - 1), "/data/limit-newest.txt")
  await runTransform(hooks, refreshed)
  await runTransform(hooks, evicted)
  await runTransform(hooks, newest)

  assert.ok(toolPartAt(refreshed.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
  assert.equal(toolPartAt(evicted.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.ok(toolPartAt(newest.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))
})

const hintSessionId = (index: number): string => `lru-hint-session-${index}`

const hintSessionSubject = (index: number): string => `/data/hint-session-${index}.txt`

const storeHintSession = async (hooks: HookMap, index: number): Promise<void> => {
  await runTransform(hooks, buildStandardBundle(hintSessionId(index), hintSessionSubject(index)))
}

test("chat system transform drops the least recently active session hint when a ninth session stores a hint", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < HINT_SESSION_BOUND; index += 1) await storeHintSession(hooks, index)

  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(0))).length, 1)
  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(HINT_SESSION_BOUND - 1))).length, 1)

  await storeHintSession(hooks, HINT_SESSION_OVERFLOW_COUNT - 1)

  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(0))).length, 1)
  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(1))).length, 0)
  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(HINT_SESSION_BOUND - 1))).length, 1)
  assert.equal(hintBlocksIn(await runSystemTransform(hooks, hintSessionId(HINT_SESSION_OVERFLOW_COUNT - 1))).length, 1)
})

const truncatedRenderOf = (raw: string): string => {
  const singleLine = raw.replaceAll("\n", " ")
  return singleLine.length > RENDERED_SUBJECT_CAP
    ? `${singleLine.slice(0, RENDERED_SUBJECT_CAP - ELLIPSIS_MARKER.length)}${ELLIPSIS_MARKER}`
    : singleLine
}

test("transform truncates a multi kilobyte heredoc subject in the tombstone and reload pointer and still reloads from the truncated name", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([[bashToolPart(HEREDOC_COMMAND, MIN_EVICTABLE_BYTES)], ...fillerMessages()])
  await runTransform(hooks, bundle)

  const truncated = truncatedRenderOf(HEREDOC_COMMAND)
  assert.equal(truncated.length, RENDERED_SUBJECT_CAP)
  assert.ok(truncated.endsWith(ELLIPSIS_MARKER))
  assert.equal(
    toolPartAt(bundle.messages[0], 0).state.output,
    `${TOMBSTONE_MARKER} bash ${truncated} (2048 bytes, ~5 messages ago)${TOMBSTONE_SUFFIX}${reloadPointerFor(truncated)}`,
  )
  assert.equal(await readEvicted(hooks, truncated, SESSION_ID), outputOfBytes(MIN_EVICTABLE_BYTES))
})

test("chat system transform renders a newline bearing heredoc subject as one truncated single line hint entry", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([[bashToolPart(HEREDOC_COMMAND, MIN_EVICTABLE_BYTES)], ...fillerMessages()])
  await runTransform(hooks, bundle)

  const hintBlocks = hintBlocksIn(await runSystemTransform(hooks, SESSION_ID))
  assert.equal(hintBlocks.length, 1)
  assert.equal(hintBlocks[0], hintLineFor([truncatedRenderOf(HEREDOC_COMMAND)]))
  assert.ok(!hintBlocks[0].includes("\n"))
})

test("transform refresh matches a huge multi line subject on its raw value despite the truncated render", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [bashToolPart(HEREDOC_COMMAND, MIN_EVICTABLE_BYTES)],
    ...fillerMessages(1),
    [bashToolPart(HEREDOC_COMMAND, APPEARANCE_ONLY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  assert.equal(toolPartAt(bundle.messages[0], 0).state.output, outputOfBytes(MIN_EVICTABLE_BYTES))
  assert.equal(toolPartAt(bundle.messages[2], 0).state.output, outputOfBytes(APPEARANCE_ONLY_OUTPUT_BYTES))
})

const COLLISION_SUBJECT_PATH = "/data/collide.txt"
const COLLISION_ENCODING_KEY = "encoding"

test("read_evicted keeps both same message same subject evictions reloadable instead of overwriting the first stash", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    [
      completedToolPart(
        READ_TOOL,
        { [PATH_INPUT_KEY]: COLLISION_SUBJECT_PATH, [COLLISION_ENCODING_KEY]: DEDUP_ENCODING_VALUE },
        outputOfBytes(THREE_ENTRY_OUTPUT_BYTES),
      ),
      pathToolPart(COLLISION_SUBJECT_PATH, COLD_OUTPUT_BYTES),
    ],
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  assert.equal(
    await readEvicted(hooks, COLLISION_SUBJECT_PATH, SESSION_ID),
    `${outputOfBytes(COLD_OUTPUT_BYTES)}\n${olderMatchesLineFor(COLLISION_SUBJECT_PATH, [pointerFor(READ_TOOL, 0)])}`,
  )
})

const STATS_TOOL_NAME = "lru_stats"
const METRICS_DIR_SEGMENTS = [".local", "share", "opencode"]
const METRICS_LOG_BASENAME = "lru-metrics.jsonl"
const DEFAULT_METRICS_PATH = join(homedir(), ...METRICS_DIR_SEGMENTS, METRICS_LOG_BASENAME)
const METRICS_TEMP_DIR_PREFIX = "lru-metrics-test-"
const METRICS_LOG_FILE_NAME = "metrics.jsonl"
const METRICS_BLOCKED_DIR_NAME = "missing-subdir"
const METRICS_LINE_SEPARATOR = "\n"
const CONTEXT_TOKENS_SOURCE_MODEL = "model"
const CONTEXT_TOKENS_SOURCE_DEFAULT = "default"
const POST_EVICT_TOUCH_PATH = "/data/post-touch.txt"
const POST_EVICT_UNMATCHED_PATH = "/data/post-touch-unmatched.txt"
const STATS_MISS_SUBJECT = "/data/stats-miss.txt"
const STATS_HIT_SUBJECT = "/data/stats-hit.txt"
const STATS_STASH_SUBJECT_PREFIX = "/data/stats-stash"
const STATS_STASH_SUBJECT_SUFFIX = ".txt"
const STATS_LOGGED_SUBJECT = "/data/logged.txt"
const STATS_RELOADED_SUBJECT = "/data/reload-logged.txt"
const STATS_UNLOGGED_SUBJECT = "/data/unlogged.txt"
const STATS_BLOCKED_SUBJECT = "/data/blocked-log.txt"
const STATS_SINGLE_EVICTION_SUBJECT = "/data/isolated-a.txt"
const STATS_ISOLATION_B_SUBJECTS = ["/data/isolated-b1.txt", "/data/isolated-b2.txt", "/data/isolated-b3.txt"]
const STATS_ISOLATION_B_EVICTED_COUNT = 2
const METRICS_SESSION_BOUND = 8
const METRICS_SESSION_OVERFLOW_COUNT = 9
const METRICS_PROBE_SESSION_ID = "lru-metrics-probe-session"
const METRICS_PROBE_MISS_SUBJECT = "/data/metrics-probe-miss.txt"
const METRICS_LINES_AFTER_RELOAD = 2
const METRICS_LINES_AFTER_RECOVERY = 1
const STATS_ZEROED_COUNTERS = {
  evictions: 0,
  bytesReclaimed: 0,
  stashHits: 0,
  stashMisses: 0,
  stashDropped: 0,
  deduped: 0,
  postEvictionTouches: 0,
}
const STATS_LOG_FILE_LINES = 1

type StatsToolDefinition = { execute: (args: unknown, context: unknown) => Promise<unknown> }

const lruStats = async (hooks: HookMap, sessionID: string): Promise<Record<string, unknown>> =>
  JSON.parse(
    (await (hooks as Record<string, Record<string, StatsToolDefinition>>)[RELOAD_TOOL_MAP_KEY][STATS_TOOL_NAME].execute(
      {},
      { sessionID },
    )) as string,
  ) as Record<string, unknown>

const countersOf = (stats: Record<string, unknown>): Record<string, number> => stats.counters as Record<string, number>

const makeMetricsDir = (): string => mkdtempSync(join(tmpdir(), METRICS_TEMP_DIR_PREFIX))

const metricsLogPathIn = (dir: string): string => join(dir, METRICS_LOG_FILE_NAME)

const blockedMetricsPathIn = (dir: string): string => join(dir, METRICS_BLOCKED_DIR_NAME, METRICS_LOG_FILE_NAME)

const cleanupMetricsDir = (dir: string): void => rmSync(dir, { recursive: true, force: true })

const loadPluginHooksWithMetricsLog = async (metricsPath: string): Promise<HookMap> =>
  loadPluginHooksWith({ metricsLog: true, metricsPath })

const metricsLinesIn = (metricsPath: string): Record<string, unknown>[] =>
  readFileSync(metricsPath, "utf8")
    .split(METRICS_LINE_SEPARATOR)
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line) as Record<string, unknown>)

const metricsSessionId = (index: number): string => `lru-metrics-session-${index}`

const metricsSessionSubject = (index: number): string => `/data/metrics-session-${index}.txt`

const storeMetricsSession = async (hooks: HookMap, index: number): Promise<void> => {
  await setContextLimit(hooks, metricsSessionId(index), WATERMARK_PROBE_CONTEXT_LIMIT)
  await runTransform(hooks, buildStandardBundle(metricsSessionId(index), metricsSessionSubject(index)))
}

test("lru_stats reports zeroed counters default budget and empty stash for a session without activity", async () => {
  const hooks = await loadPluginHooks()

  const stats = await lruStats(hooks, SESSION_ID)

  assert.equal(stats.session, SESSION_ID)
  assert.deepEqual(stats.options, {
    watermark: WATERMARK_RATIO,
    recentWindow: RECENT_WINDOW_MESSAGES,
    minEvictableBytes: MIN_EVICTABLE_BYTES,
    defaultContextTokens: DEFAULT_CONTEXT_TOKENS,
    metricsLog: false,
    metricsPath: DEFAULT_METRICS_PATH,
  })
  assert.equal(stats.modelContextTokens, DEFAULT_CONTEXT_TOKENS)
  assert.equal(stats.modelContextTokensSource, CONTEXT_TOKENS_SOURCE_DEFAULT)
  assert.deepEqual(stats.stash, { entries: 0, capacity: STASH_LIMIT })
  assert.deepEqual(countersOf(stats), STATS_ZEROED_COUNTERS)
  assert.equal(stats.lastRun, null)
  assert.equal(Object.hasOwn(stats, "logWriteError"), false)
})

test("lru_stats counts the eviction reclaimed bytes stash entry and last run deficit after one eviction run", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

  const bundle = buildStandardBundle(SESSION_ID, STATS_SINGLE_EVICTION_SUBJECT)
  await runTransform(hooks, bundle)

  const stats = await lruStats(hooks, SESSION_ID)
  assert.equal(stats.modelContextTokens, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))
  assert.equal(stats.modelContextTokensSource, CONTEXT_TOKENS_SOURCE_MODEL)
  assert.deepEqual(countersOf(stats), {
    ...STATS_ZEROED_COUNTERS,
    evictions: 1,
    bytesReclaimed: MIN_EVICTABLE_BYTES,
  })
  assert.deepEqual(stats.stash, { entries: 1, capacity: STASH_LIMIT })
  assert.deepEqual(stats.lastRun, {
    estimatedTokens: tokensForChars(STANDARD_BUNDLE_CHARS),
    watermarkTokens: tokensForChars(STANDARD_BUNDLE_CHARS) - OVER_BY_ONE_TOKENS,
    deficitTokens: OVER_BY_ONE_TOKENS,
  })
})

test("lru_stats counts stash hits and misses from read_evicted and leaves invalid subject arguments uncounted", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  assert.equal(await readEvicted(hooks, STATS_MISS_SUBJECT, SESSION_ID), stashMissFor(STATS_MISS_SUBJECT))
  assert.deepEqual(countersOf(await lruStats(hooks, SESSION_ID)), STATS_ZEROED_COUNTERS)

  const bundle = buildStandardBundle(SESSION_ID, STATS_HIT_SUBJECT)
  await runTransform(hooks, bundle)

  assert.equal(await readEvicted(hooks, STATS_MISS_SUBJECT, SESSION_ID), stashMissFor(STATS_MISS_SUBJECT))
  const afterMiss = await lruStats(hooks, SESSION_ID)
  assert.deepEqual(countersOf(afterMiss), {
    ...STATS_ZEROED_COUNTERS,
    evictions: 1,
    bytesReclaimed: MIN_EVICTABLE_BYTES,
    stashMisses: 1,
  })

  assert.equal(await readEvicted(hooks, INVALID_SUBJECT_VALUE, SESSION_ID), invalidSubjectMissFor("number"))
  assert.equal(await readEvicted(hooks, "", SESSION_ID), invalidSubjectMissFor("string"))
  const afterInvalid = await lruStats(hooks, SESSION_ID)
  assert.equal(countersOf(afterInvalid).stashMisses, 1)
  assert.equal(countersOf(afterInvalid).stashHits, 0)

  assert.equal(await readEvicted(hooks, STATS_HIT_SUBJECT, SESSION_ID), outputOfBytes(MIN_EVICTABLE_BYTES))
  const afterHit = await lruStats(hooks, SESSION_ID)
  assert.deepEqual(countersOf(afterHit), {
    ...STATS_ZEROED_COUNTERS,
    evictions: 1,
    bytesReclaimed: MIN_EVICTABLE_BYTES,
    stashHits: 1,
    stashMisses: 1,
  })
})

test("lru_stats counts a post eviction touch exactly once for a matching later call and never recounts repeated transforms", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildStandardBundle(SESSION_ID, POST_EVICT_TOUCH_PATH)
  await runTransform(hooks, bundle)
  assert.ok(toolPartAt(bundle.messages[0], 0).state.output.startsWith(TOMBSTONE_MARKER))

  bundle.messages.push(syntheticMessageFor(SESSION_ID, [pathToolPart(POST_EVICT_TOUCH_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)]))
  await runTransform(hooks, bundle)
  assert.equal(countersOf(await lruStats(hooks, SESSION_ID)).postEvictionTouches, 1)

  await runTransform(hooks, bundle)
  assert.equal(countersOf(await lruStats(hooks, SESSION_ID)).postEvictionTouches, 1)
})

test("lru_stats leaves post eviction touches at zero when a later call matches nothing evicted", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildStandardBundle(SESSION_ID, POST_EVICT_TOUCH_PATH)
  await runTransform(hooks, bundle)

  bundle.messages.push(
    syntheticMessageFor(SESSION_ID, [pathToolPart(POST_EVICT_UNMATCHED_PATH, APPEARANCE_ONLY_OUTPUT_BYTES)]),
  )
  await runTransform(hooks, bundle)

  assert.equal(countersOf(await lruStats(hooks, SESSION_ID)).postEvictionTouches, 0)
})

test("lru_stats counts dedup tombstones without counting evictions and stays incremental across repeated transforms", async () => {
  const hooks = await loadPluginHooks()

  const bundle = buildBundle([
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
    [pathToolPart(DEDUP_PATH, THREE_ENTRY_OUTPUT_BYTES)],
    ...fillerMessages(2),
  ])
  await runTransform(hooks, bundle)

  const stats = await lruStats(hooks, SESSION_ID)
  assert.equal(countersOf(stats).deduped, 1)
  assert.equal(countersOf(stats).evictions, 0)

  await runTransform(hooks, bundle)
  assert.equal(countersOf(await lruStats(hooks, SESSION_ID)).deduped, 1)
})

test("lru_stats counts stash drops when a single run evicts fifty one entries past the stash bound", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, WATERMARK_PROBE_CONTEXT_LIMIT)

  const bundle = buildBundle([
    ...Array.from(
      { length: STASH_OVERFLOW_COUNT },
      (_, index) => [pathToolPart(`${STATS_STASH_SUBJECT_PREFIX}${index}${STATS_STASH_SUBJECT_SUFFIX}`, MIN_EVICTABLE_BYTES)],
    ),
    ...fillerMessages(),
  ])
  await runTransform(hooks, bundle)

  const stats = await lruStats(hooks, SESSION_ID)
  assert.equal(countersOf(stats).evictions, STASH_OVERFLOW_COUNT)
  assert.equal(countersOf(stats).stashDropped, 1)
  assert.equal(countersOf(stats).bytesReclaimed, STASH_OVERFLOW_COUNT * MIN_EVICTABLE_BYTES)
  assert.deepEqual(stats.stash, { entries: STASH_LIMIT, capacity: STASH_LIMIT })
})

test("metrics log appends one eventful jsonl line with expected fields and nothing for a quiet repeated run", async () => {
  const metricsDir = makeMetricsDir()
  try {
    const hooks = await loadPluginHooksWithMetricsLog(metricsLogPathIn(metricsDir))
    await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

    const bundle = buildStandardBundle(SESSION_ID, STATS_LOGGED_SUBJECT)
    await runTransform(hooks, bundle)

    const lines = metricsLinesIn(metricsLogPathIn(metricsDir))
    assert.equal(lines.length, STATS_LOG_FILE_LINES)
    const line = lines[0]
    assert.equal(typeof line.ts, "string")
    assert.ok(Number.isNaN(new Date(line.ts as string).getTime()) === false)
    assert.equal(line.session, SESSION_ID)
    assert.equal(line.estimatedTokens, tokensForChars(STANDARD_BUNDLE_CHARS))
    assert.equal(line.watermarkTokens, tokensForChars(STANDARD_BUNDLE_CHARS) - OVER_BY_ONE_TOKENS)
    assert.equal(line.deficitTokens, OVER_BY_ONE_TOKENS)
    assert.deepEqual(line.evictedThisRun, [
      { tool: READ_TOOL, subject: STATS_LOGGED_SUBJECT, bytes: MIN_EVICTABLE_BYTES, messagesAgo: 5 },
    ])
    assert.equal(line.dedupedThisRun, 0)
    assert.equal(line.postEvictionTouchesThisRun, 0)
    assert.equal(line.stashReadsSinceLastLine, 0)
    assert.deepEqual(line.totals, { ...STATS_ZEROED_COUNTERS, evictions: 1, bytesReclaimed: MIN_EVICTABLE_BYTES })

    await runTransform(hooks, bundle)
    assert.equal(metricsLinesIn(metricsLogPathIn(metricsDir)).length, STATS_LOG_FILE_LINES)
  } finally {
    cleanupMetricsDir(metricsDir)
  }
})

test("metrics log records stash reads since the last line on the next transform after a reload", async () => {
  const metricsDir = makeMetricsDir()
  try {
    const hooks = await loadPluginHooksWithMetricsLog(metricsLogPathIn(metricsDir))
    await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

    const bundle = buildStandardBundle(SESSION_ID, STATS_RELOADED_SUBJECT)
    await runTransform(hooks, bundle)
    assert.equal(await readEvicted(hooks, STATS_RELOADED_SUBJECT, SESSION_ID), outputOfBytes(MIN_EVICTABLE_BYTES))

    await runTransform(hooks, bundle)
    const lines = metricsLinesIn(metricsLogPathIn(metricsDir))
    assert.equal(lines.length, METRICS_LINES_AFTER_RELOAD)
    assert.deepEqual(lines[1].evictedThisRun, [])
    assert.equal(lines[1].stashReadsSinceLastLine, 1)
    assert.deepEqual(lines[1].totals, {
      ...STATS_ZEROED_COUNTERS,
      evictions: 1,
      bytesReclaimed: MIN_EVICTABLE_BYTES,
      stashHits: 1,
    })

    await runTransform(hooks, bundle)
    assert.equal(metricsLinesIn(metricsLogPathIn(metricsDir)).length, METRICS_LINES_AFTER_RELOAD)
  } finally {
    cleanupMetricsDir(metricsDir)
  }
})

test("metrics log writes nothing when metricsLog is false while counters still update", async () => {
  const metricsDir = makeMetricsDir()
  try {
    const hooks = await loadPluginHooksWith(metricsLogPathIn(metricsDir))
    await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

    const bundle = buildStandardBundle(SESSION_ID, STATS_UNLOGGED_SUBJECT)
    await runTransform(hooks, bundle)

    assert.equal(existsSync(metricsLogPathIn(metricsDir)), false)
    assert.equal(countersOf(await lruStats(hooks, SESSION_ID)).evictions, 1)
  } finally {
    cleanupMetricsDir(metricsDir)
  }
})

test("metrics log records an unwritable path in logWriteError surfaced through lru_stats without throwing", async () => {
  const metricsDir = makeMetricsDir()
  try {
    const hooks = await loadPluginHooksWithMetricsLog(blockedMetricsPathIn(metricsDir))
    await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

    const bundle = buildStandardBundle(SESSION_ID, STATS_BLOCKED_SUBJECT)
    await runTransform(hooks, bundle)

    const stats = await lruStats(hooks, SESSION_ID)
    assert.equal(typeof stats.logWriteError, "string")
    assert.ok((stats.logWriteError as string).length > 0)
    assert.equal(countersOf(stats).evictions, 1)
  } finally {
    cleanupMetricsDir(metricsDir)
  }
})

test("lru_stats keeps metrics isolated between two sessions", async () => {
  const hooks = await loadPluginHooks()
  await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))
  await setContextLimit(hooks, SESSION_ID_B, contextForDeficit(THREE_ENTRY_BUNDLE_CHARS, TWO_ENTRY_DEFICIT_TOKENS))

  const sessionA = buildStandardBundle(SESSION_ID, STATS_SINGLE_EVICTION_SUBJECT)
  const sessionB = buildBundle(
    [
      STATS_ISOLATION_B_SUBJECTS.map((subject) => pathToolPart(subject, THREE_ENTRY_OUTPUT_BYTES)),
      ...fillerMessages(),
    ],
    SESSION_ID_B,
  )
  await runTransform(hooks, sessionB)
  await runTransform(hooks, sessionA)

  const statsA = await lruStats(hooks, SESSION_ID)
  assert.equal(statsA.session, SESSION_ID)
  assert.deepEqual(countersOf(statsA), { ...STATS_ZEROED_COUNTERS, evictions: 1, bytesReclaimed: MIN_EVICTABLE_BYTES })
  const statsB = await lruStats(hooks, SESSION_ID_B)
  assert.equal(statsB.session, SESSION_ID_B)
  assert.deepEqual(countersOf(statsB), {
    ...STATS_ZEROED_COUNTERS,
    evictions: STATS_ISOLATION_B_EVICTED_COUNT,
    bytesReclaimed: STATS_ISOLATION_B_EVICTED_COUNT * THREE_ENTRY_OUTPUT_BYTES,
  })
})

test("lru_stats drops the least recently active session metrics when a ninth session transforms", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < METRICS_SESSION_BOUND; index += 1) await storeMetricsSession(hooks, index)

  await storeMetricsSession(hooks, METRICS_SESSION_OVERFLOW_COUNT - 1)

  assert.deepEqual(countersOf(await lruStats(hooks, metricsSessionId(0))), STATS_ZEROED_COUNTERS)
  assert.equal(countersOf(await lruStats(hooks, metricsSessionId(1))).evictions, 1)
  assert.equal(countersOf(await lruStats(hooks, metricsSessionId(METRICS_SESSION_BOUND - 1))).evictions, 1)
  assert.equal(countersOf(await lruStats(hooks, metricsSessionId(METRICS_SESSION_OVERFLOW_COUNT - 1))).evictions, 1)
})

test("read_evicted leaves live session metrics untouched when a never-transformed session probes a stash miss at the session bound", async () => {
  const hooks = await loadPluginHooks()
  for (let index = 0; index < METRICS_SESSION_BOUND; index += 1) await storeMetricsSession(hooks, index)

  assert.equal(
    await readEvicted(hooks, METRICS_PROBE_MISS_SUBJECT, METRICS_PROBE_SESSION_ID),
    stashMissFor(METRICS_PROBE_MISS_SUBJECT),
  )

  assert.equal(countersOf(await lruStats(hooks, metricsSessionId(0))).evictions, 1)
  assert.equal(countersOf(await lruStats(hooks, metricsSessionId(METRICS_SESSION_BOUND - 1))).evictions, 1)
  assert.deepEqual(countersOf(await lruStats(hooks, METRICS_PROBE_SESSION_ID)), STATS_ZEROED_COUNTERS)
})

test("metrics log clears a recorded write failure once a later write succeeds", async () => {
  const metricsDir = makeMetricsDir()
  try {
    const blockedPath = blockedMetricsPathIn(metricsDir)
    const hooks = await loadPluginHooksWithMetricsLog(blockedPath)
    await setContextLimit(hooks, SESSION_ID, contextForDeficit(STANDARD_BUNDLE_CHARS, OVER_BY_ONE_TOKENS))

    const bundle = buildStandardBundle(SESSION_ID, STATS_BLOCKED_SUBJECT)
    await runTransform(hooks, bundle)
    assert.equal(typeof (await lruStats(hooks, SESSION_ID)).logWriteError, "string")

    mkdirSync(join(metricsDir, METRICS_BLOCKED_DIR_NAME), { recursive: true })
    bundle.messages.push(
      syntheticMessageFor(SESSION_ID, [pathToolPart(STATS_BLOCKED_SUBJECT, APPEARANCE_ONLY_OUTPUT_BYTES)]),
    )
    await runTransform(hooks, bundle)

    const stats = await lruStats(hooks, SESSION_ID)
    assert.equal(Object.hasOwn(stats, "logWriteError"), false)
    assert.equal(countersOf(stats).evictions, 1)
    assert.equal(countersOf(stats).postEvictionTouches, 1)
    assert.equal(metricsLinesIn(blockedPath).length, METRICS_LINES_AFTER_RECOVERY)
  } finally {
    cleanupMetricsDir(metricsDir)
  }
})
