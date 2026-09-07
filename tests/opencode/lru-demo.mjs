#!/usr/bin/env node
// LRU-16 wire proof demo: mock OpenAI-compatible provider and verdict report
// generator for the lru-context plugin. Node core only; no dependencies.
//
// Modes:
//   setup  <demoDir> <port> <pluginPath>
//   serve  <demoDir> <port> <off|on>
//   report <demoDir> <exitOff> <exitOn> <cmdOff> <cmdOn> <ocVersion>
//          <metaHashBefore> <metaHashAfter> <contentHashBefore> <contentHashAfter>

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const BIG_FILE_CHARS = 6144
const BIG_FILE_LINES = 64
const LINE_CHARS = 96
const BIG_FILE_NAMES = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "dup", "tinydup"]
const TOUCH_FILE = "one"
const RELOAD_FILE = "three"
const DUP_FILE = "dup"
const TINY_FILE = "tinydup"
const TINY_NEWEST_CHARS = 400
const TINY_NEWEST_UNIT = "TINYDUP-NEWEST-CONTENT "
const MISSING_PATH_FILL = "e"
const MISSING_PATH_CHARS = 180
const ERROR_RESULT_PREFIX = "File not found:"
const MIN_EVICTABLE_CHARS = 2048
const DEFAULT_RECENT_WINDOW = 4
const MIN_TOMBSTONES = 2
const TODO_ITEM_COUNT = 24
const HINT_SUBJECTS_OPTION = 6
const PROVIDER_ID = "mock"
const MODEL_ID = "mock-model"
const ADVERTISED_CONTEXT_TOKENS = 18000
const ADVERTISED_OUTPUT_TOKENS = 8000
const PLUGIN_OPTIONS = { hintSubjects: HINT_SUBJECTS_OPTION }
const EVICTION_MARKER = "[lru-evicted]"
const HINT_MARKER = "[lru-hot]"
const HINT_LABEL = "recently active:"
const DEDUP_MARKER = "[lru-deduped]"
const PURGED_INPUT_MARKER = "[lru-purged-input]"
const STASH_MARKER = "[lru-stash]"
const RELOAD_TOOL_NAME = "read_evicted"
const OFF_FORBIDDEN_STRINGS = [EVICTION_MARKER, HINT_MARKER, DEDUP_MARKER, PURGED_INPUT_MARKER, STASH_MARKER, RELOAD_TOOL_NAME]
const RELOAD_POINTER_SENTENCE = "re-run the tool to reload its output."
const RELOAD_POINTER_LEAD = 'reload it with read_evicted (subject "'
const CHARS_PER_TOKEN = 4
const WATERMARK_SLACK_TOKENS = 128
const EXCERPT_MAX_CHARS = 300

const usage = () => {
  console.error("usage: lru-demo.mjs setup <demoDir> <port> <pluginPath>")
  console.error("       lru-demo.mjs serve <demoDir> <port> <off|on>")
  console.error("       lru-demo.mjs report <demoDir> <exitOff> <exitOn> <cmdOff> <cmdOn> <ocVersion> <metaBefore> <metaAfter> <contentBefore> <contentAfter>")
  process.exit(2)
}

const bigFileContent = (name) => {
  const lines = []
  for (let i = 0; i < BIG_FILE_LINES; i += 1) {
    const prefix = `${name} line ${String(i + 1).padStart(3, "0")} `
    lines.push(prefix + name[0].repeat(LINE_CHARS - 1 - prefix.length))
  }
  return `${lines.join("\n")}\n`
}

const tinyNewestContent = () => TINY_NEWEST_UNIT.repeat(24).slice(0, TINY_NEWEST_CHARS)

const todoItems = () =>
  Array.from({ length: TODO_ITEM_COUNT }, (_, i) => ({
    id: String(i + 1).padStart(2, "0"),
    content: `Check ${BIG_FILE_NAMES[i % BIG_FILE_NAMES.length]}-fixture-${String(i).padStart(2, "0")} output survival across the wire proof capture window of the demo`,
    status: i % 2 === 0 ? "completed" : "pending",
    priority: "high",
  }))

