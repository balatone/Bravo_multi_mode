# Plan of action: Native HID polling for Bravo rotary encoder + trim wheel (FlyWithLua)

## Goal
Replace the Aerosoft Honeycomb Configurator dependency by **capturing raw HID input reports** from the Honeycomb Bravo directly in FlyWithLua, and reliably triggering the existing script handlers:

- Rotary encoder (value knob)
  - `handle_bravo_knob_increase()`
  - `handle_bravo_knob_decrease()`
- Trim wheel
  - `handle_bravo_trim_nose_up()`
  - `handle_bravo_trim_nose_down()`

Constraints / non-goals:
- **Do not** use the `button(n)` / X-Plane joystick button mapping approach as a fallback (it drops pulses and is rate-limited).
- Must capture **all detents/clicks** at fast rotation speeds.

## Current state (what exists today)
- `FlyWithLua/Scripts/BravoMultiMode.lua` already opens the Bravo HID device:
  - `hid_open(0x294B, 0x1901)`
  - `hid_set_nonblocking(bravo, 1)`
- The script already performs HID **writes** for LEDs (feature reports).
- The script already performs HID **reads** (input reports) for the ALT/VS/HDG/CRS/IAS selector position via `refresh_selector_hid()`.
- The rotary and trim handlers exist, but are currently triggered by Aerosoft Configurator which calls the FlyWithLua custom commands:
  - `FlyWithLua/Bravo++/knob_increase_handler`
  - `FlyWithLua/Bravo++/knob_decrease_handler`
  - `FlyWithLua/Bravo++/trim_nose_up_handler`
  - `FlyWithLua/Bravo++/trim_nose_down_handler`

## Key technical requirement
### Single-consumer rule for HID reads
HID input reports are **consumed** by `hid_read()`. If multiple functions call `hid_read()` independently (e.g., one for selector and one for rotary), they will "steal" reports from each other and pulses will be missed.

Therefore:
- There must be **exactly one** place in the script that calls `hid_read()`.
- That place must dispatch events (selector, rotary, trim, etc.) from the same report stream.

## Implementation phases

### Phase 1 — Centralize Bravo HID input polling
**Outcome:** one per-frame poller drains the HID queue and feeds all decoders.

1. Create a new function (names are suggestions):
   - `poll_bravo_hid_inputs_task()` (registered with `do_every_frame`)

2. Inside `poll_bravo_hid_inputs_task()`:
   - Loop and drain the HID queue:
     - `while true do ... hid_read(bravo, 64) ... end`
     - Stop when `hid_read()` returns no data / nil / empty.
   - For each report read, call dedicated decoder functions:
     - `decode_selector_from_report(report)`
     - `decode_rotary_from_report(report)`
     - `decode_trim_from_report(report)`

3. Remove or disable any other code path that calls `hid_read()` directly.
   - Specifically, refactor `refresh_selector_hid()` to not call `hid_read()` anymore.
   - Selector updates must be driven by `decode_selector_from_report(report)`.

Why draining matters:
- At high rotation speed, multiple pulses can arrive between frames.
- If only one report is read per frame, the queue can overflow or lag.
- Draining per frame ensures we process all pending reports.


### Phase 2 — Add a HID report logger to discover the rotary + trim fields
**Outcome:** determine exactly which bytes/bits (or counters) represent rotary and trim in the Bravo input report.

Because HID layouts vary by device/firmware, do not guess. Instrument and measure.

1. Add a debug mode flag near the top of the script, e.g.:
   - `local HID_INPUT_DEBUG = false`

2. Implement a report diff logger:
   - Keep `last_report_bytes` (an array of bytes).
   - For each new report:
     - Compare to last.
     - Log only changed byte positions and old/new values (hex) and optionally bit deltas.

3. Provide targeted logging helpers:
   - `log_hid_report_diff(report, last_report)`
   - Optionally: `log_hid_report(report)` for full dumps when needed.

4. Test procedure (when hardware is available):
   - Turn the **value rotary** slowly:
     - 10 detents CW, 10 detents CCW.
   - Turn the **trim wheel**:
     - 10 detents nose-up, 10 detents nose-down.
   - Save the log output.

5. From the logs, classify each control’s encoding:
   - **Pulse bits** (separate CW/CCW bits that pulse 0→1→0)
   - **Quadrature** (two-bit state changes in Gray-code sequence)
   - **Counter** (a byte/word increments/decrements)

Deliverable of this phase:
- Document the mapping in `plan_of_action.md` (append a table once known):
  - report length
  - byte index
  - bit mask(s)
  - encoding type


### Phase 3 — Implement robust event decoding for rotary and trim
**Outcome:** reliably call existing handlers once per detent, with no missed clicks.

General guidance:
- Prefer **edge/transition-based** detection.
- Avoid time-based debounce that can suppress valid fast pulses.

#### 3A. Rotary encoder decoding
Implement one of the following depending on Phase 2 results.

**Option A: pulse-bit decoding**
- Track previous bit state(s).
- Fire on **rising edge** only.

Pseudo:
- if `cw_bit` transitions 0→1: call `handle_bravo_knob_increase()`
- if `ccw_bit` transitions 0→1: call `handle_bravo_knob_decrease()`

**Option B: quadrature decoding**
- Extract a 2-bit state (A/B).
- Maintain last state.
- Use a transition table to infer direction.
- Emit exactly one increment/decrement per full detent cycle (or per validated step).

