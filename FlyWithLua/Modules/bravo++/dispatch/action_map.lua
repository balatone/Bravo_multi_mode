--[[
    bravo++.dispatch.action_map - Action Map Builder

    Responsibilities:
    - Build button action maps from parsed config (nav_bindings)
    - Build twist knob action maps from parsed config
    - Provide map accessors for UI module

    This module is purely responsible for constructing and providing
    access to action maps. It does not execute any commands.
]]

local util = require("bravo++.util")
local log = require("bravo++.log")

local action_map = {}

--- Build the button action map from nav_bindings.
--- Populates state.button_map_actions and state.button_is_switch_map.
--- @param state table  Shared state table
--- @param nav_bindings table  Parsed configuration bindings
--- @param ctx table  Context with modes, selections, button labels
function action_map.build_button_action_map(state, nav_bindings, ctx)
    state.button_map_actions = {}
    state.button_is_switch_map = {}

    local modes = ctx.modes or {}
    local default_selections = ctx.default_selections or {}
    local default_button_labels = ctx.default_button_labels or {}

    local up_down = { "UP", "DOWN" }

    for i = 1, #modes do
        state.button_map_actions[modes[i]] = {}
        state.button_is_switch_map[modes[i]] = {}
        state.button_is_switch_map[modes[i]]["ALL"] = {}

        for j = 1, #default_selections do
            local sel = default_selections[j]
            state.button_map_actions[modes[i]][sel] = state.button_map_actions[modes[i]][sel] or {}
            state.button_is_switch_map[modes[i]][sel] = state.button_is_switch_map[modes[i]][sel] or {}

            for k = 1, #default_button_labels do
                local btn = default_button_labels[k]
                state.button_map_actions[modes[i]][btn] = state.button_map_actions[modes[i]][btn] or {}
                state.button_map_actions[modes[i]][sel][btn] = state.button_map_actions[modes[i]][sel][btn] or {}

                -- Handle ALT selection: buttons are mode-level, not selection-aware
                if sel == "ALT" and nav_bindings[modes[i] .. "_" .. btn .. "_BUTTON"] then
                    local full_key = modes[i] .. "_" .. btn .. "_BUTTON"
                    local bindings = util.create_table(nav_bindings[full_key])

                    state.button_map_actions[modes[i]][btn]["ON_CLICK"] = bindings[1]
                    log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

                    local on_hold_action = bindings[2] or bindings[1]
                    state.button_map_actions[modes[i]][btn]["ON_HOLD"] = on_hold_action
                    log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")
                elseif sel == "ALT" and not nav_bindings[modes[i] .. "_" .. btn .. "_BUTTON"] then
                    -- ALT buttons with UP/DOWN switch behavior
                    local is_current_button_a_switch = false

                    for l = 1, #up_down do
                        local full_key = modes[i] .. "_" .. btn .. "_" .. up_down[l] .. "_BUTTON"
                        local bindings = util.create_table(nav_bindings[full_key])

                        if bindings[1] then
                            local map = state.button_map_actions[modes[i]][btn][up_down[l]]
                            state.button_map_actions[modes[i]][btn][up_down[l]] = map or {}
                            state.button_map_actions[modes[i]][btn][up_down[l]]["ON_CLICK"] = bindings[1]
                            log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

                            local on_hold_action = bindings[2] or bindings[1]
                            state.button_map_actions[modes[i]][btn][up_down[l]]["ON_HOLD"] = on_hold_action
                            log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

                            state.button_map_actions[modes[i]][btn][up_down[l]]["ON_LONG_CLICK"] =
                                "FlyWithLua/Bravo++/switch_mode_button"
                            log.info(
                                "Adding " .. full_key .. " = FlyWithLua/Bravo++/switch_mode_button for ON_LONG_CLICK"
                            )

                            is_current_button_a_switch = true
                        end
                    end

                    if is_current_button_a_switch then
                        state.button_is_switch_map[modes[i]]["ALL"][btn] = is_current_button_a_switch
                    end
                end

                -- Selection-aware button bindings
                local key = modes[i] .. "_" .. sel
                local full_key = key .. "_" .. btn .. "_BUTTON"
                local bindings = util.create_table(nav_bindings[full_key])
                local is_select_context_aware = false

                if bindings[1] then
                    state.button_map_actions[modes[i]][sel][btn]["ON_CLICK"] = bindings[1]
                    log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

                    local on_hold_action = bindings[2] or bindings[1]
                    state.button_map_actions[modes[i]][sel][btn]["ON_HOLD"] = on_hold_action
                    log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

                    is_select_context_aware = true
                else
                    -- Selection-aware buttons with UP/DOWN switch behavior
                    local is_current_button_a_switch = false

                    for l = 1, #up_down do
                        full_key = key .. "_" .. btn .. "_" .. up_down[l] .. "_BUTTON"
                        bindings = util.create_table(nav_bindings[full_key])

                        if bindings[1] then
                            local map = state.button_map_actions[modes[i]][sel][btn][up_down[l]]
                            state.button_map_actions[modes[i]][sel][btn][up_down[l]] = map or {}
                            state.button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_CLICK"] = bindings[1]
                            log.info("Adding " .. full_key .. " = " .. bindings[1] .. " for ON_CLICK")

                            local on_hold_action = bindings[2] or bindings[1]
                            state.button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_HOLD"] = on_hold_action
                            log.info("Adding " .. full_key .. " = " .. on_hold_action .. " for ON_HOLD")

                            state.button_map_actions[modes[i]][sel][btn][up_down[l]]["ON_LONG_CLICK"] =
                                "FlyWithLua/Bravo++/switch_mode_button"
                            log.info(
                                "Adding " .. full_key .. " = FlyWithLua/Bravo++/switch_mode_button for ON_LONG_CLICK"
                            )

                            is_current_button_a_switch = true
                            is_select_context_aware = true
                        end
                    end

                    if is_current_button_a_switch then
                        state.button_is_switch_map[modes[i]][sel][btn] = is_current_button_a_switch
                    end
                end

                if not is_select_context_aware and sel == "ALT" then
                    log.info(
                        "************* Adding is switch to ALL ************ "
                            .. tostring(state.button_is_switch_map[modes[i]]["ALL"][btn])
                    )
                end
            end
        end
    end
