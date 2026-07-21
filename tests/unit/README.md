# Unit Tests

Fast, isolated tests for individual modules. Each test exercises a single module
without depending on external systems or other modules beyond simple mocks.

## Purpose

Unit tests verify the internal logic of individual Lua modules in the `bravo++`
codebase. They run quickly and provide immediate feedback during development.

## Execution

```bash
busted --helper=tests/_bootstrap.lua tests/unit/
```

## Naming Convention

`<module_name>_spec.lua`

## Examples

- `decoder_spec.lua` - Tests for `bravo++.decoder` module
- `state_spec.lua` - Tests for `bravo++.state` module
- `util_spec.lua` - Tests for `bravo++.util` module
- `debug_spec.lua` - Tests for `bravo++.debug` module
- `log_spec.lua` - Tests for `bravo++.log` module
