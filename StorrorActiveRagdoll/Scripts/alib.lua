-- STORROR Active Ragdoll: the few engine helpers it needs - the player's controller, his athlete, the world, logging and
-- STORROR's own sounds. (Its own: nothing here comes from or depends on another mod.)
local UEHelpers = require("UEHelpers")

local M = {}
local SCRIPT_DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "")
M.MOD_DIR = (SCRIPT_DIR:gsub("Scripts[/\\]$", ""))

function M.log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print("[ActiveRagdoll] " .. (ok and msg or tostring(fmt)) .. "\n")
end

-- (looked up once a frame: main.lua calls frame_begin and frame_end around its work)
local fc = nil
function M.frame_begin() fc = {} end
function M.frame_end() fc = nil end

-- (player 0's controller asked of the game instance - one call - not UE4SS's GetPlayerController, which searches every
-- object. The game instance lives as long as the game, so it is kept; the controller never is, past a frame.)
local gi, GS, gi_look = nil, nil, 0.0
local function game_instance()
    if gi then
        local ok, yes = pcall(function() return gi:IsValid() end)
        if ok and yes then return gi end
        gi = nil
    end
    local now = os.clock()
    if now < gi_look then return nil end
    gi_look = now + 1.0
    pcall(function()
        for _, o in ipairs(FindAllOf("GameInstance") or {}) do
            if o:IsValid() and not o:GetFName():ToString():find("^Default__") then gi = o end
        end
    end)
    return gi
end

function M.controller()
    if fc and fc.pc ~= nil then return fc.pc or nil end
    local pc = nil
    local g = game_instance()
    if g then
        pcall(function()
            if not (GS and GS:IsValid()) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
            pc = GS:GetPlayerController(g, 0)
        end)
    else
        pcall(function() pc = UEHelpers.GetPlayerController() end)
    end
    if not (pc and pc:IsValid()) then pc = nil end
    if fc then fc.pc = pc or false end
    return pc
end

function M.world()
    if fc and fc.world ~= nil then return fc.world or nil end
    local w = nil
    local pc = M.controller()
    if pc then pcall(function() w = pc:GetWorld() end) end
    if not (w and w:IsValid()) then pcall(function() w = UEHelpers.GetWorld() end) end
    if not (w and w:IsValid()) then w = nil end
    if fc then fc.world = w or false end
    return w
end

-- (STORROR's athlete only: a pawn with a body mesh and the parkour component - never a menu's pawn. Everything is checked
-- with IsValid before it is touched: a null object read crashes the game.)
local athlete = { addr = nil, ok = false }
local function comp_named(pawn, name)
    local found = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.ActorComponent"))) do
            local o = c:get()
            if o and o:IsValid() and o:GetFName():ToString() == name then found = o; break end
        end
    end)
    return found
end
M.comp_named = comp_named

function M.pawn()
    if fc and fc.pawn ~= nil then return fc.pawn or nil end
    local pc = M.controller()
    local p = nil
    if pc then pcall(function() p = pc.Pawn end) end
    if not (p and p:IsValid()) then p = nil end
    if p then
        local addr = p:GetAddress()
        if athlete.addr ~= addr then
            athlete.addr, athlete.pk = addr, comp_named(p, "Parkour!")
            athlete.ok = athlete.pk ~= nil
            if athlete.ok then
                local okm, mesh = pcall(function() return p.Mesh end)
                athlete.ok = okm and mesh ~= nil and mesh:IsValid()
            end
        end
        if not athlete.ok then p = nil end
    end
    if fc then fc.pawn = p or false end
    return p
end
-- his parkour component ("Parkour!": StartRagdoll, TryGetupFromRagdoll)
function M.parkour(pawn)
    if not pawn then return nil end
    if athlete.addr == pawn:GetAddress() and athlete.pk then
        local ok, yes = pcall(function() return athlete.pk:IsValid() end)
        if ok and yes then return athlete.pk end
    end
    athlete.pk = comp_named(pawn, "Parkour!")
    return athlete.pk
end

-- STORROR's own sounds, by what they are for: its bail's bone breaks; heavy landings for the body and head hitting the
-- ground, its hands' slaps on concrete for limbs; its clothes' rustle; its grunts. Played where they happen (`loc`), from
-- his body - not flat in the ears: "the audios terrible", 2026-11-10.
local SFX = "/SPP/Sounds/SFX/Player/"
local SOUNDS = {
    crack = {},
    thud = { SFX .. "Footsteps/Landing/SFX_LANDING_CONCRETE_01.SFX_LANDING_CONCRETE_01", SFX .. "Footsteps/Landing/SFX_LANDING_CONCRETE_02.SFX_LANDING_CONCRETE_02",
             SFX .. "Footsteps/Landing/SFX_LANDING_CONCRETE_03.SFX_LANDING_CONCRETE_03", SFX .. "Footsteps/Landing/SFX_LANDING_CONCRETE_04.SFX_LANDING_CONCRETE_04" },
    slap = {},
    cloth = { SFX .. "Clothes/Player_ClothesMeta.Player_ClothesMeta" },
    grunt = { SFX .. "Grunts/Player_GruntsMeta.Player_GruntsMeta" },
}
for i = 1, 13 do SOUNDS.crack[i] = string.format("%sBail/BoneBreak_%02d.BoneBreak_%02d", SFX, i, i) end
for i = 1, 8 do SOUNDS.slap[i] = string.format("%sHands/Concrete_Hands_Med_%02d.Concrete_Hands_Med_%02d", SFX, i, i) end
local PITCH = { crack = { 0.92, 1.08 }, thud = { 0.9, 1.1 }, slap = { 0.85, 1.05 }, cloth = { 0.9, 1.1 }, grunt = { 0.9, 1.05 } }
local cache, missing = {}, {}
-- key: which; vol: 0..1; loc: where ({X,Y,Z}, or nil for flat); pitch: or nil for its own range
function M.sound(key, vol, loc, pitch)
    local list = SOUNDS[key]
    if not list or #list == 0 then return false end
    local path = list[math.random(1, #list)]
    local snd = cache[path]
    if not (snd and snd:IsValid()) then
        snd = StaticFindObject(path)
        if not (snd and snd:IsValid()) and LoadAsset then pcall(function() snd = LoadAsset(path) end) end
        cache[path] = snd
    end
    if not (snd and snd:IsValid()) then
        if not missing[path] then missing[path] = true; M.log("sound not found: %s", path) end
        return false
    end
    local w = M.world()
    if not w then return false end
    local pr = PITCH[key]
    local p = pitch or (pr and (pr[1] + (pr[2] - pr[1]) * math.random()) or 1.0)
    local GS = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local ok = false
    if loc then
        ok = pcall(function() GS:PlaySoundAtLocation(w, snd, loc, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }, vol or 1.0, p, 0.0, nil, nil, nil, nil) end)
    end
    if not ok then ok = pcall(function() GS:PlaySound2D(w, snd, vol or 1.0, p, 0.0, nil, nil, true) end) end
    return ok
end

function M.forget() athlete = { addr = nil, ok = false }; cache = {} end
return M
