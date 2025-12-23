# OpenCode Coding Standards and Best Practices

> Universal coding guidelines for all personalities and tasks.

## 1. Library and Helper Function Prioritization

- **Existing libraries first** - Always research and use established solutions before building custom
- **Reuse project utilities** - Check for existing helper functions before creating duplicates  
- **Common files for shared code** - Place reusable functions in shared/utility directories
- **Document implementation choices** - Note why existing solutions were insufficient (if bypassed)

## 2. Common File Organization

- **Group related utilities** - Organize functions by domain/purpose in shared files
- **Descriptive naming** - Use clear, self-documenting file and function names
- **Consistent directory structure** - Maintain predictable organization patterns
- **Named exports** - Use explicit, descriptive export names over default exports

## 3. Magic Numbers and Strings

- **Named constants** - Replace hardcoded values with descriptive constant names
- **Configuration files** - Centralize application settings in dedicated config files
- **Environment variables** - Use env vars for deployment-specific values
- **Enums for options** - Define predefined choices as enumerated types

## 4. Error Handling Patterns

- **Consistent error handling** - Use uniform error handling patterns across codebase
- **Meaningful error messages** - Provide clear, actionable error information
- **Graceful degradation** - Handle failures elegantly where possible
- **Proper error propagation** - Let errors bubble up appropriately through call stack

## 5. Testing Requirements

- **Test new functionality** - Write tests for all new features and bug fixes
- **Maintain test coverage** - Keep existing tests passing and relevant
- **Descriptive test cases** - Use clear test names that describe expected behavior
- **Edge case testing** - Include boundary conditions and error scenarios in test suites

## 6. Documentation Standards

- **Comment complex logic** - Explain non-obvious business rules and algorithms
- **Document function contracts** - Specify parameters, return values, and side effects
- **Maintain project documentation** - Keep README and setup instructions current
- **Code-documentation sync** - Update docs when changing functionality

---

*These standards ensure maintainable, professional code across all OpenCode implementations.*