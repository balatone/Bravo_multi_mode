local log = require("bravo++.log")

-- **************************************************************
-- Script that will toggle com1 and com2 without issues
-- **************************************************************

if log.LOG_LEVEL == nil then 
    log.LOG_LEVEL = log.LOG_DEBUG
end

-- Create the custom dataref if it doesn't exist
local G1000_COM_STATE_DR = create_dataref_table("FlyWithLua/G1000_COM_STATE", "Int")

-- Reset to default whenever the aircraft is loaded
function aircraft_load()
    G1000_COM_STATE_DR[0] = 0  -- PFD=COM1, MFD=COM1
end

-- Optional: initialize on first load if you want a known default
if G1000_COM_STATE_DR[0] == nil then
    G1000_COM_STATE_DR[0] = 0  -- PFD=COM1, MFD=COM1
end

-- 00 = COM1 on PFD, COM2 MFD (1)
-- 01 = COM2 on both (2)
-- 10 = COM1 on both (3)
-- 11 = COM2 on PFD, COM1 MFD (4)
-- local G1000_COM_STATE_DR[0] = 0 

local com1_freq = dataref_table("sim/cockpit/radios/com1_freq_hz")
local com1_stby_freq = dataref_table("sim/cockpit/radios/com1_stdby_freq_hz")
local com2_freq = dataref_table("sim/cockpit/radios/com2_freq_hz")
local com2_stby_freq = dataref_table("sim/cockpit/radios/com2_stdby_freq_hz")

local FLAG_PFD_COM = 0x01  -- bit 0
local FLAG_MFD_COM = 0x02  -- bit 1

-- Assume G1000_COM_STATE_DR[0] is your writable dataref
local function get_state()
    return G1000_COM_STATE_DR[0] or 0
end

local function pfd_is_com2()
    return bit.band(get_state(), FLAG_PFD_COM) ~= 0
end

local function mfd_is_com2()
    return bit.band(get_state(), FLAG_MFD_COM) ~= 0
end

local function pfd_com()
    return pfd_is_com2() and "COM2" or "COM1"
end

local function mfd_com()
    return mfd_is_com2() and "COM2" or "COM1"
end

local function set_pfd_com2(is_com2)
    local state = get_state()
    if is_com2 then
        state = bit.bor(state, FLAG_PFD_COM)               -- set bit 0
    else
        state = bit.band(state, bit.bnot(FLAG_PFD_COM))    -- clear bit 0
    end
    G1000_COM_STATE_DR[0] = state
end

local function set_mfd_com2(is_com2)
    local state = get_state()
    if is_com2 then
        state = bit.bor(state, FLAG_MFD_COM)               -- set bit 1
    else
        state = bit.band(state, bit.bnot(FLAG_MFD_COM))    -- clear bit 1
    end
    G1000_COM_STATE_DR[0] = state
end

-- Toggles between COM1 and COM2 being active on the PFD
function handle_toggle_com12_PFD()
    command_once("sim/GPS/g1000n1_com12")
    -- Toggle the bit
    set_pfd_com2(not pfd_is_com2())
end

-- Toggles between COM1 and COM2 being active on the MFD
function handle_toggle_com12_MFD()
    command_once("sim/GPS/g1000n3_com12")
    set_mfd_com2(not mfd_is_com2())
end

-- Toggles between TX and STDBY using state from PFD
function handle_toggle_com12_stby_PFD()
    if not pfd_is_com2() then -- doesn't make sense, but works...
        handle_toggle_com2_stdby()
    else
        handle_toggle_com1_stdby()
    end
end

-- Toggles between TX and STDBY using state from MFD
function handle_toggle_com12_stby_MFD()
    if not mfd_is_com2() then -- doesn't make sense, but works...
        handle_toggle_com2_stdby()
    else
        handle_toggle_com1_stdby()
    end
end

-- Toggles between TX and STDBY for COM1
function handle_toggle_com1_stdby()
    local tmp = com1_freq[0]
    com1_freq[0] = com1_stby_freq[0]
    com1_stby_freq[0] = tmp
end

-- Toggles between TX and STDBY for COM2
function handle_toggle_com2_stdby()
    local tmp = com2_freq[0]
    com2_freq[0] = com2_stby_freq[0]
    com2_stby_freq[0] = tmp
end

create_command(
    "FlyWithLua/Bravo++/toggle_n1_com12",
    "Bravo++ toggles COM1/COM2 being active on PFD",
    "handle_toggle_com12_PFD()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_n3_com12",
    "Bravo++ toggles COM1/COM2 being active on MFD",
    "handle_toggle_com12_MFD()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_n1_com12_stdby_freq",
    "Bravo++ toggles conditional COM1/COM2 and stdby freq on PFD",
    "handle_toggle_com12_stby_PFD()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_n3_com12_stdby_freq",
    "Bravo++ toggles conditional COM1/COM2 and stdby freq on MFD",
    "handle_toggle_com12_stby_MFD()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_com1_stdby_freq",
    "Bravo++ toggles COM1 and stdby freq",
    "handle_toggle_com1()", -- Call Lua function when pressed
    "",
    ""
)

create_command(
    "FlyWithLua/Bravo++/toggle_com2_stdby_freq",
    "Bravo++ toggles COM2 and stdby freq",
    "handle_toggle_com2()", -- Call Lua function when pressed
    "",
    ""
)
