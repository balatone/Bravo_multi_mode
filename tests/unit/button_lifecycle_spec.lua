-- ************************************************
-- Unit tests for button_lifecycle module (FEAT-018)
-- ************************************************

local button_lifecycle = require("bravo++.button_lifecycle")

describe("button_lifecycle module", function()
    describe("init", function()
        it("should accept ap_buttons and create_command_fn", function()
            button_lifecycle.init({
                ap_buttons = {
                    { key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
                },
                create_command_fn = function() end,
            })
            -- init should not error
        end)

        it("should handle nil options", function()
            button_lifecycle.init(nil) -- should not error
        end)
    end)

    describe("register_all", function()
        it("should log error when create_command_fn not set", function()
            button_lifecycle.init({
                ap_buttons = {
                    { key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
                },
            })
            button_lifecycle.register_all() -- should log error but not crash
        end)

        it("should create commands for all buttons", function()
            local created_commands = {}
            local test_buttons = {
                { key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
                { key = "IAS", command = "ias_button", description = "IAS" },
                { key = "VS", command = "vs_button", description = "VS" },
            }

            button_lifecycle.init({
                ap_buttons = test_buttons,
                create_command_fn = function(dataref, description, press, repeat_, release)
                    table.insert(created_commands, {
                        dataref = dataref,
                        description = description,
                        press = press,
                        repeat_ = repeat_,
                        release = release,
                    })
                end,
            })
            button_lifecycle.register_all()

            -- Should create 3 commands (one per button, each with begin/continue/end)
            assert.equals(3, #created_commands)

            -- Verify first button commands
            assert.equals("FlyWithLua/Bravo++/autopilot_button", created_commands[1].dataref)
            assert.equals("bravo_dispatch('ap_begin', 'PLT')", created_commands[1].press)
            assert.equals("bravo_dispatch('ap_continue', 'PLT')", created_commands[1].repeat_)
            assert.equals("bravo_dispatch('ap_end', 'PLT')", created_commands[1].release)
        end)
    end)

    describe("get_button_commands", function()
        it("should return commands for a known button", function()
            local test_buttons = {
                { key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
                { key = "IAS", command = "ias_button", description = "IAS" },
            }
            button_lifecycle.init({
                ap_buttons = test_buttons,
                create_command_fn = function() end,
            })

            local cmds = button_lifecycle.get_button_commands("PLT")
            assert.is_not_nil(cmds)
            assert.equals("FlyWithLua/Bravo++/autopilot_button_begin", cmds.begin)
            assert.equals("FlyWithLua/Bravo++/autopilot_button_continue", cmds.continue)
            assert.equals("FlyWithLua/Bravo++/autopilot_button_end", cmds["end"])
        end)

        it("should return nil for unknown button", function()
            local test_buttons = {
                { key = "PLT", command = "autopilot_button", description = "AUTOPILOT" },
            }
            button_lifecycle.init({
                ap_buttons = test_buttons,
                create_command_fn = function() end,
            })

            local cmds = button_lifecycle.get_button_commands("UNKNOWN")
            assert.is_nil(cmds)
        end)
    end)
end)
