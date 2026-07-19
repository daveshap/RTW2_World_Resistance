-- The root loader must distinguish module import from explicit director setup.
-- Every setup/API failure remains fail-closed and names its exact boundary in
-- the writable bootstrap stream.

local assertions = 0

local function assert_true(value, message)
    assertions = assertions + 1
    if not value then
        error(message or "assertion failed", 2)
    end
end

local function find_file(relative)
    local override = os.getenv("WR2_PACK_ROOT")
    local candidates = {}
    if override ~= nil and override ~= "" then
        candidates[#candidates + 1] = override .. "/" .. relative
    end
    candidates[#candidates + 1] = "../pack_root/" .. relative
    candidates[#candidates + 1] = "pack_root/" .. relative
    candidates[#candidates + 1] = relative

    local i
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "rb")
        if handle ~= nil then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate pack file " .. relative, 2)
end

local function load_with_environment(path, environment)
    local chunk, load_error
    if type(setfenv) == "function" then
        chunk, load_error = loadfile(path)
        if chunk ~= nil then
            setfenv(chunk, environment)
        end
    else
        chunk, load_error = loadfile(path, "t", environment)
    end
    if chunk == nil then
        error("failed to load isolated loader: " .. tostring(load_error), 2)
    end
    return chunk
end

local loader_path = find_file("lua_scripts/all_scripted.lua")
local required_events = {
    "LoadingGame",
    "SavingGame",
    "UICreated",
    "FirstTickAfterWorldCreated",
    "FactionTurnStart",
    "FactionLeaderDeclaresWar"
}
local imports = {
    "data.lua_scripts.export_triggers",
    "data.lua_scripts.export_ancillaries",
    "data.lua_scripts.export_historic_characters",
    "data.lua_scripts.export_missions",
    "data.lua_scripts.export_encyclopedia",
    "data.lua_scripts.export_experience",
    "data.lua_scripts.export_political_triggers"
}

local function new_registry()
    local result = {}
    local i
    for i = 1, #required_events do
        result[required_events[i]] = {}
    end
    return result
end

local function install_imports(registry)
    local function install(module_name)
        package.loaded[module_name] = nil
        package.preload[module_name] = function()
            if module_name == "data.lua_scripts.export_triggers" then
                return { events = registry }
            end
            return {}
        end
    end
    local i
    for i = 1, #imports do
        install(imports[i])
    end
end

local real_io = io

local function run_scenario(module_value)
    local registry = new_registry()
    install_imports(registry)
    package.loaded["wr2_world_resistance"] = nil
    package.preload["wr2_world_resistance"] = function()
        return module_value
    end

    local lines = {}
    io = {
        open = function(_path, mode)
            if mode == "r" then
                return nil
            end
            return {
                write = function(self, value)
                    if value ~= "\n" then
                        lines[#lines + 1] = tostring(value)
                    end
                end,
                flush = function(self) end,
                close = function(self) end
            }
        end
    }
    out = { ting = function(_line) end }

    local decoy = new_registry()
    events = decoy
    WR2_BOOT_EMIT = nil
    local environment = setmetatable({ _G = _G }, { __index = _G })
    local original_path = package.path
    local chunk = load_with_environment(loader_path, environment)
    local ok, failure = pcall(chunk)
    io = real_io

    assert_true(ok, "setup/API failure must not unwind vanilla loader: " .. tostring(failure))
    assert_true(environment.events == registry, "vanilla loader environment retains export_triggers registry")
    assert_true(rawget(_G, "events") == decoy, "host decoy registry remains untouched")
    assert_true(package.path == original_path, "loader restores package.path after setup outcome")
    return lines, registry
end

local function saw_stage(lines, stage)
    local i
    for i = 1, #lines do
        if string.find(lines[i], "|stage=" .. stage, 1, true) ~= nil then
            return true, lines[i]
        end
    end
    return false, nil
end

-- A successfully required value without setup is an API contract failure, not
-- a require success that can be mistaken for an active mod.
local api_lines = run_scenario({})
assert_true(saw_stage(api_lines, "DIRECTOR_REQUIRE_OK"), "API case still reports successful import")
assert_true(saw_stage(api_lines, "DIRECTOR_API_ERROR"), "missing setup method is explicit")
assert_true(not saw_stage(api_lines, "DIRECTOR_SETUP_OK"), "API failure cannot report setup success")

local received_registry = nil
local throwing_lines, throwing_registry = run_scenario({
    setup = function(registry)
        received_registry = registry
        error("simulated|setup\nfailure")
    end
})
assert_true(received_registry == throwing_registry, "loader passes the exact local registry into setup")
assert_true(saw_stage(throwing_lines, "DIRECTOR_SETUP_TRY"), "throwing setup records its attempt")
local saw_setup_error, setup_error_line = saw_stage(throwing_lines, "DIRECTOR_SETUP_ERROR")
assert_true(saw_setup_error, "throwing setup records protected failure")
assert_true(
    string.find(setup_error_line, "simulated setup failure", 1, true) ~= nil,
    "setup error detail sanitizes field delimiters/newlines"
)
assert_true(
    string.find(setup_error_line, "simulated|setup", 1, true) == nil,
    "setup error cannot forge a bootstrap field"
)
assert_true(not saw_stage(throwing_lines, "DIRECTOR_SETUP_OK"), "throwing setup cannot report success")

local partial_lines, partial_registry = run_scenario({
    setup = function(registry)
        assert_true(type(registry) == "table", "partial setup receives a registry")
        return false, "registered=1/6"
    end
})
assert_true(type(partial_registry) == "table", "partial scenario retains its registry")
assert_true(saw_stage(partial_lines, "DIRECTOR_SETUP_TRY"), "partial setup records its attempt")
local saw_partial, partial_line = saw_stage(partial_lines, "DIRECTOR_SETUP_PARTIAL")
assert_true(saw_partial, "false setup result is reported as partial")
assert_true(
    string.find(partial_line, "registered=1/6", 1, true) ~= nil,
    "partial detail reaches the bootstrap stream"
)
assert_true(not saw_stage(partial_lines, "DIRECTOR_SETUP_OK"), "partial setup cannot report success")

print("World Resistance loader setup failure boundaries: " .. tostring(assertions) .. " assertions passed")
