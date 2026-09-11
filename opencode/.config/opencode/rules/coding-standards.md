# Coding Standards

---

## Scope

This specification defines technical implementation requirements for code produced by OpenCode implementations, ensuring maintainable, secure, and performant code across all projects.

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`execution-standards.md`](execution-standards.md): Task execution requirements
- The `git-protocol` skill (version control) is loaded on demand via the skill tool

---

## Code Reuse Requirements

Implementations MUST search the current codebase and package registries for existing solutions, and evaluate whether they meet requirements, before implementing custom code. When equivalent functionality exists, implementations MUST use the existing implementation, extending it if modifications are needed, and MUST NOT create duplicate utility functions.

Implementations MUST NOT create custom implementations when adequate solutions exist unless an existing solution has a concrete technical limitation that disqualifies it (unacceptable performance or unacceptable dependencies). A bypass MUST be justified by the specific limitation, not merely asserted, and MUST be documented in a code comment explaining why each existing solution was rejected.

Repeated code patterns (3+ occurrences) MUST be extracted into a reusable helper function, class, or module in a designated shared location (utility functions in utilities/helpers directories, shared types in types/models directories, common constants in constants/config directories), documented with purpose and usage. Patterns spanning multiple projects SHOULD become a shared internal library or dedicated SDK, documented centrally for team discovery. Implementations MUST use named exports with descriptive identifiers over default exports.

---

## Literal Value Requirements

Implementations MUST NOT use literal numeric values except 0, 1, -1 in loop constructs and simple arithmetic, mathematical constants and unit conversion factors with obvious meaning (e.g., 100 for percentage, 60 for seconds per minute), and array/string indices when context is clear; all other numeric literals MUST be extracted to named constants with descriptive identifiers. Implementations MUST NOT use literal strings for configuration values, error messages used in multiple locations, API endpoints or route paths, status codes or state identifiers, or feature flags or toggle names; these MUST be extracted to constants, enums, or configuration files.

Implementations MUST externalize configuration values: environment-specific values MUST use environment variables, application settings MUST use dedicated configuration files, and feature flags MUST use a centralized feature management system or config. Implementations MUST NOT hardcode values that may vary between environments.

---

## Error Handling Requirements