const filesDirOf = (demoDir) => `${demoDir}/files`
const subjectOf = (demoDir, name) => `cat ${filesDirOf(demoDir)}/${name}.txt`

const sessionSteps = (demoDir) => [
  { type: "tool", name: "read", args: { filePath: `${demoDir}/missing/${MISSING_PATH_FILL.repeat(MISSING_PATH_CHARS)}.txt` } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, TOUCH_FILE) } },
  { type: "tool", name: "read", args: { filePath: `${filesDirOf(demoDir)}/two.txt` } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, RELOAD_FILE) } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, DUP_FILE) } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, DUP_FILE) } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "four") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "five") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "six") } },
  { type: "tool", name: "todowrite", args: { todos: todoItems() } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "seven") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "eight") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "nine") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, "ten") } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, TINY_FILE) } },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, TINY_FILE) }, onServe: "truncate-tinydup" },
  { type: "tool", name: "bash", args: { command: subjectOf(demoDir, TOUCH_FILE) } },
  { type: "tool", name: RELOAD_TOOL_NAME, args: { subject: subjectOf(demoDir, RELOAD_FILE) }, gateTool: RELOAD_TOOL_NAME },
  { type: "final", text: "All scripted steps are complete. Reply with a one-sentence summary and stop." },
]

const projectConfig = (demoDir, port, pluginPath, variant) => {
  const config = {
    $schema: "https://opencode.ai/config.json",
    model: `${PROVIDER_ID}/${MODEL_ID}`,
    provider: {
      [PROVIDER_ID]: {
        npm: "@ai-sdk/openai-compatible",
        name: "Mock Provider",
        options: { baseURL: `http://127.0.0.1:${port}/v1`, apiKey: "sk-mock" },
        models: {
          [MODEL_ID]: {
            name: "Mock Model",
            tool_call: true,
            limit: { context: ADVERTISED_CONTEXT_TOKENS, output: ADVERTISED_OUTPUT_TOKENS },
          },
        },
      },
    },
  }
  if (variant === "on") config.plugin = [[pluginPath, PLUGIN_OPTIONS]]
  return config
}

const toolsOf = (body) => (Array.isArray(body.tools) ? body.tools.map((t) => t?.function?.name).filter(Boolean) : [])

const decide = (script, body) => {
  const done = body.messages.filter((m) => m.role === "tool").length
  const tools = toolsOf(body)
  let step = script[Math.min(done, script.length - 1)]
  let gatedSkip = false
  if (step && step.type === "tool" && step.gateTool && !tools.includes(step.gateTool)) {
    gatedSkip = true
    step = script[Math.min(done + 1, script.length - 1)]
  }
  return { done, tools, step, gatedSkip }
}

