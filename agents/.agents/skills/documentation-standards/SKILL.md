---
name: documentation-standards
description: Documentation standards covering prohibited vague bullet patterns, substance requirements, specific concrete language, documentation-specific punctuation rules, and the one-paragraph-per-line wrapping format for markdown documentation. Use when writing or reviewing documentation, README files, CHANGELOG entries, PR descriptions, technical specifications, code comments and docstrings, or any extended prose output.
---

# Documentation Standards

---

## Scope

This specification defines requirements for documentation, README files, and prose written by implementations. These standards ensure clear, substantive writing without lazy shorthand patterns.

### Related Specifications

- The `coding-standards` rule (always loaded): technical implementation requirements
- The `core` rule (always loaded): core behavioral requirements

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

An entry MUST satisfy all of the following to be substantive:
- Specific enough to be actionable or informative
- Contains detail that could not be inferred from the heading alone
- Answers "what," "how," or "why," rather than merely naming a topic

---

## Punctuation Requirements

Punctuation in prose follows the core rule's Punctuation and Formatting Requirements. The three rules below are documentation-specific and supplement that canonical section.

### Em-Dash Prohibition

The em-dash prohibition in the core rule's Punctuation and Formatting Requirements extends to all prose written by implementations, formal documentation included. When connecting clauses or introducing an explanation, implementations MUST use a colon, comma, parentheses, or period as defined in that canonical section.

### Colon-as-Enthusiasm-Break Prohibition

Implementations MUST NOT use a colon as a casual enthusiasm break that splices an unrelated exclamation onto a clause (for example, `Click here: it works great!`). This restriction targets ONLY the lazy break. The colon remains the correct punctuation for introducing a genuine explanation or list.

### En-Dash Numeric-Range Rule

An en-dash (`–`) is permitted ONLY tight-bound between the endpoints of a numeric range (for example, `pages 5–12`). It MUST NEVER be space-flanked as a clause connector (for example, `Try this – you'll love it`).

---

## Line-Wrapping Format

**Scope of [Line-Wrapping Format](#line-wrapping-format):** This rule governs the physical line structure of markdown documentation files. It applies to design documents, README files, CHANGELOG entries, technical specifications, and extended prose. It does NOT apply to source code, configuration files, table cells, fenced code examples, or frontmatter, and it constrains line structure only, never wording.

### One Paragraph Per Line

Prose in a markdown documentation file MUST be written unwrapped: each paragraph occupies exactly one physical line, with no hard wrapping and no fixed column limit. Column limits, where a project sets them for source code, do not govern `.md` files. Structural line breaks are preserved: headings, list items (each item on its own line), table rows, and fenced code blocks keep their existing line structure, and only prose paragraphs are joined. A line break inside a prose paragraph is a formatting defect to fix by joining the lines, not a structure to preserve; under this rule the physical line count of a markdown file carries no meaning.

Enforcement applies to prose being written or edited: newly written prose follows this format, and an existing wrapped file conforms when it is substantively edited, in the regions the edit touches. A wholesale reflow of an otherwise untouched file is a deliberate maintenance task, not an obligation that attaches on contact.

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

Violations of MUST requirements constitute conformance failures, including the writing patterns prohibited in [Prohibited Writing Patterns](#prohibited-writing-patterns), the punctuation prohibitions in [Punctuation Requirements](#punctuation-requirements), and the wrapping requirements in [Line-Wrapping Format](#line-wrapping-format).
