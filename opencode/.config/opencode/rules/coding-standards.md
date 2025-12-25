# Coding Standards

**Specification Document — RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines technical implementation requirements for code produced by OpenCode implementations. These standards ensure maintainable, secure, and performant code across all projects.

### 1.1 Related Specifications

- `core.md` — Core behavioral requirements
- `execution-standards.md` — Task execution requirements
- `git-protocol.md` — Version control requirements

---

## 2. Code Reuse Requirements

### 2.1 Library Precedence

Implementations MUST search for existing solutions before implementing custom code.

Before writing any utility function, implementations MUST:

1. Search the current codebase for existing implementations
2. Search package registries for established libraries
3. Evaluate whether existing solutions meet requirements

Implementations MUST NOT create custom implementations when adequate solutions exist, unless:

- Existing solutions have unacceptable performance characteristics
- Existing solutions introduce unacceptable dependencies
- The limitation is documented in a code comment

### 2.2 Project Utility Reuse

Implementations MUST check for existing project utilities before creating new ones.

When equivalent functionality exists in the project, implementations MUST:

1. Use the existing implementation
2. Extend the existing implementation if modifications are needed
3. Document why the existing implementation was insufficient (if bypassed)

Implementations MUST NOT create duplicate utility functions.

### 2.3 Utility Creation Requirement

When implementations identify repeated code patterns (3+ occurrences), they MUST:

1. Extract the repeated logic into a reusable helper function, class, or module
2. Place the extracted code in an appropriate shared location
3. Document the utility's purpose and usage

When repeated patterns span multiple projects or services, implementations SHOULD:

- Create a shared internal library or package
- Extract to a dedicated SDK when appropriate
- Document in a central location for team discovery

### 2.4 Shared Code Organization

Implementations MUST place reusable code in designated shared locations:

- Utility functions in utilities/helpers directories
- Shared types in types/models directories
- Common constants in constants/config directories

Implementations MUST use named exports with descriptive identifiers over default exports.

---

## 3. Literal Value Requirements

### 3.1 Numeric Literal Restrictions

Implementations MUST NOT use literal numeric values in code except:

- 0, 1, -1 in loop constructs and simple arithmetic
- Mathematical constants with obvious meaning (e.g., 100 for percentage)
- Array/string indices when context is clear

All other numeric literals MUST be extracted to named constants with descriptive identifiers.

### 3.2 String Literal Restrictions

Implementations MUST NOT use literal strings for:

- Configuration values
- Error messages used in multiple locations
- API endpoints or route paths
- Status codes or state identifiers
- Feature flags or toggle names

These MUST be extracted to constants, enums, or configuration files.

### 3.3 Configuration Externalization

Implementations MUST externalize configuration values:

- Environment-specific values MUST use environment variables
- Application settings MUST use dedicated configuration files
- Feature flags MUST use a centralized feature management system or config

Implementations MUST NOT hardcode values that may vary between environments.

---

## 4. Error Handling Requirements

### 4.1 External Call Protection

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

### 4.2 Error Message Standards

Error messages MUST:

- Describe what operation failed
- Include relevant context (identifiers, parameters, state)
- Suggest remediation when possible
- Be appropriate for the intended audience (user vs developer)

Error messages MUST NOT:

- Expose sensitive information (credentials, internal paths, stack traces to end users)
- Be generic without actionable information
- Blame the user for system failures

### 4.3 Error Propagation

Implementations MUST propagate errors appropriately:

- Errors SHOULD bubble up to appropriate handling boundaries
- Errors MUST be caught at module/service boundaries for logging and transformation
- Errors MUST NOT cross API boundaries without sanitization

When catching errors, implementations MUST either:

- Handle the error completely, or
- Re-throw with additional context

Implementations MUST NOT catch errors only to log and ignore them.

---

## 5. Testing Requirements

### 5.1 Critical Path Coverage

Implementations MUST write tests for:

- Core business logic functions
- Data transformation and validation functions
- Error handling paths
- Security-sensitive operations
- Integration points with external services

Critical path tests MUST verify both success and failure conditions.

### 5.2 General Test Coverage

Implementations SHOULD write tests for all new functionality.

Implementations SHOULD maintain existing test coverage when modifying code.

### 5.3 Test Standards

Tests MUST:

- Have descriptive names indicating expected behavior
- Test one logical concept per test case
- Be independent and not rely on test execution order
- Clean up any state they create

Tests SHOULD:

- Include edge cases and boundary conditions
- Use realistic test data
- Be fast enough to run frequently

### 5.4 Prohibited Test Behaviors

**UNLESS ABSOLUTELY NECESSARY, DO NOT SKIP TESTS.**

Implementations MUST NOT skip or disable failing tests.

When tests fail, implementations MUST fix the underlying bug rather than bypassing the test.

Acceptable responses to failing tests:

- Fix the code that causes the failure
- Fix the test if the test itself is incorrect
- Consult with team if the expected behavior has changed

Implementations MUST NOT use skip annotations, conditional ignores, or comment-outs to hide failures.

### 5.5 Test Planning Requirement

All code implementation plans MUST include a test plan.

The test plan MUST specify:

- What will be tested
- What types of tests will be written (unit, integration, e2e)
- Key scenarios and edge cases to cover

If testing is not required for a change, implementations MUST document why testing is unnecessary (e.g., configuration-only change, documentation update, trivial rename with existing coverage).

---

## 6. Documentation Requirements

### 6.1 Non-Obvious Function Documentation

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

### 6.2 General Documentation

Implementations SHOULD document:

- All public API functions and methods
- Complex algorithms with explanatory comments
- Non-obvious implementation decisions

### 6.3 Code-Documentation Synchronization

