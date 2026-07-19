-- Vanilla-preserving ROME II campaign loader plus World Resistance.
--
-- ROME II loads this file before campaigns/<campaign>/scripting.lua. Keep the
-- stock imports intact: deleting any of them can break campaign initialization.

local triggers = require "data.lua_scripts.export_triggers"
local ancillaries = require "data.lua_scripts.export_ancillaries"
local historic_characters = require "data.lua_scripts.export_historic_characters"
local missions = require "data.lua_scripts.export_missions"
local encyclopedia = require "data.lua_scripts.export_encyclopedia"
local experience = require "data.lua_scripts.export_experience"
local political = require "data.lua_scripts.export_political_triggers"

events = triggers.events

-- This logger deliberately lives in the root loader rather than the director.
-- It can therefore prove that the pack was selected and report a director
-- import failure even when the director never reaches its own logger. Every IO
-- and native-output operation is protected: a read-only install must never
-- abort Rome II's campaign loader.
local WR_BOOT_LOG_PATH = "wr2_world_resistance_bootstrap.log"
local WR_BOOT_RELEASE = "0.1.6-beta"
local WR_BOOT_LOG_MAX_LINES = 1000
local WR_BOOT_LOG_RETAIN_LINES = 800
local WR_BOOT_LOAD_ID = tostring({})
local WR_MODULE_NAME = "wr2_world_resistance"
local WR_MODULE_PATH = "script/campaign/wr2/?.lua"

-- Keep a bounded tail in memory after one protected scan. At 1,000 records the
-- next append first rewrites only the newest 800, leaving headroom for normal
-- campaign loading without repeatedly rewriting the file. If any filesystem
-- operation is unavailable, file telemetry is skipped until its size can be
-- tracked safely, but the native trace and the vanilla loader always continue.
local wr_boot_log_scanned = false
local wr_boot_log_tracked = false
local wr_boot_log_lines = 0
local wr_boot_log_tail = {}

local function wr_boot_value(value)
    local text = tostring(value == nil and "" or value)
    text = string.gsub(text, "[\r\n\t|]", " ")
    if string.len(text) > 720 then
        text = string.sub(text, 1, 720)
    end
    return text
end

local function wr_boot_native(line)
    local out_api = rawget(_G, "out")
    if type(out_api) == "table" and type(out_api.ting) == "function" then
        local ok = pcall(function()
            out_api.ting(line)
        end)
        if ok then
            return
        end
    end

    local print_api = rawget(_G, "print")
    if type(print_api) == "function" then
        pcall(print_api, line)
    end
end

