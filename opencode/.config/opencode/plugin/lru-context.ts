import { appendFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import type { Plugin } from "@opencode-ai/plugin"

const EVICTION_MARKER = "[lru-evicted]"
const HINT_MARKER = "[lru-hot]"
const HINT_LABEL = "recently active:"
const HINT_LINE_PREFIX = `${HINT_MARKER} ${HINT_LABEL}`
const SUBJECT_SEPARATOR = ", "
const MAX_RENDERED_SUBJECT_CHARS = 160
const ELLIPSIS_MARKER = "…"
const CHARS_PER_TOKEN = 4
const DEFAULT_WATERMARK_RATIO = 0.5
const DEFAULT_RECENT_WINDOW_MESSAGES = 4
const DEFAULT_MIN_EVICTABLE_BYTES = 2048
const DEFAULT_CONTEXT_TOKENS = 100000
const DEFAULT_HINT_SUBJECTS = 10
const DEFAULT_PROTECTED_TOOLS = ["task", "todowrite"]
const PATH_INPUT_KEYS = ["filePath", "path", "file", "directory"]
const BASH_TOOL_NAME = "bash"
const COMMAND_INPUT_KEY = "command"
const OFFSET_INPUT_KEY = "offset"
const LIMIT_INPUT_KEY = "limit"
const PATTERN_INPUT_KEY = "pattern"
const MIN_SUBJECT_LENGTH_FOR_SUBSTRING_MATCH = 3
const UNKNOWN_TARGET_LABEL = "unknown target"
const PATH_RANGE_SEPARATOR = ":"
const RANGE_SEPARATOR = "-"
const DEFAULT_STASH_LIMIT = 50
const MAX_STASH_SESSIONS = 8
const MAX_LIMIT_SESSIONS = 8
const MAX_HINT_SESSIONS = 8
const RELOAD_TOOL_NAME = "read_evicted"
const RELOAD_ARG_NAME = "subject"
const RELOAD_TOOL_DESCRIPTION =
  "Return the full original output of a tool call that was evicted by the LRU context manager. Pass the subject exactly as it appears in the eviction notice."
const RELOAD_ARG_DESCRIPTION = "The subject exactly as named in the eviction notice"
const RELOAD_ARG_SCHEMA_TYPE = "string"
const RELOAD_ARG_SCHEMA: Record<string, string> = {
  type: RELOAD_ARG_SCHEMA_TYPE,
  description: RELOAD_ARG_DESCRIPTION,
}
const RELOAD_POINTER_LEAD = " Evicted output stashed; reload it with"
const STASH_MARKER = "[lru-stash]"
const STASH_OLDER_LEAD = "older matches for subject"
const STASH_MESSAGE_LABEL = "at message"
const STASH_MATCH_SEPARATOR = "; "
const STASH_MISS_LEAD = "no stashed output for subject"
const STASH_MISS_HINT = "only outputs evicted during this session are stashed"
const STASH_INVALID_SUBJECT_LEAD = "requires a non-empty subject string"
const RECEIVED_LABEL = "received"
const FALLBACK_SESSION_KEY = "no-session"
const DEDUP_MARKER = "[lru-deduped]"
const DEDUP_SUPERSEDED_LEAD = "identical call superseded by the newer output at message"
const PURGED_INPUT_MARKER = "[lru-purged-input]"
const MAX_METRICS_SESSIONS = 8
const MAX_REMEMBERED_EVICTED_SUBJECTS = 100
const TOUCH_SCAN_INITIAL_WATERMARK = -1
const DEFAULT_METRICS_LOG_ENABLED = true
const METRICS_DIR_SEGMENTS = [".local", "share", "opencode"]
const METRICS_FILE_BASENAME = "lru-metrics.jsonl"
const DEFAULT_METRICS_PATH = join(homedir(), ...METRICS_DIR_SEGMENTS, METRICS_FILE_BASENAME)
const STATS_TOOL_NAME = "lru_stats"
const STATS_TOOL_DESCRIPTION =
  "Return live metrics for the LRU context manager in this session: eviction counters, post-eviction touches, stash occupancy, the effective context budget, and the most recent transform run's token estimate."
const JSON_INDENT_SPACES = 2
const CONTEXT_TOKENS_SOURCE_MODEL = "model"
const CONTEXT_TOKENS_SOURCE_DEFAULT = "default"

type LruContextOptions = {
  watermark?: number
  recentWindow?: number
  minEvictableBytes?: number
  defaultContextTokens?: number
  hintSubjects?: number
  protectedTools?: string[]
  metricsLog?: boolean
  metricsPath?: string
}

type ResolvedOptions = Required<LruContextOptions>

type SubjectRange = { start: number; end: number }

type Subject = {
  path: string
  range?: SubjectRange
}

type ToolAppearance = {
  msgIndex: number
  tool: string
  subjects: Subject[]
}

type EvictableEntry = {
  stateRef: { output: string }
  tool: string
  msgIndex: number
  partIndex: number
  lastTouch: number
  bytes: number
  subjects: Subject[]
}

type HotSubject = { subject: Subject; lastTouch: number }

type EvictionResult = {
  hotSubjects: HotSubject[]
  appearances: ToolAppearance[]
  estimatedTokens: number
  watermarkTokens: number
  deficitTokens: number
  evicted: EvictedEntryInfo[]
  stashDropped: number
}

type EvictedEntryInfo = {
  tool: string
  subject: string
  subjects: Subject[]
  bytes: number
  messagesAgo: number
}

type LastRunMetrics = { estimatedTokens: number; watermarkTokens: number; deficitTokens: number }

type SessionMetrics = {
  evictions: number
  bytesReclaimed: number
  stashHits: number
  stashMisses: number
  stashDropped: number
  deduped: number
  postEvictionTouches: number
  evictedSubjects: Subject[]
  touchScanThrough: number
  stashReadsLoggedThrough: number
  lastRun?: LastRunMetrics
  logWriteError?: string
}

type MetricsStore = Map<string, SessionMetrics>

type StatsSource = {
  options: ResolvedOptions
  limits: Map<string, number>
  stashes: StashStore
  metrics: MetricsStore
}

type RetainedDuplicate = { msgIndex: number; tool: string; supersedes: boolean }

type DedupTarget = { stateRef: { output: string }; tool: string; input: Record<string, unknown> }

type MessageBundle = {
  info: { sessionID?: string }
  parts: Array<Record<string, unknown>>
}

type StashEntry = {
  output: string
  tool: string
  subject: string
  msgIndex: number
  partIndex: number
}

type SessionStash = Map<string, StashEntry>

type StashStore = Map<string, SessionStash>

const resolveOptions = (raw: LruContextOptions = {}): ResolvedOptions => ({
  watermark: typeof raw.watermark === "number" && raw.watermark > 0 && raw.watermark < 1 ? raw.watermark : DEFAULT_WATERMARK_RATIO,
  recentWindow: typeof raw.recentWindow === "number" && raw.recentWindow >= 0 ? Math.floor(raw.recentWindow) : DEFAULT_RECENT_WINDOW_MESSAGES,
  minEvictableBytes: typeof raw.minEvictableBytes === "number" && raw.minEvictableBytes >= 0 ? raw.minEvictableBytes : DEFAULT_MIN_EVICTABLE_BYTES,
  defaultContextTokens: typeof raw.defaultContextTokens === "number" && raw.defaultContextTokens > 0 ? raw.defaultContextTokens : DEFAULT_CONTEXT_TOKENS,
  hintSubjects:
    typeof raw.hintSubjects === "number" && Number.isInteger(raw.hintSubjects) && raw.hintSubjects >= 0
      ? raw.hintSubjects
      : DEFAULT_HINT_SUBJECTS,
  protectedTools:
    Array.isArray(raw.protectedTools) && raw.protectedTools.every((tool) => typeof tool === "string" && tool.length > 0)
      ? raw.protectedTools
      : DEFAULT_PROTECTED_TOOLS,
  metricsLog: typeof raw.metricsLog === "boolean" ? raw.metricsLog : DEFAULT_METRICS_LOG_ENABLED,
  metricsPath: typeof raw.metricsPath === "string" && raw.metricsPath.length > 0 ? raw.metricsPath : DEFAULT_METRICS_PATH,
})

const isProtectedTool = (tool: string, options: ResolvedOptions): boolean => options.protectedTools.includes(tool)

const rangeOf = (input: Record<string, unknown>): SubjectRange | undefined => {
  const offset = input[OFFSET_INPUT_KEY]
  const limit = input[LIMIT_INPUT_KEY]
  if (typeof offset !== "number" || typeof limit !== "number") return undefined
  return { start: offset, end: offset + limit }
}

const patternSubjectOf = (input: Record<string, unknown>): Subject | undefined => {
  const pattern = input[PATTERN_INPUT_KEY]
  if (typeof pattern !== "string" || pattern.length === 0) return undefined
  return { path: pattern }
}

const subjectsOf = (tool: string, input: Record<string, unknown>): Subject[] => {
  const range = rangeOf(input)
  const subjects: Subject[] = []
  for (const key of PATH_INPUT_KEYS) {
    const value = input[key]
    if (typeof value === "string" && value.length > 0) subjects.push(range ? { path: value, range } : { path: value })
  }
  const patternSubject = patternSubjectOf(input)
  if (patternSubject) subjects.push(patternSubject)
  const command = input[COMMAND_INPUT_KEY]
  if (tool === BASH_TOOL_NAME && typeof command === "string" && command.length > 0) subjects.push({ path: command })
  return subjects
}

const renderSubject = (subject: Subject): string => {
  const rendered = subject.range
    ? `${subject.path}${PATH_RANGE_SEPARATOR}${subject.range.start}${RANGE_SEPARATOR}${subject.range.end}`
    : subject.path
  const singleLine = rendered.replaceAll("\n", " ")
  return singleLine.length > MAX_RENDERED_SUBJECT_CHARS
    ? `${singleLine.slice(0, MAX_RENDERED_SUBJECT_CHARS - ELLIPSIS_MARKER.length)}${ELLIPSIS_MARKER}`
    : singleLine
}

const appearanceTouches = (entrySubjects: Subject[], appearance: ToolAppearance): boolean =>
  appearance.subjects.some((appearanceSubject) =>
    entrySubjects.some(
      (entrySubject) =>
        entrySubject.path === appearanceSubject.path ||
        (appearance.tool === BASH_TOOL_NAME &&
          entrySubject.path.length > MIN_SUBJECT_LENGTH_FOR_SUBSTRING_MATCH &&
          appearanceSubject.path.includes(entrySubject.path)),
    ),
  )

const completedOutputOf = (part: Record<string, unknown>): { output: string } | undefined => {
  if (part["type"] !== "tool") return undefined
  const state = part["state"]
  if (typeof state !== "object" || state === null) return undefined
  const typedState = state as Record<string, unknown>
  if (typedState["status"] !== "completed" || typeof typedState["output"] !== "string") return undefined
  return typedState as { output: string }
}

const stableStringify = (value: unknown): string => {
  if (Array.isArray(value)) return `[${value.map((element) => stableStringify(element)).join(",")}]`
  if (typeof value !== "object" || value === null) return JSON.stringify(value)
  const entries = Object.entries(value).sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
  return `{${entries.map(([key, entryValue]) => `${JSON.stringify(key)}:${stableStringify(entryValue)}`).join(",")}}`
}

const dedupKeyOf = (tool: string, input: Record<string, unknown>): string => JSON.stringify([tool, stableStringify(input)])

const buildDedupTombstone = (tool: string, msgIndex: number): string =>
  `${DEDUP_MARKER} ${tool} ${DEDUP_SUPERSEDED_LEAD} ${msgIndex}`

const dedupTargetOf = (part: Record<string, unknown>): DedupTarget | undefined => {
  const outputRef = completedOutputOf(part)
  if (outputRef === undefined) return undefined
  if (outputRef.output.startsWith(EVICTION_MARKER) || outputRef.output.startsWith(DEDUP_MARKER)) return undefined
  const tool = part["tool"]
  if (typeof tool !== "string") return undefined
  const typedState = part["state"] as Record<string, unknown>
  const input = typeof typedState["input"] === "object" && typedState["input"] !== null ? (typedState["input"] as Record<string, unknown>) : {}
  return { stateRef: outputRef, tool, input }
}

const deduplicateToolOutputs = (messages: MessageBundle[], options: ResolvedOptions): number => {
  const retainedByKey = new Map<string, RetainedDuplicate>()
  let tombstones = 0
  for (let msgIndex = messages.length - 1; msgIndex >= 0; msgIndex -= 1) {
    for (const part of messages[msgIndex].parts) {
      const target = dedupTargetOf(part)
      if (target === undefined) continue
      const key = dedupKeyOf(target.tool, target.input)
      const retained = retainedByKey.get(key)
      if (retained === undefined) {
        retainedByKey.set(key, {
          msgIndex,
          tool: target.tool,
          supersedes: target.stateRef.output.length >= options.minEvictableBytes,
        })
        continue
      }
      if (retained.supersedes) {
        target.stateRef.output = buildDedupTombstone(retained.tool, retained.msgIndex)
        tombstones += 1
      }
    }
  }
  return tombstones
}

const estimateTokens = (messages: MessageBundle[]): number => {
  let chars = 0
  for (const message of messages) {
    for (const part of message.parts) {
      if (part["type"] === "text" && typeof part["text"] === "string") {
        chars += part["text"].length
      } else {
        const outputRef = completedOutputOf(part)
        if (outputRef) chars += outputRef.output.length
      }
    }
  }
  return Math.ceil(chars / CHARS_PER_TOKEN)
}

const purgeErroredToolInputs = (messages: MessageBundle[], options: ResolvedOptions): void => {
  const hotFromIndex = messages.length - options.recentWindow
  for (let msgIndex = 0; msgIndex < hotFromIndex; msgIndex += 1) {
    for (const part of messages[msgIndex].parts) {
      if (part["type"] !== "tool") continue
      const state = part["state"]
      if (typeof state !== "object" || state === null) continue
      const typedState = state as Record<string, unknown>
      if (typedState["status"] !== "error") continue
      if (typedState["input"] === PURGED_INPUT_MARKER) continue
      typedState["input"] = PURGED_INPUT_MARKER
    }
  }
}

const stripLegacyHintParts = (messages: MessageBundle[]): void => {
  for (const message of messages) {
    for (let partIndex = message.parts.length - 1; partIndex >= 0; partIndex -= 1) {
      const part = message.parts[partIndex]
      const text = part["text"]
      if (part["type"] === "text" && typeof text === "string" && text.startsWith(HINT_LINE_PREFIX)) {
        message.parts.splice(partIndex, 1)
      }
    }
  }
}

const buildTombstone = (tool: string, subject: string, bytes: number, messagesAgo: number): string =>
  `${EVICTION_MARKER} ${tool} ${subject} (${bytes} bytes, ~${messagesAgo} messages ago) was evicted to reclaim context; re-run the tool to reload its output.`

const buildReloadPointer = (subject: string): string =>
  `${RELOAD_POINTER_LEAD} ${RELOAD_TOOL_NAME} (subject "${subject}").`

const stashKeyOf = (tool: string, subject: string, msgIndex: number, partIndex: number): string =>
  `${tool}:${subject}:${msgIndex}:${partIndex}`

const touchMapEntry = <T>(map: Map<string, T>, key: string): T | undefined => {
  const existing = map.get(key)
  if (existing === undefined) return undefined
  map.delete(key)
  map.set(key, existing)
  return existing
}

const trimMapToBound = <T>(map: Map<string, T>, bound: number): void => {
  while (map.size >= bound) {
    const leastRecentlyActive = map.keys().next()
    if (leastRecentlyActive.done === true) break
    map.delete(leastRecentlyActive.value)
  }
}

const rememberSessionValue = <T>(map: Map<string, T>, key: string, value: T, bound: number): void => {
  map.delete(key)
  trimMapToBound(map, bound)
  map.set(key, value)
}

const stashForSession = (stashes: StashStore, sessionKey: string): SessionStash => {
  const touched = touchMapEntry(stashes, sessionKey)
  if (touched !== undefined) return touched
  trimMapToBound(stashes, MAX_STASH_SESSIONS)
  const created: SessionStash = new Map()
  stashes.set(sessionKey, created)
  return created
}

const trimStash = (stash: SessionStash): number => {
  let dropped = 0
  while (stash.size > DEFAULT_STASH_LIMIT) {
    const oldest = stash.keys().next()
    if (oldest.done === true) break
    stash.delete(oldest.value)
    dropped += 1
  }
  return dropped
}

const stashEvictedOutput = (stash: SessionStash, entry: StashEntry): number => {
  stash.set(stashKeyOf(entry.tool, entry.subject, entry.msgIndex, entry.partIndex), entry)
  return trimStash(stash)
}

const stashMissTextFor = (subject: string): string =>
  `${STASH_MARKER} ${STASH_MISS_LEAD} "${subject}"; ${STASH_MISS_HINT}.`

const invalidSubjectTextFor = (received: string): string =>
  `${STASH_MARKER} ${RELOAD_TOOL_NAME} ${STASH_INVALID_SUBJECT_LEAD} (${RECEIVED_LABEL} ${received}).`

const olderMatchesLineFor = (subject: string, older: StashEntry[]): string =>
  `${STASH_MARKER} ${STASH_OLDER_LEAD} "${subject}": ${older
    .map((entry) => `${entry.tool} ${STASH_MESSAGE_LABEL} ${entry.msgIndex}`)
    .join(STASH_MATCH_SEPARATOR)}`

const stashedMatchesFor = (stash: SessionStash, subject: string): StashEntry[] => {
  const matches: StashEntry[] = []
  for (const entry of stash.values()) {
    if (entry.subject === subject) matches.push(entry)
  }
  return matches
}

const sessionIDFromContext = (source: unknown): string | undefined => {
  const sessionID =
    typeof source === "object" && source !== null ? (source as { sessionID?: unknown }).sessionID : undefined
  return typeof sessionID === "string" && sessionID.length > 0 ? sessionID : undefined
}

const sessionKeyFromContext = (source: unknown): string => sessionIDFromContext(source) ?? FALLBACK_SESSION_KEY

const executeReadEvicted = (stashes: StashStore, metrics: MetricsStore, args: unknown, toolContext: unknown): string => {
  const subject = typeof args === "object" && args !== null ? (args as { subject?: unknown }).subject : undefined
  if (typeof subject !== "string" || subject.length === 0) return invalidSubjectTextFor(typeof subject)
  const sessionKey = sessionKeyFromContext(toolContext)
  const stash = stashes.get(sessionKey)
  const matches = stash === undefined ? [] : stashedMatchesFor(stash, subject)
  if (matches.length === 0) {
    const existing = metrics.get(sessionKey)
    if (existing !== undefined) existing.stashMisses += 1
    return stashMissTextFor(subject)
  }
  const sessionMetrics = metricsForSession(metrics, sessionKey)
  sessionMetrics.stashHits += 1
  touchMapEntry(stashes, sessionKey)
  const newest = matches[matches.length - 1]
  const older = matches.slice(0, -1)
  return older.length === 0 ? newest.output : `${newest.output}\n${olderMatchesLineFor(subject, older)}`
}

const createSessionMetrics = (): SessionMetrics => ({
  evictions: 0,
  bytesReclaimed: 0,
  stashHits: 0,
  stashMisses: 0,
  stashDropped: 0,
  deduped: 0,
  postEvictionTouches: 0,
  evictedSubjects: [],
  touchScanThrough: TOUCH_SCAN_INITIAL_WATERMARK,
  stashReadsLoggedThrough: 0,
})

const metricsForSession = (metrics: MetricsStore, sessionKey: string): SessionMetrics => {
  const touched = touchMapEntry(metrics, sessionKey)
  if (touched !== undefined) return touched
  trimMapToBound(metrics, MAX_METRICS_SESSIONS)
  const created = createSessionMetrics()
  metrics.set(sessionKey, created)
  return created
}

const countPostEvictionTouches = (metrics: SessionMetrics, appearances: ToolAppearance[]): number => {
  let touches = 0
  let latestIndex = metrics.touchScanThrough
  for (const appearance of appearances) {
    if (appearance.msgIndex <= metrics.touchScanThrough) continue
    if (appearanceTouches(metrics.evictedSubjects, appearance)) touches += 1
    latestIndex = appearance.msgIndex
  }
  metrics.touchScanThrough = latestIndex
  return touches
}

const recordRunOutcome = (metrics: SessionMetrics, eviction: EvictionResult, dedupedThisRun: number, touchesThisRun: number): void => {
  metrics.lastRun = {
    estimatedTokens: eviction.estimatedTokens,
    watermarkTokens: eviction.watermarkTokens,
    deficitTokens: eviction.deficitTokens,
  }
  metrics.evictions += eviction.evicted.length
  metrics.stashDropped += eviction.stashDropped
  for (const entry of eviction.evicted) {
    metrics.bytesReclaimed += entry.bytes
    metrics.evictedSubjects.push(...entry.subjects)
  }
  while (metrics.evictedSubjects.length > MAX_REMEMBERED_EVICTED_SUBJECTS) metrics.evictedSubjects.shift()
  metrics.deduped += dedupedThisRun
  metrics.postEvictionTouches += touchesThisRun
}

const recordMetricsLine = async (
  options: ResolvedOptions,
  metrics: SessionMetrics,
  sessionKey: string,
  eviction: EvictionResult,
  dedupedThisRun: number,
  touchesThisRun: number,
): Promise<void> => {
  const stashReadsSinceLastLine = metrics.stashHits + metrics.stashMisses - metrics.stashReadsLoggedThrough
  const isEventful = eviction.evicted.length > 0 || dedupedThisRun > 0 || touchesThisRun > 0 || stashReadsSinceLastLine > 0
  if (options.metricsLog === false || isEventful === false) return
  const line = {
    ts: new Date().toISOString(),
    session: sessionKey,
    estimatedTokens: eviction.estimatedTokens,
    watermarkTokens: eviction.watermarkTokens,
    deficitTokens: eviction.deficitTokens,
    evictedThisRun: eviction.evicted.map((entry) => ({
      tool: entry.tool,
      subject: entry.subject,
      bytes: entry.bytes,
      messagesAgo: entry.messagesAgo,
    })),
    dedupedThisRun,
    postEvictionTouchesThisRun: touchesThisRun,
    stashReadsSinceLastLine,
    totals: {
      evictions: metrics.evictions,
      bytesReclaimed: metrics.bytesReclaimed,
      stashHits: metrics.stashHits,
      stashMisses: metrics.stashMisses,
      stashDropped: metrics.stashDropped,
      deduped: metrics.deduped,
      postEvictionTouches: metrics.postEvictionTouches,
    },
  }
  try {
    await appendFile(options.metricsPath, `${JSON.stringify(line)}\n`)
    metrics.stashReadsLoggedThrough = metrics.stashHits + metrics.stashMisses
    delete metrics.logWriteError
  } catch (error) {
    metrics.logWriteError = error instanceof Error ? error.message : String(error)
  }
}

const executeLruStats = (source: StatsSource, toolContext: unknown): string => {
  const sessionID = sessionIDFromContext(toolContext)
  const sessionKey = sessionID ?? FALLBACK_SESSION_KEY
  const sessionLimit = sessionID === undefined ? undefined : touchMapEntry(source.limits, sessionID)
  const metrics = touchMapEntry(source.metrics, sessionKey) ?? createSessionMetrics()
  const stash = source.stashes.get(sessionKey)
  const report = {
    session: sessionKey,
    options: {
      watermark: source.options.watermark,
      recentWindow: source.options.recentWindow,
      minEvictableBytes: source.options.minEvictableBytes,
      defaultContextTokens: source.options.defaultContextTokens,
      metricsLog: source.options.metricsLog,
      metricsPath: source.options.metricsPath,
    },
    modelContextTokens: sessionLimit ?? source.options.defaultContextTokens,
    modelContextTokensSource:
      sessionLimit === undefined ? CONTEXT_TOKENS_SOURCE_DEFAULT : CONTEXT_TOKENS_SOURCE_MODEL,
    stash: { entries: stash === undefined ? 0 : stash.size, capacity: DEFAULT_STASH_LIMIT },
    counters: {
      evictions: metrics.evictions,
      bytesReclaimed: metrics.bytesReclaimed,
      stashHits: metrics.stashHits,
      stashMisses: metrics.stashMisses,
      stashDropped: metrics.stashDropped,
      deduped: metrics.deduped,
      postEvictionTouches: metrics.postEvictionTouches,
    },
    lastRun: metrics.lastRun ?? null,
    ...(metrics.logWriteError === undefined ? {} : { logWriteError: metrics.logWriteError }),
  }
  return JSON.stringify(report, null, JSON_INDENT_SPACES)
}

const liveSubjectsOf = (entries: EvictableEntry[]): HotSubject[] =>
  entries.flatMap((entry) =>
    entry.stateRef.output.startsWith(EVICTION_MARKER) || entry.stateRef.output.startsWith(DEDUP_MARKER)
      ? []
      : entry.subjects.map((subject) => ({ subject, lastTouch: entry.lastTouch })),
  )

const evictLeastRecentlyUsed = (
  messages: MessageBundle[],
  options: ResolvedOptions,
  watermarkTokens: number,
  stash: SessionStash,
): EvictionResult => {
  const appearances: ToolAppearance[] = []
  const entries: EvictableEntry[] = []

  messages.forEach((message, msgIndex) => {
    for (const [partIndex, part] of message.parts.entries()) {
      if (part["type"] !== "tool") continue
      const state = part["state"]
      if (typeof state !== "object" || state === null) continue
      const typedState = state as Record<string, unknown>
      if (typedState["status"] !== "completed") continue
      const tool = part["tool"]
      if (typeof tool !== "string") continue
      const input = typeof typedState["input"] === "object" && typedState["input"] !== null ? (typedState["input"] as Record<string, unknown>) : {}
      const subjects = subjectsOf(tool, input)
      appearances.push({ msgIndex, tool, subjects })

      if (typeof typedState["output"] !== "string") continue
      const output = typedState["output"]
      if (output.startsWith(EVICTION_MARKER) || output.startsWith(DEDUP_MARKER) || output.length < options.minEvictableBytes) continue
      entries.push({
        stateRef: typedState as { output: string },
        tool,
        msgIndex,
        partIndex,
        lastTouch: msgIndex,
        bytes: output.length,
        subjects,
      })
    }
  })

  for (const entry of entries) {
    for (const appearance of appearances) {
      if (appearance.msgIndex > entry.lastTouch && appearanceTouches(entry.subjects, appearance)) {
        entry.lastTouch = appearance.msgIndex
      }
    }
  }

  const hotFromIndex = messages.length - options.recentWindow
  const evictable = entries
    .filter((entry) => !isProtectedTool(entry.tool, options))
    .filter((entry) => entry.lastTouch < hotFromIndex)
    .sort((a, b) => a.lastTouch - b.lastTouch || b.bytes - a.bytes)

  const estimatedTokens = estimateTokens(messages)
  const deficitTokens = estimatedTokens - watermarkTokens
  const evicted: EvictedEntryInfo[] = []
  let stashDropped = 0
  if (deficitTokens > 0 && evictable.length > 0) {
    let reclaimedTokens = 0
    for (const entry of evictable) {
      if (reclaimedTokens >= deficitTokens) break
      const subject = entry.subjects.length > 0 ? renderSubject(entry.subjects[0]) : UNKNOWN_TARGET_LABEL
      const messagesAgo = messages.length - entry.lastTouch
      const tombstone = buildTombstone(entry.tool, subject, entry.bytes, messagesAgo)
      const stashed: StashEntry = {
        output: entry.stateRef.output,
        tool: entry.tool,
        subject,
        msgIndex: entry.msgIndex,
        partIndex: entry.partIndex,
      }
      stashDropped += stashEvictedOutput(stash, stashed)
      entry.stateRef.output = `${tombstone}${buildReloadPointer(subject)}`
      reclaimedTokens += entry.bytes / CHARS_PER_TOKEN
      evicted.push({ tool: entry.tool, subject, subjects: entry.subjects, bytes: entry.bytes, messagesAgo })
    }
  }
  return {
    hotSubjects: liveSubjectsOf(entries),
    appearances,
    estimatedTokens,
    watermarkTokens,
    deficitTokens,
    evicted,
    stashDropped,
  }
}

const buildHintLine = (hotSubjects: HotSubject[], limit: number): string | undefined => {
  const seen = new Set<string>()
  const rendered: string[] = []
  const ordered = [...hotSubjects].sort((a, b) => b.lastTouch - a.lastTouch)
  for (const { subject } of ordered) {
    const renderedSubject = renderSubject(subject)
    if (seen.has(renderedSubject)) continue
    seen.add(renderedSubject)
    rendered.push(renderedSubject)
    if (rendered.length >= limit) break
  }
  if (rendered.length === 0) return undefined
  return `${HINT_LINE_PREFIX} ${rendered.join(SUBJECT_SEPARATOR)}`
}

const storeHint = (hintBySession: Map<string, string>, sessionKey: string, hotSubjects: HotSubject[], limit: number): void => {
  if (limit <= 0) return
  const hintLine = buildHintLine(hotSubjects, limit)
  if (hintLine !== undefined) rememberSessionValue(hintBySession, sessionKey, hintLine, MAX_HINT_SESSIONS)
}

const deliverHint = (hintBySession: Map<string, string>, input: unknown, output: { system: string[] }): void => {
  if (!Array.isArray(output.system)) return
  const sessionKey = sessionKeyFromContext(input)
  const hintLine = touchMapEntry(hintBySession, sessionKey)
  if (hintLine === undefined) return
  const existingIndex = output.system.findIndex((block) => typeof block === "string" && block.startsWith(HINT_LINE_PREFIX))
  if (existingIndex === -1) output.system.push(hintLine)
  else output.system[existingIndex] = hintLine
}

export default (async (_input, rawOptions) => {
  const options = resolveOptions(rawOptions as LruContextOptions)
  const contextTokensBySession = new Map<string, number>()
  const stashBySession = new Map<string, SessionStash>()
  const hintBySession = new Map<string, string>()
  const metricsBySession: MetricsStore = new Map()

  // Workaround: read_evicted and lru_stats are registered as plain
  // { description, args, execute } definitions instead of calling tool() from
  // @opencode-ai/plugin. The package only resolves inside the opencode runtime
  // (Bun follows the stow symlink to this repo's real path, where no node_modules
  // exists up-tree; the runtime's own copy at ~/.config/opencode/node_modules is
  // off that resolution path), so importing it throws here. The runtime's tool
  // registry (packages/opencode/src/tool/registry.ts, fromPlugin) consumes
  // definition objects directly and derives the JSON schema itself: args values
  // that are not zod schemas take its legacyJsonSchema path, so the plain
  // { type: "string" } schema below is sufficient. If this file ever ships
  // somewhere @opencode-ai/plugin resolves, switch back to tool().
  const readEvicted = async (args: unknown, toolContext: unknown): Promise<string> =>
    executeReadEvicted(stashBySession, metricsBySession, args, toolContext)

  const lruStats = async (_args: unknown, toolContext: unknown): Promise<string> =>
    executeLruStats({ options, limits: contextTokensBySession, stashes: stashBySession, metrics: metricsBySession }, toolContext)

  return {
    "chat.params": async (input: { sessionID: string; model?: { limit?: { context?: number } } }) => {
      const context = input.model?.limit?.context
      if (typeof context === "number" && context > 0)
        rememberSessionValue(contextTokensBySession, input.sessionID, context, MAX_LIMIT_SESSIONS)
    },
    "experimental.chat.messages.transform": async (_input: unknown, output: { messages: MessageBundle[] }) => {
      const messages = output.messages
      if (!Array.isArray(messages) || messages.length === 0) return
      const info = messages[0]?.info
      const sessionKey = sessionKeyFromContext(info)
      const sessionID = info?.sessionID
      const contextTokens =
        (sessionID !== undefined ? touchMapEntry(contextTokensBySession, sessionID) : undefined) ?? options.defaultContextTokens
      const sessionStash = stashForSession(stashBySession, sessionKey)
      const sessionMetrics = metricsForSession(metricsBySession, sessionKey)
      stripLegacyHintParts(messages)
      const dedupedThisRun = deduplicateToolOutputs(messages, options)
      purgeErroredToolInputs(messages, options)
      const eviction = evictLeastRecentlyUsed(messages, options, contextTokens * options.watermark, sessionStash)
      const touchesThisRun = countPostEvictionTouches(sessionMetrics, eviction.appearances)
      recordRunOutcome(sessionMetrics, eviction, dedupedThisRun, touchesThisRun)
      storeHint(hintBySession, sessionKey, eviction.hotSubjects, options.hintSubjects)
      await recordMetricsLine(options, sessionMetrics, sessionKey, eviction, dedupedThisRun, touchesThisRun)
    },
    "experimental.chat.system.transform": async (input: { sessionID?: string }, output: { system: string[] }) => {
      deliverHint(hintBySession, input, output)
    },
    tool: {
      [RELOAD_TOOL_NAME]: {
        description: RELOAD_TOOL_DESCRIPTION,
        args: { [RELOAD_ARG_NAME]: RELOAD_ARG_SCHEMA },
        execute: readEvicted,
      },
      [STATS_TOOL_NAME]: {
        description: STATS_TOOL_DESCRIPTION,
        args: {},
        execute: lruStats,
      },
    },
  }
}) satisfies Plugin
