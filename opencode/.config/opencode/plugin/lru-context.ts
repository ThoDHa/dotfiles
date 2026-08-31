import type { Plugin } from "@opencode-ai/plugin"

const EVICTION_MARKER = "[lru-evicted]"
const CHARS_PER_TOKEN = 4
const DEFAULT_WATERMARK_RATIO = 0.5
const DEFAULT_RECENT_WINDOW_MESSAGES = 4
const DEFAULT_MIN_EVICTABLE_BYTES = 2048
const DEFAULT_CONTEXT_TOKENS = 100000
const PATH_INPUT_KEYS = ["filePath", "path", "file", "directory"]
const BASH_TOOL_NAME = "bash"
const COMMAND_INPUT_KEY = "command"
const MIN_SUBJECT_LENGTH_FOR_SUBSTRING_MATCH = 3

type LruContextOptions = {
  watermark?: number
  recentWindow?: number
  minEvictableBytes?: number
  defaultContextTokens?: number
}

type ResolvedOptions = Required<LruContextOptions>

type ToolAppearance = {
  msgIndex: number
  tool: string
  subjects: string[]
}

type EvictableEntry = {
  stateRef: { output: string }
  tool: string
  msgIndex: number
  lastTouch: number
  bytes: number
  subjects: string[]
}

type MessageBundle = {
  info: { sessionID?: string }
  parts: Array<Record<string, unknown>>
}

const resolveOptions = (raw: LruContextOptions = {}): ResolvedOptions => ({
  watermark: typeof raw.watermark === "number" && raw.watermark > 0 && raw.watermark < 1 ? raw.watermark : DEFAULT_WATERMARK_RATIO,
  recentWindow: typeof raw.recentWindow === "number" && raw.recentWindow >= 0 ? Math.floor(raw.recentWindow) : DEFAULT_RECENT_WINDOW_MESSAGES,
  minEvictableBytes: typeof raw.minEvictableBytes === "number" && raw.minEvictableBytes >= 0 ? raw.minEvictableBytes : DEFAULT_MIN_EVICTABLE_BYTES,
  defaultContextTokens: typeof raw.defaultContextTokens === "number" && raw.defaultContextTokens > 0 ? raw.defaultContextTokens : DEFAULT_CONTEXT_TOKENS,
})

const subjectsOf = (tool: string, input: Record<string, unknown>): string[] => {
  const subjects: string[] = []
  for (const key of PATH_INPUT_KEYS) {
    const value = input[key]
    if (typeof value === "string" && value.length > 0) subjects.push(value)
  }
  const command = input[COMMAND_INPUT_KEY]
  if (tool === BASH_TOOL_NAME && typeof command === "string" && command.length > 0) subjects.push(command)
  return subjects
}

const appearanceTouches = (entrySubjects: string[], appearance: ToolAppearance): boolean =>
  appearance.subjects.some((appearanceSubject) =>
    entrySubjects.some(
      (entrySubject) =>
        entrySubject === appearanceSubject ||
        (appearance.tool === BASH_TOOL_NAME &&
          entrySubject.length > MIN_SUBJECT_LENGTH_FOR_SUBSTRING_MATCH &&
          appearanceSubject.includes(entrySubject)),
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

const buildTombstone = (tool: string, subject: string, bytes: number, messagesAgo: number): string =>
  `${EVICTION_MARKER} ${tool} ${subject} (${bytes} bytes, ~${messagesAgo} messages ago) was evicted to reclaim context; re-run the tool to reload its output.`

const evictLeastRecentlyUsed = (messages: MessageBundle[], options: ResolvedOptions, watermarkTokens: number): number => {
  const appearances: ToolAppearance[] = []
  const entries: EvictableEntry[] = []

  messages.forEach((message, msgIndex) => {
    for (const part of message.parts) {
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
      if (output.startsWith(EVICTION_MARKER) || output.length < options.minEvictableBytes) continue
      entries.push({
        stateRef: typedState as { output: string },
        tool,
        msgIndex,
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
    .filter((entry) => entry.lastTouch < hotFromIndex)
    .sort((a, b) => a.lastTouch - b.lastTouch || b.bytes - a.bytes)

  const deficitTokens = estimateTokens(messages) - watermarkTokens
  if (deficitTokens <= 0 || evictable.length === 0) return 0

  let reclaimedTokens = 0
  let evicted = 0
  for (const entry of evictable) {
    if (reclaimedTokens >= deficitTokens) break
    const subject = entry.subjects[0] ?? "unknown target"
    entry.stateRef.output = buildTombstone(entry.tool, subject, entry.bytes, messages.length - entry.lastTouch)
    reclaimedTokens += entry.bytes / CHARS_PER_TOKEN
    evicted += 1
  }
  return evicted
}

export default (async (_input, rawOptions) => {
  const options = resolveOptions(rawOptions as LruContextOptions)
  const contextTokensBySession = new Map<string, number>()

  return {
    "chat.params": async (input: { sessionID: string; model?: { limit?: { context?: number } } }) => {
      const context = input.model?.limit?.context
      contextTokensBySession.set(input.sessionID, typeof context === "number" && context > 0 ? context : options.defaultContextTokens)
    },
    "experimental.chat.messages.transform": async (_input: unknown, output: { messages: MessageBundle[] }) => {
      const messages = output.messages
      if (!Array.isArray(messages) || messages.length === 0) return
      const sessionID = messages[0]?.info?.sessionID
      const contextTokens = (sessionID !== undefined ? contextTokensBySession.get(sessionID) : undefined) ?? options.defaultContextTokens
      evictLeastRecentlyUsed(messages, options, contextTokens * options.watermark)
    },
  }
}) satisfies Plugin
