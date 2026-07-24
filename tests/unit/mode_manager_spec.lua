-- ************************************************
-- Unit tests for mode_manager module (FEAT-019)
-- ************************************************

-- Clear module cache for fresh state per test
package.loaded["bravo++.mode_manager"] = nil

describe("mode_manager module", function()
    local mock_dispatch

    local function create_mock_dispatch()
        return {
            current_mode = "AUTO",
            current_selection = "ALT",
            current_cf_mode = "outer",
            current_switch_mode = "up",
            current_selection_label = "Label1",
            mode_select = false,
            button_is_switch_map = {},
            default_button_labels = { "BTN1", "BTN2" },
            current_buttons = { "BTN1", "BTN2" },
            twist_knob_map_actions = {},
            cycle_mode_up_called = false,
            cycle_mode_down_called = false,
            cycle_cf_mode_called = false,
            cycle_switch_mode_called = false,
            activate_mode_select_called = false,
            deactivate_mode_select_called = false,
            selector_index = nil,
        }
    end

    local function wire_mock_dispatch(m)
        m.get_current_mode = function() return m.current_mode end
        m.get_current_selection = function() return m.current_selection end
        m.get_current_cf_mode = function() return m.current_cf_mode end
        m.get_current_switch_mode = function() return m.current_switch_mode end
        m._get_current_selection_label = function() return m.current_selection_label end
        m.get_button_is_switch_map = function() return m.button_is_switch_map end
        m.get_current_buttons = function() return m.current_buttons end
        m.get_twist_knob_map_actions = function() return m.twist_knob_map_actions end
        m.cycle_mode_up = function()
            m.cycle_mode_up_called = true
            m.current_mode = "NAV"
            return "NAV"
        end
        m.cycle_mode_down = function()
            m.cycle_mode_down_called = true
            m.current_mode = "AUTO"
            return "AUTO"
        end
        m.cycle_cf_mode = function()
            m.cycle_cf_mode_called = true
            m.current_cf_mode = "inner"
            return "inner"
        end
        m.cycle_switch_mode = function()
            m.cycle_switch_mode_called = true
            m.current_switch_mode = "down"
            return "down"
        end
        m.activate_mode_select = function()
            m.activate_mode_select_called = true
            m.mode_select = true
        end
        m.deactivate_mode_select = function()
            m.deactivate_mode_select_called = true
            m.mode_select = false
        end
        m.set_selector_index = function(idx)
            m.selector_index = idx
        end
        return m
    end

    local function reload_mode_manager()
        package.loaded["bravo++.mode_manager"] = nil
        return require("bravo++.mode_manager")
    end

    local function setup_with_dispatch()
        mock_dispatch = wire_mock_dispatch(create_mock_dispatch())
        local mm = reload_mode_manager()
        mm.init({
            dispatch_module = mock_dispatch,
            modes_array = { "AUTO", "NAV", "COM" },
            selection_map_labels = {
                AUTO = { "Label1", "Label2" },
                NAV = { "Label1", "Label2" },
            },
            default_selections = { "ALT", "VS" },
            default_button_labels = { "BTN1", "BTN2" },
            button_map_labels = {},
        })
        return mm
    end

    describe("init", function()
        it("should accept dispatch_module and modes_array", function()
            local mm = reload_mode_manager()
            mm.init({
                dispatch_module = create_mock_dispatch(),
                modes_array = { "AUTO", "NAV" },
            })
            -- init should not error
        end)

        it("should handle nil options", function()
            local mm = reload_mode_manager()
            mm.init(nil) -- should not error
        end)

        it("should handle missing dispatch_module", function()
            local mm = reload_mode_manager()
            mm.init({})
            -- Should not error
        end)

        it("should build conceptual mode order", function()
            local mm = reload_mode_manager()
            mm.init({
                dispatch_module = create_mock_dispatch(),
                modes_array = { "AUTO", "AUTO_2", "NAV", "NAV_2", "COM" },
            })
            local order = mm.get_conceptual_mode_order()
            assert.equals(3, #order)
            assert.equals("AUTO", order[1])
            assert.equals("NAV", order[2])
            assert.equals("COM", order[3])
        end)

        it("should build mode group info with counts", function()
            local mm = reload_mode_manager()
            mm.init({
                dispatch_module = create_mock_dispatch(),
                modes_array = { "AUTO", "AUTO_2", "NAV" },
            })
            local info = mm.get_mode_group_info()
            assert.equals(2, info.AUTO.count)
            assert.equals(1, info.NAV.count)
        end)
    end)

    describe("cycle_mode_up", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            local result = mm.cycle_mode_up()
            assert.is_true(mock_dispatch.cycle_mode_up_called)
            assert.equals("NAV", result)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            local result = mm.cycle_mode_up()
            assert.is_nil(result)
        end)
    end)

    describe("cycle_mode_down", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            local result = mm.cycle_mode_down()
            assert.is_true(mock_dispatch.cycle_mode_down_called)
            assert.equals("AUTO", result)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            local result = mm.cycle_mode_down()
            assert.is_nil(result)
        end)
    end)

    describe("cycle_cf_mode", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            local result = mm.cycle_cf_mode()
            assert.is_true(mock_dispatch.cycle_cf_mode_called)
            assert.equals("inner", result)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            local result = mm.cycle_cf_mode()
            assert.is_nil(result)
        end)
    end)

    describe("cycle_switch_mode", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            local result = mm.cycle_switch_mode()
            assert.is_true(mock_dispatch.cycle_switch_mode_called)
            assert.equals("down", result)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            local result = mm.cycle_switch_mode()
            assert.is_nil(result)
        end)
    end)

    describe("activate_mode_select", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            mm.activate_mode_select()
            assert.is_true(mock_dispatch.activate_mode_select_called)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            mm.activate_mode_select() -- should not error
        end)
    end)

    describe("deactivate_mode_select", function()
        it("should delegate to dispatch module", function()
            local mm = setup_with_dispatch()
            mm.deactivate_mode_select()
            assert.is_true(mock_dispatch.deactivate_mode_select_called)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            mm.deactivate_mode_select() -- should not error
        end)
    end)

    describe("set_selector_index", function()
        it("should set selector index and delegate to dispatch", function()
            local mm = setup_with_dispatch()
            mm.set_selector_index(3)
            assert.equals(3, mm.get_selector_index())
            assert.equals(3, mock_dispatch.selector_index)
        end)

        it("should warn when dispatch_module not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            mm.set_selector_index(2) -- should not error
        end)
    end)

    describe("get_selector_index", function()
        it("should return the current selector index", function()
            local mm = setup_with_dispatch()
            mm.set_selector_index(4)
            assert.equals(4, mm.get_selector_index())
        end)
    end)

    describe("get_current_mode", function()
        it("should return current mode from dispatch", function()
            local mm = setup_with_dispatch()
            assert.equals("AUTO", mm.get_current_mode())
        end)

        it("should return nil when dispatch not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            assert.is_nil(mm.get_current_mode())
        end)
    end)

    describe("get_current_selection", function()
        it("should return current selection from dispatch", function()
            local mm = setup_with_dispatch()
            assert.equals("ALT", mm.get_current_selection())
        end)

        it("should return nil when dispatch not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            assert.is_nil(mm.get_current_selection())
        end)
    end)

    describe("get_mode_count", function()
        it("should return the number of modes", function()
            local mm = setup_with_dispatch()
            assert.equals(3, mm.get_mode_count())
        end)
    end)

    describe("get_conceptual_mode_order", function()
        it("should return conceptual mode order", function()
            local mm = setup_with_dispatch()
            local order = mm.get_conceptual_mode_order()
            assert.is_table(order)
            assert.equals(3, #order)
        end)
    end)

    describe("get_mode_group_info", function()
        it("should return mode group info", function()
            local mm = setup_with_dispatch()
            local info = mm.get_mode_group_info()
            assert.is_table(info)
        end)
    end)

    describe("build_ui_context", function()
        it("should return a UI context table", function()
            local mm = setup_with_dispatch()
            local ctx = mm.build_ui_context()
            assert.is_table(ctx)
            assert.equals("AUTO", ctx.current_mode)
            assert.equals("ALT", ctx.current_selection)
            assert.equals("outer", ctx.current_cf_mode)
            assert.equals("OUTER", ctx.current_cf_mode_upper)
            assert.equals("up", ctx.current_switch_mode)
            assert.equals("Label1", ctx.current_selection_label)
            assert.is_table(ctx.conceptual_mode_order)
            assert.is_table(ctx.mode_group_info)
            assert.is_table(ctx.selection_map_labels)
            assert.is_table(ctx.button_is_switch_map)
            assert.is_table(ctx.default_button_labels)
            assert.is_table(ctx.current_buttons)
            assert.is_table(ctx.twist_knob_map_actions)
        end)

        it("should return empty table when dispatch not initialized", function()
            local mm = reload_mode_manager()
            mm.init({})
            local ctx = mm.build_ui_context()
            assert.is_table(ctx)
        end)

        it("should update current_index for multi-count mode groups", function()
            local mm = reload_mode_manager()
            local m = wire_mock_dispatch(create_mock_dispatch())
            m.current_mode = "AUTO_2"
            mm.init({
                dispatch_module = m,
                modes_array = { "AUTO", "AUTO_2", "NAV" },
                selection_map_labels = {},
                default_selections = {},
                default_button_labels = {},
                button_map_labels = {},
            })
            local ctx = mm.build_ui_context()
            assert.equals(2, ctx.mode_group_info.AUTO.current_index)
        end)
    end)
end)
