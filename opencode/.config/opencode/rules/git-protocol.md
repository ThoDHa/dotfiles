# Git Protocol

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for version control operations, including commit creation, message formatting, and branch management.

### 1.1 Related Specifications

- `core.md`: Core behavioral requirements (formal output standards)
- `coding-standards.md`: Technical implementation requirements

---

## 2. Commit Analysis Requirements

### 2.1 Pre-Commit Analysis

Before creating commits, implementations MUST:

1. Review all staged changes
2. Review all unstaged changes that should be included
3. Identify the logical units of change present

Implementations MUST NOT create commits without analyzing the full scope of changes.

### 2.2 Change Identification

Implementations MUST identify and categorize all changes by type:

- Features (new functionality)
- Fixes (bug corrections)
- Refactors (structural changes without behavior change)
- Documentation (docs, comments, README)
- Tests (test additions or modifications)
- Chores (dependencies, tooling, configuration)
- Style (formatting, whitespace)

---

## 3. Commit Grouping Requirements

### 3.1 Logical Unit Separation

Implementations MUST separate unrelated changes into distinct commits.

Each commit MUST represent one complete, coherent logical change.

### 3.2 Relationship Preservation

Related changes MUST be grouped together in the same commit:

- A feature with its tests
- A refactor with its updated documentation
- A fix with its regression test

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

| Prefix | Purpose |
|--------|---------|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `docs/` | Documentation |
| `test/` | Test additions |
| `chore/` | Maintenance tasks |

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
2. Explain what will be overwritten (if detectable)
3. Ask for explicit confirmation to proceed

Required confirmation prompt:

```
WARNING: Force push will overwrite remote history. This action cannot be undone.

Continue with force push? (y/n): _
```

### 8.2 No-Verify Protection

Implementations MUST NOT execute commits with `--no-verify` flag without explicit user confirmation.

Before proceeding with a no-verify commit, implementations MUST:

1. Warn the user that pre-commit and commit-msg hooks will be bypassed
2. Explain what hooks are being skipped
3. Ask for explicit confirmation to proceed

Required confirmation prompt:

```
WARNING: Commit with --no-verify will bypass all git hooks (pre-commit, commit-msg, etc.).

Continue with no-verify commit? (y/n): _
```

### 8.3 Safe Push Behavior

Implementations MAY use `git push --force-with-lease` instead of `git push --force` when appropriate.

`force-with-lease` is safer because it checks if the remote branch has been updated by others before overwriting.

---

## 9. Conformance

ALL requirements in this specification are mandatory. Any violation of MUST or MUST NOT constitutes an immediate conformance failure.

Poorly formatted or unclear commit messages degrade repository history and are considered conformance failures.

Proceeding with force pushes or --no-verify commits without user confirmation is a critical safety violation and constitutes immediate conformance failure.

---

*This specification defines version control requirements for all OpenCode implementations.*
