# Coding Standards

**Specification Document: RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

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

Implementations MUST wrap all external calls in error-handling constructs appropriate to the language.

External calls include:

- Network requests (HTTP, RPC, WebSocket)
- Database operations (queries, transactions, connections)
- File system operations (read, write, delete)
- Subprocess or shell execution
- Third-party library calls that may fail

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

Test names MUST describe WHAT is being tested and the EXPECTED behavior, NOT how the test was created or what bug it fixes.

**Descriptive Test Names (Required):**
- `test_user_authentication_with_valid_credentials_succeeds`
- `test_api_returns_404_when_user_not_found`
- `test_calculate_total_with_multiple_discounts_applies_correctly`
- `test_password_reset_token_expires_after_24_hours`

**Prohibited Test Names:**
- `test_fixing_bug_asd_123` (use descriptive name instead)
- `test_temp_fix` (describe the behavior being tested)
- `test_working` (too vague: what works?)
- `test_1`, `test_test123` (non-descriptive identifiers)

**Test Name Guidelines:**
- Use snake_case or camelCase consistent with project convention
- Include the system/component being tested
- Include the scenario or condition
- Include the expected result
- Keep names reasonably concise but descriptive
- Focus on behavior and business logic, not implementation details

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

### Comment Style Requirements

Code comments MUST be written in natural, conversational style.

Comments MUST use direct, straightforward language that focuses on WHY rather than WHAT. Comments MUST sound like notes a developer would leave for their future self or teammates.

**Good comment characteristics:**

- Direct, straightforward language
- Focus on WHY rather than WHAT (code shows what, comments explain why)
- Sound like a colleague explaining something briefly
- Concise without unnecessary preamble

**Examples:**

| Comment Style | Example |
|---------------|---------|
| **Casual and direct** | `// Validate to prevent corrupted data downstream` |
| **Context-focused** | `// Async call - don't block the UI` |
| **Purpose-driven** | `// Cache results - API is slow` |

### Comment Purpose Guidelines

Comments MUST explain code context and non-obvious decisions. Comments MUST NEVER document internal bug-fixing history.

#### What Comments MUST Explain

Comments MUST document:

- **External library workarounds** with full context
- **Non-obvious implementation choices** and their reasoning
- **Complex business logic** that requires domain knowledge
- **Performance considerations** when optimization choices aren't obvious

#### External Library Workaround Documentation

**CRITICAL DISTINCTION:**

- **External library bugs/issues:** MUST be documented in code comments with full context
- **Internal application bugs:** FORBIDDEN in code comments (these belong in commit messages and issue trackers only)

When working around external library bugs or limitations, comments MUST include:

- Library name and version affected
- Issue reference (if available)
- Expected behavior vs. actual behavior
- Conditions for removing the workaround

**Examples:**

```javascript
// Working around React 18.2 hydration mismatch - useLayoutEffect runs 
// twice on initial mount. See facebook/react#24430
// Remove when React 18.3+ is stable
```

```python
# Workaround for requests 2.28.x SSL verification bug with custom CA
# Expected: verify=ca_bundle should work
# Actual: throws SSLError on valid certificates  
# Remove when requests 2.29+ fixes issue #6078
```

#### What Comments MUST NOT Explain

**Internal application bug-fixing history is FORBIDDEN in code comments.**

Comments MUST NOT include:

- **Historical bug references**: bug IDs, issue numbers, or ticket references
- **Attribution**: who fixed something, when it was fixed, or why
- **Fix chronology**: when problems occurred, how they evolved over time
- **Deprecated behavior**: explanations of removed functionality
- **Temporal context**: "before the fix", "after the change", "previously", etc.

**Internal application bugs belong EXCLUSIVELY in commit messages and issue trackers. NEVER in code comments.**

Code comments explain the current state, not the history of how we got there.

**PROHIBITED comment patterns:**

```javascript
// ❌ FORBIDDEN
// Fixed bug #1234 where users couldn't login (removed by John on 2024-01-15)

// ❌ FORBIDDEN
// This was broken until v2.1 when we fixed the timeout issue

// ❌ FORBIDDEN
// Previously returned null, now throws exception as per PR #456
```

**ACCEPTABLE comment patterns:**

```javascript
// ✅ Acceptable: explains current behavior
// Validate session token before accessing protected resources
// (prevents auth bypass attempts when tokens expire mid-request)

// ✅ Acceptable: documents business context
// Customer tier determines discount calculation:
// - Premium: 15% on orders >$100, 10% otherwise
// - Standard: 5% on orders >$50
// - Basic: no discounts
```

### Documentation Context Distribution

Different types of information belong in different places. Choose the appropriate documentation context based on scope and audience.

#### Inline Comments

Use inline comments for:

