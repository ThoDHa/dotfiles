# Documentation Standards

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## Scope

This specification defines requirements for documentation, README files, and prose written by implementations. These standards ensure clear, substantive writing without lazy shorthand patterns.

### Related Specifications

- [`coding-standards.md`](coding-standards.md): Technical implementation requirements
- [`core.md`](core.md): Core behavioral requirements

---

## Prohibited Writing Patterns

**Scope of Sections [2](#prohibited-writing-patterns) and [3](#punctuation-requirements):** These rules govern prose. They do NOT apply to table cells, fenced code examples, or `term: definition` reference lists (including the illustrative tables, code fences, and reference lists within this document itself). Those structures are exempt, since they exist to demonstrate patterns or define terms concisely rather than to read as continuous prose.

### Vague Bullet Lists

Implementations MUST NOT use lazy bullet point patterns that substitute for actual explanation.

Prohibited patterns include:

| Pattern | Example | Problem |
|---------|---------|---------|
| `- <noun>` alone | `- Authentication` | States a topic without explaining it |
| `- <noun>: <vague phrase>` | `- Security: handled properly` | Provides no actionable information |
| `- <verb> <thing>` | `- Update dependencies` | Lacks context, rationale, or detail |
| `- etc.` or `- and more` | `- etc.` | Lazy placeholder that adds nothing |

### Examples of Prohibited vs Acceptable

**Prohibited:**
```
Features:
- Authentication
- Authorization  
- Logging
- Error handling
```

**Acceptable:**
```
Features:
- JWT-based authentication with refresh token rotation
- Role-based authorization using middleware guards
- Structured JSON logging with correlation IDs
- Centralized error handling with meaningful error codes
```

**Prohibited:**
```
Changes:
- Fixed bug
- Updated code
- Improved performance
```

**Acceptable:**
```
Changes:
- Fixed null reference when user profile is incomplete
- Refactored database queries to use connection pooling
- Reduced API latency by 40% through response caching
```

### Substance Requirement

Every bullet point, list item, or documentation entry MUST provide substantive information.

An entry MUST satisfy ALL of the following to be substantive:
- Specific enough to be actionable or informative
- Contains detail that could not be inferred from the heading alone
- Answers "what," "how," or "why," rather than merely naming a topic

---

## Punctuation Requirements

Punctuation in prose follows [core.md Punctuation and Formatting Requirements](core.md#punctuation-and-formatting-requirements). The two rules below are documentation-specific and supplement that canonical section.

### Colon-as-Enthusiasm-Break Prohibition

Implementations MUST NOT use a colon as a casual enthusiasm break that splices an unrelated exclamation onto a clause (for example, `Click here: it works great!`). This restriction targets ONLY the lazy break. The colon remains the CORRECT punctuation for introducing a genuine explanation or list.

### En-Dash Numeric-Range Rule

An en-dash (`–`) is permitted ONLY tight-bound between the endpoints of a numeric range (for example, `pages 5–12`). It MUST NEVER be space-flanked as a clause connector (for example, `Try this – you'll love it`).

---

## Prose Quality Requirements

### Completeness

Documentation MUST explain concepts fully with detailed descriptions, and MUST NOT name a concept without explaining it. This prohibition is consistent with [Prohibited Writing Patterns](#prohibited-writing-patterns) (Prohibited Writing Patterns).

### Specificity

Implementations MUST use specific, concrete language over vague generalities.

| Vague | Specific |
|-------|----------|
| "handles errors properly" | "catches exceptions at API boundaries and returns structured error responses" |
| "improves performance" | "reduces memory allocation by reusing buffers" |
| "adds security" | "validates input against whitelist and sanitizes output" |

---

## Conformance

Violations of MUST requirements constitute conformance failures. This includes the writing patterns prohibited in [Prohibited Writing Patterns](#prohibited-writing-patterns) (vague bullet lists) and the punctuation prohibitions in [Punctuation Requirements](#punctuation-requirements) (casual dash and colon separators).

---

*This specification defines documentation quality requirements for all OpenCode implementations.*
