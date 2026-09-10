// Out-of-band benchmark: run explicitly with `node lru-context.bench.ts`.
// Deliberately NOT named *.test.ts so it never enters default test discovery
// and `make test` stays zero-skip.
import { performance } from "node:perf_hooks"

import lruContextFactory from "../../opencode/.config/opencode/plugin/lru-context.ts"

const TRANSFORM_HOOK = "experimental.chat.messages.transform"
const SYSTEM_TRANSFORM_HOOK = "experimental.chat.system.transform"
const SESSION_ID = "lru-bench-session"
const READ_TOOL = "read"
const GREP_TOOL = "grep"
const BASH_TOOL = "bash"
const PATH_INPUT_KEY = "filePath"
const OFFSET_INPUT_KEY = "offset"
const LIMIT_INPUT_KEY = "limit"
const PATTERN_INPUT_KEY = "pattern"
const INCLUDE_INPUT_KEY = "include"
const COMMAND_INPUT_KEY = "command"
const MESSAGE_COUNT = 500
const LARGE_READ_COUNT = 50
const LARGE_READ_BYTES = 8192
const DEDUP_PAIR_COUNT = 30
const DEDUP_PART_BYTES = 4096
const RANGED_READ_COUNT = 10
const RANGED_READ_BYTES = 3072
const GREP_COUNT = 10
const GREP_BYTES = 2560
const ERROR_PART_COUNT = 8
const HOT_BASH_BYTES = 4096
const FILLER_TEXT_CHARS = 200
const BENCH_CONTEXT_TOKENS = 200000
const WATERMARK_RATIO = 0.5
const WARMUP_RUNS = 1
const MEASURED_RUNS = 5
const BUDGET_MS = 50
const EVICTION_MARKER = "[lru-evicted]"
const DEDUP_MARKER = "[lru-deduped]"
const PURGE_MARKER = "[lru-purged-input]"
const HINT_MARKER = "[lru-hot]"
const HINT_LABEL = "recently active:"
const HINT_LINE_PREFIX = `${HINT_MARKER} ${HINT_LABEL}`

type Message = { info: { sessionID?: string }; parts: Array<Record<string, unknown>> }
type Bundle = { messages: Message[] }

const filler = (chars: number): string => "t".repeat(chars)

const completed = (tool: string, input: Record<string, unknown>, output: string): Record<string, unknown> => ({
  type: "tool",
  tool,
  state: { status: "completed", input, output },
})

const errored = (tool: string, input: Record<string, unknown>, output: string): Record<string, unknown> => ({
  type: "tool",
  tool,
  state: { status: "error", input, output },
})

const text = (chars: number): Record<string, unknown> => ({ type: "text", text: filler(chars) })

const buildBundle = (): Bundle => {
  const messages: Message[] = []
  const push = (parts: Array<Record<string, unknown>>): void => {
    messages.push({ info: { sessionID: SESSION_ID }, parts })
  }
  for (let index = 0; index < LARGE_READ_COUNT; index += 1) {
    push([
      completed(READ_TOOL, { [PATH_INPUT_KEY]: `/data/large-${index}.txt` }, "x".repeat(LARGE_READ_BYTES)),
      text(FILLER_TEXT_CHARS),
    ])
  }
  for (let pair = 0; pair < DEDUP_PAIR_COUNT; pair += 1) {
    const input = { [PATH_INPUT_KEY]: `/data/dedup-${pair}.txt` }
    const output = "d".repeat(DEDUP_PART_BYTES)
    push([completed(READ_TOOL, input, output), text(FILLER_TEXT_CHARS)])
    push([completed(READ_TOOL, input, output), text(FILLER_TEXT_CHARS)])
  }
  for (let index = 0; index < RANGED_READ_COUNT; index += 1) {
    push([
      completed(
        READ_TOOL,
        { [PATH_INPUT_KEY]: `/data/ranged-${index}.txt`, [OFFSET_INPUT_KEY]: 10, [LIMIT_INPUT_KEY]: 20 },
        "r".repeat(RANGED_READ_BYTES),
      ),
      text(FILLER_TEXT_CHARS),
    ])
  }
  for (let index = 0; index < GREP_COUNT; index += 1) {
    push([
      completed(GREP_TOOL, { [PATTERN_INPUT_KEY]: `parseConfig${index}`, [INCLUDE_INPUT_KEY]: "*.ts" }, "g".repeat(GREP_BYTES)),
      text(FILLER_TEXT_CHARS),
    ])
  }
  for (let index = 0; index < ERROR_PART_COUNT; index += 1) {
    push([
      errored(READ_TOOL, { [PATH_INPUT_KEY]: `/data/errored-${index}.txt` }, "e".repeat(DEDUP_PART_BYTES)),
      text(FILLER_TEXT_CHARS),
    ])
  }
  push([completed(BASH_TOOL, { [COMMAND_INPUT_KEY]: "head -c 4096 /data/hot.txt" }, "h".repeat(HOT_BASH_BYTES)), text(FILLER_TEXT_CHARS)])
  while (messages.length < MESSAGE_COUNT) push([text(FILLER_TEXT_CHARS)])
  return { messages }
}