- **Immediate code context** that affects the current function or block
- **External library workarounds** (governed by [External Library Workaround Documentation](#external-library-workaround-documentation), which is canonical for this topic)
- **Non-obvious algorithmic choices** within the implementation
- **Performance optimizations** that aren't self-evident

Inline comments should be casual and conversational (following [Comment Style Requirements](#comment-style-requirements) style requirements).

#### Commit Messages

Use commit messages for:

- **What changed** in this specific commit
- **Why the change was necessary** (business justification)
- **Impact scope** (what systems/features are affected)
- **Bug fix history** (what was broken, what the fix was, and why), which per [What Comments MUST NOT Explain](#what-comments-must-not-explain) belongs EXCLUSIVELY in commit messages and issue trackers

Follow formal commit message standards defined in [`git-protocol.md`](git-protocol.md).

#### Formal Documentation

Use formal documentation (README, API docs, architecture docs) for:

- **High-level design decisions** and architectural tradeoffs
- **API specifications** and usage examples
- **System overviews** and integration patterns
- **Deployment and configuration** guidance

Formal documentation MUST maintain professional tone and structured format, suitable for external audiences or formal review.

### Comment Minimalism Requirements

Comments are exceptional, not habitual. Most code communicates intent through clear naming, structure, and tests. When reading a codebase, the default experience SHOULD be code, not prose explaining the code. This section governs WHEN to comment and how dense comments may be. Where a comment survives this filter, [Comment Style Requirements](#comment-style-requirements) governs its style.

#### Default Absence Principle

Comments MUST be absent by default. The baseline rule is simple: do not write comments unless asked.

Implementations MUST NOT add comments unless one of the following is true:

1. **The user explicitly requests commentary**: this is the primary and expected path for any comment.
2. **The narrow autonomous exception** in [Autonomous Comment Exception](#autonomous-comment-exception) applies.

When the user has not explicitly asked for comments, implementations MUST assume no comments are wanted and produce clean, self-explanatory code instead.

#### Autonomous Comment Exception

A comment MAY be added without an explicit user request ONLY when ALL of the following are true:

- The code genuinely cannot express its intent on its own
- The attempts below to make the code self-explanatory have been exhausted
- The comment explains non-obvious WHY, not WHAT (per [Comment Style Requirements](#comment-style-requirements))
- Removing the comment would leave a future reader genuinely confused

Before writing an autonomous comment, implementations MUST first attempt to make the code self-explanatory through:

- Renaming variables, functions, or types for clarity
- Extracting logic into named functions
- Simplifying complex expressions
- Introducing named constants for magic values

If intent remains non-obvious ONLY after these attempts AND the comment explains WHY (not WHAT), the comment is permitted. Otherwise, no comment is written.

#### Redundant Comment Prohibition

Implementations MUST NOT write comments that restate what the code already expresses. Redundant comments are noise that adds maintenance burden without insight.

**Prohibited redundancy:**

```python
# ❌ Prohibited: restates the code
counter = 0  # Initialize counter to zero

# ❌ Prohibited: narrates obvious control flow
for item in items:
    process(item)  # Process each item

# ❌ Prohibited: restates the function name
def validate_email(address):
    # Validate the email address
    ...
```

If a comment can be deleted and the code remains equally clear, the comment MUST be deleted.

#### Prohibited Comment Patterns

Implementations MUST NOT use filler markers or formulaic comment conventions. These add no information and read as padding.

**Prohibited markers and patterns:**

- Imperative preambles: `Note:`, `Important:`, `Consider:`, `NB:`, `FYI:`, `Remember:`, `Warning:`
- Signature restatement: `This function...`, `This method...`, `Here we...`, `Below we...`, `Now we...`
- Section banners (governed canonically by [Section Commentary Prohibition](#section-commentary-prohibition) below)
- Placeholder TODOs lacking owner, context, or tracking reference: `# TODO: improve this`, `# FIXME later`, `# refactor at some point`

A bare `TODO` or `FIXME` is acceptable ONLY when it includes a concrete description AND a tracking reference (issue number, ticket, or design doc).

```python
# ❌ Prohibited: empty placeholder
# TODO: improve
data = load()

# ✅ Acceptable: concrete and tracked
# TODO(#142): stream from disk once files exceed 1 GB
data = load()
```

#### Comment Density as a Complexity Signal

If a function, block, or module requires many comments to be understood, the code is too complex. Implementations MUST treat dense comments as a signal to refactor, not as a reason to annotate.

Required response to dense comments:

1. Simplify the code first (extract functions, rename, reduce branching)
2. Move explanatory context to commit messages or formal documentation where appropriate
3. Keep only comments that explain non-obvious WHY after simplification

Comments MUST NOT compensate for poor naming, deep nesting, or tangled control flow. If a comment exists to explain HOW the code works, the code MUST be rewritten until the comment becomes unnecessary.

#### Over-Documentation Prohibition

Implementations MUST NOT add docstrings or comments to trivial constructs:

- Getters, setters, and simple property accessors
- One-line functions whose name fully describes their behavior
- Obvious return statements
- Standard language idioms familiar to the target audience

Trivial constructs that speak for themselves require zero commentary.

#### Section Commentary Prohibition

Implementations MUST NOT decorate code with ornamental section headers, file-level manifestos, or closing summaries.

**Prohibited:**

```python
# ============================================
# IMPORTS
# ============================================

# --------------------------------------------
# Public API
# --------------------------------------------

# End of file - everything above is tested
```

Standard language conventions for module organization (package declarations, import grouping enforced by linters) are exempt. Hand-written banner comments are not.

---

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

ALL strong requirements in this specification are mandatory. Any violation of MUST or MUST NOT constitutes an immediate conformance failure.

Violations of SHOULD requirements may result in suboptimal code quality but are not conformance failures.

---

*This specification defines technical implementation requirements for all OpenCode-produced code.*
