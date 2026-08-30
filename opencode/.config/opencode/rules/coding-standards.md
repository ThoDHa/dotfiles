# Coding Standards

---

## Scope

This specification defines technical implementation requirements for code produced by OpenCode implementations. These standards ensure maintainable, secure, and performant code across all projects.

### Related Specifications

- [`core.md`](core.md): Core behavioral requirements
- [`execution-standards.md`](execution-standards.md): Task execution requirements
- [`git-protocol.md`](git-protocol.md): Version control requirements

---

## Code Reuse Requirements

### Library Precedence

Implementations MUST search for existing solutions before implementing custom code.

Before writing any utility function, implementations MUST:

1. Search the current codebase for existing implementations
2. Search package registries for established libraries
3. Evaluate whether existing solutions meet requirements

Implementations MUST NOT create custom implementations when adequate solutions exist, unless:

- Existing solutions have unacceptable performance characteristics
- Existing solutions introduce unacceptable dependencies
- The limitation is documented in a code comment

### Project Utility Reuse

Implementations MUST check for existing project utilities before creating new ones.

When equivalent functionality exists in the project, implementations MUST:

1. Use the existing implementation
2. Extend the existing implementation if modifications are needed
3. Document why the existing implementation was insufficient (if bypassed)

Implementations MUST NOT create duplicate utility functions.

### Utility Creation Requirement

When implementations identify repeated code patterns (3+ occurrences), they MUST:

1. Extract the repeated logic into a reusable helper function, class, or module
2. Place the extracted code in an appropriate shared location
3. Document the utility's purpose and usage

When repeated patterns span multiple projects or services, implementations SHOULD:

- Create a shared internal library or package
- Extract to a dedicated SDK when appropriate
- Document in a central location for team discovery

### Shared Code Organization

Implementations MUST place reusable code in designated shared locations:

- Utility functions in utilities/helpers directories
- Shared types in types/models directories
- Common constants in constants/config directories

Implementations MUST use named exports with descriptive identifiers over default exports.

---

## Literal Value Requirements

### Numeric Literal Restrictions

Implementations MUST NOT use literal numeric values in code except:

- 0, 1, -1 in loop constructs and simple arithmetic
- Mathematical constants with obvious meaning (e.g., 100 for percentage)
- Array/string indices when context is clear

All other numeric literals MUST be extracted to named constants with descriptive identifiers.

### String Literal Restrictions

Implementations MUST NOT use literal strings for:

- Configuration values
- Error messages used in multiple locations
- API endpoints or route paths
- Status codes or state identifiers
- Feature flags or toggle names

These MUST be extracted to constants, enums, or configuration files.

### Configuration Externalization

Implementations MUST externalize configuration values:

- Environment-specific values MUST use environment variables
- Application settings MUST use dedicated configuration files
- Feature flags MUST use a centralized feature management system or config

Implementations MUST NOT hardcode values that may vary between environments.

---

## Error Handling Requirements

### External Call Protection

Implementations MUST wrap all external calls (network requests, database operations, file system operations, subprocess execution, fallible third-party libraries) in error-handling constructs appropriate to the language.

The error-handling mechanism MUST:

1. Catch or propagate errors explicitly (never silently swallow)
2. Provide meaningful context for debugging
3. Clean up resources on failure paths
4. Log errors at appropriate severity levels

### Error Message Standards

Error messages MUST:

- Describe what operation failed
- Include relevant context (identifiers, parameters, state)  
- Suggest remediation when a known remediation exists
- Be appropriate for the intended audience (user vs developer)
- Protect sensitive information (credentials, internal paths, stack traces from end users)
- Provide actionable information
- Focus on the system issue rather than user fault

### Error Propagation

Implementations MUST propagate errors appropriately:

- Errors MUST bubble up to appropriate handling boundaries unless handled completely at the point of capture
- Errors MUST be caught at module/service boundaries for logging and transformation
- Errors MUST NOT cross API boundaries without sanitization