local function wr_boot_tail_push(line)
    wr_boot_log_tail[#wr_boot_log_tail + 1] = line
    if #wr_boot_log_tail > WR_BOOT_LOG_RETAIN_LINES then
        table.remove(wr_boot_log_tail, 1)
    end
end

local function wr_boot_scan_log(io_api)
    if wr_boot_log_scanned then
        return wr_boot_log_tracked
    end
    wr_boot_log_scanned = true

    local open_ok, file = pcall(function()
        return io_api.open(WR_BOOT_LOG_PATH, "r")
    end)
    if not open_ok then
        wr_boot_log_scanned = false
        return false
    end
    if file == nil then
        wr_boot_log_tracked = true
        wr_boot_log_lines = 0
        wr_boot_log_tail = {}
        return true
    end

    local lines = 0
    local tail = {}
    local read_ok = pcall(function()
        while true do
            local value = file:read("*l")
            if value == nil then
                break
            end
            lines = lines + 1
            tail[#tail + 1] = tostring(value)
            if #tail > WR_BOOT_LOG_RETAIN_LINES then
                table.remove(tail, 1)
            end
        end
    end)
    pcall(function()
        file:close()
    end)
    if not read_ok then
        wr_boot_log_scanned = false
        return false
    end

    wr_boot_log_tracked = true
    wr_boot_log_lines = lines
    wr_boot_log_tail = tail
    return true
end

local function wr_boot_compact_log(io_api)
    local open_ok, file = pcall(function()
        return io_api.open(WR_BOOT_LOG_PATH, "w")
    end)
    if not open_ok or file == nil then
        return false
    end

    local write_ok = pcall(function()
        local i
        for i = 1, #wr_boot_log_tail do
            file:write(wr_boot_log_tail[i])
            file:write("\n")
        end
        file:flush()
    end)
    pcall(function()
        file:close()
    end)
    if not write_ok then
        -- A later record may rescan and recover whatever the filesystem kept.
        wr_boot_log_scanned = false
        wr_boot_log_tracked = false
        return false
    end

    wr_boot_log_lines = #wr_boot_log_tail
    return true
end

local function wr_boot_append(line)
    pcall(function()
        local io_api = rawget(_G, "io")
        if type(io_api) ~= "table" or type(io_api.open) ~= "function" then
            return
        end

        local tracked = wr_boot_scan_log(io_api)
        if not tracked then
            return
        end
        if wr_boot_log_lines >= WR_BOOT_LOG_MAX_LINES then
            if not wr_boot_compact_log(io_api) then
                return
            end
        end

        local open_ok, file = pcall(function()
            return io_api.open(WR_BOOT_LOG_PATH, "a")
        end)
        if not open_ok or file == nil then
            return
        end
        local write_ok = pcall(function()
            file:write(line)
            file:write("\n")
            file:flush()
        end)
        pcall(function()
            file:close()
        end)
        if not write_ok then
            wr_boot_log_scanned = false
            wr_boot_log_tracked = false
            return
        end

        if tracked then
            wr_boot_log_lines = wr_boot_log_lines + 1
            wr_boot_tail_push(line)
        end
    end)
end

local function wr_boot_emit(stage, detail)
    local line = "WR2|schema=1|event=BOOT|release=" .. WR_BOOT_RELEASE
        .. "|load=" .. wr_boot_value(WR_BOOT_LOAD_ID)
        .. "|stage=" .. wr_boot_value(stage)
    if detail ~= nil then
        line = line .. "|detail=" .. wr_boot_value(detail)
    end
    wr_boot_append(line)
    wr_boot_native(line)
end

-- Give the director a fail-closed bridge back to this root logger. Never
-- expose the unguarded implementation: third-party/global calls must not be
-- able to break Rome II's campaign loader.
local function wr_boot_emit_protected(stage, detail)
    pcall(wr_boot_emit, stage, detail)
end
rawset(_G, "WR2_BOOT_EMIT", wr_boot_emit_protected)

-- Custom pack modules are not reliably discoverable through Rome II's special
-- lua_scripts namespace in every fresh Lua state. Temporarily prepend WR's
-- unique pack path, protected-require the simple module name, then restore the
-- ambient path so later scripts and mods see exactly what Rome II supplied.
local function wr_require_director()
    local package_api = rawget(_G, "package")
    local require_api = rawget(_G, "require")
    if type(package_api) ~= "table" or type(package_api.path) ~= "string" then
        return false, "package.path is unavailable"
    end
    if type(require_api) ~= "function" then
        return false, "global require is unavailable"
    end

    local original_path = package_api.path
    package_api.path = WR_MODULE_PATH .. ";" .. original_path
    wr_boot_emit_protected("MODULE_PATH_READY", WR_MODULE_PATH)
    wr_boot_emit_protected("DIRECTOR_ROUTE_TRY", WR_MODULE_NAME)
    local ok, value_or_error = pcall(require_api, WR_MODULE_NAME)
    package_api.path = original_path
    if ok then
        wr_boot_emit_protected("DIRECTOR_ROUTE_OK", WR_MODULE_NAME)
        return true, value_or_error
    end
    wr_boot_emit_protected("DIRECTOR_ROUTE_ERROR", value_or_error)
    return false, value_or_error
end

-- Requiring the director only defines its API. Listener attachment is a
-- separate, protected operation so a successfully parsed module can never be
-- mistaken for a successfully attached campaign script. Most importantly,
-- pass the exact registry returned by export_triggers; do not ask the required
-- module to rediscover an environment-bound global through raw _G access.
local function wr_setup_director(director, event_registry)
    if type(director) ~= "table" then
        local detail = "director return type=" .. tostring(type(director))
        wr_boot_emit_protected("DIRECTOR_API_ERROR", detail)
        return false, detail
    end

    local setup_ok, setup_function = pcall(function()
        return director.setup
    end)
    if not setup_ok or type(setup_function) ~= "function" then
        local detail = "director.setup type=" .. tostring(type(setup_function))
        if not setup_ok then
            detail = "director.setup lookup failed: " .. tostring(setup_function)
        end
        wr_boot_emit_protected("DIRECTOR_API_ERROR", detail)
        return false, detail
    end

    wr_boot_emit_protected(
        "DIRECTOR_SETUP_TRY",
        "source=export_triggers;registry_type=" .. tostring(type(event_registry))
            .. ";registry=" .. tostring(event_registry)
    )
    local call_ok, ready, detail = pcall(function()
        -- Dot semantics are deliberate: setup's only argument is the exact
        -- export_triggers registry, never the director table as an implicit
        -- colon-call receiver.
        return director.setup(event_registry)
    end)
    if not call_ok then
        wr_boot_emit_protected("DIRECTOR_SETUP_ERROR", ready)
        return false, tostring(ready)
    end
    if ready == true then
        wr_boot_emit_protected("DIRECTOR_SETUP_OK", detail)
        return true, detail
    end

    detail = detail or "director setup returned false"
    wr_boot_emit_protected("DIRECTOR_SETUP_PARTIAL", detail)
    return false, detail
end

-- Fail closed: a script error is logged, while the preserved vanilla loader
-- still allows the campaign to initialize instead of aborting the load screen.
wr_boot_emit_protected("LOADER_START")
wr_boot_emit_protected(
    "EVENT_REGISTRY_READY",
    "source=export_triggers;registry_type=" .. tostring(type(triggers.events))
        .. ";registry=" .. tostring(triggers.events)
)
local wr_ok, wr_value = wr_require_director()
if wr_ok then
    wr_boot_emit_protected("DIRECTOR_REQUIRE_OK", WR_MODULE_NAME)
    local wr_setup_ok, wr_setup_detail = wr_setup_director(wr_value, triggers.events)
    if not wr_setup_ok then
        local message = "[WR2 World Resistance] director setup incomplete: "
            .. tostring(wr_setup_detail)
        wr_boot_native(message)
    end
else
    wr_boot_emit_protected("DIRECTOR_REQUIRE_ERROR", wr_value)
    local message = "[WR2 World Resistance] loader error: " .. tostring(wr_value)
    local out_api = rawget(_G, "out")
    local logged = false
    if type(out_api) == "table" and type(out_api.ting) == "function" then
        logged = pcall(function()
            out_api.ting(message)
        end)
    end
    if not logged and type(rawget(_G, "print")) == "function" then
        pcall(print, message)
    end
end