const respondSse = (res, body, step) => {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" })
  const chunk = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`)
  const base = { id: "chatcmpl-mock", object: "chat.completion.chunk", created: 1, model: body.model ?? MODEL_ID }
  if (step.type === "final") {
    chunk({ ...base, choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] })
    chunk({ ...base, choices: [{ index: 0, delta: { content: step.text }, finish_reason: null }] })
    chunk({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 512, completion_tokens: 16, total_tokens: 528 } })
    res.write("data: [DONE]\n\n")
    res.end()
    return
  }
  chunk({ ...base, choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] })
  chunk({
    ...base,
    choices: [
      {
        index: 0,
        delta: {
          tool_calls: [
            {
              index: 0,
              id: `call_${Math.random().toString(36).slice(2, 10)}`,
              type: "function",
              function: { name: step.name, arguments: JSON.stringify(step.args) },
            },
          ],
        },
        finish_reason: null,
      },
    ],
  })
  chunk({ ...base, choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }], usage: { prompt_tokens: 512, completion_tokens: 24, total_tokens: 536 } })
  res.write("data: [DONE]\n\n")
  res.end()
}

const writeFixtures = (demoDir) => {
  fs.mkdirSync(filesDirOf(demoDir), { recursive: true })
  for (const name of BIG_FILE_NAMES) {
    fs.writeFileSync(`${filesDirOf(demoDir)}/${name}.txt`, bigFileContent(name))
  }
}

const runSetup = (args) => {
  const [demoDir, portRaw, pluginPath] = args
  const port = Number(portRaw)
  if (!demoDir || !Number.isInteger(port) || !pluginPath) usage()
  for (const dir of [
    filesDirOf(demoDir),
    `${demoDir}/projects/off/.opencode`,
    `${demoDir}/projects/on/.opencode`,
    `${demoDir}/capture/off`,
    `${demoDir}/capture/on`,
    `${demoDir}/logs`,
    `${demoDir}/xdg/config`,
    `${demoDir}/xdg/data`,
    `${demoDir}/xdg/cache`,
    `${demoDir}/xdg/state`,
  ]) {
    fs.mkdirSync(dir, { recursive: true })
  }
  writeFixtures(demoDir)
  for (const variant of ["off", "on"]) {
    const json = `${JSON.stringify(projectConfig(demoDir, port, pluginPath, variant), null, 2)}\n`
    fs.writeFileSync(`${demoDir}/projects/${variant}/.opencode/opencode.json`, json)
  }
  fs.writeFileSync(`${demoDir}/header.json`, `${JSON.stringify({ demoDir, port, pluginPath }, null, 2)}\n`)
}

const truncateTinydup = (demoDir) => {
  fs.writeFileSync(`${filesDirOf(demoDir)}/${TINY_FILE}.txt`, tinyNewestContent())
}

const runServe = (args) => {
  const [demoDir, portRaw, variant] = args
  const port = Number(portRaw)
  if (!demoDir || !Number.isInteger(port) || (variant !== "off" && variant !== "on")) usage()
  writeFixtures(demoDir)
  const outdir = `${demoDir}/capture/${variant}`
  fs.mkdirSync(outdir, { recursive: true })
  const script = sessionSteps(demoDir)
  const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`)
  const server = http.createServer((req, res) => {
    if (req.method === "GET" && req.url.includes("/models")) {
      log(`GET ${req.url}`)
      res.writeHead(200, { "content-type": "application/json" })
      res.end(
        JSON.stringify({
          object: "list",
          data: [{ id: MODEL_ID, object: "model", owned_by: PROVIDER_ID, context_length: ADVERTISED_CONTEXT_TOKENS }],
        }),
      )
      return
    }
    if (req.method === "POST" && req.url.includes("/chat/completions")) {
      let raw = ""
      req.on("data", (c) => (raw += c))
      req.on("end", () => {
        let body
        try {
          body = JSON.parse(raw)
        } catch {
          res.writeHead(400, { "content-type": "application/json" })
          res.end(JSON.stringify({ error: { message: "bad json" } }))
          return
        }
        const n = fs.readdirSync(outdir).filter((f) => /^req-\d+\.json$/.test(f)).length
        fs.writeFileSync(path.join(outdir, `req-${String(n).padStart(3, "0")}.json`), raw)
        const { done, tools, step, gatedSkip } = decide(script, body)
        log(`req ${n}: bytes=${raw.length} toolResults=${done} step=${script.indexOf(step)} tools=[${tools.join(",")}]${gatedSkip ? " GATED-SKIP" : ""}`)
        if (tools.length === 0) {
          respondSse(res, body, { type: "final", text: "mock session title" })
          return
        }
        if (step?.onServe === "truncate-tinydup") truncateTinydup(demoDir)
        respondSse(res, body, step)
      })
      return
    }
    res.writeHead(404, { "content-type": "application/json" })
    res.end(JSON.stringify({ error: { message: `no route ${req.method} ${req.url}` } }))
  })
  server.listen(port, "127.0.0.1", () => log(`mock provider listening on 127.0.0.1:${port} variant=${variant} outdir=${outdir} steps=${script.length}`))
  process.on("SIGTERM", () => server.close(() => process.exit(0)))
  process.on("SIGINT", () => server.close(() => process.exit(0)))
}

