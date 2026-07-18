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

-- Fail closed: a script error is logged, while the preserved vanilla loader
-- still allows the campaign to initialize instead of aborting the load screen.
local wr_ok, wr_error = pcall(require, "lua_scripts.wr2_world_resistance")
if not wr_ok then
    local message = "[WR2 World Resistance] loader error: " .. tostring(wr_error)
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