end

--- Build the twist knob action map from nav_bindings.
--- Populates state.twist_knob_map_actions.
--- @param state table  Shared state table
--- @param nav_bindings table  Parsed configuration bindings
--- @param ctx table  Context with modes, selections
function action_map.build_twist_knob_action_map(state, nav_bindings, ctx)
    state.twist_knob_map_actions = {}

    local modes = ctx.modes or {}
    local default_selections = ctx.default_selections or {}

    local up_down = { "UP", "DOWN" }
    local outer_inner = { "OUTER", "INNER" }

    for i = 1, #modes do
        state.twist_knob_map_actions[modes[i]] = {}

        for j = 1, #default_selections do
            local sel = default_selections[j]
            state.twist_knob_map_actions[modes[i]][sel] = {}

            local outer_map = {}
            for l = 1, #outer_inner do
                local oi = outer_inner[l]
                outer_map[oi] = {}

                for k = 1, #up_down do
                    local dir = up_down[k]
                    local key = modes[i] .. "_" .. sel

                    -- Check for INNER-specific binding (fallback if no OUTER/INNER specified)
                    if oi == "INNER" and nav_bindings[key .. "_" .. dir] then
                        local full_key = key .. "_" .. dir
                        state.twist_knob_map_actions[modes[i]][sel][dir] = nav_bindings[full_key]
                        log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key])
                    end

                    -- Check for OUTER/INNER specific binding
                    if nav_bindings[key .. "_" .. oi .. "_" .. dir] then
                        local full_key = key .. "_" .. oi .. "_" .. dir
                        outer_map[oi][dir] = nav_bindings[full_key]
                        state.twist_knob_map_actions[modes[i]][sel] = outer_map
                        log.info("Adding " .. full_key .. " = " .. nav_bindings[full_key] .. " to " .. oi)
                    end
                end
            end
        end
    end
end

--- Get the button is-switch map from state.
--- @param state table  Shared state table
function action_map.get_button_is_switch_map(state)
    return state.button_is_switch_map
end

--- Get the twist knob map actions from state.
--- @param state table  Shared state table
function action_map.get_twist_knob_map_actions(state)
    return state.twist_knob_map_actions
end

return action_map