const countWhere = (bundle: Bundle, predicate: (part: Record<string, unknown>) => boolean): number =>
  bundle.messages.reduce(
    (total, message) => total + message.parts.filter(predicate).length,
    0,
  )

const outputStartsWith = (part: Record<string, unknown>, marker: string): boolean =>
  part["type"] === "tool" &&
  typeof part["state"] === "object" &&
  part["state"] !== null &&
  typeof (part["state"] as Record<string, unknown>)["output"] === "string" &&
  ((part["state"] as Record<string, unknown>)["output"] as string).startsWith(marker)

const inputIsMarker = (part: Record<string, unknown>): boolean =>
  part["type"] === "tool" &&
  typeof part["state"] === "object" &&
  part["state"] !== null &&
  (part["state"] as Record<string, unknown>)["input"] === PURGE_MARKER

const median = (values: number[]): number => {
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

const hooks = (await lruContextFactory({}, { defaultContextTokens: BENCH_CONTEXT_TOKENS, metricsLog: false })) as Record<
  string,
  (input: unknown, output: unknown) => Promise<unknown>
>
const transform = hooks[TRANSFORM_HOOK]
const systemTransform = hooks[SYSTEM_TRANSFORM_HOOK]
const base = buildBundle()
const baseChars = JSON.stringify(base).length

for (let run = 0; run < WARMUP_RUNS; run += 1) {
  const clone = structuredClone(base)
  await transform({}, clone)
  await systemTransform({ sessionID: SESSION_ID }, { system: [] })
}

const samples: number[] = []
let last: { bundle: Bundle; system: string[] } | undefined
for (let run = 0; run < MEASURED_RUNS; run += 1) {
  const clone = structuredClone(base)
  const systemOutput: { system: string[] } = { system: [] }
  const started = performance.now()
  await transform({}, clone)
  await systemTransform({ sessionID: SESSION_ID }, systemOutput)
  samples.push(performance.now() - started)
  last = { bundle: clone, system: systemOutput.system }
}
if (last === undefined) {
  console.error(`lru-context.bench: FAIL: no measured runs executed (MEASURED_RUNS=${MEASURED_RUNS})`)
  process.exit(1)
}

const evicted = countWhere(last.bundle, (part) => outputStartsWith(part, EVICTION_MARKER))
const deduped = countWhere(last.bundle, (part) => outputStartsWith(part, DEDUP_MARKER))
const purged = countWhere(last.bundle, inputIsMarker)
const messageHints = countWhere(last.bundle, (part) => part["type"] === "text" && typeof part["text"] === "string" && part["text"].startsWith(HINT_MARKER))
const systemHints = last.system.filter((block) => typeof block === "string" && block.startsWith(HINT_LINE_PREFIX)).length
const medianMs = median(samples)

console.log(`lru-context.bench: bundle=${MESSAGE_COUNT} messages, ${baseChars} serialized chars, context=${BENCH_CONTEXT_TOKENS} tokens, watermark=${BENCH_CONTEXT_TOKENS * WATERMARK_RATIO} tokens`)
console.log(`lru-context.bench: path coverage evicted=${evicted} deduped=${deduped} purged=${purged} messageHints=${messageHints} systemHints=${systemHints}`)
samples.forEach((sample, index) => console.log(`lru-context.bench: run ${index + 1}: ${sample.toFixed(3)} ms`))
console.log(`lru-context.bench: median of ${MEASURED_RUNS}: ${medianMs.toFixed(3)} ms (budget ${BUDGET_MS} ms)`)

if (evicted === 0 || deduped === 0 || purged === 0 || messageHints !== 0 || systemHints !== 1) {
  console.error(`lru-context.bench: FAIL: plugin run did not exercise every path (evicted=${evicted} deduped=${deduped} purged=${purged} messageHints=${messageHints} systemHints=${systemHints})`)
  process.exit(1)
}
if (medianMs >= BUDGET_MS) {
  console.error(`lru-context.bench: FAIL: median ${medianMs.toFixed(3)} ms meets or exceeds the ${BUDGET_MS} ms budget`)
  process.exit(1)
}
console.log("lru-context.bench: PASS")
