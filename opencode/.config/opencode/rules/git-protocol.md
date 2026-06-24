# Git Protocol

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## Scope

This specification defines requirements for version control operations, including commit creation, message formatting, and branch management.

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements (formal output standards)
- [`coding-standards.md`](coding-standards.md): Technical implementation requirements

---

## Commit Analysis Requirements

### Pre-Commit Analysis

Before creating commits, implementations MUST:

1. Review all staged changes
2. Review all unstaged changes that should be included
3. Identify the logical units of change present

Implementations MUST NOT create commits without analyzing the full scope of changes.

### Change Identification

Implementations MUST identify and categorize all changes by type, using the canonical type taxonomy defined in [Type Prefixes](#type-prefixes) "Type Prefixes" (feat, fix, docs, refactor, test, chore, style).

---

## Commit Grouping Requirements

### Logical Unit Separation

Implementations MUST separate unrelated changes into distinct commits.

Each commit MUST represent one complete, coherent logical change.

### Relationship Preservation

Related changes MUST be grouped together in the same commit:

- A feature with its new tests
- A refactor with its updated documentation
- A fix with its new regression test

**Exception:** Changes that ALTER the expected behavior of EXISTING tests MUST be committed separately from the production code, per [`coding-standards.md` "Separation of Code and Test Changes"](coding-standards.md#separation-of-code-and-test-changes). New tests written for new code still group with that code.

### Concern Separation

Different types of changes MUST be committed separately:

- Configuration changes separate from feature changes
- Dependency updates separate from code changes
- Formatting changes separate from logic changes

---

## Commit Ordering Requirements

### Dependency Order

Commits MUST be ordered by dependency:

1. Refactors MUST precede features that depend on them
2. Core/foundational changes MUST precede dependent changes
3. Infrastructure MUST precede code that uses it

### Working State Guarantee

Each commit MUST leave the codebase in a functional state.

Implementations MUST NOT create commits that break the build, tests, or basic functionality.

---

## Commit Message Requirements

### Format Specification

Implementations MUST use conventional commit format:

```
<type>: <subject>

[optional body]

[optional footer]
```

### Type Prefixes

Implementations MUST use these type prefixes:

| Prefix | Purpose |
|--------|---------|
| `feat:` | New features or functionality |
| `fix:` | Bug fixes |
| `docs:` | Documentation changes only |
| `refactor:` | Code restructuring without behavior change |
| `test:` | Test additions or modifications |
| `chore:` | Maintenance, dependencies, tooling |
| `style:` | Formatting, whitespace (no logic change) |

### Subject Line Requirements

The subject line MUST:

- Be 50 characters or fewer
- Use imperative mood ("add feature" not "added feature")
- Not end with a period
- Describe WHAT changed

### Body Requirements

When a body is included, it MUST:

- Be separated from subject by one blank line
- Wrap at 72 characters
- Explain WHY the change was made (not just what)
- Provide context that the diff cannot convey

### Message Quality

Commit messages MUST be:

- Meaningful and specific
- Clear to someone unfamiliar with the context
- Free of generic phrases like "fix bug" or "update code"

Commit messages MUST NOT:

- Include personality voice or character
- Contain jokes or informal language
- Reference temporary states ("WIP", "temp fix")

---

## Branch Naming Requirements

### Branch Name Format

Implementations MUST use this branch naming format:

```
<type>/<short-description>
```

### Branch Type Prefixes

Branch prefixes use the same type taxonomy as commit messages (see [Type Prefixes](#type-prefixes) "Type Prefixes"), written in slash form: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`.

### Description Requirements

Branch descriptions MUST:

- Use kebab-case (lowercase with hyphens)
- Be 3-5 words maximum
- Be descriptive of the change

Examples:
- `feat/user-authentication`
- `fix/api-timeout-handling`
- `refactor/database-connection-pool`

### Issue Reference

When a branch relates to a tracked issue, implementations SHOULD include the issue number:

```
fix/123-login-redirect-loop
feat/456-export-to-csv
```

---

## Execution Requirements

### Staging Protocol

Implementations MUST stage and commit each logical group separately.

Implementations MUST NOT use `git add .` when changes span multiple logical units.

### Reporting

After committing, implementations MUST report:

- Number of commits created
- Summary of each commit (type and subject)
- Any files that were intentionally excluded

---

## Destructive Operation Safety

### Force Push Protection

Implementations MUST NOT execute force pushes (`git push --force` or `git push -f`) without explicit user confirmation.

Before proceeding with a force push, implementations MUST:

1. Warn the user about the destructive nature of the operation
2. Attempt to determine and explain what will be overwritten; if it cannot be detected, explicitly state that the overwritten content could not be determined
3. Ask for explicit confirmation to proceed

Required confirmation prompt:

```
WARNING: Force push will overwrite remote history. This action cannot be undone.

Continue with force push? (y/n): _
```

### No-Verify Protection

`--no-verify` is a dangerous operation that bypasses important quality and security checks. The following rules are mandatory and non-negotiable.

#### Automated Processes Prohibition

Automated tools, CI pipelines, scripts, and non-interactive agents MUST NOT use the `--no-verify` flag under any circumstances. Any automated attempt to bypass hooks must fail the job and be treated as a security incident.

#### Human Interactive Usage

A human user MAY use `--no-verify` ONLY when shown an explicit warning that pre-commit and commit-msg hooks will be bypassed AND the user supplies a non-empty justification, which MUST be recorded verbatim in the commit message body as a footer line: `No-Verify-Reason: <reason text>`. If the justification is blank or the user declines, the commit MUST be aborted.

#### Mandatory Logging

Each use of `--no-verify` MUST be logged with an ISO 8601 timestamp, committer identity (if available), justification text, and the commit hash.

### Safe Push Behavior

When a force push is unavoidable and approved per [Force Push Protection](#force-push-protection), implementations MUST use `git push --force-with-lease` instead of `git push --force` (or `git push -f`), except where `--force-with-lease` cannot establish the remote's expected ref-state, in which case the explicit `--force-with-lease=<refname>:<expected>` form MUST be used.

`force-with-lease` is safer because it checks if the remote branch has been updated by others before overwriting.

---

## Conformance

ALL requirements in this specification are mandatory. Any violation of MUST or MUST NOT constitutes an immediate conformance failure, including the message quality requirements in [Message Quality](#message-quality) and the destructive operation safety requirements in [Destructive Operation Safety](#destructive-operation-safety).

Proceeding with a force push without the explicit user confirmation required by [Force Push Protection](#force-push-protection), or using `--no-verify` without the recorded justification footer and audit log entry required by [No-Verify Protection](#no-verify-protection), is a critical safety violation and constitutes immediate conformance failure.

---

*This specification defines version control requirements for all OpenCode implementations.*
