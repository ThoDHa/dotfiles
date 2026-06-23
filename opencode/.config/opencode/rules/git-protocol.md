# Git Protocol

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for version control operations, including commit creation, message formatting, and branch management.

### 1.1 Related Specifications

- [`core.md`](core.md): Core behavioral requirements (formal output standards)
- [`coding-standards.md`](coding-standards.md): Technical implementation requirements

---

## 2. Commit Analysis Requirements

### 2.1 Pre-Commit Analysis

Before creating commits, implementations MUST:

1. Review all staged changes
2. Review all unstaged changes that should be included
3. Identify the logical units of change present

Implementations MUST NOT create commits without analyzing the full scope of changes.

### 2.2 Change Identification

Implementations MUST identify and categorize all changes by type, using the canonical type taxonomy defined in [Section 5.2](#52-type-prefixes) "Type Prefixes" (feat, fix, docs, refactor, test, chore, style).

---

## 3. Commit Grouping Requirements

### 3.1 Logical Unit Separation

Implementations MUST separate unrelated changes into distinct commits.

Each commit MUST represent one complete, coherent logical change.

### 3.2 Relationship Preservation

Related changes MUST be grouped together in the same commit:

- A feature with its new tests
- A refactor with its updated documentation
- A fix with its new regression test

**Exception:** Changes that ALTER the expected behavior of EXISTING tests MUST be committed separately from the production code, per [`coding-standards.md` "Separation of Code and Test Changes"](coding-standards.md#56-separation-of-code-and-test-changes). New tests written for new code still group with that code.

### 3.3 Concern Separation

Different types of changes MUST be committed separately:

- Configuration changes separate from feature changes
- Dependency updates separate from code changes
- Formatting changes separate from logic changes

---

## 4. Commit Ordering Requirements

### 4.1 Dependency Order

Commits MUST be ordered by dependency:

1. Refactors MUST precede features that depend on them
2. Core/foundational changes MUST precede dependent changes
3. Infrastructure MUST precede code that uses it

### 4.2 Working State Guarantee

Each commit MUST leave the codebase in a functional state.

Implementations MUST NOT create commits that break the build, tests, or basic functionality.

---

## 5. Commit Message Requirements

### 5.1 Format Specification

Implementations MUST use conventional commit format:

```
<type>: <subject>

[optional body]

[optional footer]
```

### 5.2 Type Prefixes

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

### 5.3 Subject Line Requirements

The subject line MUST:

- Be 50 characters or fewer
- Use imperative mood ("add feature" not "added feature")
- Not end with a period
- Describe WHAT changed

### 5.4 Body Requirements

When a body is included, it MUST:

- Be separated from subject by one blank line
- Wrap at 72 characters
- Explain WHY the change was made (not just what)
- Provide context that the diff cannot convey

### 5.5 Message Quality

Commit messages MUST be:

- Meaningful and specific
- Clear to someone unfamiliar with the context
- Free of generic phrases like "fix bug" or "update code"

Commit messages MUST NOT:

- Include personality voice or character
- Contain jokes or informal language
- Reference temporary states ("WIP", "temp fix")

---

## 6. Branch Naming Requirements

### 6.1 Branch Name Format

Implementations MUST use this branch naming format:

```
<type>/<short-description>
```

### 6.2 Branch Type Prefixes

Branch prefixes use the same type taxonomy as commit messages (see [Section 5.2](#52-type-prefixes) "Type Prefixes"), written in slash form: `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`.

### 6.3 Description Requirements

Branch descriptions MUST:

- Use kebab-case (lowercase with hyphens)
- Be 3-5 words maximum
- Be descriptive of the change

Examples:
- `feat/user-authentication`
- `fix/api-timeout-handling`
- `refactor/database-connection-pool`

### 6.4 Issue Reference

When a branch relates to a tracked issue, implementations SHOULD include the issue number:

```
fix/123-login-redirect-loop
feat/456-export-to-csv
```

---

## 7. Execution Requirements

### 7.1 Staging Protocol

Implementations MUST stage and commit each logical group separately.

Implementations MUST NOT use `git add .` when changes span multiple logical units.

### 7.2 Reporting

After committing, implementations MUST report:

- Number of commits created
- Summary of each commit (type and subject)
- Any files that were intentionally excluded

---

## 8. Destructive Operation Safety

### 8.1 Force Push Protection

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

### 8.2 No-Verify Protection

Strict enforcement: `--no-verify` is a dangerous operation that bypasses important quality and security checks. The following rules are mandatory and non-negotiable.

#### 8.2.1 Automated Processes Prohibition

Automated tools, CI pipelines, scripts, and non-interactive agents MUST NOT use the `--no-verify` flag under any circumstances. Any automated attempt to bypass hooks must fail the job and be treated as a security incident.

#### 8.2.2 Human Interactive Usage

Human users MUST NOT use `--no-verify` except when all of the following conditions are met:

   a. The user is shown an explicit warning that pre-commit and commit-msg hooks will be bypassed.

   b. The user supplies a non-empty, clear justification for bypassing hooks. The exact justification text MUST be recorded verbatim in the commit message body as a footer line with the format:

   `No-Verify-Reason: <reason text>`

   c. The interactive confirmation flow echoes the justification back to the user and requires explicit acceptance. If the justification is blank or the user declines, the commit MUST be aborted.

#### 8.2.3 Mandatory Logging

The act of using `--no-verify` MUST be recorded immediately in the repository under `.opencode/no-verify.log`. Each log entry MUST include: ISO 8601 timestamp, committer identity (if available), justification text, and the commit hash. The repository MUST track this file in source control or via an auditable mechanism.

**Note:** Because `.opencode/` is recommended for gitignore (see [`task-files.md`](task-files.md#33-gitignore-recommendation)), this audit log MUST be explicitly un-ignored (for example, a `!.opencode/no-verify.log` negation rule) or stored in an equivalent auditable location, so the log remains tracked and tamper-evident.

#### 8.2.4 Repository Enforcement

Repositories and CI systems MUST implement checks that reject commits or pushes that use `--no-verify` without the required `No-Verify-Reason` footer and a matching log entry. Hooks or CI jobs that enforce this policy are REQUIRED.

#### 8.2.5 Escalation and Conformance

Any use of `--no-verify` that does not follow these rules is a critical conformance failure. Such incidents MUST be reported immediately to repository maintainers and operational security contacts. A maintainer-level investigation MUST occur and a remediation plan documented.

### 8.3 Safe Push Behavior

When a force push is unavoidable and approved per [Section 8.1](#81-force-push-protection), implementations MUST use `git push --force-with-lease` instead of `git push --force` (or `git push -f`), except where `--force-with-lease` cannot establish the remote's expected ref-state, in which case the explicit `--force-with-lease=<refname>:<expected>` form MUST be used.

`force-with-lease` is safer because it checks if the remote branch has been updated by others before overwriting.

---

## 9. Conformance

ALL requirements in this specification are mandatory. Any violation of MUST or MUST NOT constitutes an immediate conformance failure, including the message quality requirements in [Section 5.5](#55-message-quality) and the destructive operation safety requirements in [Section 8](#8-destructive-operation-safety).

Proceeding with a force push without the explicit user confirmation required by [Section 8.1](#81-force-push-protection), or using `--no-verify` without the recorded justification footer and audit log entry required by [Section 8.2](#82-no-verify-protection), is a critical safety violation and constitutes immediate conformance failure.

---

*This specification defines version control requirements for all OpenCode implementations.*
