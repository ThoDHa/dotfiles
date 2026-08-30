# Documentation Standards

---

## Scope

This specification defines requirements for documentation, README files, and prose written by implementations. These standards ensure clear, substantive writing without lazy shorthand patterns.

### Related Specifications

- [`coding-standards.md`](coding-standards.md): Technical implementation requirements
- [`core.md`](core.md): Core behavioral requirements

---

## Prohibited Writing Patterns

**Scope of [Prohibited Writing Patterns](#prohibited-writing-patterns) and [Punctuation Requirements](#punctuation-requirements):** These rules govern prose. They do NOT apply to table cells, fenced code examples, or `term: definition` reference lists (including the illustrative tables, code fences, and reference lists within this document itself). Those structures are exempt, since they exist to demonstrate patterns or define terms concisely rather than to read as continuous prose.

### Vague Bullet Lists

Implementations MUST NOT use lazy bullet point patterns that substitute for actual explanation.

Prohibited patterns include:

| Pattern | Example | Problem |
|---------|---------|---------|
| `- <noun>` alone | `- Authentication` | States a topic without explaining it |
| `- <noun>: <vague phrase>` | `- Security: handled properly` | Provides no actionable information |
| `- <verb> <thing>` | `- Update dependencies` | Lacks context, rationale, or detail |
| `- etc.` or `- and more` | `- etc.` | Lazy placeholder that adds nothing |

**Prohibited vs acceptable (a topic named is worthless; the same topic substantiated is required):**

```
- Authentication                          <- prohibited: names a topic, explains nothing
- JWT-based authentication with refresh token rotation   <- acceptable
```

### Substance Requirement

Every bullet point, list item, or documentation entry MUST provide substantive information.

An entry MUST satisfy ALL of the following to be substantive:
- Specific enough to be actionable or informative
- Contains detail that could not be inferred from the heading alone
- Answers "what," "how," or "why," rather than merely naming a topic

---

## Punctuation Requirements

Punctuation in prose follows [core.md Punctuation and Formatting Requirements](core.md#punctuation-and-formatting-requirements). The three rules below are documentation-specific and supplement that canonical section.

### Em-Dash Prohibition

The em-dash prohibition in [core.md Punctuation and Formatting Requirements](core.md#punctuation-and-formatting-requirements) extends to all prose written by implementations, formal documentation included. When connecting clauses or introducing an explanation, implementations MUST use a colon, comma, parentheses, or period as defined in that canonical section.

### Colon-as-Enthusiasm-Break Prohibition

Implementations MUST NOT use a colon as a casual enthusiasm break that splices an unrelated exclamation onto a clause (for example, `Click here: it works great!`). This restriction targets ONLY the lazy break. The colon remains the CORRECT punctuation for introducing a genuine explanation or list.

### En-Dash Numeric-Range Rule

An en-dash (`–`) is permitted ONLY tight-bound between the endpoints of a numeric range (for example, `pages 5–12`). It MUST NEVER be space-flanked as a clause connector (for example, `Try this – you'll love it`).

---

## Prose Quality Requirements

### Completeness

Documentation MUST explain concepts fully with detailed descriptions, and MUST NOT name a concept without explaining it. This prohibition is consistent with [Prohibited Writing Patterns](#prohibited-writing-patterns).

### Specificity

Implementations MUST use specific, concrete language over vague generalities.

| Vague | Specific |
|-------|----------|
| "handles errors properly" | "catches exceptions at API boundaries and returns structured error responses" |
| "improves performance" | "reduces memory allocation by reusing buffers" |
| "adds security" | "validates input against whitelist and sanitizes output" |

---

## Conformance

Violations of MUST requirements constitute conformance failures, including the writing patterns prohibited in [Prohibited Writing Patterns](#prohibited-writing-patterns) and the punctuation prohibitions in [Punctuation Requirements](#punctuation-requirements).