**Option C: counter decoding**
- Maintain last counter value.
- Compute delta (with wrap handling).
- For delta>0, call increase delta times; for delta<0, call decrease -delta times.

Notes:
- The existing 20ms debounce in `handle_bravo_knob_increase/decrease` (`debounce_delay=0.02`) may drop detents at speed.
- Once decoding is reliable, remove that debounce or reduce it to a minimal value only if required.


#### 3B. Trim wheel decoding
Same decoder strategy as rotary, but trigger:
- Nose-up → `handle_bravo_trim_nose_up()`
- Nose-down → `handle_bravo_trim_nose_down()`

Notes:
- Your trim handlers already include a "boost" mechanism based on inter-click timing. Keep that logic.
- Do not add a large debounce in the HID decoder; rely on edge/quadrature correctness.


### Phase 4 — Integration into existing script flow
**Outcome:** the rest of BravoMultiMode remains unchanged; only input source changes.

1. Ensure the new HID poller runs every frame:
   - `do_every_frame("bravo_dispatch('poll_bravo_hid_inputs_task')")`

2. Keep LED write logic intact. HID reads and HID writes can coexist; just keep reads centralized.

3. Confirm that calling the existing handlers from the HID decoder behaves identically to Aerosoft-generated commands.

4. Remove Aerosoft dependencies operationally:
   - Unbind rotary and trim wheel in Aerosoft Configurator.
   - Ensure X-Plane joystick assignments for these controls are cleared to avoid double actions.


### Phase 5 — Validation and performance testing
**Outcome:** demonstrate no missed clicks, even at high speed.

1. Add temporary counters (debug-only):
   - count detected CW/CCW detents
   - count trim up/down detents
   - optionally log rates per second

2. Stress tests:
   - Spin rotary quickly for several seconds; confirm no stutter/missed steps compared to expected.
   - Roll trim wheel quickly; confirm consistent trim changes.

3. Confirm CPU impact is acceptable:
   - draining loop should terminate quickly when no data is pending.
   - logging must be off for normal use.


## Deliverables
- Code changes in `FlyWithLua/Scripts/BravoMultiMode.lua`:
  - new centralized HID poller
  - new report decoding functions
  - new debug diff logger
- Updated documentation of the discovered HID mapping (byte/bit positions) once measured.
- Operational steps to disable Aerosoft Configurator mappings for rotary + trim.

## Phase 2.5 — Linux (and general) verification: endpoint polling interval and report rate
**Outcome:** determine whether missed detents are fundamentally caused by device-side report cadence/encoding vs application-side polling/decoding.

Background:
- `hid_read()` returns raw HID **input reports**, but it cannot exceed the device’s USB interrupt IN endpoint cadence (`bInterval`) or recover transitions that the device firmware never reports.
- On Linux, it’s common to *observe* 125 Hz when using higher-level joystick/button APIs, but that’s not necessarily the true USB limit. The authoritative source is the USB descriptor `bInterval` for the endpoint you’re actually reading.

### 2.5A. Inspect the Bravo USB descriptors (Linux)
1. Identify the device:
   ```bash
   lsusb | grep -i -E 'honeycomb|bravo'
   ```

2. Dump the full descriptor for the bus/device you found (replace `BBB:DDD`):
   ```bash
   lsusb -v -s BBB:DDD
   ```

3. In the output, locate the relevant **HID interface** and its **Interrupt IN** endpoint descriptor and note:
   - `bInterval` (polling interval)
   - `wMaxPacketSize` (report packet size)

Interpretation (typical):
- `bInterval 1` → ~1 ms polling (up to ~1000 Hz, depending on speed mode)
- `bInterval 8` → ~8 ms polling (125 Hz)

> If the endpoint `bInterval` is 8 ms and the device reports only instantaneous pulse/state bits for an encoder, then very fast rotation *can* lose detents because multiple transitions can occur between polls.

### 2.5B. Measure actual report arrival rate (runtime)
In the FlyWithLua script (debug mode), add optional counters to measure:
- reports per second observed by the HID draining loop
- maximum number of reports drained in a single frame

This helps differentiate:
- **device/endpoint-limited** (reports/sec capped near descriptor rate)
- vs **application-limited** (reports arriving but not drained/decoded fast enough)

### 2.5C. Confirm whether the report contains deltas/counters vs state/pulses
From Phase 2 diff logs, determine whether rotary/trim are encoded as:
- state bits / pulse bits / quadrature state (more likely to lose steps at low report rates)
- accumulated counters/deltas (less likely to lose steps; can be lossless even at 125 Hz)

If fast-rotation loss persists even with a correct draining loop and correct interface:
- It is likely the device reports instantaneous state only and the endpoint cadence is too low.
- In that scenario, the only viable solution is to find an alternative Bravo HID interface/report (or vendor protocol) that provides accumulated deltas/counters.

## Open items / required information
When hardware is available, Phase 2 logging is required to finalize:
- which input report bytes/bits correspond to:
  - rotary encoder CW/CCW
  - trim wheel up/down
- encoding type for each control (pulse/quadrature/counter)

Additionally, on Linux (and useful on Windows too), capture:
- `bInterval` for the Interrupt IN endpoint of the interface being read
- observed report rate (reports/sec) from the FlyWithLua drain loop

Once the mapping and rate characteristics are known, Phase 3 becomes straightforward and deterministic.
