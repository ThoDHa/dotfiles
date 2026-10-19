# Coding Standards

---

## Scope

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`execution-standards.md`](execution-standards.md): Task execution requirements
- The `git-protocol` skill (version control) is loaded on demand via the skill tool

---

## Code Reuse Requirements

Implementations MUST search the current codebase and package registries for existing solutions, and evaluate whether they meet requirements, before implementing custom code. When equivalent functionality exists, implementations MUST use the existing implementation, extending it if modifications are needed, and MUST NOT create duplicate utility functions. Implementations MUST NOT create custom implementations when adequate solutions exist unless an existing solution has a concrete technical limitation that disqualifies it (unacceptable performance or unacceptable dependencies). A bypass MUST be justified by the specific limitation, not merely asserted, and MUST be documented in a code comment explaining why each existing solution was rejected.

Repeated code patterns (3+ occurrences) SHOULD be extracted into a reusable helper function, class, or module in a designated shared location (utility functions in utilities/helpers directories, shared types in types/models directories, common constants in constants/config directories), documented with purpose and usage, following the language's and project's prevailing conventions. Genuine duplication is extracted; implementations MUST NOT add abstraction layers that introduce indirection without removing duplication. Patterns spanning multiple projects SHOULD become a shared internal library or dedicated SDK, documented centrally for team discovery. Named exports with descriptive identifiers are preferred over default exports unless the project's conventions dictate otherwise.

---

## Literal Value Requirements

Literal values follow the language's and project's prevailing conventions for naming and placement. Numeric and string literals whose meaning matters use named constants, enums, or configuration entries with descriptive identifiers: numeric values that are not obvious from context (indices and trivial arithmetic excepted), error messages reused in multiple locations, API endpoints or route paths, status codes or state identifiers, and feature flags or toggle names. Values that may vary between environments MUST be externalized rather than hardcoded: environment-specific values via environment variables, application settings via dedicated configuration files, and feature flags via a centralized feature management system or config.

---

## Error Handling Requirements