Implementations MUST wrap all external calls (network requests, database operations, file system operations, subprocess execution, fallible third-party libraries) in language-appropriate error handling. The mechanism MUST either handle the error completely or re-throw it with additional context (errors are never silently swallowed and MUST NOT be caught only to log and ignore), provide meaningful context for debugging, release resources per [Resource Cleanup](#resource-cleanup), and log errors at appropriate severity levels at the boundary where they are handled or transformed rather than at every catch point.

Error messages MUST describe what operation failed, include relevant context (identifiers, parameters, state), provide actionable information, suggesting remediation when a known remediation exists, suit the intended audience (user vs developer), protect sensitive information (internal paths and stack traces from end users; secrets per [Secrets Management](#secrets-management)), and focus on the system issue rather than user fault.

Errors MUST bubble up to appropriate handling boundaries unless handled completely at the point of capture, MUST be caught at module/service boundaries for logging and transformation, and MUST NOT cross API boundaries without sanitization.

---

## Testing Requirements

### Critical Path Coverage

Implementations MUST write tests for core business logic functions, data transformation and validation functions, error handling paths, security-sensitive operations, and integration points with external services, and critical path tests MUST verify both success and failure conditions. Implementations SHOULD write tests for all new functionality.

Implementations MUST NOT reduce existing test coverage when modifying code: reducing coverage includes deleting, disabling, or skipping tests and weakening assertions or fixtures (for example, loosening expected outcomes or narrowing tested inputs), whether they verify success or failure conditions. The sole exception is removal of the covered code itself.

### Test Standards

Test names MUST describe the system under test, the scenario, and the expected behavior, in the project's naming convention (e.g., `test_api_returns_404_when_user_not_found`), and MUST NOT reference bug IDs, temporary states, or vague identifiers (`test_working`, `test_1`). Tests MUST test one logical concept per case, be independent and not rely on test execution order, and clean up any state they create. Tests SHOULD include edge cases and boundary conditions, use realistic test data, be fast enough to run frequently, and use the AAA pattern (Arrange, Act, Assert) when appropriate.

### Test Result Verification

Test run verification MUST gate on the tool's own reported result (the exit status or result code when it encodes the outcome, the reported result metrics when it does not), never on text matching against output, because failed runs also print summary lines a filter matches. Reported results MUST account for every outcome class the runner reports: passed, failed, skipped, and error counts. Any non-zero failure or skip count MUST be named explicitly and investigated before the run is treated as green ([Prohibited Test Behaviors](#prohibited-test-behaviors)): `1 failed | 2530 passed` is a failed run, and `2 passed | 1 skipped` is a run with an uninvestigated skip, not a green run. Where output is truncated or filtered for length, the unfiltered summary (total, passed, failed, skipped) and the runner's exit status MUST still be captured directly at the point of invocation and reported; filtered reading MUST NOT be the sole failure signal.

### Prohibited Test Behaviors

Implementations MUST NOT skip, disable, or comment out failing tests, or use skip annotations or conditional ignores to hide them. When tests fail, implementations MUST fix the underlying bug by addressing the code issue, by fixing the test if the test itself is incorrect, or by consulting with the team if the expected behavior has changed.

### Test Planning Requirement

All code implementation plans MUST include a test plan specifying what will be tested, what types of tests will be written (unit, integration, e2e), and the key scenarios and edge cases to cover. If testing is not required for a change, implementations MUST document why testing is unnecessary (e.g., configuration-only change, documentation update, trivial rename with existing coverage).

### Separation of Code and Test Changes

This rule applies ONLY to test changes that ALTER the expected behavior of EXISTING tests; NEW tests for NEW feature code are grouped WITH that code per the `git-protocol` skill's Relationship Preservation section. Implementations MUST NOT update production code and the corresponding tests in the same commit, pull request, or change set, except when the two are inseparable and directly coupled.

When a bug fix changes expected behavior, implementations MUST submit the production code fix in one commit or PR and the test update documenting the new expected behavior in a follow-up commit or PR, referencing the related issue or the original change. Only when the test and code change are small, tightly coupled, and cannot be meaningfully reviewed in isolation MAY they share one change set, documenting the rationale in the PR description and securing reviewer approval. All exceptions to the separation rule MUST be documented in the change description, including the reason for coupling, the minimal scope, and a link to an approving review or decision record. Test-only behavior changes MUST reference an issue, design decision, or reviewer approval that authorizes them.

### Test Change Intent Verification

When modifying tests with the goal of making them pass (rather than in the course of developing new features), implementers MUST verify that the change reflects intended system behavior and not an accidental regression, side effect, or masking of a real defect: review relevant git history, commit messages, and project documentation for the original intent behind the test and the logic it validates; analyze whether the failing test indicates a real bug, a deliberate business rule change, or an obsolete expectation; update the test ONLY when the intended behavior has changed; and document the rationale in the commit message, referencing relevant git history or stakeholder decisions. If the intent is unclear or disputed, implementers MUST escalate to relevant reviewers, stakeholders, or product owners before altering the test.

---

## Documentation Requirements

### Function Documentation

Every function MUST carry a function header (docstring) documenting its behavior. Function documentation MUST include, where applicable: a purpose description, parameter descriptions with types and constraints, the return value description, side effects, and exceptions or errors that may be thrown.

### General Documentation

Implementations SHOULD document complex algorithms with explanatory comments, subject to the [Comment Policy](#comment-policy), and non-obvious implementation decisions.

### Code-Documentation Synchronization

When modifying code, implementations MUST update associated documentation and MUST NOT leave it stale; stale documentation is worse than no documentation.

### Comment Policy

This policy governs inline code comments; docstrings follow [Function Documentation](#function-documentation) above. Comments are absent by default: implementations MUST NOT add comments unless the user explicitly requests them or the narrow exception below applies, and before adding any comment implementations MUST first attempt self-explanatory code by renaming variables, functions, or types, extracting logic into named functions, simplifying expressions, and introducing named constants. An autonomous comment is permitted ONLY when ALL of the following hold: the code cannot express its intent on its own after those attempts, the comment explains non-obvious WHY rather than WHAT, and removing it would leave a future reader genuinely confused. Written comments MUST be direct and conversational, and MUST NOT restate what the code already expresses, use filler markers (`Note:`, `Important:`, `Consider:`, `This function...`, `Here we...`), or decorate code with section banners, file-level manifestos, or closing summaries.

A TODO/FIXME is acceptable only with a concrete description and a tracking reference (e.g., `TODO(#142): stream from disk once files exceed 1 GB`); untracked TODOs are barred. Comments MUST NEVER document internal bug-fixing history: bug IDs, attribution, fix chronology, or temporal references ("previously", "before the fix"); internal bugs belong exclusively in commit messages and issue trackers. External library workarounds are the exception: they MUST be documented in comments with full context, including library name and version, issue reference if available, expected vs actual behavior, and the conditions for removing the workaround.

Choose the right home for information: inline comments for code context and library workarounds; commit messages for what changed, why, and bug-fix history; formal documentation for architecture, API specifications, and deployment guidance.

---

## Type Safety Requirements

### Strict Typing Requirement

Implementations MUST use the strictest type-checking mode available in the project's language and tooling: strict/pedantic compiler flags, static type checkers where available, function-signature annotations per [Type Annotation Boundaries](#type-annotation-boundaries), and no type-escape mechanisms (e.g., `any`, `Object`, `void*`, dynamic casts).

### Type-Escape Exceptions

Type-escape mechanisms MAY be used ONLY when a concrete technical constraint requires it: interfacing with untyped external libraries, or the type system cannot express the required constraint. An escape MUST be justified by the specific constraint, not merely asserted, and documented in a code comment.

### Type Annotation Boundaries

Implementations SHOULD allow type inference for local variables where the type is obvious. Implementations MUST NOT rely on type inference for function parameters, function return types, public API boundaries, or data structures crossing module boundaries.

---

## Code Quality Tool Requirements

### Linting and Static Analysis

Implementations MUST NOT disable linting rules, static analysis warnings, or code quality checks except when unavoidable and justified. When unavoidable, implementations MUST use the most targeted suppression available (single line over file-wide, file-wide over project-wide), document the specific reason why the rule cannot be satisfied, and reference any related issue or technical constraint. Implementations MUST NOT suppress security-related warnings, type safety warnings, unused variable warnings (remove the variable instead), or any warning that can be resolved by fixing the code; the sanctioned responses are fixing the code, restructuring the implementation, or escalating to the user or maintainer, and suppression is barred even where the warning appears to be an unfixable false positive.

### Naming Conventions

Case style (camelCase, snake_case, and similar) follows the project's linter or formatter configuration per [Community Standards and Configuration](#community-standards-and-configuration); this subsection governs semantic naming. Implementations MUST use descriptive, proportionate names: one- and two-letter names are barred except for loop counters in tight scopes (e.g., `i`) and established identifiers (e.g., `id`); function names MUST state the operation performed as a concise verb phrase (`parseConfig`), neither cryptic (`do`) nor padded (`parseTheConfigurationFileFromDisk`); abbreviations MUST NOT truncate words into opaque fragments (`cnt`, `usrMgr`), though established domain terms (`config`, `auth`) are acceptable; one concept keeps one name across the codebase, and mixing synonyms for one operation (`fetch` and `retrieve`) is barred; boolean identifiers MUST read as predicates (`isValid`, `hasAccess`).

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

Implementations MUST use asynchronous patterns for network I/O (API calls, database queries), file system operations on multiple files, and any operation that may block for >100ms, and MUST NOT block the main thread or event loop with synchronous I/O in applications with concurrency requirements. When parallelizing work, implementations MUST limit concurrent operations to prevent resource exhaustion, handle partial failures gracefully, and provide cancellation mechanisms for long-running operations.

### Resource Cleanup

Implementations MUST ensure cleanup of file handles, database connections, network sockets, event subscriptions and listeners, and timers and scheduled tasks, using the language's idiomatic resource management pattern (e.g., try/finally, context managers, defer, RAII, using statements). Resources MUST be released on both success and failure paths.

---

## Solution Selection Requirements

### Correctness Priority

Implementations MUST prioritize correctness over simplicity: when a solution is both correct and simple it is optimal, and simple solutions that sacrifice correctness are not acceptable.

### Simple Solution Documentation

When a simple solution is chosen over a more comprehensive one for pragmatic reasons (time constraints, scope limitations), implementations MUST document that a simpler approach was taken, describe what the more comprehensive or correct solution would entail, and create a tracking item (issue, tracked TODO, or ticket) for the future improvement, keeping technical debt visible and actionable.

---

## Conformance

ALL MUST and MUST NOT requirements are mandatory; violations constitute conformance failures. SHOULD violations yield suboptimal quality but are not conformance failures.
