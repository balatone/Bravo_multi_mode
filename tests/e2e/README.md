# End-to-End (E2E) Tests

Full workflow tests simulating complete user interactions across the system.

## Purpose

E2E tests simulate complete user workflows and real-world scenarios. They exercise
the full stack of modules together, validating that the system behaves correctly
under realistic conditions.

## Execution

```bash
busted --helper=tests/_bootstrap.lua tests/e2e/
```

## Naming Convention

`<workflow>_e2e_spec.lua`

## Examples

- `hid_report_cycle_e2e_spec.lua` - Full HID report processing cycles
- `button_press_workflow_e2e_spec.lua` - Complete button press to action workflow
- `mode_switch_e2e_spec.lua` - Full mode switching scenarios
