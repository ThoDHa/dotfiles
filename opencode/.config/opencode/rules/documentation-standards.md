# Documentation Standards

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for documentation, README files, and prose written by implementations. These standards ensure clear, substantive writing without lazy shorthand patterns.

### 1.1 Related Specifications

- `coding-standards.md`: Technical implementation requirements
- `core.md`: Core behavioral requirements

---

## 2. Prohibited Writing Patterns

### 2.1 Vague Bullet Lists

Implementations MUST NOT use lazy bullet point patterns that substitute for actual explanation.

Prohibited patterns include:

| Pattern | Example | Problem |
|---------|---------|---------|
| `- <noun>` alone | `- Authentication` | States a topic without explaining it |
| `- <noun>: <vague phrase>` | `- Security: handled properly` | Provides no actionable information |
| `- <verb> <thing>` | `- Update dependencies` | Lacks context, rationale, or detail |
| `- etc.` or `- and more` | `- etc.` | Lazy placeholder that adds nothing |

### 2.2 Examples of Prohibited vs Acceptable

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

### 2.3 Substance Requirement

Every bullet point, list item, or documentation entry MUST provide substantive information.

Substantive means:
- Specific enough to be actionable or informative
- Contains detail that could not be inferred from the heading alone
- Answers "what," "how," or "why": not just naming a topic

---

## 3. Punctuation Requirements

### 3.1 Dash as Separator Prohibition

Implementations MUST NOT use hyphens or dashes as casual separators in prose.

Prohibited patterns:

| Pattern | Example | Problem |
|---------|---------|---------|
| ` - ` as separator | `Do this - it is fun!` | Informal, improper punctuation |
| `: ` as casual break | `Click here: it works great!` | Overused, lazy writing |
| ` – ` as connector | `Try this – you'll love it` | Substitutes for proper structure |

### 3.2 Acceptable Alternatives

Instead of dashes as separators, implementations MUST use proper punctuation:

| Use Case | Correct Approach | Example |
|----------|------------------|---------|
| Adding information | Period | `Do this. It is very useful.` |
| Parenthetical aside | Parentheses | `Do this (it is very useful).` |
| Introducing explanation | Colon | `Do this: it simplifies the workflow.` |
| Connecting related clauses | Semicolon | `Do this; it simplifies the workflow.` |
| Adding non-essential info | Comma | `Do this, as it really helps.` |

### 3.3 Legitimate Dash Usage

Dashes MAY be used for:

- Numeric ranges: `lines 10-20`, `pages 5–12`
- Compound modifiers: `well-known`, `user-defined`
- CLI flags and options: `--verbose`, `-h`
- Code identifiers: `my-component`, `api-gateway`

---

## 4. Prose Quality Requirements

### 4.1 Completeness

Documentation MUST explain concepts fully rather than listing topics.

Implementations MUST NOT write documentation that merely names things without explaining them.

### 4.2 Specificity

Implementations MUST use specific, concrete language over vague generalities.

| Vague | Specific |
|-------|----------|
| "handles errors properly" | "catches exceptions at API boundaries and returns structured error responses" |
| "improves performance" | "reduces memory allocation by reusing buffers" |
| "adds security" | "validates input against whitelist and sanitizes output" |

---

## 5. Conformance

Violations of MUST requirements constitute conformance failures.

Lazy bullet lists that name topics without explanation fail to serve their documentary purpose and are conformance failures.

Casual dash usage as separators produces informal, unprofessional documentation and is a conformance failure.

---

*This specification defines documentation quality requirements for all OpenCode implementations.*
