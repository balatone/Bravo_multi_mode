-- Autopilot button
function start_timer_for_PLT_button()
    return try_catch(function() start_timer("PLT") end, 'start_timer_for_PLT_button')
end

function handle_continuous_mode_for_PLT_button()
    return try_catch(function() handle_continuous_mode("PLT") end, 'handle_continuous_mode_for_PLT_button')
end

function handle_single_click_mode_for_PLT_button()
    return try_catch(function() handle_single_click_mode("PLT") end, 'handle_single_click_mode_for_PLT_button')
end

create_command(
    "FlyWithLua/Bravo++/autopilot_button",
    "Bravo++ toggles AUTOPILOT button",
    "start_timer_for_PLT_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_PLT_button()",
    "handle_single_click_mode_for_PLT_button()"
)

-- IAS button
function start_timer_for_IAS_button()
    return try_catch(function() start_timer("IAS") end, 'start_timer_for_IAS_button')
end

function handle_continuous_mode_for_IAS_button()
    return try_catch(function() handle_continuous_mode("IAS") end, 'handle_continuous_mode_for_IAS_button')
end

function handle_single_click_mode_for_IAS_button()
    return try_catch(function() handle_single_click_mode("IAS") end, 'handle_single_click_mode_for_IAS_button')
end

create_command(
    "FlyWithLua/Bravo++/ias_button",
    "Bravo++ toggles IAS button",
    "start_timer_for_IAS_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_IAS_button()",
    "handle_single_click_mode_for_IAS_button()"
)

-- VS button
function start_timer_for_VS_button()
    return try_catch(function() start_timer("VS") end, 'start_timer_for_VS_button')
end

function handle_continuous_mode_for_VS_button()
    return try_catch(function() handle_continuous_mode("VS") end, 'handle_continuous_mode_for_VS_button')
end

function handle_single_click_mode_for_VS_button()
    return try_catch(function() handle_single_click_mode("VS") end, 'handle_single_click_mode_for_VS_button')
end

create_command(
    "FlyWithLua/Bravo++/vs_button",
    "Bravo++ toggles VS button",
    "start_timer_for_VS_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_VS_button()",
    "handle_single_click_mode_for_VS_button()"
)

-- ALT button
function start_timer_for_ALT_button()
    return try_catch(function() start_timer("ALT") end, 'start_timer_for_ALT_button')
end

function handle_continuous_mode_for_ALT_button()
    return try_catch(function() handle_continuous_mode("ALT") end, 'handle_continuous_mode_for_ALT_button')
end

function handle_single_click_mode_for_ALT_button()
    return try_catch(function() handle_single_click_mode("ALT") end, 'handle_single_click_mode_for_ALT_button')
end

create_command(
    "FlyWithLua/Bravo++/alt_button",
    "Bravo++ toggles ALT button",
    "start_timer_for_ALT_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_ALT_button()",
    "handle_single_click_mode_for_ALT_button()"
)

-- REV button
function start_timer_for_REV_button()
    return try_catch(function() start_timer("REV") end, 'start_timer_for_REV_button')
end

function handle_continuous_mode_for_REV_button()
    return try_catch(function() handle_continuous_mode("REV") end, 'handle_continuous_mode_for_REV_button')
end

function handle_single_click_mode_for_REV_button()
    return try_catch(function() handle_single_click_mode("REV") end, 'handle_single_click_mode_for_REV_button')
end

create_command(
    "FlyWithLua/Bravo++/rev_button",
    "Bravo++ toggles REV button",
    "start_timer_for_REV_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_REV_button()",
    "handle_single_click_mode_for_REV_button()"
)

-- APR button
function start_timer_for_APR_button()
    return try_catch(function() start_timer("APR") end, 'start_timer_for_APR_button')
end

function handle_continuous_mode_for_APR_button()
    return try_catch(function() handle_continuous_mode("APR") end, 'handle_continuous_mode_for_APR_button')
end

function handle_single_click_mode_for_APR_button()
    return try_catch(function() handle_single_click_mode("APR") end, 'handle_single_click_mode_for_APR_button')
end

create_command(
    "FlyWithLua/Bravo++/apr_button",
    "Bravo++ toggles APR button",
    "start_timer_for_APR_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_APR_button()",
    "handle_single_click_mode_for_APR_button()"
)

-- NAV button
function start_timer_for_NAV_button()
    return try_catch(function() start_timer("NAV") end, 'start_timer_for_NAV_button')
end

function handle_continuous_mode_for_NAV_button()
    return try_catch(function() handle_continuous_mode("NAV") end, 'handle_continuous_mode_for_NAV_button')
end

function handle_single_click_mode_for_NAV_button()
    return try_catch(function() handle_single_click_mode("NAV") end, 'handle_single_click_mode_for_NAV_button')
end

create_command(
    "FlyWithLua/Bravo++/nav_button",
    "Bravo++ toggles NAV button",
    "start_timer_for_NAV_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_NAV_button()",
    "handle_single_click_mode_for_NAV_button()"
)

-- HDG button
function start_timer_for_HDG_button()
    return try_catch(function() start_timer("HDG") end, 'start_timer_for_HDG_button')
end

function handle_continuous_mode_for_HDG_button()
    return try_catch(function() handle_continuous_mode("HDG") end, 'handle_continuous_mode_for_HDG_button')
end

function handle_single_click_mode_for_HDG_button()
    return try_catch(function() handle_single_click_mode("HDG") end, 'handle_single_click_mode_for_HDG_button')
end

create_command(
    "FlyWithLua/Bravo++/hdg_button",
    "Bravo++ toggles HDG button",
    "start_timer_for_HDG_button()", -- Call Lua function when pressed
    "handle_continuous_mode_for_HDG_button()",
    "handle_single_click_mode_for_HDG_button()"
)

--------------------------------------
---- LED HANDLING
--------------------------------------
local LED_LDG_L_GREEN =		{2, 1}
local LED_LDG_L_RED =		{2, 2}
local LED_LDG_N_GREEN =		{2, 3}
local LED_LDG_N_RED =		{2, 4}
local LED_LDG_R_GREEN =		{2, 5}
local LED_LDG_R_RED =		{2, 6}
local LED_ANC_MSTR_WARNG =	{2, 7}
local LED_ANC_ENG_FIRE =	{2, 8}
local LED_ANC_OIL =			{3, 1}
local LED_ANC_FUEL =		{3, 2}
local LED_ANC_ANTI_ICE =	{3, 3}
local LED_ANC_STARTER =		{3, 4}
local LED_ANC_APU =			{3, 5}
local LED_ANC_MSTR_CTN =	{3, 6}
local LED_ANC_VACUUM =		{3, 7}
local LED_ANC_HYD =			{3, 8}
local LED_ANC_AUX_FUEL =	{4, 1}
local LED_ANC_PRK_BRK =		{4, 2}
local LED_ANC_VOLTS =		{4, 3}
