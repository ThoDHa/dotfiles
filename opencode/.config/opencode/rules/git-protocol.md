# Git Commit Protocol

**RFC 2119 Compliant**

> Extracted from common behavioral requirements. These standards apply to all implementations.

---

## Overview

When requested to commit changes, implementations MUST execute the following protocol.

---

## Analysis Phase

1. **Review all modifications** - Both staged and unstaged changes MUST be analyzed
2. **Identify change scope** - Nothing SHALL be missed in the assessment

---

## Grouping Requirements

1. **Separate by logical unit** - Unrelated changes MUST be split into distinct commits
2. **Maintain coherence** - Each commit MUST represent one complete, coherent change
3. **Preserve relationships** - Related changes (e.g., feature with tests) MUST be grouped together
4. **Separate concerns** - Different types of changes (config, features, bug fixes, refactors, docs) MUST be committed separately

---

## Ordering Protocol

1. **Dependencies first** - Refactors MUST precede features that depend on them
2. **Core before peripheral** - Foundational changes MUST precede dependent changes  
3. **Working state guarantee** - Each commit MUST leave the codebase in a functional state

---

## Message Format Requirements

Implementations MUST use conventional commit format without exceptions:

| Prefix | Purpose |
|--------|---------|
| `feat:` | New features |
| `fix:` | Bug fixes |
| `docs:` | Documentation changes |
| `refactor:` | Code restructuring without behavior change |
| `test:` | Adding or updating tests |
| `chore:` | Maintenance, dependencies, tooling |
| `style:` | Formatting, whitespace (no code change) |

---

## Message Content Standards

1. **First line** - Type + concise summary (50 characters or less)
2. **Body** (if needed) - Explain motivation and reasoning, not just changes made
3. **Clarity requirement** - Messages MUST be meaningful and specific

---

## Execution Requirements

1. **Stage and commit** each logical group separately
2. **Report results** - Document what was committed for user visibility

---

*This protocol ensures clean, meaningful git history that serves both current development and future maintenance.*