Failures from external interactions (network requests, database operations, file system operations, subprocess execution, fallible third-party libraries) MUST be handled at an appropriate boundary rather than wrapped uniformly at every call site, without redundant intermediate catches that only log or re-raise the error unchanged. The handling MUST either resolve the error completely or re-throw it with additional context (errors are never silently swallowed and MUST NOT be caught only to log and ignore), provide meaningful context for debugging, release resources per [Resource Cleanup](#resource-cleanup), and log at appropriate severity levels where the error is handled or transformed rather than at every catch point.

Error messages MUST describe what operation failed, include relevant context (identifiers, parameters, state), provide actionable information, suggesting remediation when a known remediation exists, suit the intended audience (user vs developer), protect sensitive information (internal paths and stack traces from end users; secrets per [Secrets Management](#secrets-management)), and focus on the system issue rather than user fault. Errors MUST bubble up to appropriate handling boundaries unless handled completely at the point of capture, MUST be caught at module/service boundaries for logging and transformation, and MUST NOT cross API boundaries without sanitization.

---

## Testing Requirements

### Test Coverage and Standards

Implementations MUST write tests for core business logic functions, data transformation and validation functions, error handling paths, security-sensitive operations, and integration points with external services, and critical path tests MUST verify both success and failure conditions. Implementations SHOULD write tests for all new functionality.

Implementations MUST NOT reduce existing test coverage when modifying code: reducing coverage includes deleting, disabling, or skipping tests and weakening assertions or fixtures (for example, loosening expected outcomes or narrowing tested inputs), whether they verify success or failure conditions. The sole exception is removal of the covered code itself.

Test names MUST describe the system under test, the scenario, and the expected behavior, in the project's naming convention, and MUST NOT reference bug IDs, temporary states, or vague identifiers. Tests MUST test one logical concept per case, be independent and not rely on test execution order, and clean up any state they create. Tests SHOULD include edge cases and boundary conditions, use realistic test data, be fast enough to run frequently, and use the AAA pattern (Arrange, Act, Assert) when appropriate.

### Test Result Verification

Test run verification MUST gate on the tool's own reported result (the exit status or result code when it encodes the outcome, the reported result metrics when it does not), never on text matching against output, because failed runs also print summary lines a filter matches. Reported results MUST account for every outcome class the runner reports: passed, failed, skipped, and error counts, each named explicitly. Any non-zero failure or error count MUST be investigated before the run is treated as green ([Prohibited Test Behaviors](#prohibited-test-behaviors)). Skips are differentiated: a skip that existing documentation records as expected MAY be named and the run accepted; a new, changed, or unexplained skip MUST be investigated before the run is treated as green. Where output is truncated or filtered for length, the unfiltered summary (total, passed, failed, skipped) and the runner's exit status MUST still be captured directly at the point of invocation and reported; filtered reading MUST NOT be the sole failure signal.

### Prohibited Test Behaviors

Implementations MUST NOT skip, disable, or comment out failing tests, or use skip annotations or conditional ignores to hide them. When tests fail, implementations MUST fix the underlying bug by addressing the code issue, by fixing the test if the test itself is incorrect, or by consulting with the team if the expected behavior has changed.

### Test Planning Requirement

All code implementation plans MUST include a test plan specifying what will be tested, what types of tests will be written (unit, integration, e2e), and the key scenarios and edge cases to cover. If testing is not required for a change, implementations MUST document why testing is unnecessary (e.g., configuration-only change, documentation update, trivial rename with existing coverage).

### Separation of Code and Test Changes

Code and test changes that form one logical change SHOULD land together in a single atomic, green commit; atomic, green, logically complete commits are the default review and revert unit. NEW tests for NEW feature code are grouped WITH that code per the `git-protocol` skill's Relationship Preservation section.

Separation is reserved for changes where the production fix and the test-expectation update are each independently meaningful: the production fix lands first, the test update documenting the new expected behavior second, referencing the related issue or the original change. The ordered pair MUST be pushed together as one landing: the red intermediate MUST NOT be pushed or integrated as its own landing, the test suite MUST be green at the pull request head and at every landed tip, and the red intermediate is permitted only as the first commit of the pair, where it MUST comply with the `git-protocol` skill's Working State Guarantee. Test-only behavior changes MUST reference an issue, design decision, or reviewer approval that authorizes them.

### Test Change Intent Verification

When modifying tests with the goal of making them pass (rather than in the course of developing new features), implementers MUST verify that the change reflects intended system behavior and not an accidental regression, side effect, or masking of a real defect: review relevant git history, commit messages, and project documentation for the original intent behind the test and the logic it validates; analyze whether the failing test indicates a real bug, a deliberate business rule change, or an obsolete expectation; update the test ONLY when the intended behavior has changed; and document the rationale in the commit message, referencing relevant git history or stakeholder decisions. If the intent is unclear or disputed, implementers MUST escalate to relevant reviewers, stakeholders, or product owners before altering the test.

---

## Documentation Requirements

### Function Documentation

Functions with public or nonobvious contracts MUST carry a function header (docstring) documenting their behavior: public API boundaries, contracts crossing module boundaries, and internal functions whose intent the code does not make obvious on its own. Trivial internal functions MAY remain self-documenting without a header. Where a header is required, it MUST include, when applicable: a purpose description, parameter descriptions with types and constraints, the return value description, side effects, and exceptions or errors that may be thrown.

### General Documentation

Implementations SHOULD document complex algorithms with explanatory comments, subject to the [Comment Policy](#comment-policy), and non-obvious implementation decisions. When modifying code, implementations MUST update associated documentation and MUST NOT leave it stale; stale documentation is worse than no documentation.

### Comment Policy

This policy governs inline code comments; docstrings follow [Function Documentation](#function-documentation) above. Comments are absent by default: implementations MUST NOT add comments unless the user explicitly requests them or the narrow exception below applies, and before adding any comment implementations MUST first attempt self-explanatory code by renaming variables, functions, or types, extracting logic into named functions, simplifying expressions, and introducing named constants. An autonomous comment is permitted ONLY when ALL of the following hold: the code cannot express its intent on its own after those attempts, the comment explains non-obvious WHY rather than WHAT, and removing it would leave a future reader genuinely confused. Written comments MUST be direct and conversational, and MUST NOT restate what the code already expresses, use filler markers (`Note:`, `Important:`, `Consider:`, `This function...`, `Here we...`), or decorate code with section banners, file-level manifestos, or closing summaries.

A TODO/FIXME is acceptable only with a concrete description and a tracking reference (e.g., `TODO(#142): stream from disk once files exceed 1 GB`); untracked TODOs are barred. Comments MUST NEVER document internal bug-fixing history: bug IDs, attribution, fix chronology, or temporal references ("previously", "before the fix"); internal bugs belong exclusively in commit messages and issue trackers. External library workarounds are the exception: they MUST be documented in comments with full context, including library name and version, issue reference if available, expected vs actual behavior, and the conditions for removing the workaround. Choose the right home for information: inline comments for code context and library workarounds; commit messages for what changed, why, and bug-fix history; formal documentation for architecture, API specifications, and deployment guidance.

---

## Type Safety Requirements

### Strict Typing Requirement

Implementations MUST use the strictest type-checking mode available in the project's language and tooling: strict/pedantic compiler flags, static type checkers where available, function-signature annotations per [Type Annotation Boundaries](#type-annotation-boundaries), and no type-escape mechanisms (e.g., `any`, `Object`, `void*`, dynamic casts).

Type-escape mechanisms MAY be used ONLY when a concrete technical constraint requires it: interfacing with untyped external libraries, or the type system cannot express the required constraint. An escape MUST be justified by the specific constraint, not merely asserted, and documented in a code comment.

### Type Annotation Boundaries

Implementations SHOULD allow type inference for local variables where the type is obvious. Implementations MUST NOT rely on type inference for function parameters, function return types, public API boundaries, or data structures crossing module boundaries.

---

## Code Quality Tool Requirements

### Linting and Static Analysis

Implementations MUST NOT disable linting rules, static analysis warnings, or code quality checks except when unavoidable and justified. When unavoidable, implementations MUST use the most targeted suppression available (single line over file-wide, file-wide over project-wide), document the specific reason why the rule cannot be satisfied, and reference any related issue or technical constraint. Implementations MUST NOT suppress security-related warnings, type safety warnings, unused variable warnings (remove the variable instead), or any warning that can be resolved by fixing the code; the sanctioned responses are fixing the code, restructuring the implementation, or escalating to the user or maintainer, and suppression is barred even where the warning appears to be an unfixable false positive.

### Naming Conventions

Case style (camelCase, snake_case, and similar) follows the project's linter or formatter configuration per [Community Standards and Configuration](#community-standards-and-configuration); this subsection governs semantic naming. Implementations MUST use descriptive, proportionate names: one- and two-letter names are barred except for loop counters in tight scopes and established identifiers; function names MUST state the operation performed as a concise verb phrase, neither cryptic nor padded; abbreviations MUST NOT truncate words into opaque fragments, though established domain terms are acceptable; one concept keeps one name across the codebase, and mixing synonyms for one operation is barred; boolean identifiers MUST read as predicates.

### Community Standards and Configuration

Implementations MUST use widely accepted community coding standards, linters, and formatters for the target language and framework: start from official or recommended rule sets and default configurations; minimize deviations, documenting specific justifications when deviations are necessary; commit lint and format configurations to version control and enforce them in CI; where a standard formatter exists, use it consistently rather than introducing competing tools. Implementations SHOULD prefer stable, well-maintained tools with broad adoption.

---

## Security Requirements

### Input Validation

Implementations MUST validate all external input before processing: user input from forms, APIs, and command-line arguments; data from external services or files; and environment variables used in logic. Validation MUST include type checking (expected data type), range or length bounds (where applicable), format validation (pattern matching for structured strings), and whitelist validation for enumerated values.

### Output Sanitization

Implementations MUST sanitize output when rendering user-provided content in HTML, constructing database queries, building shell commands, or logging potentially sensitive data. Implementations MUST use parameterized queries or prepared statements for database operations, and MUST NOT construct queries or commands via string concatenation with user input.

### Secrets Management

Implementations MUST NOT hardcode secrets, API keys, or credentials in source code, commit secrets to version control, log secrets at any log level, or include secrets in error messages or stack traces. Secrets MUST be loaded from environment variables, dedicated secrets management systems, or encrypted configuration with proper key management.

### Extended Security Considerations

An application is security-sensitive when it exposes a network service or handles authentication, personal data, or payment data. For security-sensitive applications, implementations MUST address the following according to project security requirements: authentication and authorization patterns, session management and token handling, rate limiting and abuse prevention, CORS and CSP header configuration, dependency vulnerability scanning, and security audit logging. Each consideration MUST be either implemented or explicitly documented as not applicable, with justification.

---

## Performance Requirements

### Algorithmic Complexity Awareness

Implementations MUST consider algorithmic complexity for operations on collections: O(n²) or worse algorithms MUST be documented with justification, nested loops over the same collection MUST be reviewed for optimization, and large dataset operations MUST use streaming or pagination patterns when the dataset can exceed available memory or is unbounded. Implementations MUST NOT use inefficient algorithms when efficient alternatives are readily available.

### Async and Concurrent Patterns

In applications with concurrency requirements, implementations MUST NOT block the main thread or event loop with synchronous I/O: network I/O (API calls, database queries), file system operations on multiple files, and other long-running or latency-sensitive work use the language's asynchronous or nonblocking patterns where the runtime provides them. Concurrency MUST be justified by need rather than introduced as a default structure; when parallelizing work, implementations MUST limit concurrent operations to prevent resource exhaustion, handle partial failures gracefully, and provide cancellation mechanisms for long-running operations.

### Resource Cleanup

Implementations MUST ensure cleanup of file handles, database connections, network sockets, event subscriptions and listeners, and timers and scheduled tasks, using the language's idiomatic resource management pattern (e.g., try/finally, context managers, defer, RAII, using statements). Resources MUST be released on both success and failure paths.

---

## Solution Selection Requirements

Implementations MUST prioritize correctness over simplicity: when a solution is both correct and simple it is optimal, and simple solutions that sacrifice correctness are not acceptable.

### Simple Solution Documentation

A simple solution that is correct and appropriately scoped needs no fuller-solution record. When a chosen solution knowingly omits material capability or robustness, implementations MUST document the omission, describe what the more comprehensive or correct solution would entail, and create a tracking item (issue, tracked TODO, or ticket) for the future improvement, keeping technical debt visible and actionable.

---

Conformance is canonical in the core rule's [Conformance](core.md#conformance) section.
