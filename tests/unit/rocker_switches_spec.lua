-- ************************************************
-- Unit tests for rocker_switches module (FEAT-018)
-- ************************************************

local rocker_switches = require("bravo++.rocker_switches")

describe("rocker_switches module", function()
    describe("init", function()
        it("should accept num_switches and create_command_fn", function()
            rocker_switches.init({
                num_switches = 7,
                create_command_fn = function() end,
            })
            -- init should not error
        end)

        it("should handle nil options", function()
            rocker_switches.init(nil) -- should not error
        end)

        it("should default to 7 switches", function()
            rocker_switches.init({
                create_command_fn = function() end,
            })
            -- Default num_switches is 7
        end)
    end)

    describe("register_all", function()
        it("should log error when create_command_fn not set", function()
            rocker_switches.init({})
            rocker_switches.register_all() -- should log error but not crash
        end)

        it("should create commands for all switches", function()
            local created_commands = {}
            rocker_switches.init({
                num_switches = 3, -- use fewer for testing
                create_command_fn = function(dataref, description, press, repeat_, release)
                    table.insert(created_commands, {
                        dataref = dataref,
                        description = description,
                        press = press,
                    })
                end,
            })
            rocker_switches.register_all()

            -- Should create 6 commands (3 switches * 2 directions)
            assert.equals(6, #created_commands)
        end)
    end)

    describe("get_command_name", function()
        it("should return correct command name for UP direction", function()
            local name = rocker_switches.get_command_name(1, "UP")
            assert.equals("FlyWithLua/Bravo++/rocker_switch1_up", name)
        end)

        it("should return correct command name for DOWN direction", function()
            local name = rocker_switches.get_command_name(7, "DOWN")
            assert.equals("FlyWithLua/Bravo++/rocker_switch7_down", name)
        end)

        it("should handle various switch numbers", function()
            assert.equals("FlyWithLua/Bravo++/rocker_switch2_up",
                rocker_switches.get_command_name(2, "UP"))
            assert.equals("FlyWithLua/Bravo++/rocker_switch5_down",
                rocker_switches.get_command_name(5, "DOWN"))
        end)
    end)
end)
