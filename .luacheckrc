-- .luacheckrc — Centralized luacheck configuration for Bravo++ / FlyWithLua project
-- All FlyWithLua host-provided globals are declared here to avoid scattered inline ignores.

std = "lua54"

-- Ignore tables (globals provided by the FlyWithLua NG host environment)
ignore = {
    -- UI rendering
    "imgui",
    "float_wnd_create",
    "float_wnd_destroy",
    "float_wnd_pos",
    "float_wnd_size",
    "float_wnd_show",
    "float_wnd_hide",
    "float_wnd_begin",
    "float_wnd_end",

    -- XPLM data access
    "XPLMFindDataRef",
    "dataref_table",
    "dataref_ro",
    "dataref_rw",

    -- XPLM command dispatch
    "XPLMFindCommand",
    "command_once",
    "command_begin",
    "command_end",

    -- FlyWithLua host functions
    "do_every_frame",
    "logMsg",
    "get_string",
    "set_string",
    "get_number",
    "set_number",
    "get_integer",
    "set_integer",
    "get_boolean",
    "set_boolean",

    -- HID API (Honeycomb Bravo)
    "hid_open",
    "hid_close",
    "hid_read",
    "hid_write",
    "hid_get_feature_report",
    "hid_set_feature_report",
    "hid_error",
    "hid_enumerate",

    -- X-Plane UI callbacks
    "XPLMCreateWindowEx",
    "XPLMDestroyWindow",
    "XPLMDrawWindow",
    "XPGetMouseLocationDouble",
}

-- Per-file ignores (module-specific globals not covered above)
ignore_files = {}

-- Exclude patterns — files/directories to skip during linting
exclude_files = {
    ".luacheckrc",
    "stylua.toml",
    "tests/",
}

-- Warnings configuration
warnings = {
    "unused_variable",
    "shadow",
    "missing_fields",
    "missing_returns",
    "reading_global_before_assignment",
    "writing_global",
    "trailing_whitespace",
    "empty_block",
    "not_yetimplemented",
}

-- Enable all warnings by default (no --allow-defined-to-shadow, etc.)
