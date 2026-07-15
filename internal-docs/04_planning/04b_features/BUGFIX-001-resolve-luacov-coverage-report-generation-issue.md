---
id: BUGFIX-001
title: Resolve Luacov coverage report generation issue
version: 1.0.0
status: DRAFT
created: 2026-07-15 11:47:27
updated: 2026-07-15 11:47:37
related_docs: ["FEAT-001", "REVIEW-001"]
---
# Summary

Investigate and resolve why `luacov` does not produce coverage output files (`.luacov.stats.out`) when run with the `busted` test runner in the current environment.

# Scope

This bugfix focuses specifically on the integration between `luacov` instrumentation and the `busted` test execution flow to ensure that code coverage data is correctly captured and persisted.

## In Scope

- Investigation of `luacov` instrumentation activation during `busted` runs.
- Testing alternative invocation methods for `busted` with `luacov`.
- Validation and correction of `source_paths` in `.luacov` configuration.
- Ensuring coverage reports can be successfully parsed by `toolbox/luacov_utils.py`.

## Out of Scope

- Fixing pre-existing syntax issues in `mapbuilder.lua`.
- Resolving the lack of `pre-commit install` (to be handled as a separate setup task).
- Modifying the core logic of `decoder.lua`.

# Proposed Fix

The exact fix will be determined after investigation, but potential approaches include:
1. Adjusting the `.luacov` configuration to use absolute paths or more accurate relative paths for `source_paths`.
2. Changing how tests are invoked to ensure the `luacov` module is correctly required and active during the `busted` lifecycle.
3. Updating `tests/_bootstrap.lua` to explicitly handle instrumentation if necessary.

# Implementation Tasks

1. **Diagnostic Phase**: Add debug prints to `.luacov` or use `lua -l luacov` to verify that the module is actually being loaded during test execution.
2. **Path Verification**: Verify if the current `source_paths` in `.luacov` (currently `"FlyWithLua/Modules/bravo++/"`) correctly matches the paths seen by the Lua interpreter during tests.
3. **Alternative Invocation Test**: Attempt to run tests using: `lua -l luacov -e "require 'busted.core'" tests/ --helper=tests/_bootstrap.lua`.
4. **Implementation**: Apply the successful configuration or invocation change.
5. **Verification**: Run the test suite and confirm that `.luacov.stats.out` is generated.

# Acceptance Criteria

- [ ] Running `busted tests/ --helper=tests/_bootstrap.lua` (or the identified working alternative) produces a valid `.luacov.stats.out` file.
- [ ] The coverage report can be successfully parsed and summarized using `toolbox/luacov_utils.py`.
- [ ] No regression in test execution speed or reliability.

# Verification Plan

- **Primary Test**: Execute the test suite with luacov instrumentation and check for the existence of `.luacov.stats.out`.
- **Tooling Test**: Run `python3 toolbox/luacov_utils.py summary` to ensure it can read the newly generated stats.
- **Regression Test**: Ensure all 45 existing tests still pass.

# Risks / Notes

- The issue might be an environmental limitation of how `busted` manages its own module loading, which could require a more complex workaround in the test bootstrap.
