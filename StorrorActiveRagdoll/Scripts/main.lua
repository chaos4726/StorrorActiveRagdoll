-- STORROR Active Ragdoll - better ragdolls for STORROR Parkour Pro (a UE4SS Lua mod).
--
-- STORROR's own bails, with what Lincoln Margison's "Improving ragdolls forever" videos do to a ragdoll: soft joint
-- limits, a gentle pull of every joint toward the neutral body posture, a spin on the limbs at every impact, a falling
-- animation layered under the physics, the head protected on the way down, joints that dislocate, and gore.
--
-- Dev channel (only with a dev folder present): write Lua into <mod>/dev/cmd.lua (first line "-- id: N"); it runs on the
-- game thread and its result is appended to <mod>/dev/out.txt. Globals there: AR (the ragdoll), ARLIB (helpers),
-- AR_RELOAD(name) (loads a module's file again, live).
local function plog(msg) print("[ActiveRagdoll] " .. tostring(msg) .. "\n") end
pcall(collectgarbage, "generational", 4, 100)

local SCRIPT_DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
local MOD_DIR = (SCRIPT_DIR:gsub("Scripts[/\\]$", ""))
local DEV_DIR = MOD_DIR .. "dev\\"

-- (modules loaded from their files with loadfile, not require: UE4SS's require keeps its first copy, so a module could
-- never be loaded again live)
local function load_module(name)
    local fn, err = loadfile(SCRIPT_DIR .. name .. ".lua")
    if not fn then return nil, err end
    local ok, mod = xpcall(fn, debug.traceback)
    if not ok then return nil, mod end
    return mod
end

local LIB, e1 = load_module("alib")
if not LIB then plog("alib failed to load: " .. tostring(e1)); return end
_G.ARLIB = LIB
-- (armp, armpmenu: the multiplayer - peer to peer through Steam, binrnet.dll - and its screen in STORROR's ONLINE tab)
-- (xray: the x-ray skeleton, "skate 3 skeleton", 2026-11-11)
local MODS = { "armenu", "arhud", "gore", "ragdoll", "armp", "armpmenu", "xray" }
local loaded = {}
for _, name in ipairs(MODS) do
    local m, e = load_module(name)
    if m then loaded[name] = m else plog(name .. " failed to load: " .. tostring(e)) end
end
_G.AR, _G.ARHUD, _G.ARGORE, _G.ARMENU = loaded.ragdoll, loaded.arhud, loaded.gore, loaded.armenu
_G.ARMP, _G.ARMPMENU = loaded.armp, loaded.armpmenu
_G.ARXRAY = loaded.xray
_G.AR_MAIN_HUD, _G.AR_MAIN_GORE = true, true     -- (this main ticks the HUD and the gore itself)

function _G.AR_RELOAD(name)
    name = name or "ragdoll"
    local old = loaded[name]
    local m, e = load_module(name)
    if not m then return "reload failed: " .. tostring(e) end
    if old and old.unload then pcall(old.unload) elseif old and old.forget then pcall(old.forget) end
    loaded[name] = m
    if name == "ragdoll" then _G.AR = m end
    if name == "arhud" then _G.ARHUD = m end
    if name == "gore" then _G.ARGORE = m end
    if name == "armenu" then _G.ARMENU = m end
    if name == "armp" then _G.ARMP = m end
    if name == "armpmenu" then _G.ARMPMENU = m end
    if name == "xray" then _G.ARXRAY = m end
    return "reloaded " .. name .. (m.VERSION and (" v" .. tostring(m.VERSION)) or "")
end

-- ---------------------------------------------------------------- dev channel
local last_id = nil
do
    local f0 = io.open(DEV_DIR .. "cmd.lua", "r")
    if f0 then local s0 = f0:read("a"); f0:close(); last_id = s0:match("^%-%-%s*id:%s*(%S+)") end
end
local function dev_poll()
    local f = io.open(DEV_DIR .. "cmd.lua", "r")
    if not f then return end
    local src = f:read("a")
    f:close()
    local id = src:match("^%-%-%s*id:%s*(%S+)")
    if not id or id == last_id then return end
    last_id = id
    local fn, err = load(src, "cmd", "t", _ENV)
    local ok, res
    if fn then ok, res = xpcall(fn, debug.traceback) else ok, res = false, err end
    local out = io.open(DEV_DIR .. "out.txt", "a")
    if out then out:write("== run " .. id .. "\n" .. (ok and "ok: " or "error: ") .. tostring(res) .. "\n"); out:close() end
end

-- ---------------------------------------------------------------- every frame
local last_t, dev_t, world_addr = os.clock(), 0.0, nil
LoopInGameThreadAfterFrames(1, function()
    local now = os.clock()
    local dt = math.min(now - last_t, 0.1)
    last_t = now
    LIB.frame_begin()
    dev_t = dev_t + dt
    if dev_t >= 0.25 then dev_t = 0.0; pcall(dev_poll) end
    -- (a new map: nothing of the old one is touched again)
    local w = LIB.world()
    local addr = nil
    if w then pcall(function() addr = w:GetAddress() end) end
    if addr ~= world_addr then
        world_addr = addr
        pcall(LIB.forget)
        for _, m in pairs(loaded) do if m.forget then pcall(m.forget) end end
    end
    local R = _G.AR
    if R and R.tick then
        local ok, e = pcall(R.tick, dt)
        if not ok and not R.tick_err then R.tick_err = true; plog("tick error: " .. tostring(e)) end
    end
    local GO = _G.ARGORE
    if GO and GO.tick then
        local ok, e = pcall(GO.tick, dt, R and R.DAMAGE and R.DAMAGE.gore)
        if not ok and not GO.tick_err then GO.tick_err = true; plog("gore error: " .. tostring(e)) end
    end
    local H = _G.ARHUD
    if H and H.tick then pcall(H.tick, dt) end
    local MN = _G.ARMENU
    if MN and MN.tick then
        local ok, e = pcall(MN.tick, dt)
        if not ok and not MN.tick_err then MN.tick_err = true; plog("menu error: " .. tostring(e)) end
    end
    local MPN = _G.ARMP
    if MPN and MPN.tick then
        local ok, e = pcall(MPN.tick, dt)
        if not ok and not MPN.tick_err then MPN.tick_err = true; plog("multiplayer error: " .. tostring(e)) end
    end
    local XR = _G.ARXRAY
    if XR and XR.tick then
        local ok, e = pcall(XR.tick, dt)
        if not ok and not XR.tick_err then XR.tick_err = true; plog("x-ray error: " .. tostring(e)) end
    end
    local MPM = _G.ARMPMENU
    if MPM and MPM.tick then
        local ok, e = pcall(MPM.tick)
        if not ok and not MPM.tick_err then MPM.tick_err = true; plog("multiplayer screen error: " .. tostring(e)) end
    end
    LIB.frame_end()
    return false
end)
plog("loaded (" .. MOD_DIR .. ")")