const runReport = (args) => {
  const [demoDir, exitOffRaw, exitOnRaw, cmdOff, cmdOn, ocVersion, metaBefore, metaAfter, contentBefore, contentAfter] = args
  if (!demoDir || !cmdOff || !cmdOn || !ocVersion || !metaBefore || !metaAfter || !contentBefore || !contentAfter) usage()
  const header = JSON.parse(fs.readFileSync(`${demoDir}/header.json`, "utf8"))

  const loadCapture = (variant) => {
    const dir = `${demoDir}/capture/${variant}`
    const files = fs.readdirSync(dir).filter((f) => /^req-\d+\.json$/.test(f)).sort()
    let last = null
    for (const f of files) {
      const raw = fs.readFileSync(`${dir}/${f}`, "utf8")
      const parsed = JSON.parse(raw)
      if (Array.isArray(parsed.tools) && parsed.tools.length > 0) last = { raw, parsed }
    }
    if (last === null) {
      console.error(`report: no tools-bearing request captured for variant ${variant} in ${dir}`)
      process.exit(2)
    }
    fs.writeFileSync(`${demoDir}/payload-${variant}.json`, last.raw)
    return last
  }

  const contentOf = (m) => {
    if (typeof m?.content === "string") return m.content
    if (Array.isArray(m?.content)) return m.content.map((c) => (typeof c?.text === "string" ? c.text : "")).join("")
    return ""
  }

  const callsOf = (p) => {
    const meta = new Map()
    const order = []
    p.messages.forEach((m, msgIndex) => {
      if (m.role === "assistant" && Array.isArray(m.tool_calls)) {
        for (const tc of m.tool_calls) {
          meta.set(tc.id, { id: tc.id, name: tc.function.name, args: tc.function.arguments, result: undefined, resultMsgIndex: -1 })
          order.push(tc.id)
        }
      }
      if (m.role === "tool") {
        const c = meta.get(m.tool_call_id)
        if (c) {
          c.result = contentOf(m)
          c.resultMsgIndex = msgIndex
        }
      }
    })
    return order.map((id) => meta.get(id))
  }

  const wireChars = (p) => p.messages.reduce((acc, m) => acc + contentOf(m).length, 0)
  const wholeText = (p) => p.messages.map(contentOf).join("\n")
  const countOf = (hay, needle) => hay.split(needle).length - 1
  const tokensOf = (chars) => Math.ceil(chars / CHARS_PER_TOKEN)

  const byNeedle = (calls, needle) => {
    const hits = calls.filter((c) => typeof c.args === "string" && c.args.includes(needle))
    return hits[hits.length - 1]
  }

  const exc = (text, max = EXCERPT_MAX_CHARS) => {
    const oneLine = String(text ?? "undefined").replaceAll("\n", "\\n")
    return oneLine.length <= max ? oneLine : `${oneLine.slice(0, max)}...[+${oneLine.length - max} chars]`
  }

  const off = loadCapture("off")
  const on = loadCapture("on")
  const offCalls = callsOf(off.parsed)
  const onCalls = callsOf(on.parsed)
  const reloadNeedle = `${demoDir}/files/${RELOAD_FILE}.txt`
  const dupNeedle = `${demoDir}/files/${DUP_FILE}.txt`
  const tinyNeedle = `${demoDir}/files/${TINY_FILE}.txt`
  const touchNeedle = `${demoDir}/files/${TOUCH_FILE}.txt`
  const reloadSubject = subjectOf(demoDir, RELOAD_FILE)
  const touchSubject = subjectOf(demoDir, TOUCH_FILE)

  const checks = []
  const check = (title, ok, detail, excerpt) => checks.push({ title, ok: ok === true, detail, excerpt })

  const offMarkerCounts = {}
  for (const needle of OFF_FORBIDDEN_STRINGS) {
    let total = 0
    for (const f of fs.readdirSync(`${demoDir}/capture/off`).filter((name) => /^req-\d+\.json$/.test(name)).sort()) {
      total += countOf(fs.readFileSync(`${demoDir}/capture/off/${f}`, "utf8"), needle)
    }
    offMarkerCounts[needle] = total
  }
  check(
    "OFF purity: zero plugin markers and zero read_evicted references in every captured OFF request",
    OFF_FORBIDDEN_STRINGS.every((needle) => offMarkerCounts[needle] === 0),
    `occurrence counts across all OFF requests: ${JSON.stringify(offMarkerCounts)}`,
  )

  const offOne = byNeedle(offCalls, touchNeedle)
  const offThree = byNeedle(offCalls, reloadNeedle)
  const offTen = byNeedle(offCalls, `${demoDir}/files/ten.txt`)
  const offTinyCalls = offCalls.filter((c) => c.args.includes(tinyNeedle))
  const offTinyOlder = offTinyCalls[0]
  const offTinyNewer = offTinyCalls[offTinyCalls.length - 1]
  const offVerbatim =
    offOne?.result === bigFileContent(TOUCH_FILE) &&
    offThree?.result === bigFileContent(RELOAD_FILE) &&
    offTen?.result === bigFileContent("ten") &&
    offTinyCalls.length === 2 &&
    offTinyOlder?.result === bigFileContent(TINY_FILE) &&
    offTinyNewer?.result === tinyNewestContent()
  check(
    "OFF baseline: sampled big tool outputs and the tinydup pair arrive verbatim from the runtime",
    offVerbatim,
    `one.txt=${offOne?.result?.length} three.txt=${offThree?.result?.length} ten.txt=${offTen?.result?.length} tinyOlder=${offTinyOlder?.result?.length} tinyNewer=${offTinyNewer?.result?.length} chars (expected ${BIG_FILE_CHARS}/${BIG_FILE_CHARS}/${BIG_FILE_CHARS}/${BIG_FILE_CHARS}/${TINY_NEWEST_CHARS})`,
    `three.txt head: ${exc(offThree?.result, 160)}`,
  )

  const offTodoHits = offCalls.filter((c) => c.name === "todowrite")
  const offTodo = offTodoHits[offTodoHits.length - 1]
  check(
    "OFF baseline: todowrite output is large enough to be evictable without protection",
    offTodoHits.length === 1 && typeof offTodo?.result === "string" && offTodo.result.length >= MIN_EVICTABLE_CHARS,
    `todowrite calls=${offTodoHits.length} output=${offTodo?.result?.length} chars (needs >= ${MIN_EVICTABLE_CHARS})`,
    `todowrite head: ${exc(offTodo?.result, 200)}`,
  )

  const offTools = toolsOf(off.parsed)
  const onTools = toolsOf(on.parsed)
  check(
    "ON registration: read_evicted present in ON tool listing, absent from OFF",
    onTools.includes(RELOAD_TOOL_NAME) && !offTools.includes(RELOAD_TOOL_NAME),
    `ON tools=[${onTools.join(",")}] OFF tools=[${offTools.join(",")}]`,
  )

  const onTombstones = onCalls.filter((c) => typeof c.result === "string" && c.result.startsWith(EVICTION_MARKER))
  check(
    "ON eviction: tombstones on cold outputs, each carrying the reload-pointer sentences",
    onTombstones.length >= MIN_TOMBSTONES &&
      onTombstones.every((c) => c.result.includes(RELOAD_POINTER_SENTENCE) && c.result.includes(RELOAD_POINTER_LEAD)),
    `tombstoned calls=${onTombstones.length}: [${onTombstones.map((c) => c.args.slice(0, 60)).join(" | ")}]`,
    `first tombstone verbatim: ${exc(onTombstones[0]?.result, 520)}`,
  )

  const onOriginalBytes = onTombstones.map((c) => Number(c.result.match(/\((\d+) bytes/)?.[1] ?? 0))
  const tombTextChars = onTombstones.reduce((acc, c) => acc + c.result.length, 0)
  const onDedupCall = onCalls.find((c) => typeof c.result === "string" && c.result.startsWith(DEDUP_MARKER))
  const onHintLine = wholeText(on.parsed)
    .split("\n")
    .find((line) => line.startsWith(HINT_MARKER))
  const preTransformChars =
    wireChars(on.parsed) -
    tombTextChars +
    onOriginalBytes.reduce((a, b) => a + b, 0) +
    (bigFileContent(DUP_FILE).length - (onDedupCall?.result?.length ?? 0)) -
    (onHintLine?.length ?? 0)
  const preTokens = tokensOf(preTransformChars)
  const reclaimedTokens = onOriginalBytes.reduce((a, b) => a + b, 0) / CHARS_PER_TOKEN
  const watermarkUpperTokens = preTokens - reclaimedTokens + tokensOf(Math.max(...onOriginalBytes, 0)) + WATERMARK_SLACK_TOKENS
  const onWireTokens = tokensOf(wireChars(on.parsed))
  check(
    "ON eviction depth: post-transform estimate sits under the watermark implied by the plugin stop rule",
    onWireTokens <= watermarkUpperTokens,
    `pre-transform ~${preTokens} tok, reclaimed ${reclaimedTokens} tok via ${onTombstones.length} tombstones, wire after ~${onWireTokens} tok, watermark window (${preTokens - reclaimedTokens}, ${watermarkUpperTokens}] tok`,
  )

  const onOneFresh = byNeedle(onCalls, touchNeedle)
  const twoEvicted = onTombstones.some((c) => c.args.includes(`${demoDir}/files/two.txt`))
  const threeEvicted = onTombstones.some((c) => c.args.includes(reloadNeedle))
  check(
    "ON touch-refresh: the re-read first file is verbatim while colder same-size peers are tombstoned",
    onOneFresh?.result === bigFileContent(TOUCH_FILE) && twoEvicted && threeEvicted,
    `one.txt fresh copy=${onOneFresh?.result?.length} chars (expected ${BIG_FILE_CHARS}); two.txt evicted=${twoEvicted}; three.txt evicted=${threeEvicted}`,
  )

  const hintSubjects = typeof onHintLine === "string" ? onHintLine.slice(`${HINT_MARKER} ${HINT_LABEL} `.length).split(", ") : []
  const hintOccurrences = countOf(wholeText(on.parsed), HINT_MARKER)
  check(
    "ON hint: exactly one [lru-hot] line, freshest subject first, at most hintSubjects entries",
    hintOccurrences === 1 &&
      typeof onHintLine === "string" &&
      onHintLine.startsWith(`${HINT_MARKER} ${HINT_LABEL} `) &&
      hintSubjects[0] === touchSubject &&
      hintSubjects.length <= HINT_SUBJECTS_OPTION,
    `occurrences=${hintOccurrences} subjects=${hintSubjects.length} (hintSubjects option=${HINT_SUBJECTS_OPTION}) first=${JSON.stringify(hintSubjects[0])}`,
    `hint line verbatim: ${exc(onHintLine, 520)}`,
  )

  const onDupCalls = onCalls.filter((c) => c.args.includes(dupNeedle))
  const onDupOlder = onDupCalls[0]
  const onDupNewer = onDupCalls[onDupCalls.length - 1]
  const onTouchCalls = onCalls.filter((c) => c.args.includes(touchNeedle))
  const onTouchFirst = onTouchCalls[0]
  const onDeduped = onCalls.filter((c) => typeof c.result === "string" && c.result.startsWith(DEDUP_MARKER))
  const expectedDeduped = [onDupOlder, onTouchFirst]
  check(
    "ON dedup: [lru-deduped] on the older member of the substantial pair (the identical re-read also supersedes its first copy), and nothing else",
    onDupCalls.length === 2 &&
      typeof onDupOlder?.result === "string" &&
      onDupOlder.result.startsWith(DEDUP_MARKER) &&
      onDupOlder.result.includes("at message") &&
      onDeduped.length === expectedDeduped.length &&
      onDeduped.every((c) => expectedDeduped.includes(c)),
    `pair calls=${onDupCalls.length} older=${JSON.stringify(onDupOlder?.result)} deduped calls=${onDeduped.length} (expected: dup older + first one.txt copy superseded by the re-read)`,
  )

  const dupNewerVerbatim = onDupNewer?.result === bigFileContent(DUP_FILE)
  const dupNewerEvicted = typeof onDupNewer?.result === "string" && onDupNewer.result.startsWith(EVICTION_MARKER)
  check(
    "ON dedup composition: retained dup copy verbatim, or itself evicted after dedup as the coldest live entry",
    dupNewerVerbatim || dupNewerEvicted,
    `newer copy outcome=${dupNewerVerbatim ? "verbatim" : dupNewerEvicted ? "evicted (dedup-then-evict composition)" : "unexpected"}`,
    `newer copy: ${exc(onDupNewer?.result, 200)}`,
  )

  const onTinyCalls = onCalls.filter((c) => c.args.includes(tinyNeedle))
  const onTinyOlder = onTinyCalls[0]
  const onTinyNewer = onTinyCalls[onTinyCalls.length - 1]
  check(
    "ON tiny-newest guard: identical tiny-newest duplicate pair kept verbatim, not deduped",
    onTinyCalls.length === 2 &&
      onTinyOlder?.result === bigFileContent(TINY_FILE) &&
      onTinyNewer?.result === tinyNewestContent() &&
      !String(onTinyOlder?.result).startsWith(DEDUP_MARKER) &&
      !String(onTinyNewer?.result).startsWith(DEDUP_MARKER) &&
      !onDeduped.includes(onTinyOlder) &&
      !onDeduped.includes(onTinyNewer),
    `older=${onTinyOlder?.result?.length} chars (expected ${BIG_FILE_CHARS}) newest=${onTinyNewer?.result?.length} chars (expected ${TINY_NEWEST_CHARS})`,
    `older head: ${exc(onTinyOlder?.result, 120)} | newest head: ${exc(onTinyNewer?.result, 120)}`,
  )

  const onErrCall = onCalls.find((c) => typeof c.result === "string" && c.result.startsWith(ERROR_RESULT_PREFIX))
  check(
    "ON error purge: errored call's wire input is the purge marker while its error output stays intact",
    typeof onErrCall?.args === "string" &&
      onErrCall.args.includes(PURGED_INPUT_MARKER) &&
      !onErrCall.args.includes("missing/") &&
      typeof onErrCall.result === "string" &&
      onErrCall.result.startsWith(ERROR_RESULT_PREFIX),
    `args=${JSON.stringify(onErrCall?.args)} resultHead=${JSON.stringify(exc(onErrCall?.result, 120))}`,
  )

  const onTodo = onCalls.find((c) => c.name === "todowrite")
  const totalWireMessages = on.parsed.messages.length
  check(
    "ON protection: todowrite output survives verbatim under eviction pressure (default protectedTools)",
    typeof onTodo?.result === "string" &&
      typeof offTodo?.result === "string" &&
      onTodo.result === offTodo.result &&
      onTodo.result.length >= MIN_EVICTABLE_CHARS &&
      onTodo.resultMsgIndex >= 0 &&
      onTodo.resultMsgIndex < totalWireMessages - DEFAULT_RECENT_WINDOW,
    `on=${onTodo?.result?.length} chars off=${offTodo?.result?.length} chars identical=${onTodo?.result === offTodo?.result} msgIndex=${onTodo?.resultMsgIndex}/${totalWireMessages} (cold when < ${totalWireMessages - DEFAULT_RECENT_WINDOW})`,
    `todowrite head: ${exc(onTodo?.result, 200)}`,
  )

  const onReload = onCalls.find((c) => c.name === RELOAD_TOOL_NAME)
  const reloadExpected = bigFileContent(RELOAD_FILE)
  check(
    "ON reload: read_evicted returns the original evicted bytes within the session",
    typeof onReload?.result === "string" &&
      (onReload.result === reloadExpected || onReload.result.startsWith(`${reloadExpected}\n${STASH_MARKER}`)),
    `result=${onReload?.result?.length} chars (expected ${reloadExpected.length}) call=${JSON.stringify(onReload?.args)} subject=${JSON.stringify(reloadSubject)}`,
    `reload head: ${exc(onReload?.result, 200)}`,
  )

  const offChars = wireChars(off.parsed)
  const onChars = wireChars(on.parsed)
  const reclaimedDelta = offChars - onChars
  check(
    "ON sizes: the plugin reclaims wire context (OFF chars > ON chars, ~tokens at 4 chars/token)",
    reclaimedDelta > 0,
    `OFF=${offChars} chars (~${tokensOf(offChars)} tok, ${off.raw.length} raw bytes) ON=${onChars} chars (~${tokensOf(onChars)} tok, ${on.raw.length} raw bytes) delta=${reclaimedDelta} chars (~${tokensOf(reclaimedDelta)} tok)`,
  )

  const pluginHash = crypto.createHash("sha256").update(fs.readFileSync(header.pluginPath)).digest("hex")
  const pass = checks.filter((c) => c.ok).length
  const fail = checks.length - pass
  const metaUntouched = metaBefore === metaAfter ? "yes" : "NO"
  const contentUntouched = contentBefore === contentAfter ? "yes" : "NO"

  const lines = []
  lines.push("# LRU Context Plugin Wire Proof Demo Report")
  lines.push("")
  lines.push(`- Date (UTC): ${new Date().toISOString()}`)
  lines.push(`- opencode: ${ocVersion}`)
  lines.push(`- Plugin: ${header.pluginPath}`)
  lines.push(`- Plugin sha256: ${pluginHash}`)
  lines.push(`- Mock provider: http://127.0.0.1:${header.port}/v1 (model ${PROVIDER_ID}/${MODEL_ID}, advertised limit context ${ADVERTISED_CONTEXT_TOKENS} / output ${ADVERTISED_OUTPUT_TOKENS})`)
  lines.push(`- OFF command: ${cmdOff}`)
  lines.push(`- ON command: ${cmdOn}`)
  lines.push(`- Session exit codes: OFF=${exitOffRaw} ON=${exitOnRaw}`)
  lines.push(`- Config untouched proof (~/.config/opencode): metadata hash ${metaBefore} -> ${metaAfter} (equal: ${metaUntouched}); content hash ${contentBefore} -> ${contentAfter} (equal: ${contentUntouched})`)
  lines.push(`- Log directory: ${demoDir}`)
  lines.push("")
  if (fail > 0) {
    lines.push("## FAILED CHECKS (REVIEW REQUIRED)")
    lines.push("")
    for (const c of checks.filter((entry) => !entry.ok)) {
      lines.push(`### FAIL: ${c.title}`)
      lines.push("")
      lines.push(c.detail)
      if (c.excerpt) {
        lines.push("")
        lines.push("```text")
        lines.push(c.excerpt)
        lines.push("```")
      }
      lines.push("")
    }
  }
  lines.push(`## Check Results (${pass} pass / ${fail} fail)`)
  lines.push("")
  for (const [i, c] of checks.entries()) {
    lines.push(`### ${c.ok ? "PASS" : "FAIL"} ${i + 1}. ${c.title}`)
    lines.push("")
    lines.push(c.detail)
    if (c.excerpt) {
      lines.push("")
      lines.push("```text")
      lines.push(c.excerpt)
      lines.push("```")
    }
    lines.push("")
  }
  lines.push("## Payload Totals")
  lines.push("")
  lines.push("| payload | content chars | ~tokens (chars/4) | raw JSON bytes |")
  lines.push("|---|---|---|---|")
  lines.push(`| payload-off.json (final OFF request) | ${offChars} | ${tokensOf(offChars)} | ${off.raw.length} |`)
  lines.push(`| payload-on.json (final ON request) | ${onChars} | ${tokensOf(onChars)} | ${on.raw.length} |`)
  lines.push(`| reclaimed delta (OFF minus ON) | ${reclaimedDelta} | ~${tokensOf(reclaimedDelta)} | ${off.raw.length - on.raw.length} |`)
  lines.push("")
  lines.push(`## VERDICT: ${fail === 0 ? "ALL CHECKS PASS" : `${fail} CHECK(S) FAILED`} (${pass}/${checks.length})`)
  lines.push("")

  fs.writeFileSync(`${demoDir}/demo-report.md`, lines.join("\n"))
  console.log(`report: ${pass}/${checks.length} checks pass -> ${demoDir}/demo-report.md`)
  process.exit(fail === 0 ? 0 : 1)
}

const [mode] = process.argv.slice(2)
if (mode === "setup") runSetup(process.argv.slice(3))
else if (mode === "serve") runServe(process.argv.slice(3))
else if (mode === "report") runReport(process.argv.slice(3))
else usage()
