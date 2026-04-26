--[[
    MapBuilder.lua
    Unified mapping initialization utility for BravoMultiMode.
    Replaces deeply nested, redundant loops with a single hierarchical traversal
    that populates all registry tables in one pass.
]]

local util = require("bravo++.util")

local MapBuilder = {}

--------------------------------------------------------------------------------
-- Helper: safe ipairs over nil/empty values
--------------------------------------------------------------------------------
local function safe_ipairs(t)
    if not t or #t == 0 then return function() end end
    return ipairs(t)
end


--------------------------------------------------------------------------------
-- Core builder
--------------------------------------------------------------------------------
function MapBuilder.build(nav_bindings, modes, default_selections,
                          default_button_labels, no_button_labels,
                          outer_inner_modes, up_down_modes, annunciator_labels)

    local R = {
        button_map_labels           = {},
        button_map_actions          = {},
        button_is_switch_map        = {},
        twist_knob_map_labels       = {},
        selection_map_labels        = {},
        button_map_leds             = {},
        button_map_leds_cond        = {},
        button_map_leds_index       = {},
        rocker_switch_map_actions   = {},
        rocker_switch_map_buttons   = {},
    }

    -- Mode-level LEDs: apply to ALL selections in the given mode
    local function handle_mode_level_leds(mode, btn)
        local led_key = mode .. "_" .. btn .. "_BUTTON_LED"
        if nav_bindings[led_key] then
            for _, sel in safe_ipairs(default_selections) do
                local k = mode .. "_" .. sel .. "_" .. btn
                R.button_map_leds[k]       = nav_bindings[led_key]
                R.button_map_leds_cond[k]  = "FALSE"
                R.button_map_leds_index[k] = 1
            end
        end
    end

    -- Selection-level LEDs: ALL expansion + specific selection + annunciator multi-LED
    local function handle_selection_level_leds(mode, sel, btn)
        -- ALL keyword expansion
        local all_key   = mode .. "_ALL_" .. btn .. "_BUTTON_LED"
        if nav_bindings[all_key] then
            for _, s in safe_ipairs(default_selections) do
                local k = mode .. "_" .. s .. "_" .. btn
                R.button_map_leds[k]       = nav_bindings[all_key]
                R.button_map_leds_cond[k]  = "FALSE"
                R.button_map_leds_index[k] = 1
            end
        end

        -- Specific selection LED
        local sel_key   = mode .. "_" .. sel .. "_" .. btn .. "_BUTTON_LED"
        if nav_bindings[sel_key] then
            local k = mode .. "_" .. sel .. "_" .. btn
            R.button_map_leds[k]       = nav_bindings[sel_key]
            R.button_map_leds_cond[k]  = "FALSE"
            R.button_map_leds_index[k] = 1
        end

        -- Multi-LED annunciators (LABEL_1_LED … LABEL_N_LED)
        for _, ann in safe_ipairs(annunciator_labels) do
            local base_key = mode .. "_" .. sel .. "_" .. btn .. "_"
            for idx = 1, 16 do
                local ann_led_key = base_key .. ann .. "_" .. tostring(idx) .. "_LED"
                if nav_bindings[ann_led_key] then
                    local k = mode .. "_" .. sel .. "_" .. btn
                    R.button_map_leds[k]       = ann_led_key
                    R.button_map_leds_cond[k]  = "TRUE"
                    R.button_map_leds_index[k] = idx
                    break
                end
            end
        end
    end

    -- Button actions: selection-level → mode-level fallback, UP/DOWN switch detection
    local function handle_button_actions(mode, sel, btn)
        local base      = mode .. "_" .. sel .. "_" .. btn
        local sel_btn   = base .. "_BUTTON"
        local is_switch = false

        -- Selection-level ON_CLICK / ON_HOLD
        if nav_bindings[sel_btn] then
            R.button_map_actions[base .. "_ON_CLICK"] = nav_bindings[sel_btn]
            R.button_map_actions[base .. "_ON_HOLD"]  = nav_bindings[sel_btn]
        end

        -- Selection-level UP/DOWN
        for _, ud in safe_ipairs(up_down_modes) do
            local uu = string.upper(ud)
            local uk = base .. "_" .. uu .. "_BUTTON"
            if nav_bindings[uk] then
                R.button_map_actions[base .. "_" .. uu] = nav_bindings[uk]
                is_switch = true
            end
        end

        -- Mode-level fallback ON_CLICK / ON_HOLD
        if not nav_bindings[sel_btn] then
            local mode_btn_key = mode .. "_" .. btn .. "_BUTTON"
            if nav_bindings[mode_btn_key] then
                R.button_map_actions[base .. "_ON_CLICK"] = nav_bindings[mode_btn_key]
                R.button_map_actions[base .. "_ON_HOLD"]  = nav_bindings[mode_btn_key]
            end

            -- Mode-level UP/DOWN fallback
            for _, ud in safe_ipairs(up_down_modes) do
                local uu = string.upper(ud)
                local muk = mode .. "_" .. btn .. "_" .. uu .. "_BUTTON"
                if nav_bindings[muk] then
                    R.button_map_actions[base .. "_" .. uu] = nav_bindings[muk]
                    is_switch = true
                end
            end
        end

        if is_switch then
            R.button_is_switch_map[mode .. "_" .. btn] = true
        end
    end

    -- ======================================================================
    -- Main hierarchical traversal: modes → selections → buttons
    -- ======================================================================
    for _, mode in safe_ipairs(modes) do

        -- Mode-level button labels (no selection component)
        for _, btn in safe_ipairs(default_button_labels) do
            local lbl_key = mode .. "_" .. btn .. "_BUTTON_LABELS"
            if nav_bindings[lbl_key] then
                R.button_map_labels[mode .. "_" .. btn] = nav_bindings[lbl_key]
            else
                R.button_map_labels[mode .. "_" .. btn] = tostring(util.find(default_button_labels, btn))
            end
        end

        -- Mode-level LEDs (applies to all selections)
        for _, btn in safe_ipairs(default_button_labels) do
            handle_mode_level_leds(mode, btn)
        end

        -- Selection-level traversal
        for _, sel in safe_ipairs(default_selections) do

            -- Selector labels
            local slk = mode .. "_" .. sel .. "_SELECTOR_LABELS"
            if nav_bindings[slk] then
                R.selection_map_labels[mode .. "_" .. sel] = nav_bindings[slk]
            end

            -- Twist knob labels
            local knk = mode .. "_" .. sel .. "_KNOB_LABELS"
            if nav_bindings[knk] then
                R.twist_knob_map_labels[mode .. "_" .. sel] = nav_bindings[knk]
            else
                R.twist_knob_map_labels[mode .. "_" .. sel] = sel
            end

            -- Button labels for this mode/selection
            for _, btn in safe_ipairs(default_button_labels) do
                local bllk = mode .. "_" .. sel .. "_BUTTON_LABELS"
                if nav_bindings[bllk] then
                    R.button_map_labels[mode .. "_" .. sel .. "_" .. btn] = nav_bindings[bllk]
                end
            end

            -- Button actions for this mode/selection
            for _, btn in safe_ipairs(default_button_labels) do
                handle_button_actions(mode, sel, btn)
            end

            -- Selection-level LEDs
            for _, btn in safe_ipairs(default_button_labels) do
                handle_selection_level_leds(mode, sel, btn)
            end
        end
    end

    -- ======================================================================
    -- Post-loop: non-hierarchical mappings (rocker switches)
    -- ======================================================================
    for i = 1, 7 do
        local suk = "SWITCH" .. tostring(i) .. "_UP"
        local sdk = "SWITCH" .. tostring(i) .. "_DOWN"
        if nav_bindings[suk] then
            R.rocker_switch_map_actions["ROCKER_SWITCH_" .. tostring(i) .. "_UP"] = nav_bindings[suk]
        end
        if nav_bindings[sdk] then
            R.rocker_switch_map_actions["ROCKER_SWITCH_" .. tostring(i) .. "_DOWN"] = nav_bindings[sdk]
        end
        R.rocker_switch_map_buttons["ROCKER_SWITCH_" .. tostring(i)] = "SWITCH" .. tostring(i)
    end

    return R
end

--------------------------------------------------------------------------------
-- Public API: returns all maps as individual tables for 1:1 replacement
--------------------------------------------------------------------------------
function MapBuilder.build_all(...)
    local R = MapBuilder.build(...)
    return R.button_map_labels,
           R.button_map_actions,
           R.button_is_switch_map,
           R.twist_knob_map_labels,
           R.selection_map_labels,
           R.button_map_leds,
           R.button_map_leds_cond,
           R.button_map_leds_index,
           R.rocker_switch_map_actions,
           R.rocker_switch_map_buttons
end

return MapBuilder
