# Integration Tests

Tests that verify interactions between multiple modules working together.

## Purpose

Integration tests verify that multiple `bravo++` modules interact correctly. They
test cross-module data flow, shared state management, and coordinated behavior
that cannot be verified by unit tests alone.

## Execution

```bash
busted --helper=tests/_bootstrap.lua tests/integration/
```

## Naming Convention

`<feature>_integration_spec.lua`

## Examples

- `decoder_state_integration_spec.lua` - Tests decoder and state module interaction
- `dispatch_config_integration_spec.lua` - Tests dispatch and config coordination
- `ui_state_integration_spec.lua` - Tests UI rendering with state changes