When catching errors, implementations MUST either:

- Handle the error completely, or
- Re-throw with additional context

Implementations MUST NOT catch errors only to log and ignore them.

---

## Testing Requirements

### Critical Path Coverage

Implementations MUST write tests for:

- Core business logic functions
- Data transformation and validation functions
- Error handling paths
- Security-sensitive operations
- Integration points with external services

Critical path tests MUST verify both success and failure conditions.

### General Test Coverage

Implementations SHOULD write tests for all new functionality.

Implementations MUST NOT reduce existing test coverage when modifying code, except where the covered code is itself removed.

### Test Standards

**Test Naming Requirements:**

Test names MUST describe the system under test, the scenario, and the expected behavior, in the project's naming convention (e.g., `test_api_returns_404_when_user_not_found`). Names MUST NOT reference bug IDs, temporary states, or vague identifiers (`test_working`, `test_fixing_bug_123`, `test_1`).

**Test Structure Requirements:**

Tests MUST:

- Have descriptive names indicating expected behavior
- Test one logical concept per test case
- Be independent and not rely on test execution order
- Clean up any state they create

Tests SHOULD:

- Include edge cases and boundary conditions
- Use realistic test data
- Be fast enough to run frequently
- Use AAA pattern (Arrange, Act, Assert) when appropriate

### Prohibited Test Behaviors


Implementations MUST NOT skip or disable failing tests.

When tests fail, implementations MUST fix the underlying bug by addressing the code issue.

Acceptable responses to failing tests:

- Fix the code that causes the failure
- Fix the test if the test itself is incorrect
- Consult with team if the expected behavior has changed

Implementations MUST NOT use skip annotations, conditional ignores, or comment-outs to hide failures.

### Test Planning Requirement

All code implementation plans MUST include a test plan.

The test plan MUST specify:

- What will be tested
- What types of tests will be written (unit, integration, e2e)
- Key scenarios and edge cases to cover

If testing is not required for a change, implementations MUST document why testing is unnecessary (e.g., configuration-only change, documentation update, trivial rename with existing coverage).

### Separation of Code and Test Changes