When modifying code, implementations MUST update associated documentation.

Stale documentation is worse than no documentation.

---

## 7. Type Safety Requirements

### 7.1 Strict Typing Requirement

Implementations MUST use the strictest type-checking mode available in the project's language and tooling.

This includes:

- Enabling strict/pedantic compiler flags
- Using static type checkers where available
- Annotating function signatures with explicit types
- Avoiding type-escape mechanisms (e.g., `any`, `Object`, `void*`, dynamic casts)

### 7.2 Type-Escape Exceptions

Type-escape mechanisms MAY be used ONLY when:

- Interfacing with untyped external libraries
- The type system cannot express the required constraint
- The limitation is documented in a code comment explaining why

### 7.3 Type Annotation Boundaries

Implementations SHOULD allow type inference for local variables where type is obvious.

Implementations MUST NOT rely on type inference for:

- Function parameters
- Function return types
- Public API boundaries
- Data structures crossing module boundaries

---

## 8. Code Quality Tool Requirements

### 8.1 Linting and Static Analysis

**UNLESS ABSOLUTELY NECESSARY, DO NOT DISABLE LINT CHECKERS.**

Implementations MUST NOT disable linting rules, static analysis warnings, or code quality checks unless absolutely necessary.

When disabling is absolutely necessary, implementations MUST:

1. Use the most targeted suppression available (single line over file-wide, file-wide over project-wide)
2. Document the specific reason why the rule cannot be satisfied
3. Reference any related issue or technical constraint

### 8.2 Prohibited Suppressions

Implementations MUST NOT suppress:

- Security-related warnings
- Type safety warnings
- Unused variable warnings (remove the variable instead)
- Any warning that can be resolved by fixing the code

### 8.3 Acceptable Suppression Scenarios

Suppression MAY be acceptable ONLY when:

- Interfacing with external libraries that trigger false positives
- Working around known tooling bugs (with issue reference)
- Generated code that cannot conform to rules
- Legacy code during incremental migration (with migration plan)

Even in these scenarios, implementations SHOULD prefer fixing the underlying issue over suppression.

---

## 9. Security Requirements

### 8.1 Input Validation

Implementations MUST validate all external input before processing:

- User input from forms, APIs, command-line arguments
- Data from external services or files
- Environment variables used in logic

Validation MUST include:

- Type checking (expected data type)
- Range/length bounds (where applicable)
- Format validation (pattern matching for structured strings)
- Whitelist validation for enumerated values

### 8.2 Output Sanitization

Implementations MUST sanitize output when:

- Rendering user-provided content in HTML
- Constructing database queries
- Building shell commands
- Logging potentially sensitive data

Implementations MUST use parameterized queries or prepared statements for database operations.

Implementations MUST NOT construct queries or commands via string concatenation with user input.

### 8.3 Secrets Management

Implementations MUST NOT:

- Hardcode secrets, API keys, or credentials in source code
- Commit secrets to version control
- Log secrets at any log level
- Include secrets in error messages or stack traces

Secrets MUST be loaded from:

- Environment variables
- Dedicated secrets management systems
- Encrypted configuration (with proper key management)

### 8.4 Extended Security Considerations

For security-sensitive applications, implementations SHOULD also consider:

- Authentication and authorization patterns
- Session management and token handling
- Rate limiting and abuse prevention
- CORS and CSP header configuration
- Dependency vulnerability scanning
- Security audit logging

These extended considerations SHOULD be addressed according to project security requirements.

---

## 10. Performance Requirements

### 9.1 Algorithmic Complexity Awareness

Implementations MUST consider algorithmic complexity for operations on collections.

When implementing algorithms:

- O(n²) or worse algorithms MUST be documented with justification
- Nested loops over the same collection MUST be reviewed for optimization
- Large dataset operations SHOULD use streaming or pagination patterns

Implementations MUST NOT use inefficient algorithms when efficient alternatives are readily available.

### 9.2 Async and Concurrent Patterns

Implementations MUST use asynchronous patterns for:

- Network I/O (API calls, database queries)
- File system operations on multiple files
- Any operation that may block for >100ms

Implementations MUST NOT block the main thread or event loop with synchronous I/O in applications with concurrency requirements.

When parallelizing work, implementations MUST:

- Limit concurrent operations to prevent resource exhaustion
- Handle partial failures gracefully
- Provide cancellation mechanisms for long-running operations

### 9.3 Resource Cleanup

Implementations MUST ensure cleanup of:

- File handles
- Database connections
- Network sockets
- Event subscriptions and listeners
- Timers and scheduled tasks

Implementations MUST use the language's idiomatic resource management pattern (e.g., try/finally, context managers, defer, RAII, using statements).

Resources MUST be released on both success and failure paths.

---

## 11. Solution Selection Requirements

### 11.1 Correctness Priority

Implementations MUST prioritize correctness over simplicity.

When evaluating solutions:

1. **Correct solutions** take precedence over simple solutions
2. When a solution is both correct AND simple, this is optimal
3. Simple solutions that sacrifice correctness are not acceptable

### 11.2 Simple Solution Documentation

When a simple solution is chosen over a more comprehensive one for pragmatic reasons (time constraints, scope limitations), implementations MUST:

1. Document that a simpler approach was taken
2. Describe what the more comprehensive/correct solution would entail
3. Create a tracking item (issue, TODO, or ticket) for the future improvement

This documentation ensures technical debt is visible and actionable.

---

## 12. Conformance

Violations of MUST requirements constitute conformance failures.

Violations of SHOULD requirements may result in suboptimal code quality but do not constitute conformance failures.

---

*This specification defines technical implementation requirements for all OpenCode-produced code.*