This separation rule applies ONLY to test changes that ALTER the expected behavior of EXISTING tests. NEW tests written for NEW feature code are grouped WITH that code per [`git-protocol.md` Relationship Preservation](git-protocol.md#relationship-preservation), and are NOT subject to this separation requirement.

For behavior-changing test updates, implementations MUST NOT update production code and the corresponding tests in the same commit, pull request, or change set, except when the code and test changes are inseparable and directly coupled. This rule aims to prevent behavioral changes from being hidden by simultaneous test updates and to make intent and reviewability explicit.

When a behavioral change is required because a bug is fixed, implementations MUST follow one of these approaches:

- Separate commits and pull requests: submit the production code fix in one commit or PR and the test update that documents the new expected behavior in a follow-up commit or PR, referencing the related issue or the original change.
- Single change only when inseparable: if the test and code change are small, tightly coupled, and cannot be meaningfully reviewed in isolation, include them together, but document the rationale in the PR description and ensure reviewers approve the combined change.

All exceptions to the separation rule MUST be explicitly documented in the change description, including the reason for coupling, the minimal scope, and a link to an approving review or decision record. Test-only changes that alter expected behavior without accompanying production code changes MUST reference an issue, design decision, or reviewer approval that authorizes the behavioral change.

### Test Change Intent Verification

When modifying tests with the goal of making them pass (rather than in the course of developing new features), implementers MUST verify that the proposed change accurately reflects intended system behavior and not an accidental regression, side effect, or masking of a real defect.

Specifically, implementers MUST:

1. Review relevant git history, commit messages, and project documentation to determine the original intent behind the test and the logic it validates.
2. Analyze whether the failing test indicates a real bug in the production code, a deliberate business rule change, or an obsolete expectation.
3. Update tests ONLY when the intended behavior has changed, and NOT as a byproduct of regression or unintentional side effect.
4. Document the rationale for any test change in the commit message, referencing relevant git history or stakeholder decision as appropriate.

If the intent behind a test is unclear or disputed, implementers MUST escalate the question to relevant reviewers, stakeholders, or product owners before altering the test.

---

## Documentation Requirements

### Non-Obvious Function Documentation

Implementations MUST document functions when:

- The function name does not fully convey its purpose
- The function has non-obvious side effects
- The function has complex parameter requirements
- The function implements business logic that requires context

Documentation MUST include:

- Purpose description
- Parameter descriptions with types and constraints
- Return value description
- Side effects (if any)
- Exceptions/errors that may be thrown

### General Documentation

Implementations SHOULD document:

- All public API functions and methods
- Complex algorithms with explanatory comments
- Non-obvious implementation decisions

### Code-Documentation Synchronization

When modifying code, implementations MUST update associated documentation.

Implementations MUST NOT leave documentation stale after a code change; stale documentation is worse than no documentation.

### Comment Policy

Comments are absent by default. Implementations MUST NOT add comments unless the user explicitly requests them, or the narrow exception below applies. Before adding any comment, implementations MUST first attempt self-explanatory code: renaming variables, functions, or types; extracting logic into named functions; simplifying expressions; introducing named constants.

An autonomous comment is permitted ONLY when ALL of the following hold: the code cannot express its intent on its own after the attempts above, the comment explains non-obvious WHY rather than WHAT, and removing it would leave a future reader genuinely confused. When written, comments MUST be direct and conversational, like notes a developer leaves for teammates.

Comments MUST NOT:

- Restate what the code already expresses
- Use filler markers (`Note:`, `Important:`, `Consider:`, `This function...`, `Here we...`)
- Decorate code with section banners, file-level manifestos, or closing summaries
- Contain untracked TODOs; a TODO/FIXME is acceptable only with a concrete description and a tracking reference (e.g., `TODO(#142): stream from disk once files exceed 1 GB`)

Comments MUST NEVER document internal bug-fixing history: bug IDs, attribution, fix chronology, or temporal references ("previously", "before the fix"). Internal bugs belong exclusively in commit messages and issue trackers.

External library workarounds are the exception: they MUST be documented in comments with full context, including library name and version, issue reference if available, expected vs actual behavior, and the conditions for removing the workaround.

Choose the right home for information: inline comments for immediate code context and library workarounds; commit messages for what changed, why, and bug-fix history; formal documentation for architecture, API specifications, and deployment guidance.

## Type Safety Requirements

### Strict Typing Requirement

Implementations MUST use the strictest type-checking mode available in the project's language and tooling.

This includes:

- Enabling strict/pedantic compiler flags
- Using static type checkers where available
- Annotating function signatures with explicit types
- Avoiding type-escape mechanisms (e.g., `any`, `Object`, `void*`, dynamic casts)

### Type-Escape Exceptions

Type-escape mechanisms MAY be used ONLY when:

- Interfacing with untyped external libraries
- The type system cannot express the required constraint
- The limitation is documented in a code comment explaining why

### Type Annotation Boundaries

Implementations SHOULD allow type inference for local variables where type is obvious.

Implementations MUST NOT rely on type inference for:

- Function parameters
- Function return types
- Public API boundaries
- Data structures crossing module boundaries

---

## Code Quality Tool Requirements

### Linting and Static Analysis

**UNLESS ABSOLUTELY NECESSARY, DO NOT DISABLE LINT CHECKERS.**

Implementations MUST NOT disable linting rules, static analysis warnings, or code quality checks EXCEPT when unavoidable and justified.

When disabling is unavoidable, implementations MUST:
1. Use the most targeted suppression available (single line over file-wide, file-wide over project-wide)
2. Document the specific reason why the rule cannot be satisfied
3. Reference any related issue or technical constraint

### Prohibited Suppressions

Implementations MUST NOT suppress:

- Security-related warnings
- Type safety warnings
- Unused variable warnings (remove the variable instead)
- Any warning that can be resolved by fixing the code

### Community Standards and Configuration

Implementations MUST use widely accepted community coding standards, linters, and formatters for the target language and framework.

- Start from official or recommended rule sets and default configurations.
- Minimize deviations; when deviations are necessary, document specific justifications.
- Commit lint and format configurations to version control and enforce them in CI.
- Where a standard formatter exists, implementations MUST use it consistently rather than introducing competing tools.
- Implementations SHOULD prefer stable, well‑maintained tools with broad adoption.


## Security Requirements

### Input Validation

Implementations MUST validate all external input before processing:

- User input from forms, APIs, command-line arguments
- Data from external services or files
- Environment variables used in logic

Validation MUST include:

- Type checking (expected data type)
- Range/length bounds (where applicable)
- Format validation (pattern matching for structured strings)
- Whitelist validation for enumerated values

### Output Sanitization

Implementations MUST sanitize output when:

- Rendering user-provided content in HTML
- Constructing database queries
- Building shell commands
- Logging potentially sensitive data

Implementations MUST use parameterized queries or prepared statements for database operations.

Implementations MUST NOT construct queries or commands via string concatenation with user input.

### Secrets Management

Implementations MUST NOT:

- Hardcode secrets, API keys, or credentials in source code
- Commit secrets to version control
- Log secrets at any log level
- Include secrets in error messages or stack traces

Secrets MUST be loaded from:

- Environment variables
- Dedicated secrets management systems
- Encrypted configuration (with proper key management)

### Extended Security Considerations

For security-sensitive applications, implementations MUST address the following according to project security requirements:

- Authentication and authorization patterns
- Session management and token handling
- Rate limiting and abuse prevention
- CORS and CSP header configuration
- Dependency vulnerability scanning
- Security audit logging

Each consideration MUST be either implemented or explicitly documented as not applicable, with justification.

---

## Performance Requirements

### Algorithmic Complexity Awareness

Implementations MUST consider algorithmic complexity for operations on collections.

When implementing algorithms:

- O(n²) or worse algorithms MUST be documented with justification
- Nested loops over the same collection MUST be reviewed for optimization
- Large dataset operations MUST use streaming or pagination patterns when the dataset can exceed available memory or is unbounded

Implementations MUST NOT use inefficient algorithms when efficient alternatives are readily available.

### Async and Concurrent Patterns

Implementations MUST use asynchronous patterns for:

- Network I/O (API calls, database queries)
- File system operations on multiple files
- Any operation that may block for >100ms

Implementations MUST NOT block the main thread or event loop with synchronous I/O in applications with concurrency requirements.

When parallelizing work, implementations MUST:

- Limit concurrent operations to prevent resource exhaustion
- Handle partial failures gracefully
- Provide cancellation mechanisms for long-running operations

### Resource Cleanup

Implementations MUST ensure cleanup of:

- File handles
- Database connections
- Network sockets
- Event subscriptions and listeners
- Timers and scheduled tasks

Implementations MUST use the language's idiomatic resource management pattern (e.g., try/finally, context managers, defer, RAII, using statements).

Resources MUST be released on both success and failure paths.

---

## Solution Selection Requirements

### Correctness Priority

Implementations MUST prioritize correctness over simplicity.

When evaluating solutions:

1. **Correct solutions** take precedence over simple solutions
2. When a solution is both correct AND simple, this is optimal
3. Simple solutions that sacrifice correctness are not acceptable

### Simple Solution Documentation

When a simple solution is chosen over a more comprehensive one for pragmatic reasons (time constraints, scope limitations), implementations MUST:

1. Document that a simpler approach was taken
2. Describe what the more comprehensive/correct solution would entail
3. Create a tracking item (issue, TODO, or ticket) for the future improvement

This documentation ensures technical debt is visible and actionable.

---

## Conformance

ALL MUST and MUST NOT requirements are mandatory; violations constitute conformance failures. SHOULD violations yield suboptimal quality but are not conformance failures.
