-- STORROR Active Ragdoll: gore - limbs torn off in the worst blows, bleeding (from the SM64 mashup's gore, "the only thing
-- I wanted from the mashup was the gore", 2026-11-10; there all of him came apart as he died, here one part at a time).
--
-- A part torn off is a copy of him - a PoseableMeshComponent of his body, copies of his face, shoes and clothes led by it -
-- with everything but that part shrunk to nothing into its cut (his skeleton's root scaled to a thousandth and put at the
-- joint, the part set back where it was; parts of it torn off before shrunk into their own cuts), riding a physics box of
-- its size, thrown off him. His own body is drawn as one more such copy, posed from him every frame, the parts gone
-- shrunk into their stumps - his body hidden, his face, shoes and clothes led by the copy.
-- Blood: drops from every cut - each stump and both ends of each part - in spurts with his heartbeat, fading over some
-- seconds, each leaving a splat where it lands, painting the ground; a pool spreading under him.
-- All put back (M.clear) as he gets up; the blood on the ground stays till the next time.
local lib = _G.ARLIB
local log = lib.log
local M = { VERSION = 37 }

local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local EPS = { X = 0.001, Y = 0.001, Z = 0.001 }
local POSEABLE = "/Script/Engine.PoseableMeshComponent"
local SKEL = "/Script/Engine.SkeletalMeshComponent"
local CLOTH = "/Script/ChaosClothAssetEngine.ChaosClothComponent"
local GROOM = "/Script/HairStrandsCore.GroomComponent"
local sqrt, sin, pi, random, min, max = math.sqrt, math.sin, math.pi, math.random, math.min, math.max

-- ------------------------------------------------------------ engine helpers (actors, meshes, pictures, materials)
local function here() local w = lib.world(); return w and w:GetAddress() end
local function spawn_actor(world, loc, yaw)
    local a = world:SpawnActor(StaticFindObject("/Script/Engine.StaticMeshActor"), loc, { Pitch = 0.0, Yaw = yaw or 0.0, Roll = 0.0 })
    if not (a and a:IsValid()) then return nil end
    pcall(function() a.RootComponent:SetMobility(2) end)
    return a
end
local function add_pmc(actor)
    local cls = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
    local c = actor:AddComponentByClass(cls, false, IDENT, false)
    if c and c:IsValid() then pcall(function() c:SetMobility(2) end); return c end
    return nil
end
local function destroy(actor)
    if not actor then return end
    pcall(function() if actor:IsValid() then actor:K2_DestroyActor() end end)
end
-- (CreateMeshSection_LinearColor's arguments by its own parameter names)
local sig_cache = nil
local function create_section(pmc, id, verts, idx, nrms, uvs, cols, collide)
    if sig_cache == nil then
        sig_cache = false
        local fn = StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent:CreateMeshSection_LinearColor")
        if fn and fn:IsValid() then
            local names = {}
            local ok = pcall(function() fn:ForEachProperty(function(prop) names[#names + 1] = prop:GetFName():ToString() end) end)
            if ok and #names > 0 then sig_cache = names end
        end
    end
    local args
    if sig_cache then
        args = {}
        for i, name in ipairs(sig_cache) do
            local n = name:lower()
            if n == "sectionindex" then args[i] = id
            elseif n == "vertices" then args[i] = verts
            elseif n == "triangles" then args[i] = idx
            elseif n == "normals" then args[i] = nrms
            elseif n == "uv0" then args[i] = uvs
            elseif n == "vertexcolors" then args[i] = cols
            elseif n == "bcreatecollision" then args[i] = collide
            elseif n:sub(1, 1) == "b" then args[i] = false
            else args[i] = {} end
        end
    else
        args = { id, verts, idx, nrms, uvs, {}, {}, {}, cols, {}, collide, false }
    end
    pmc:CreateMeshSection_LinearColor(table.unpack(args, 1, #args))
end
-- (the mod's pictures, from its textures folder; each kept while the engine still has it by the same name)
local tex_cache, mid_cache, mid_n = {}, {}, 0
local function same(e) return e ~= nil and e.obj:IsValid() and e.obj:GetFName():ToString() == e.name end
local function texture(world, file)
    local c = tex_cache[file]
    local ok, yes = pcall(same, c)
    if ok and yes then return c.obj end
    local KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    local path = lib.MOD_DIR .. "textures\\" .. file .. ".png"
    local okt, t = pcall(function() return KRL:ImportFileAsTexture2D(world, path) end)
    if okt and t and t:IsValid() then
        tex_cache[file] = { obj = t, name = t:GetFName():ToString() }
        return t
    end
    log("gore: picture not found: %s", path)
    return nil
end
-- (a cut-out material with the picture: the engine's masked widget material, its picture "SlateUI", unlit - the blood's
-- pictures made dark in the file (x0.38), so it reads as blood and does not glow: drawn bright with it, "blood is showing
-- as neon", 2026-11-10. The glTF importer's lit masked material, tried for that, did not cut the picture out - every drop
-- and splat a square, "all the sprites are squared" - and is left as an option: LIT_BLOOD.)
local LIT = { path = "/InterchangeAssets/gltf/MaterialInstances/MI_Default_Mask.MI_Default_Mask", param = "BaseColorTexture" }
local UNLIT = { path = "/Engine/EngineMaterials/Widget3DPassThrough_Masked_OneSided.Widget3DPassThrough_Masked_OneSided", param = "SlateUI" }
M.BLOOD_TINT = { R = 0.42, G = 0.32, B = 0.32, A = 1.0 }
M.BLOOD_ROUGH = 0.35
M.LIT_BLOOD = false
local function load_mat(path)
    local o = StaticFindObject(path)
    if not (o and o:IsValid()) then pcall(function() o = LoadAsset(path) end) end
    if o and o:IsValid() then return o end
    return nil
end
local function get_mid(world, file)
    local c = mid_cache[file]
    local ok, yes = pcall(same, c)
    if ok and yes then return c.obj end
    local spec = M.LIT_BLOOD and LIT or UNLIT
    local parent = load_mat(spec.path)
    if not parent and spec == LIT then spec = UNLIT; parent = load_mat(spec.path) end
    if not parent then return nil end
    mid_n = mid_n + 1
    local KML = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local mid = KML:CreateDynamicMaterialInstance(world, parent, FName(string.format("ARGore_%d_%d", os.time(), mid_n)), 0)
    if not (mid and mid:IsValid()) then return nil end
    local t = texture(world, file)
    if t then pcall(function() mid:SetTextureParameterValue(FName(spec.param), t) end) end
    if spec == LIT then
        pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), M.BLOOD_TINT) end)
        pcall(function() mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0) end)
        pcall(function() mid:SetScalarParameterValue(FName("RoughnessFactor"), M.BLOOD_ROUGH) end)
    end
    mid_cache[file] = { obj = mid, name = mid:GetFName():ToString() }
    return mid
end
-- (the ground under a point: its height and slope, or nil)
local KSL = nil
local NO_COLOR = { R = 0, G = 0, B = 0, A = 0 }
local function floor_normal(x, y, z)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local pawn = lib.pawn()
    local hit = {}
    local ok, r = pcall(function()
        return KSL:LineTraceSingle(lib.world(), { X = x, Y = y, Z = z }, { X = x, Y = y, Z = z - 3000.0 }, 0, false,
            pawn and { pawn } or {}, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    if not (ok and r) then return nil end
    local okp, fz, nx, ny, nz = pcall(function()
        return hit.ImpactPoint.Z, hit.ImpactNormal.X, hit.ImpactNormal.Y, hit.ImpactNormal.Z
    end)
    if okp then return fz, nx, ny, nz end
    return nil
end
local function floor_under(x, y, z) local fz = floor_normal(x, y, z); return fz end

local function comps(actor, path)
    local out = {}
    pcall(function()
        local cls = StaticFindObject(path)
        if not (cls and cls:IsValid()) then return end
        for _, c in ipairs(actor:K2_GetComponentsByClass(cls)) do
            local o = c:get()
            if o and o:IsValid() then out[#out + 1] = o end
        end
    end)
    return out
end
local function at(c, bone) local p = c:GetSocketLocation(FName(bone)); return { p.X, p.Y, p.Z } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
local function len(a) return sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
local function unit(a) local l = len(a); if l < 1e-6 then return { 0.0, 0.0, 1.0 } end; return mul(a, 1.0 / l) end
local function V(a) return { X = a[1], Y = a[2], Z = a[3] } end
local function rnd(a, b) return a + (b - a) * random() end
local function KML() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end

-- ------------------------------------------------------------ the parts
-- id; region: the damage figure's part it comes off from; root: its top bone (where it is cut off him); tip: the bone its
-- length runs to (stretch: past it, a hand's fingers); sphere / w: its box's radius or half-width (cm); kg; wear: his
-- meshes it takes copies of (Head the face, TorsoCloth the shirt, LegsCloth the trousers, Feet the shoes); ends: its cuts -
-- the bone at each and the way blood leaves it, from -> to; stump: on him, the bone shrunk and the way blood leaves it;
-- inside: the parts that come away with it.
M.PARTS = {
    { id = "head", region = "head", root = "neck_01", tip = "head", sphere = 15.0, up = 11.0, kg = 5.0, wear = {}, face = true,
      ends = { { at = "neck_01", from = "head", to = "neck_01", w = 5.0 } }, stump = { at = "neck_01", from = "spine_05", w = 6.0 } },
}
for _, s in ipairs({ "l", "r" }) do
    local function b(n) return n .. "_" .. s end
    local P = M.PARTS
    P[#P + 1] = { id = b("arm"), region = b("upperarm"), root = b("upperarm"), tip = b("hand"), stretch = 1.12, w = 6.5, kg = 4.2,
        wear = { "TorsoCloth" }, inside = { b("forearm"), b("hand") },
        ends = { { at = b("upperarm"), from = b("lowerarm"), to = b("upperarm"), w = 5.0 } }, stump = { at = b("upperarm"), from = b("clavicle"), w = 5.5 } }
    P[#P + 1] = { id = b("forearm"), region = b("lowerarm"), root = b("lowerarm"), tip = b("hand"), stretch = 1.3, w = 5.2, kg = 1.9,
        wear = { "TorsoCloth" }, inside = { b("hand") },
        ends = { { at = b("lowerarm"), from = b("hand"), to = b("lowerarm"), w = 4.0 } }, stump = { at = b("lowerarm"), from = b("upperarm"), w = 4.5 } }
    P[#P + 1] = { id = b("hand"), region = b("hand"), root = b("hand"), tip = b("middle_01"), stretch = 1.8, w = 4.6, kg = 0.6, wear = {},
        ends = { { at = b("hand"), from = b("middle_01"), to = b("hand"), w = 3.5 } }, stump = { at = b("hand"), from = b("lowerarm"), w = 3.5 } }
    P[#P + 1] = { id = b("leg"), region = b("thigh"), root = b("thigh"), tip = b("foot"), w = 9.0, kg = 12.0,
        wear = { "LegsCloth", "Feet" }, inside = { b("shin"), b("foot") },
        ends = { { at = b("thigh"), from = b("calf"), to = b("thigh"), w = 7.0 } }, stump = { at = b("thigh"), from = "pelvis", w = 7.5 } }
    P[#P + 1] = { id = b("shin"), region = b("calf"), root = b("calf"), tip = b("foot"), stretch = 1.15, w = 7.0, kg = 4.5,
        wear = { "LegsCloth", "Feet" }, inside = { b("foot") },
        ends = { { at = b("calf"), from = b("foot"), to = b("calf"), w = 5.0 } }, stump = { at = b("calf"), from = b("thigh"), w = 6.0 } }
    P[#P + 1] = { id = b("foot"), region = b("foot"), root = b("foot"), tip = b("ball"), stretch = 1.6, w = 6.0, kg = 1.2, wear = { "Feet" },
        ends = { { at = b("foot"), from = b("foot"), to = b("calf"), w = 4.0 } }, stump = { at = b("foot"), from = b("calf"), w = 4.0 } }
end
local BY_ID, BY_REGION = {}, {}
for i, P in ipairs(M.PARTS) do P.i = i; BY_ID[P.id] = P; BY_REGION[P.region] = P end
-- (the parts each part is inside of: a hand is inside the forearm and the arm)
local OUTER = {}
for _, P in ipairs(M.PARTS) do for _, inner in ipairs(P.inside or {}) do OUTER[inner] = OUTER[inner] or {}; table.insert(OUTER[inner], P.id) end end
-- the regions a part takes with it (for the figure)
function M.regions_of(id)
    local P = BY_ID[id]
    if not P then return {} end
    local out = { P.region }
    for _, inner in ipairs(P.inside or {}) do out[#out + 1] = BY_ID[inner].region end
    return out
end
function M.part_for(region) return BY_REGION[region] end

-- how the parts leave him: out from his chest, up, turning (cm/s, degrees/s) - on top of how that part of him was moving
M.FLING = { out = 200.0, up = 150.0, spin = 420.0 }
-- the blood (as the mashup's: rate drops a second at a stump / at a part's cut at the height of a beat; beat: beats a
-- second; life: s it lasts, fading; burst: drops at once as it comes off; speed: cm/s out of the cut (stump, part);
-- spread: cm/s every way; size: a drop's half-size, cm; max: drops at once; splats laid on in batches)
-- (`life`: every cut bleeds two minutes, whatever - "severed last 2 minutes", 2026-11-10; it was five - easing off to
-- `floor` of its rate over them. A broken bone's wound: M.FRACTURE's `life`)
M.BLOOD = { rate = 42.0, end_rate = 16.0, beat = 1.4, low = 0.45, life = 120.0, floor = 0.35, burst = 22, speed = { 300.0, 190.0 },
            spread = 60.0, size = { 2.6, 5.2 }, gravity = 1500.0, max = 50, prewarm = 3,
            every = 0.1, secs = 400, batch = 28 }

M.FLOOR_EVERY = 0.2
-- ------------------------------------------------------------ his blood
-- ("make a hp bar depending on blood drops, 1000 blood drops fall the player dies", 2026-11-10.) Every drop out of his own
-- wounds - a stump of his, a broken bone through his skin; not a part torn off him - is blood he has lost, `per_drop` HP
-- each (1000 drops at 100 HP); his HP all gone and he has bled out (ragdoll.lua: dead, kept down till a waypoint). His HP:
-- the RAGDOLL tab's MAX HP ("add a hp slide up to 1000 hp", 2026-11-10), less what he has lost. Given back as he is healed.
M.HP = { per_drop = 0.1 }
-- limb HP, the RAGDOLL tab's LIMB HP switch ("each limb should have its own seperate hp that adds up to 100 like tarkov",
-- "or a switch actually", 2026-11-10): his MAX HP split over every part of the damage figure - his head 8%, his chest 36%,
-- each arm 14% (upper arm 6, forearm 5, hand 3) and each leg 14% (thigh 6, shin 5, foot 3): Tarkov's shares, to 100, each
-- part its own ("some limbs still have no hp on them", 2026-11-11). What a part of him loses comes off it; a part at none
-- passes on what more it takes, shared over the rest; his head's or his chest's gone - dead. Healed one part at a time
-- (ragdoll.lua's REGENERATION picks which).
-- (`spill`: what a part can't take - none left, or more than it had - goes on to the rest of him at this much, as Tarkov's
-- blacked limbs pass damage on: "now can you also improve tarkov damage as well", "0 HP rules", 2026-11-11)
M.LIMB_HP = { share = { head = 0.08, chest = 0.36 }, order = { "head", "chest" }, spill = 0.7 }
for _, sd in ipairs({ "l", "r" }) do
    for _, e in ipairs({ { "upperarm", 0.06 }, { "lowerarm", 0.05 }, { "hand", 0.03 }, { "thigh", 0.06 }, { "calf", 0.05 }, { "foot", 0.03 } }) do
        local id = e[1] .. "_" .. sd
        M.LIMB_HP.share[id] = e[2]
        M.LIMB_HP.order[#M.LIMB_HP.order + 1] = id
    end
end
local GROUP_OF = {}
for id in pairs(M.LIMB_HP.share) do GROUP_OF[id] = id end
M.GROUP_OF = GROUP_OF
local his_lost = 0       -- (HP, as one)
local limb_lost = {}     -- (HP each group has lost)
local function hp_max()
    local Mn = _G.ARMENU
    local v = Mn and Mn.hp_max and Mn.hp_max()
    return (v and v > 0) and v or 100
end
local function limb_on() local Mn = _G.ARMENU; return Mn ~= nil and Mn.limb_hp ~= nil and Mn.limb_hp() end
local function gmax(g, T) return T * M.LIMB_HP.share[g] end
local function g_left(g, T) return max(0.0, gmax(g, T) - (limb_lost[g] or 0.0)) end
local function limb_lose(g, n)
    if n <= 0.0 then return end
    local T = hp_max()
    local L = M.LIMB_HP
    if g and L.share[g] then
        local take = min(g_left(g, T), n)
        if take > 0.0 then limb_lost[g] = (limb_lost[g] or 0.0) + take; n = n - take end
        n = n * (L.spill or 1.0)
    end
    -- (what it could not take - or with no part: shared out over the parts with HP left, his arms and legs first; his chest only
    -- once they are all gone, his head last - "make the head and body the last things to lose hp in this", 2026-11-11)
    local guard = 0
    while n > 1e-6 and guard < 8 do
        guard = guard + 1
        local open = {}
        for _, k in ipairs(L.order) do if k ~= "head" and k ~= "chest" and g_left(k, T) > 1e-6 then open[#open + 1] = k end end
        -- (then his chest, his head last of all - "then chest heads last")
        if #open == 0 then
            for _, k in ipairs({ "chest", "head" }) do if #open == 0 and g_left(k, T) > 1e-6 then open[1] = k end end
        end
        if #open == 0 then return end
        local each = n / #open
        n = 0.0
        for _, k in ipairs(open) do
            local take = min(g_left(k, T), each)
            limb_lost[k] = (limb_lost[k] or 0.0) + take
            n = n + (each - take)
        end
    end
end
-- `n` HP lost from his `region` (the damage figure's part, or nil: all of him)
local function lose(n, region)
    his_lost = his_lost + n
    limb_lose(GROUP_OF[region or ""], n)
end
-- (BLEEDING off, on the RAGDOLL tab: no blood out of him and none lost - "blood player doesnt bleed option", 2026-11-11)
function M.bleeding_on() local Mn = _G.ARMENU; return not (Mn and Mn.bleeding and not Mn.bleeding()) end
local function bled(n, region) if not M.bleeding_on() then return end; lose((n or 1) * M.HP.per_drop, region) end
local function limb_points()
    if not limb_on() then return nil end
    local T, left = hp_max(), 0.0
    for _, g in ipairs(M.LIMB_HP.order) do left = left + g_left(g, T) end
    return left, T
end
function M.limb_mode() return limb_on() end
-- each group's HP left and its most, { [group] = { left, most } }, with LIMB HP on
function M.limb_hp()
    if not limb_on() then return nil end
    local T, out = hp_max(), {}
    for _, g in ipairs(M.LIMB_HP.order) do out[g] = { g_left(g, T), gmax(g, T) } end
    return out
end
-- his head's or his chest's HP gone: which (death)
function M.limb_dead()
    if not limb_on() then return nil end
    local T = hp_max()
    for _, g in ipairs({ "head", "chest" }) do if g_left(g, T) <= 1e-6 then return g end end
    return nil
end
-- (his head's or chest's HP gone: none at all - with HP still in his other parts he looked alive, lying dead, "player cant
-- get up even though they're alive?", 2026-11-11)
function M.hp()
    local left, T = limb_points()
    if left then return M.limb_dead() and 0.0 or max(0.0, left / T) end
    return max(0.0, 1.0 - his_lost / hp_max())
end
function M.hp_points()
    local left = limb_points()
    if left then return M.limb_dead() and 0.0 or left end
    return max(0.0, hp_max() - his_lost)
end
function M.hp_lost() local left, T = limb_points(); if left then return T - left end; return his_lost end
function M.blood_lost() return math.floor(his_lost / M.HP.per_drop + 0.5) end
function M.blood_reset() his_lost = 0; limb_lost = {} end
-- HP taken at once (ragdoll.lua's HP_COST: each injury as it happens, `region` the part of him hurt)
function M.take_hp(points, region) lose(points or 0, region) end
-- HP given back (REGENERATION, ragdoll.lua): with LIMB HP, to one group at a time - `group` if it has lost any, else the one
-- that has lost most
function M.heal_hp(points, group)
    points = points or 0
    his_lost = max(0.0, his_lost - points)
    if not limb_on() then return end
    local g = (group and (limb_lost[group] or 0.0) > 1e-6) and group or nil
    if not g then
        local most = 1e-6
        for _, k in ipairs(M.LIMB_HP.order) do if (limb_lost[k] or 0.0) > most then g, most = k, limb_lost[k] end end
    end
    if g then limb_lost[g] = max(0.0, limb_lost[g] - points) end
end
local st = nil              -- { world, pawn, body, torso, pieces = { [id] = part }, emitters, t }
local drops = nil
local paint = nil
local body_pool = nil

-- ------------------------------------------------------------ the meshes of the blood
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local function mesh(h, flat)
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
    local tc = { { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 } }
    local function quad(ax, ay, az, bx, by, bz, nx, ny, nz)
        local n = #verts
        for k = 1, 4 do
            local s, t = corners[k][1] * h, corners[k][2] * h
            verts[n + k] = { X = ax * s + bx * t, Y = ay * s + by * t, Z = az * s + bz * t }
            nrms[n + k] = { X = nx, Y = ny, Z = nz }
            uvs[n + k] = { X = tc[k][1], Y = tc[k][2] }
            cols[n + k] = WHITE
        end
        local m = #idx
        idx[m + 1], idx[m + 2], idx[m + 3], idx[m + 4], idx[m + 5], idx[m + 6] = n, n + 1, n + 2, n, n + 2, n + 3
        idx[m + 7], idx[m + 8], idx[m + 9], idx[m + 10], idx[m + 11], idx[m + 12] = n, n + 2, n + 1, n, n + 3, n + 2
    end
    quad(1, 0, 0, 0, 1, 0, 0, 0, 1)
    if not flat then
        quad(1, 0, 0, 0, 0, 1, 0, 1, 0)
        quad(0, 1, 0, 0, 0, 1, 1, 0, 0)
    end
    return verts, idx, nrms, uvs, cols
end
local function section(world, pmc, h, flat, tex)
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetReceivesDecals(false) end)
    pcall(function() pmc:SetCastShadow(false) end)
    local v, i, n, u, c = mesh(h, flat)
    create_section(pmc, 0, v, i, n, u, c, false)
    local mid = get_mid(world, tex)
    if mid then pcall(function() pmc:SetMaterial(0, mid) end) end
end
local function sprite(world, flat, tex)
    local a = spawn_actor(world, { X = 0.0, Y = 0.0, Z = -100000.0 }, 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = add_pmc(a)
    if not pmc then destroy(a); return nil end
    section(world, pmc, 1.0, flat, tex)
    pcall(function() a:SetActorHiddenInGame(true) end)
    return a
end
local function wound(world, a, pose, bone, h)
    local pmc = add_pmc(a)
    if not pmc then return end
    section(world, pmc, h, false, "gore_blood_cut")
    pcall(function() pmc:K2_AttachToComponent(pose, FName(bone), 2, 2, 2, false) end)
end

-- ------------------------------------------------------------ the copies of him
local function copy_mats(dst, src)
    pcall(function()
        for i = 0, src:GetNumMaterials() - 1 do
            local m = src:GetMaterial(i)
            if m and m:IsValid() then dst:SetMaterial(i, m) end
        end
    end)
end
local function make_followers(a, pawn, pose, wear)
    local out = {}
    local want = {}
    for _, n in ipairs(wear or {}) do want[n] = true end
    if not next(want) then return out end
    for _, src in ipairs(comps(pawn, SKEL)) do
        local n = src:GetFName():ToString()
        if want[n] then pcall(function()
            local c = a:AddComponentByClass(StaticFindObject(SKEL), true, IDENT, false)
            c:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
            c:K2_AttachToComponent(pose, FName("None"), 0, 0, 0, false)
            pcall(function() c:SetCollisionEnabled(0) end)
            c:SetLeaderPoseComponent(pose, true, false)
            pcall(function() c:SetReceivesDecals(false) end)
            pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
            pcall(function() c:SetForcedLOD(1) end)
            pcall(function() c.bComponentUseFixedSkelBounds = true end)
            pcall(function() c:SetBoundsScale(1.5) end)
            out[#out + 1] = { c = c, name = n }
        end) end
    end
    local ccls = StaticFindObject(CLOTH)
    if not (ccls and ccls:IsValid()) then return out end
    for _, src in ipairs(comps(pawn, CLOTH)) do
        local n = src:GetFName():ToString()
        if want[n] then pcall(function()
            local asset = src:GetAsset()
            if not (asset and asset:IsValid()) then return end
            local c = a:AddComponentByClass(ccls, true, IDENT, false)
            c:SetAsset(asset)
            c:K2_AttachToComponent(pose, FName("None"), 0, 0, 0, false)
            c:SetLeaderPoseComponent(pose, true, false)
            pcall(function() c:SetReceivesDecals(false) end)
            pcall(function() c:SetEnableSimulation(false) end)
            pcall(function() c:SetBoundsScale(1.5) end)
            out[#out + 1] = { c = c, name = n }
        end) end
    end
    return out
end
local function dress_followers(pawn, list)
    if #list == 0 then return end
    local by = {}
    for _, src in ipairs(comps(pawn, SKEL)) do by[src:GetFName():ToString()] = src end
    for _, src in ipairs(comps(pawn, CLOTH)) do by[src:GetFName():ToString()] = src end
    for _, f in ipairs(list) do
        local src = by[f.name]
        if src then pcall(function()
            f.c:K2_SetWorldTransform(src:K2_GetComponentToWorld(), false, {}, true)
            copy_mats(f.c, src)
        end) end
    end
end
-- what hangs on his head socket: onto `to`'s head, or back onto his body
local function carry(s, to)
    if to then
        s.carried = {}
        local kids = {}
        pcall(function() s.body:GetChildrenComponents(false, kids) end)
        for _, c in ipairs(kids) do
            pcall(function()
                local o = c.get and c:get() or c
                if not (o and o:IsValid()) then return end
                local sock = o:GetAttachSocketName():ToString()
                if sock:lower() == "head" then
                    o:K2_AttachToComponent(to, FName(sock), 0, 0, 0, false)
                    s.carried[#s.carried + 1] = { o = o, sock = sock }
                end
            end)
        end
    else
        for _, e in ipairs(s.carried or {}) do
            pcall(function() if e.o:IsValid() then e.o:K2_AttachToComponent(s.body, FName(e.sock), 0, 0, 0, false) end end)
        end
        s.carried = nil
    end
end
local function face_of(pawn)
    for _, c in ipairs(comps(pawn, SKEL)) do if c:GetFName():ToString() == "Head" then return c end end
    return pawn.Mesh
end

-- one part, ready: its box (no collision, no physics yet), the copy on it, his clothes on that, a wound on each cut
local function prep_part(world, pawn, body, P)
    local a = spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorHiddenInGame(true) end)
    local part = { actor = a, P = P }
    local ok, err = pcall(function()
        local box = a:AddComponentByClass(StaticFindObject(P.sphere and "/Script/Engine.SphereComponent"
            or "/Script/Engine.BoxComponent"), true, IDENT, false)
        box:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        box:SetCollisionProfileName(FName("PhysicsActor"), true)
        -- (never him, the camera, the ragdoll's bodies, each other, or his traces: STORROR's parkour keeps pointers to
        -- what its traces hit)
        for _, ch in ipairs({ 2, 3, 4, 5 }) do pcall(function() box:SetCollisionResponseToChannel(ch, 0) end) end
        pcall(function() box:SetUseCCD(true, FName("None")) end)
        pcall(function() box:SetLinearDamping(0.1) end)
        pcall(function() box:SetAngularDamping(1.2) end)
        box:SetCollisionEnabled(0)
        part.box = box
        local pose = a:AddComponentByClass(StaticFindObject(POSEABLE), true, IDENT, false)
        local src = P.face and face_of(pawn) or body
        pose:SetSkinnedAssetAndUpdate(src:GetSkinnedAsset(), true)
        pose:K2_AttachToComponent(box, FName("None"), 0, 0, 0, false)
        pcall(function() pose:SetCastShadow(true) end)
        pcall(function() pose:SetReceivesDecals(false) end)
        pcall(function() pose:SetForcedLOD(1) end)
        pcall(function() pose.bComponentUseFixedSkelBounds = true end)
        pcall(function() pose:SetBoundsScale(1.5) end)
        part.pose = pose
        part.follow = make_followers(a, pawn, pose, P.wear)
        for _, E in ipairs(P.ends) do wound(world, a, pose, E.at, E.w) end
    end)
    if not ok then
        log("gore: the %s's copy could not be made: %s", P.id, tostring(err))
        destroy(a)
        return nil
    end
    part.ready = true
    return part
end

-- one part off him: put where it is on him, dressed and posed as he is, all of him but it shrunk into its cut, thrown
local function fire_part(world, pawn, body, part, base_v, chest, gone, fling)
    local P = part.P
    local p0 = at(body, P.root)
    local p1 = at(body, P.tip)
    local center, xdir, half
    if P.sphere then
        center = add(p1, mul(unit(sub(p1, p0)), P.up))
    else
        local d = sub(p1, p0)
        half = len(d) * (P.stretch or 1.0) / 2.0
        xdir = unit(d)
        center = add(p0, mul(xdir, half))
    end
    local box, pose = part.box, part.pose
    if P.sphere then
        box:SetSphereRadius(P.sphere, false)
        box:K2_SetWorldLocationAndRotation(V(center), { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 }, false, {}, true)
    else
        box:SetBoxExtent({ X = half, Y = P.w, Z = P.w }, false)
        box:K2_SetWorldLocationAndRotation(V(center), KML():MakeRotFromX(V(xdir)), false, {}, true)
    end
    local src = P.face and face_of(pawn) or body
    pose:K2_SetWorldTransform(src:K2_GetComponentToWorld(), false, {}, true)
    copy_mats(pose, src)
    dress_followers(pawn, part.follow)
    pose:CopyPoseFromSkeletalComponent(body)
    local tp = pose:GetBoneTransformByName(FName(P.root), 0)
    local root = pose:GetBoneName(0)
    -- (the copy's own origin moved to the part's middle, its clothes' with it, before its bones are set where they are in
    -- the world: the engine draws a mesh by bounds round its origin, and left at his feet - under the floor once the part
    -- lay on the ground - the part was taken for hidden and not drawn: "body parts going invisable because there too close
    -- to the floor", 2026-11-10)
    pose:K2_SetWorldLocation(V(center), false, {}, true)
    local pt = pose:K2_GetComponentToWorld()
    for _, f in ipairs(part.follow) do pcall(function() f.c:K2_SetWorldTransform(pt, false, {}, true) end) end
    pose:SetBoneScaleByName(root, EPS, 1)
    pose:SetBoneLocationByName(root, tp.Translation, 0)
    pose:SetBoneTransformByName(FName(P.root), tp, 0)
    -- (what came off it before - a hand off the forearm now going - shrunk into its own cut)
    for _, inner in ipairs(P.inside or {}) do
        if gone[inner] then pose:SetBoneScaleByName(FName(BY_ID[inner].root), EPS, 1) end
    end
    part.ends = {}
    local bt = box:K2_GetComponentToWorld()
    for _, E in ipairs(P.ends) do
        local d = unit(sub(at(body, E.to), at(body, E.from)))
        local dl = KML():InverseTransformDirection(bt, V(d))
        part.ends[#part.ends + 1] = { bone = E.at, dl = { dl.X, dl.Y, dl.Z }, w = E.w }
    end
    pcall(function() part.actor:SetActorHiddenInGame(false) end)
    box:SetCollisionEnabled(3)
    box:SetSimulatePhysics(true)
    pcall(function() box:SetMassOverrideInKg(FName("None"), P.kg, true) end)
    local out = unit(sub(center, chest))
    local F = M.FLING
    local k = fling or 1.0
    local v = add(base_v, add(mul(out, F.out * k * rnd(0.7, 1.2)), { rnd(-40, 40) * k, rnd(-40, 40) * k, F.up * k * rnd(0.6, 1.2) }))
    box:SetPhysicsLinearVelocity(V(v), false, FName("None"))
    local sp = F.spin * k
    box:SetPhysicsAngularVelocityInDegrees({ X = rnd(-sp, sp), Y = rnd(-sp, sp), Z = rnd(-sp, sp) }, false, FName("None"))
    part.ready = false
end
local function reset_part(part)
    pcall(function() part.box:SetSimulatePhysics(false) end)
    pcall(function() part.box:SetCollisionEnabled(0) end)
    pcall(function() part.box:K2_AttachToComponent(part.actor.RootComponent, FName("None"), 1, 1, 1, false) end)
    pcall(function() part.actor:SetActorHiddenInGame(true) end)
    part.ready = true
end

-- his own body drawn as a copy, posed from him every frame, the parts gone shrunk into their stumps
local function prep_torso(world, pawn, body)
    local a = spawn_actor(world, body:K2_GetComponentLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorHiddenInGame(true) end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local t = { actor = a, cuts = {}, ready = true }
    local ok, err = pcall(function()
        a:K2_AttachToComponent(body, FName("None"), 2, 2, 2, false)
        local pose = a:AddComponentByClass(StaticFindObject(POSEABLE), true, IDENT, false)
        pose:SetSkinnedAssetAndUpdate(body:GetSkinnedAsset(), true)
        pose:K2_AttachToComponent(a.RootComponent, FName("None"), 2, 2, 2, false)
        pcall(function() pose:SetCastShadow(true) end)
        pcall(function() pose:SetReceivesDecals(false) end)
        pcall(function() pose:SetForcedLOD(1) end)
        t.pose = pose
        t.hid = {}
        -- (his own body drawn, the parts gone hidden on it - the engine poses it every frame, his clothes and face with it.
        -- The copy drawn in his place was posed from him once a frame by the mod, a frame behind, and in a fast fall
        -- everything but his head shook - "the only thing that doesnt glitch out is the head", 2026-11-11. The copy is
        -- kept, hidden, for where his stumps are)
        t.posed = function()
            pose:CopyPoseFromSkeletalComponent(body)
            for _, f in ipairs(t.cuts) do
                pose:SetBoneScaleByName(f, EPS, 1)
                local k = f:ToString()
                if not t.hid[k] then t.hid[k] = f; pcall(function() body:HideBoneByName(f, 0) end) end
            end
        end
    end)
    if not ok then
        log("gore: his body's copy could not be made: %s", tostring(err))
        destroy(a)
        return nil
    end
    return t
end
local function own_head_off(s, pawn, body, part)
    local head = face_of(pawn)
    if head == body then return end
    s.head = { c = head, hair = {} }
    pcall(function() head:SetVisibility(false, false) end)
    for _, g in ipairs(comps(pawn, GROOM)) do
        pcall(function()
            local sock = g:GetAttachSocketName()
            g:K2_AttachToComponent(part.pose, sock, 0, 0, 0, false)
            pcall(function() g:ResetSimulation() end)
            s.head.hair[#s.head.hair + 1] = { g = g, sock = sock }
        end)
    end
end
local function own_head_back(s)
    local h = s.head
    s.head = nil
    if not h then return end
    for _, e in ipairs(h.hair) do
        pcall(function() if e.g:IsValid() then e.g:K2_AttachToComponent(h.c, e.sock, 0, 0, 0, false); e.g:ResetSimulation() end end)
    end
    pcall(function() if h.c:IsValid() then h.c:SetVisibility(true, false) end end)
end
local function fire_torso(pawn, body, t, skip)
    copy_mats(t.pose, body)
    t.cuts = {}
    pcall(t.posed)
    pcall(function() t.tick_was = body.VisibilityBasedAnimTickOption; body.VisibilityBasedAnimTickOption = 0 end)
    -- (posed every frame while hidden: his face and hair stay led by him, not by the copy - "hair flickering and
    -- deleting", 2026-11-10, with his MetaHuman face and its hair cards led by the copy)
    pcall(function() t.uro_was = body.bEnableUpdateRateOptimizations; body.bEnableUpdateRateOptimizations = false end)
    t.follow = {}
    t.ready = false
end
local function reset_torso(t, body)
    for _, f in pairs(t.hid or {}) do pcall(function() if body:IsValid() then body:UnHideBoneByName(f) end end) end
    t.hid = {}
    for _, c in ipairs(t.follow or {}) do pcall(function() if c:IsValid() then c:SetLeaderPoseComponent(body, true, false) end end) end
    t.follow = nil
    t.cuts = {}
    pcall(function()
        if body:IsValid() then
            body:SetVisibility(true, false)
            if t.tick_was ~= nil then body.VisibilityBasedAnimTickOption = t.tick_was end
            if t.uro_was ~= nil then body.bEnableUpdateRateOptimizations = t.uro_was end
        end
    end)
    pcall(function() t.actor:SetActorHiddenInGame(true) end)
    t.ready = true
end

-- the copies made ahead, one every PREP_EVERY s while he is about (made all at once as a part came off, they held the
-- game up): { world, pawn, sig, torso, parts = { [i] = part or false } }
local prep = nil
local function sig_of(pawn)
    local t = {}
    pcall(function() t[#t + 1] = pawn.Mesh:GetSkinnedAsset():GetFName():ToString() end)
    for _, c in ipairs(comps(pawn, SKEL)) do pcall(function() t[#t + 1] = c:GetSkinnedAsset():GetFName():ToString() end) end
    for _, c in ipairs(comps(pawn, CLOTH)) do pcall(function() t[#t + 1] = c:GetAsset():GetFName():ToString() end) end
    return table.concat(t, "|")
end
local function prep_drop()
    local p = prep
    prep = nil
    if not (p and p.world == here()) then return end
    if p.torso then destroy(p.torso.actor) end
    for _, part in pairs(p.parts) do if part then destroy(part.actor) end end
end
local function prep_step(world, pawn)
    local wa, pa = world:GetAddress(), pawn:GetAddress()
    if not (prep and prep.world == wa and prep.pawn == pa) then
        prep_drop()
        prep = { world = wa, pawn = pa, body = pawn.Mesh, sig = sig_of(pawn), parts = {} }
        pcall(function()
            for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
                local o = c:get()
                if o and o:IsValid() then pcall(function() o:SetReceivesDecals(false) end) end
            end
        end)
    end
    if prep.torso == nil then prep.torso = prep_torso(world, pawn, pawn.Mesh) or false; return true end
    for i, P in ipairs(M.PARTS) do
        if prep.parts[i] == nil then prep.parts[i] = prep_part(world, pawn, pawn.Mesh, P) or false; return true end
    end
    return false
end
function M.ready() return prep ~= nil and prep.torso ~= nil and prep.parts[#M.PARTS] ~= nil end

-- ------------------------------------------------------------ the blood
local function drop_list(world)
    local w = world:GetAddress()
    if not (drops and drops.world == w) then drops = { world = w, list = {}, next = 1 } end
    return drops
end
-- A drop's flight: its arc (from where and how fast it left the cut, under gravity), traced ahead PREDICT_STEP s at a time
-- to the first thing it hits - floor, wall, anything - where it lands and paints. A few traces a frame at most
-- (TRACE_BUDGET), so a gush of drops is worked out over some frames; a drop not yet worked out is drawn along its arc and
-- lands where its hit is found. Never taken away in the air ("make sure blood drops dont despawn before hitting
-- something", 2026-11-10 - they were after 2.5 s, and the oldest in the air were taken for new ones): a new drop with
-- none free is not made; one that has met nothing in DROP_MAX_T s has fallen out of the world.
M.PREDICT_STEP, M.PREDICT_AHEAD, M.TRACE_BUDGET, M.DROP_MAX_T = 0.08, 1.0, 60, 8.0
local budget = 0
local function arc_at(d, t)
    local g = M.BLOOD.gravity
    return { d.p0[1] + d.v0[1] * t, d.p0[2] + d.v0[2] * t, d.p0[3] + d.v0[3] * t - 0.5 * g * t * t }
end
local function predict_some(d)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local pawn = lib.pawn()
    local ign = pawn and { pawn } or {}
    local world = lib.world()
    local step = M.PREDICT_STEP
    local a = arc_at(d, d.pf)
    while budget > 0 and d.pf < d.t + M.PREDICT_AHEAD do
        budget = budget - 1
        local t1 = d.pf + step
        local b = arc_at(d, t1)
        local hit = {}
        local ok, r = pcall(function()
            return KSL:LineTraceSingle(world, V(a), V(b), 0, false, ign, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
        end)
        if ok and r then
            local okh, hx, hy, hz, nx, ny, nz, frac = pcall(function()
                return hit.ImpactPoint.X, hit.ImpactPoint.Y, hit.ImpactPoint.Z, hit.ImpactNormal.X, hit.ImpactNormal.Y,
                    hit.ImpactNormal.Z, hit.Time
            end)
            if okh and hx then
                d.hit = { hx, hy, hz, nx or 0.0, ny or 0.0, nz or 1.0 }
                d.t_hit = d.pf + step * max(0.0, min(1.0, frac or 1.0))
                return
            end
        end
        d.pf = t1
        a = b
    end
end
M.UNDER_LOOK = 15.0
-- the speed of a body part of him, `inherit` of it, for the drops leaving it (lying: that bone's; on his feet: his)
M.INHERIT = 1.0
local function vel_of(mesh, bone)
    local ok, v = pcall(function()
        if mesh:IsSimulatingPhysics(bone) then return mesh:GetPhysicsLinearVelocity(bone) end
        return lib.pawn():GetVelocity()
    end)
    if ok and v then local k = M.INHERIT; return { v.X * k, v.Y * k, v.Z * k } end
    return nil
end
local function emit(world, e, pos, dir, speed, small, inherit)
    if not M.bleeding_on() then return end
    local D = drop_list(world)
    local B = M.BLOOD
    local d = nil
    for i = 1, #D.list do if not D.list[i].on then d = D.list[i]; break end end
    if not d then
        if #D.list >= B.max then
            -- ("bleeding ends randomly", 2026-11-10: every drop in the air at once - told, now and then)
            if os.clock() - (D.full_t or -99.0) > 5.0 then
                D.full_t = os.clock()
                local old = 0
                for _, q in ipairs(D.list) do if q.on and q.t > 3.0 then old = old + 1 end end
                log("gore: no blood drop free (%d in the air over 3 s)", old)
            end
            return
        end
        local a = sprite(world, false, "gore_blood_tear")
        if not a then return end
        d = { actor = a }
        D.list[#D.list + 1] = d
    end
    local sp = speed * rnd(0.6, 1.15)
    local s = B.spread
    d.on, d.t, d.e = true, 0.0, e
    d.roll = rnd(0.0, 360.0)
    d.splash = small ~= nil
    d.p0 = { pos[1], pos[2], pos[3] }
    d.v0 = { dir[1] * sp + rnd(-s, s), dir[2] * sp + rnd(-s, s), dir[3] * sp + rnd(-s, s) }
    -- (and the speed of what it bled from: "give blood momentum", 2026-11-10)
    if inherit then d.v0[1], d.v0[2], d.v0[3] = d.v0[1] + inherit[1], d.v0[2] + inherit[2], d.v0[3] + inherit[3] end
    d.pf, d.hit, d.t_hit = 0.0, nil, nil
    -- (a cut against the ground - a stump on the floor, a foot gone and the ankle in it: the drop starts under the
    -- surface, its arc never meets it and it fell for DROP_MAX_T, every drop at once in the air - the bleeding stopped,
    -- "bleeding ends randomly". Looked down to it from a little above: met on the way, it lands there at once.)
    pcall(function()
        KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local pawn = lib.pawn()
        local hit = {}
        local top = { X = pos[1], Y = pos[2], Z = pos[3] + M.UNDER_LOOK }
        if KSL:LineTraceSingle(world, top, V(d.p0), 0, false, pawn and { pawn } or {}, 0, hit, true, NO_COLOR, NO_COLOR, 0.0) then
            local hx, hy, hz = hit.ImpactPoint.X, hit.ImpactPoint.Y, hit.ImpactPoint.Z
            local nx, ny, nz = hit.ImpactNormal.X, hit.ImpactNormal.Y, hit.ImpactNormal.Z
            if hx and nz and nz > 0.3 then
                d.p0 = { hx + nx, hy + ny, hz + nz }
                d.hit, d.t_hit = { hx, hy, hz, nx, ny, nz }, 0.0
            end
        end
    end)
    local k = rnd(B.size[1], B.size[2]) * (small or 1.0)
    d.size = k
    pcall(function()
        d.actor:SetActorScale3D({ X = k, Y = k, Z = k })
        d.actor:K2_SetActorLocation(V(d.p0), false, {}, true)
        d.actor:SetActorHiddenInGame(false)
    end)
end
-- The ground painted: every drop leaves a splat where it lands (four kinds and sixteen streaks, each cut from one sheet)
M.SPLATS = {
    { name = "impact", r = { 2.2, 3.6 }, stretch = 1.0 / 260.0, long = 2.6, at = 0.18, dir = true },
    { name = "pool", r = { 3.6, 6.2 }, stretch = 0.0, long = 1.0, at = 0.0 },
    { name = "streak", r = { 1.6, 2.6 }, stretch = 1.0 / 170.0, long = 4.6, at = 0.5, dir = true },
    { name = "tiny", r = { 0.7, 1.3 }, stretch = 0.0, long = 1.0, at = 0.0 },
}
for _ = 1, 16 do
    M.SPLATS[#M.SPLATS + 1] = { r = { 1.6, 2.8 }, stretch = 1.0 / 190.0, long = 4.2, at = 0.55, dir = true, streak = true }
end
local STREAKS = { 3 }
for i, K in ipairs(M.SPLATS) do if K.streak then STREAKS[#STREAKS + 1] = i end end
M.ODDS = { tiny = 0.15, glob = 0.45, slow_glob = 0.75 }
local GLOBS = { 1, 2 }
local function splat_kind(hs)
    local O = M.ODDS
    if random() < O.tiny then return 4 end
    if random() < O.glob then return GLOBS[math.random(#GLOBS)] end
    if hs > 120.0 then return STREAKS[math.random(#STREAKS)] end
    if random() < O.slow_glob then return GLOBS[math.random(#GLOBS)] end
    return STREAKS[math.random(#STREAKS)]
end

-- ("I want it to wrap around objects correctly also I want the blood to pool into eachother", 2026-11-10.) Every splat
-- is a decal - projected onto whatever is there: over edges, down steps, onto things lying about - drawn with the
-- material STORROR paints its spray tags with (GraffitiMaster: a picture cut out by its alpha, coloured by its tint; the
-- glTF and widget materials draw no decals, and the bin stickers' and chalk marks' would not take the mod's pictures).
-- Slow drops on the floor run into puddles instead: each a decal grown to the blood in it (`area_k` of each drop's
-- splat, all added up), spreading at `grow` cm/s, its middle drawn toward where more lands. Two that meet run together:
-- the smaller's blood the bigger's, the bigger drawn toward the middle of both and spreading over the smaller, which is
-- taken away once covered. The pool under him is one of them. (Splats on it: `keep_splat` of the drops pooled.)
M.DECAL = { master = "/Game/Shared/VandalismShtuff/Graff/GraffitiMaster.GraffitiMaster",
            tint = { R = 0.055, G = 0.0016, B = 0.0022, A = 1.0 }, flip_u = 1.0,
            max = 1600, splat_depth = 10.0, every = 0.05, batch = 10,
            flat = 0.75, pool_hs = 140.0, keep_splat = 0.15 }
local abs = math.abs
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
local function GS() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end
local dmid_cache = {}
local function decal_mid(world, file)
    local c = dmid_cache[file]
    local ok, yes = pcall(same, c)
    if ok and yes then return c.obj end
    local parent = load_mat(M.DECAL.master)
    if not parent then return nil end
    mid_n = mid_n + 1
    local mid = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(world, parent,
        FName(string.format("ARBlood_%d_%d", os.time(), mid_n)), 0)
    if not (mid and mid:IsValid()) then return nil end
    local t = texture(world, file)
    if t then pcall(function() mid:SetTextureParameterValue(FName("GraffitiTEX"), t) end) end
    pcall(function() mid:SetVectorParameterValue(FName("ColourTint"), M.DECAL.tint) end)
    pcall(function() mid:SetScalarParameterValue(FName("TintAmount"), 1.0) end)
    -- (none of the spray paint's wear: with it, puddles were see-through, darker where they crossed - "the pooling
    -- sucks", 2026-11-10. Opacity 1: the pictures are solid white inside now, and at 3 the edge's filtered pixels - its
    -- colour and its cover both from the picture's brightness - came out solid and dark, "can still see a slight black
    -- outline")
    pcall(function() mid:SetScalarParameterValue(FName("Opacity"), 1.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("DamageFade"), 0.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("DamageChannel"), 0.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("BlurAmount"), 0.0) end)
    dmid_cache[file] = { obj = mid, name = mid:GetFName():ToString() }
    return mid
end
-- a decal: its middle `c`, pressed along -`n`, `sy` cm each way along `u` (its picture's width) and `sz` across, `depth`
-- deep each way
local function decal_spawn(world, mid, c, n, u, sy, sz, depth, order)
    local ok, d = pcall(function()
        local rot = KML():MakeRotFromXY(V(mul(n, -1.0)), V(u))
        return GS():SpawnDecalAtLocation(world, mid, { X = depth, Y = 1.0, Z = 1.0 }, V(c), rot, 0.0)
    end)
    if not (ok and d and d:IsValid()) then return nil end
    pcall(function() d:SetWorldScale3D({ X = 1.0, Y = sy, Z = sz }) end)
    pcall(function() d:SetSortOrder(order or 0) end)
    -- (never faded out for being small on the screen: they went as he moved off, "blood splats despawning", 2026-11-10)
    pcall(function() d:SetFadeScreenSize(0.0) end)
    return d
end
local function decal_drop(d) pcall(function() if d and d:IsValid() then d:K2_DestroyComponent(d) end end) end
-- a way along a surface: any, turned `a` round it
local function tangent(n, a)
    local ref = (abs(n[3]) < 0.9) and { 0.0, 0.0, 1.0 } or { 1.0, 0.0, 0.0 }
    local t1 = unit(cross(n, ref))
    local t2 = cross(n, t1)
    return unit(add(mul(t1, math.cos(a)), mul(t2, math.sin(a))))
end
local function paint_of(world)
    local w = world:GetAddress()
    if paint and paint.world == w then return paint end
    paint = { world = w, pending = {}, t = 0.0, list = {}, head = 1, tail = 0, spots = {} }
    return paint
end

-- ------------------------------------------------------------ puddles: the blood on the floor running together
-- ("its the pooling that sucks its just a texture growing in size I want the blood to combine on the floor and connect
-- not just one texture that gets bigger", 2026-11-10.) The blood on a floor is a field of soft blobs - one where each
-- slow drop lands, spreading out over `spread` s - and the puddle is wherever they add up past `edge`: a mesh of its
-- own, made from the field by marching squares over a `cell` cm grid. So blobs near each other reach out and bridge
-- before they touch, and run into one; blood landing well inside a puddle swells the blob it lands in (its area added),
-- at its edge starts a lobe of its own. Drawn lit and wet (the glTF lit material: deep red, `rough`), `lift` cm over
-- where the blood landed - the height under each blob, blended. Each floor's puddles are one mesh, rebuilt while they
-- spread (one a frame, each at most every `rebuild` s), in `region`-wide squares.
-- (its points shared between cells, its faces one-sided - `flip` turns them, `two_sided` draws both: at 4 cm cells, a
-- point of its own for every corner and both faces, 150 blobs took 12-14 ms a build)
M.PUDDLE = { cell = 5.0, edge = 0.35, region = 700.0, regions = 8, blobs = 160, rebuild = 0.2, lift = 0.4,
             r_k = 1.25, grow0 = 0.4, spread = 1.4, r_max = 50.0, join_in = 0.7, max_cells = 50000,
             two_sided = false, flip = false, min_blob = 12.0,
             color = { R = 0.06, G = 0.0009, B = 0.0013, A = 1.0 }, rough = 0.14 }
local puddles = nil      -- { world, regions = { { ox, oy, z0, blobs, actor, pmc, dirty, t } }, mid, next }
local floor_, ceil_ = math.floor, math.ceil
local function puddles_of(world)
    local w = world:GetAddress()
    if puddles and puddles.world == w then return puddles end
    puddles = { world = w, regions = {}, next = 1 }
    return puddles
end
local function puddle_mid(world, P)
    local ok, yes = pcall(same, P.mid)
    if ok and yes then return P.mid.obj end
    local parent = load_mat("/InterchangeAssets/gltf/M_Default.M_Default")
    if not parent then return nil end
    mid_n = mid_n + 1
    local mid = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(world, parent,
        FName(string.format("ARPuddle_%d_%d", os.time(), mid_n)), 0)
    if not (mid and mid:IsValid()) then return nil end
    pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), M.PUDDLE.color) end)
    pcall(function() mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("RoughnessFactor"), M.PUDDLE.rough) end)
    P.mid = { obj = mid, name = mid:GetFName():ToString() }
    return mid
end
local function region_for(world, P, x, y, z)
    local PD = M.PUDDLE
    local h = PD.region * 0.5
    for _, R in ipairs(P.regions) do
        if abs(x - R.ox) < h and abs(y - R.oy) < h and abs(z - R.z0) < 60.0 then return R end
    end
    if #P.regions >= PD.regions then
        -- (the oldest left as it is: no more blood joins it)
        table.remove(P.regions, 1)
    end
    local a = spawn_actor(world, { X = x, Y = y, Z = z }, 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    local pmc = add_pmc(a)
    if not pmc then destroy(a); return nil end
    pcall(function() pmc:SetCollisionEnabled(0) end)
    pcall(function() pmc:SetCastShadow(false) end)
    -- (the splats under it stay under it: drawn on it too, every splat it spread over showed as a ring in it - "scaly
    -- lines inside", 2026-11-10)
    pcall(function() pmc:SetReceivesDecals(false) end)
    local R = { ox = x, oy = y, z0 = z, blobs = {}, actor = a, pmc = pmc, dirty = false, t = 0.0 }
    P.regions[#P.regions + 1] = R
    return R
end
-- the field at a point: how much blood, and the blob most of it is from
local function field_at(R, x, y)
    local f, best, bk = 0.0, nil, 0.0
    for _, b in ipairs(R.blobs) do
        local dx, dy = x - b.x, y - b.y
        local r2 = b.r * b.r
        local d2 = dx * dx + dy * dy
        if d2 < r2 then
            local q = 1.0 - d2 / r2
            local k = q * q * q
            f = f + k
            if k > bk then best, bk = b, k end
        end
    end
    return f, best
end
-- blood on the floor at (x, y, z): `r` cm of it (the blob's reach)
local function blob_add(world, x, y, z, r)
    local PD = M.PUDDLE
    local P = puddles_of(world)
    local R = region_for(world, P, x, y, z)
    if not R then return end
    local f, near = field_at(R, x, y)
    local inside = f >= PD.edge
    if near and (#R.blobs >= PD.blobs or (inside and len({ x - near.x, y - near.y, 0.0 }) < near.r * PD.join_in)) then
        near.r1 = min(PD.r_max, sqrt(near.r1 * near.r1 + (r * 0.6) ^ 2))
        R.dirty = true
        return inside
    end
    R.blobs[#R.blobs + 1] = { x = x, y = y, z = z, r = r * PD.grow0, r1 = min(PD.r_max, r) }
    R.dirty = true
    return inside
end
-- the mesh of one floor's puddles, from its field
local function puddle_build(world, P, R)
    local PD = M.PUDDLE
    local c, T = PD.cell, PD.edge
    if #R.blobs == 0 then return end
    local x0, y0, x1, y1 = 1e18, 1e18, -1e18, -1e18
    for _, b in ipairs(R.blobs) do
        x0, y0 = min(x0, b.x - b.r), min(y0, b.y - b.r)
        x1, y1 = max(x1, b.x + b.r), max(y1, b.y + b.r)
    end
    x0, y0 = floor_(x0 / c) * c, floor_(y0 / c) * c
    local nx, ny = ceil_((x1 - x0) / c) + 2, ceil_((y1 - y0) / c) + 2
    if nx * ny > PD.max_cells then return end
    local F, Z, W = {}, {}, {}
    for _, b in ipairs(R.blobs) do
        local r = b.r
        local r2 = r * r
        local i0, i1 = max(0, floor_((b.x - r - x0) / c)), min(nx - 1, ceil_((b.x + r - x0) / c))
        local j0, j1 = max(0, floor_((b.y - r - y0) / c)), min(ny - 1, ceil_((b.y + r - y0) / c))
        for j = j0, j1 do
            local dy = y0 + j * c - b.y
            local dy2 = dy * dy
            if dy2 < r2 then
                local base = j * nx
                for i = i0, i1 do
                    local dx = x0 + i * c - b.x
                    local d2 = dx * dx + dy2
                    if d2 < r2 then
                        local q = 1.0 - d2 / r2
                        local k = q * q * q
                        local id = base + i
                        F[id] = (F[id] or 0.0) + k
                        W[id] = (W[id] or 0.0) + k
                        Z[id] = (Z[id] or 0.0) + k * b.z
                    end
                end
            end
        end
    end
    local ox, oy, oz = R.ox, R.oy, R.z0
    local lift = PD.lift
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local UP, WHITE_ = { X = 0.0, Y = 0.0, Z = 1.0 }, { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
    local function zof(id) local w = W[id]; if w and w > 0.0 then return Z[id] / w end; return nil end
    local function vert(gx, gy, z)
        local n = #verts
        local wx, wy = x0 + gx * c, y0 + gy * c
        verts[n + 1] = { X = wx - ox, Y = wy - oy, Z = (z or oz) + lift - oz }
        nrms[n + 1] = UP
        uvs[n + 1] = { X = wx * 0.01, Y = wy * 0.01 }
        cols[n + 1] = WHITE_
        return n
    end
    -- (a grid corner's point, made once)
    local CV = {}
    local function corner(id, gx, gy)
        local v = CV[id]
        if not v then v = vert(gx, gy, zof(id)); CV[id] = v end
        return v
    end
    -- (a point where the edge crosses between two corners, made once: key by the lower corner and the way)
    local EV = {}
    local two, flip = PD.two_sided, PD.flip
    local function tri(a, b, cc)
        local m = #idx
        if flip then b, cc = cc, b end
        idx[m + 1], idx[m + 2], idx[m + 3] = a, b, cc
        if two then idx[m + 4], idx[m + 5], idx[m + 6] = a, cc, b end
    end
    local CX, CY = { 0, 1, 1, 0 }, { 0, 0, 1, 1 }
    for j = 0, ny - 2 do
        local i = 0
        while i <= nx - 2 do
            local a, b = j * nx + i, j * nx + i + 1
            local d, e = (j + 1) * nx + i, (j + 1) * nx + i + 1
            local fa, fb, fd, fe = F[a] or 0.0, F[b] or 0.0, F[d] or 0.0, F[e] or 0.0
            if fa >= T and fb >= T and fd >= T and fe >= T then
                -- (a run of whole cells: one quad)
                local k = i + 1
                while k <= nx - 2 do
                    local b2, e2 = j * nx + k + 1, (j + 1) * nx + k + 1
                    if (F[b2] or 0.0) >= T and (F[e2] or 0.0) >= T then k = k + 1 else break end
                end
                local bb, ee = j * nx + k, (j + 1) * nx + k
                local v1 = corner(a, i, j)
                local v2 = corner(bb, k, j)
                local v3 = corner(ee, k, j + 1)
                local v4 = corner(d, i, j + 1)
                tri(v1, v2, v3); tri(v1, v3, v4)
                i = k
            else
                if fa >= T or fb >= T or fd >= T or fe >= T then
                    -- (a cell on the edge: its corners in the blood and the points between where the edge crosses)
                    local ids = { a, b, e, d }
                    local fs = { fa, fb, fe, fd }
                    local EK = { a * 2, b * 2 + 1, d * 2, a * 2 + 1 }   -- (the edges: bottom, right, top, left)
                    local poly = {}
                    for q = 1, 4 do
                        local r_ = (q % 4) + 1
                        local ga, gb = fs[q] >= T, fs[r_] >= T
                        if ga then poly[#poly + 1] = corner(ids[q], i + CX[q], j + CY[q]) end
                        if ga ~= gb then
                            local v = EV[EK[q]]
                            if not v then
                                local t = (T - fs[q]) / (fs[r_] - fs[q])
                                local za, zb = zof(ids[q]), zof(ids[r_])
                                local z = (za and zb) and (za + (zb - za) * t) or za or zb
                                v = vert(i + CX[q] + (CX[r_] - CX[q]) * t, j + CY[q] + (CY[r_] - CY[q]) * t, z)
                                EV[EK[q]] = v
                            end
                            poly[#poly + 1] = v
                        end
                    end
                    for q = 2, #poly - 1 do tri(poly[1], poly[q], poly[q + 1]) end
                end
                i = i + 1
            end
        end
    end
    if #idx == 0 then return end
    local mid = puddle_mid(world, P)
    local t1 = os.clock()
    pcall(create_section, R.pmc, 0, verts, idx, nrms, uvs, cols, false)
    P.send_ms = (os.clock() - t1) * 1000.0
    if mid then pcall(function() R.pmc:SetMaterial(0, mid) end) end
    P.built = (P.built or 0) + 1
    P.verts = #verts
end
local function puddles_tick(world, dt)
    local P = puddles
    if not (P and P.world == world:GetAddress()) then return end
    local PD = M.PUDDLE
    local now = os.clock()
    local k = min(1.0, dt / PD.spread)
    for _, R in ipairs(P.regions) do
        for _, b in ipairs(R.blobs) do
            if b.r1 - b.r > 0.05 then b.r = b.r + (b.r1 - b.r) * k * 2.0; R.dirty = true end
        end
    end
    -- (one rebuilt a frame, each at most every `rebuild` s)
    local n = #P.regions
    for _ = 1, n do
        if P.next > n then P.next = 1 end
        local R = P.regions[P.next]
        P.next = P.next + 1
        if R.dirty and now - R.t >= PD.rebuild then
            R.dirty, R.t = false, now
            local t0 = os.clock()
            local ok, err = pcall(puddle_build, world, P, R)
            local ms = (os.clock() - t0) * 1000.0
            if not ok then log("gore: a puddle failed (%s)", tostring(err))
            elseif (P.built or 0) <= 3 or ms > 8.0 then
                log("gore: puddle made (%d blobs, %d points, %.1f ms, %.1f of it handing it over)", #R.blobs, P.verts or 0, ms, P.send_ms or 0.0)
            end
            return
        end
    end
end
local function puddles_wipe()
    local P = puddles
    puddles = nil
    if not (P and P.world == here()) then return end
    for _, R in ipairs(P.regions) do destroy(R.actor) end
end

-- (where the drops went: a puddle, a splat, or nowhere - fallen out of the world)
M.BLOOD_STATS = { blob = 0, splat = 0, lost = 0 }
-- (a drop landing in blood already there: `n` small drops thrown up from it, `out` of the way sideways for each up, at
-- `speed` cm/s, `size` of a drop)
M.SPLASH = { n = { 2, 4 }, out = { 0.4, 1.1 }, speed = { 70.0, 150.0 }, size = 0.35 }
local function landed(world, d)
    local Pt = paint_of(world)
    if not Pt then return end
    local h = d.hit
    local g = M.BLOOD.gravity
    local nx, ny, nz = h[4], h[5], h[6]
    local vx, vy, vz = d.v0[1], d.v0[2], d.v0[3] - g * d.t_hit
    local vn = vx * nx + vy * ny + vz * nz
    local tx, ty, tz = vx - vn * nx, vy - vn * ny, vz - vn * nz       -- (its speed along the surface)
    local hs = sqrt(tx * tx + ty * ty + tz * tz)
    local kind = splat_kind(hs)
    local K = M.SPLATS[kind]
    local r = d.size * rnd(K.r[1], K.r[2])
    local DC = M.DECAL
    -- (every drop a splat, floor and wall alike - the puddles of their own put away: "bring back the old textures just
    -- remove the black outline on the edges of the blood", 2026-11-10)
    local S = M.BLOOD_STATS
    S.splat = S.splat + 1
    Pt.pending[#Pt.pending + 1] = { x = h[1], y = h[2], z = h[3], nx = nx, ny = ny, nz = nz, vx = tx, vy = ty, vz = tz, hs = hs,
        r = r, long = min(K.long, 1.0 + hs * K.stretch), kind = kind, at = K.at }
end
local function paint_flush(world, force)
    local Pt = paint
    if not (Pt and Pt.world == world:GetAddress()) or #Pt.pending == 0 then return end
    local DC = M.DECAL
    if not force and os.clock() - Pt.t < DC.every then return end
    Pt.t = os.clock()
    -- (BLOOD STAIN LIMIT at 0: no stains made at all - "oh and 0", 2026-11-11)
    local Mz = _G.ARMENU
    if Mz and Mz.blood_max and Mz.blood_max() <= 0 then Pt.pending = {}; return end
    local n = 0
    while #Pt.pending > 0 and n < DC.batch do
        n = n + 1
        local q = table.remove(Pt.pending, 1)
        local nrm = { q.nx, q.ny, q.nz }
        local u
        if q.hs > 20.0 and M.SPLATS[q.kind].dir then
            u = { q.vx / q.hs, q.vy / q.hs, (q.vz or 0.0) / q.hs }
            u = unit(sub(u, mul(nrm, dot(u, nrm))))
        else
            u = tangent(nrm, rnd(0.0, 2.0 * pi))
        end
        local a, b = q.r * q.long, q.r
        local c = { q.x + u[1] * a * q.at, q.y + u[2] * a * q.at, q.z + u[3] * a * q.at }
        local mid = decal_mid(world, string.format("gore_bdecal_splat_%02d", q.kind))
        if mid then
            -- (`splat_depth` deep each way: what is drawn can lie some cm off what the drop hit - gravel, a roof's covering -
            -- and a splat 3 cm deep missed it, "some drops dont connect to the floor", 2026-11-10)
            local dc = decal_spawn(world, mid, c, nrm, mul(u, DC.flip_u), a, b, DC.splat_depth + b * 0.3, 1)
            if dc then
                Pt.tail = Pt.tail + 1
                Pt.list[Pt.tail] = dc
                if q.nz > 0.75 then
                    Pt.spots[#Pt.spots + 1] = { c[1], c[2], c[3], max(a, b) }
                    if #Pt.spots > 500 then table.remove(Pt.spots, 1) end
                end
            end
        end
    end
    -- (how many: the RAGDOLL tab's BLOOD STAIN LIMIT)
    local Mn = _G.ARMENU
    local cap = (Mn and Mn.blood_max) and Mn.blood_max() or DC.max
    -- (a few hundred a frame at most: the limit lowered by tens of thousands, all at once, held a frame 2.2 s)
    local n_drop = 0
    -- (a queue: taken off its front by moving where it starts - table.remove from the front of 200 000 moved them all)
    while Pt.tail - Pt.head + 1 > cap and n_drop < 300 do
        decal_drop(Pt.list[Pt.head])
        Pt.list[Pt.head] = nil
        Pt.head = Pt.head + 1
        n_drop = n_drop + 1
    end
end
local function paint_wipe()
    local Pt = paint
    if not (Pt and Pt.world == here()) then return end
    for i = Pt.head, Pt.tail do decal_drop(Pt.list[i]) end
    Pt.list, Pt.head, Pt.tail, Pt.pending, Pt.spots = {}, 1, 0, {}, {}
    pcall(puddles_wipe)
end
-- the pool round his body: blood run out round where he lies (followed while he settles), blob after blob for `grow` s
-- once `start` s in - `every` s apart, each `r` cm, up to `reach` cm out (more with more of him cut off) - so it runs
-- together as the rest does
-- (off, `on`: the splats of the drops make the blood round him - a pool growing of its own was "just a texture growing")
M.BODY_POOL = { on = false, start = 0.3, grow = 7.0, every = 0.12, r = { 16.0, 30.0 }, reach = { 12.0, 55.0 }, follow = 2.0, bone = "spine_03" }
local function body_pool_tick(world, s, dt)
    local BP = M.BODY_POOL
    if not BP.on then return end
    if not s.torso or s.t < BP.start or s.t > BP.start + BP.grow then return end
    local bp = s.bpool
    if not bp then bp = { acc = 0.0 }; s.bpool = bp end
    if not bp.c or s.t < BP.follow then
        local okp, p = pcall(function() return s.torso.pose:GetSocketLocation(FName(BP.bone)) end)
        if okp and p then
            local fz = floor_normal(p.X, p.Y, p.Z + 20.0)
            if fz and p.Z - fz < 80.0 then bp.c = { p.X, p.Y, fz } end
        end
    end
    if not bp.c then return end
    bp.acc = bp.acc + dt
    while bp.acc >= BP.every do
        bp.acc = bp.acc - BP.every
        local k = min(1.0, (s.t - BP.start) / BP.grow) * min(1.0, 0.35 + 0.2 * s.n_cut)
        local reach = BP.reach[1] + (BP.reach[2] - BP.reach[1]) * k
        local a, d = rnd(0.0, 2.0 * pi), reach * sqrt(random())
        pcall(blob_add, world, bp.c[1] + math.cos(a) * d, bp.c[2] + math.sin(a) * d, bp.c[3], rnd(BP.r[1], BP.r[2]))
    end
end
M.DROP_LOOK = { size = 0.8, stretch = 1.0 / 200.0, stretch_max = 3.4, thin = 0.62 }
local function drops_tick(world, dt)
    local D = drops
    if not (D and D.world == world:GetAddress()) then return end
    budget = M.TRACE_BUDGET
    local HF = M._onhim
    local Pb, pawn_b = nil, nil
    local checked = false
    for _, d in ipairs(D.list) do
        if d.on then
            d.t = d.t + dt
            if not d.hit then predict_some(d) end
            -- (him in its way first: it stops on him - see "drops landing on him")
            local on_body = false
            if HF and M.ONHIM.on and d.t > M.ONHIM.after and not (d.hit and d.t >= d.t_hit) then
                if not checked then
                    checked = true
                    pawn_b = lib.pawn()
                    if pawn_b then local okb, P_ = pcall(HF.body_now, pawn_b); Pb = okb and P_ or nil end
                end
                if Pb then
                    local okh, part, ht, hp, ha, hb = pcall(HF.hit_him, Pb, arc_at(d, max(0.0, d.t - dt)), arc_at(d, d.t))
                    if okh and part then
                        on_body = true
                        d.on = false
                        pcall(function() d.actor:SetActorHiddenInGame(true) end)
                        pcall(HF.on_him, world, pawn_b, Pb, part, ht, hp, ha, hb)
                    end
                end
            end
            if on_body then
                -- (stopped on him)
            elseif d.hit and d.t >= d.t_hit then
                d.on = false
                pcall(function() d.actor:SetActorHiddenInGame(true) end)
                pcall(landed, world, d)
            elseif d.t > M.DROP_MAX_T then
                d.on = false
                M.BLOOD_STATS.lost = M.BLOOD_STATS.lost + 1
                pcall(function() d.actor:SetActorHiddenInGame(true) end)
            else
                -- (turned the way it flies, drawn out by its speed - a drop in flight, not a ball: "we gotta upgrade the
                -- blood drops, right now they're just balls", 2026-11-10)
                local DL = M.DROP_LOOK
                local vx, vy, vz = d.v0[1], d.v0[2], d.v0[3] - M.BLOOD.gravity * d.t
                local hv = sqrt(vx * vx + vy * vy)
                local sp = sqrt(hv * hv + vz * vz)
                local k = d.size * DL.size
                local sx = k * min(DL.stretch_max, 1.0 + sp * DL.stretch)
                pcall(function()
                    d.actor:K2_SetActorLocationAndRotation(V(arc_at(d, d.t)),
                        { Pitch = math.deg(math.atan(vz, hv)), Yaw = math.deg(math.atan(vy, vx)), Roll = d.roll or 0.0 }, false, {}, true)
                    if not d.sx or abs(sx - d.sx) > 0.06 * sx then d.sx = sx; d.actor:SetActorScale3D({ X = sx, Y = k * DL.thin, Z = k * DL.thin }) end
                end)
            end
        end
    end
end

-- ------------------------------------------------------------ open fractures
-- ("on broken limb make them randomly bleed and have bone sticking out", 2026-11-10.) A broken long bone torn through the
-- skin: a jagged shard of bone - a mesh of the mod's own, ivory, lit - out of the limb at a random place along it, leaning
-- out at a random way, a wound at its foot; and from the wound, blood: a trickle, and spurts at no set beat. Riding his
-- body's bone, so it moves with the limb; gone when he is healed, or with the part if it is torn off.
-- (sized to be seen from STORROR's camera: at 2.3 cm across and 5 cm out it was a pixel or two - "I dont see no bone")
M.FRACTURE = { radius = 2.1, len = { 13.0, 18.0 }, color = { R = 0.93, G = 0.90, B = 0.80, A = 1.0 }, rough = 0.5, lean = 0.3, out = 4.0,
               trickle = { 2.0, 6.0 }, burst = { 3, 8 }, burst_every = { 0.5, 2.2 }, burst_speed = { 90.0, 220.0 },
               trickle_speed = { 25.0, 70.0 }, wound = 3.6,
               life = 30.0 }   -- (s a broken bone's wound bleeds: "broken bleeds last only 30 seconds", 2026-11-10)
local fracs = { world = nil, list = {} }
local LIT = "/InterchangeAssets/gltf/M_Default.M_Default"
local bone_mid = nil
local function bone_material(world)
    local ok, yes = pcall(same, bone_mid)
    if ok and yes then return bone_mid.obj end
    local parent = StaticFindObject(LIT)
    if not (parent and parent:IsValid()) then pcall(function() parent = LoadAsset(LIT) end) end
    if not (parent and parent:IsValid()) then return nil end
    mid_n = mid_n + 1
    local mid = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(world, parent,
        FName(string.format("ARBone_%d_%d", os.time(), mid_n)), 0)
    if not (mid and mid:IsValid()) then return nil end
    pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), M.FRACTURE.color) end)
    pcall(function() mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("RoughnessFactor"), M.FRACTURE.rough) end)
    bone_mid = { obj = mid, name = mid:GetFName():ToString() }
    return mid
end
-- (the shard: seven sides, its root inside the limb, its broken end ragged, a splintered point; both faces of every
-- triangle, so it shows from any side)
local function shard_mesh(len, r)
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local n = 7
    for i = 0, n - 1 do
        local a = i / n * 2.0 * pi
        verts[#verts + 1] = { X = math.cos(a) * r, Y = math.sin(a) * r, Z = -3.0 }
        nrms[#nrms + 1] = { X = math.cos(a), Y = math.sin(a), Z = 0.0 }
    end
    for i = 0, n - 1 do
        local a = i / n * 2.0 * pi
        local rr = r * rnd(0.6, 0.95)
        verts[#verts + 1] = { X = math.cos(a) * rr, Y = math.sin(a) * rr, Z = len + rnd(-1.8, 1.0) }
        nrms[#nrms + 1] = { X = math.cos(a), Y = math.sin(a), Z = 0.3 }
    end
    verts[#verts + 1] = { X = rnd(-0.4, 0.4) * r, Y = rnd(-0.4, 0.4) * r, Z = len + rnd(0.5, 1.8) }
    nrms[#nrms + 1] = { X = 0.0, Y = 0.0, Z = 1.0 }
    for i = 1, #verts do uvs[i] = { X = 0.0, Y = 0.0 }; cols[i] = WHITE end
    local function tri(a, b, c)
        local m = #idx
        idx[m + 1], idx[m + 2], idx[m + 3] = a, b, c
        idx[m + 4], idx[m + 5], idx[m + 6] = a, c, b
    end
    for i = 0, n - 1 do
        local a, b = i, (i + 1) % n
        tri(a, b, n + b)
        tri(a, n + b, n + a)
        tri(n + a, n + b, 2 * n)
    end
    return verts, idx, nrms, uvs, cols
end
local function frac_list(world)
    local w = world:GetAddress()
    if fracs.world ~= w then fracs = { world = w, list = {} } end
    return fracs.list
end
-- an open fracture on `region` (its bone `bone`, running to `tip`); `show`: the bone out, or only the wound
function M.fracture(pawn, region, bone, tip, show)
    local world = lib.world()
    pawn = pawn or lib.pawn()
    if not (world and pawn) then return false end
    local mesh = pawn.Mesh
    local F = M.FRACTURE
    for _, f in ipairs(frac_list(world)) do if f.region == region then return false end end
    local p0, p1 = at(mesh, bone), at(mesh, tip)
    local axis = unit(sub(p1, p0))
    local base = add(p0, mul(sub(p1, p0), rnd(0.35, 0.65)))
    local rv = { rnd(-1, 1), rnd(-1, 1), rnd(-1, 1) }
    local k = rv[1] * axis[1] + rv[2] * axis[2] + rv[3] * axis[3]
    local perp = unit(sub(rv, mul(axis, k)))
    local dir = unit(add(perp, mul(axis, rnd(-F.lean, F.lean))))
    local bt = mesh:GetSocketTransform(FName(bone), 0)
    local lb = KML():InverseTransformLocation(bt, V(add(base, mul(perp, F.out))))
    local ld = KML():InverseTransformDirection(bt, V(dir))
    local rot = KML():MakeRotFromZ(ld)
    local a = spawn_actor(world, V(base), 0.0)
    if not a then return false end
    pcall(function() a:SetActorEnableCollision(false) end)
    local f = { actor = a, region = region, bone = bone, tip = tip, next = os.clock() + rnd(0.1, 0.5), acc = 0.0, trickle = rnd(F.trickle[1], F.trickle[2]),
                t0 = os.clock() }
    local function place(c)
        pcall(function() c:SetCollisionEnabled(0) end)
        c:K2_AttachToComponent(mesh, FName(bone), 2, 2, 2, false)
        c:K2_SetRelativeLocationAndRotation(lb, rot, false, {}, true)
    end
    if show then
        local pmc = add_pmc(a)
        if pmc then
            local v, i, n, u, c = shard_mesh(rnd(F.len[1], F.len[2]), F.radius)
            create_section(pmc, 0, v, i, n, u, c, false)
            local m = bone_material(world)
            if m then pcall(function() pmc:SetMaterial(0, m) end) end
            pcall(function() pmc:SetCastShadow(true) end)
            place(pmc)
            f.shard = pmc
        end
    end
    local w = add_pmc(a)
    if w then
        section(world, w, F.wound, false, "gore_blood_cut")
        place(w)
        f.wound = w
    end
    table.insert(frac_list(world), f)
    log("gore: open fracture of the %s%s", region, show and ", the bone out" or "")
    return true
end
-- (taken away: all of them, or those of the parts in `regions`)
function M.fractures_clear(regions)
    local keep = {}
    local only = nil
    if regions then only = {}; for _, rg in ipairs(regions) do only[rg] = true end end
    for _, f in ipairs(fracs.list) do
        if not only or only[f.region] then
            pcall(function() f.actor:SetActorHiddenInGame(true) end)
            for _, c in ipairs({ f.shard, f.wound }) do
                if c then pcall(function() c:K2_DetachFromComponent(1, 1, 1) end) end
            end
            destroy(f.actor)
        else
            keep[#keep + 1] = f
        end
    end
    fracs.list = keep
end
local function fractures_tick(world)
    if fracs.world ~= world:GetAddress() or #fracs.list == 0 then return end
    local F = M.FRACTURE
    local now = os.clock()
    for _, f in ipairs(fracs.list) do
        local w = f.wound
        if w and (now - (f.t0 or now) < F.life or (_G.ARMENU and _G.ARMENU.bleed_forever and _G.ARMENU.bleed_forever())) then
            local ok, p, u = pcall(function() return w:K2_GetComponentLocation(), w:GetUpVector() end)
            if ok and p and u then
                local pos, dir = { p.X, p.Y, p.Z }, unit({ u.X, u.Y, u.Z })
                local pw = lib.pawn()
                local iv = pw and vel_of(pw.Mesh, FName(f.bone)) or nil
                local dt = min(0.1, now - (f.last or now))
                f.last = now
                if now >= f.next then
                    f.next = now + rnd(F.burst_every[1], F.burst_every[2])
                    for _ = 1, math.random(F.burst[1], F.burst[2]) do bled(1, f.region); emit(world, f, pos, dir, rnd(F.burst_speed[1], F.burst_speed[2]), nil, iv) end
                end
                f.acc = f.acc + f.trickle * dt
                while f.acc >= 1.0 do
                    f.acc = f.acc - 1.0
                    bled(1, f.region)
                    emit(world, f, pos, dir, rnd(F.trickle_speed[1], F.trickle_speed[2]), nil, iv)
                end
            end
        end
    end
end

-- blood from another player's figure (armp.lua: a stump of theirs, in multiplayer) - `n` drops at `pos` going `dir`
local PUPPET_E = {}
function M.puppet_bleed(pos, dir, n, speed)
    local world = lib.world()
    if not world then return end
    for _ = 1, n or 1 do pcall(emit, world, PUPPET_E, pos, dir, (speed or M.BLOOD.speed[1]) * rnd(0.5, 1.0)) end
end

-- ------------------------------------------------------------ a part off him
function M.active() return st ~= nil end
function M.gone(id) return st ~= nil and st.pieces[id] ~= nil end
-- (the parts torn off him, by id - each its copy of him, `pose`: the x-ray's bones go with them, xray.lua)
function M.pieces() return st and st.pieces or nil end

-- tear off the part for `region` (the damage figure's part): the regions it took with it, or nil. opts: fling (how hard
-- it is thrown, x), burst (how much blood at once, x)
function M.sever(pawn, region, opts)
    opts = opts or {}
    local P = BY_REGION[region]
    if not P then return nil end
    local world = lib.world()
    pawn = pawn or lib.pawn()
    if not (world and pawn) then return nil end
    local body = pawn.Mesh
    if not (body and body:IsValid()) then return nil end
    -- (already off, or inside a part that is)
    if st and st.pieces[P.id] then return nil end
    for _, outer in ipairs(OUTER[P.id] or {}) do if st and st.pieces[outer] then return nil end end
    -- (the copies ready - any not made yet made now)
    if prep and prep.world == world:GetAddress() and prep.pawn == pawn:GetAddress() and prep.sig ~= sig_of(pawn) then prep_drop() end
    while prep_step(world, pawn) do end
    local part = prep.parts[P.i]
    if not (part and part.ready) then return nil end
    -- (the drops fall as everything there does: STORROR's gravity)
    pcall(function()
        local A = _G.AR
        if A and A.GRAV then M.BLOOD.gravity = A.GRAV.g; return end
        local gz = pawn.CharacterMovement:GetGravityZ(); if gz < -1.0 then M.BLOOD.gravity = -gz end
    end)
    local t0 = os.clock()
    -- the first part off him: his body as its copy from now on; the blood from before wiped
    if not st then
        -- (the blood from before kept: wiped here, it went whenever a part came off after he was healed - "blood splats
        -- despawning", 2026-11-10)
        if not (prep.torso and prep.torso.ready) then return nil end
        local okt, errt = pcall(fire_torso, pawn, body, prep.torso, { Head = true })
        if not okt then log("gore: his body copy failed: %s", tostring(errt)); reset_torso(prep.torso, body); return nil end
        st = { world = world:GetAddress(), pawn = pawn:GetAddress(), body = body, torso = prep.torso, pieces = {}, emitters = {},
               t = 0.0, n_cut = 0, cost = { n = 0, sum = 0.0, top = 0.0 } }
    end
    local s = st
    local base_v = { 0.0, 0.0, 0.0 }
    pcall(function() local v = body:GetPhysicsLinearVelocity(FName(P.root)); base_v = { v.X, v.Y, v.Z } end)
    local chest = at(body, "spine_03")
    local ok, err = pcall(fire_part, world, pawn, body, part, base_v, chest, s.pieces, opts.fling)
    if not ok then log("gore: the %s did not come off: %s", P.id, tostring(err)); reset_part(part); return nil end
    s.pieces[P.id] = part
    s.n_cut = s.n_cut + 1
    -- (parts inside it that were already off: their blood stops there - they are part of this one's cut now)
    -- his body's stump
    table.insert(s.torso.cuts, FName(P.root))
    pcall(s.torso.posed)
    if P.face then
        pcall(own_head_off, s, pawn, body, part)
        pcall(carry, s, part.pose)
        -- (his face mesh led by the body copy no more: it is hidden, its hair on the flying head)
    end
    -- (the stumps of parts inside it, off before, now inside its cut: they bleed from it, not of their own)
    if P.inside then
        local inner = {}
        for _, id in ipairs(P.inside) do inner[id] = true end
        local keep = {}
        for _, e in ipairs(s.emitters) do if not (e.stump and inner[e.id]) then keep[#keep + 1] = e end end
        s.emitters = keep
    end
    local S = P.stump
    local bk = opts.burst or 1.0
    s.emitters[#s.emitters + 1] = { stump = true, id = P.id, region = P.region, pose = s.torso.pose, at = FName(S.at), from = FName(S.from), acc = 0.0,
                                    burst = math.floor(M.BLOOD.burst * bk), t0 = s.t }
    for _, E in ipairs(part.ends) do
        s.emitters[#s.emitters + 1] = { part = part, at = FName(E.bone), dl = E.dl, acc = 0.0, burst = math.floor(M.BLOOD.burst / 2 * bk), t0 = s.t }
    end
    pcall(M.fractures_clear, M.regions_of(P.id))
    log("gore: the %s torn off (%.0f ms)", P.id, (os.clock() - t0) * 1000.0)
    return M.regions_of(P.id)
end

-- put back as he gets up: his body and clothes his own again, the parts gone, the drops in the air taken away (the blood
-- on the ground stays till the next time)
function M.clear()
    pcall(body_clear)
    pcall(stain_clear)
    local s = st
    st = nil
    local w = here()
    if s and s.world == w then
        pcall(own_head_back, s)
        pcall(carry, s, nil)
        if s.torso then reset_torso(s.torso, s.body) end
        for _, part in pairs(s.pieces) do reset_part(part) end
        local c = s.cost
        log("gore: put back (its frames: %.1f ms on average, %.1f at most, over %d)", c.n > 0 and c.sum / c.n or 0.0, c.top, c.n)
    end
    if drops and drops.world == w then
        for _, d in ipairs(drops.list) do if d.on then d.on = false; pcall(function() d.actor:SetActorHiddenInGame(true) end) end end
    end
end

-- ------------------------------------------------------------ blood on him
-- ("I want blood to get on the player", 2026-11-10.) Splats on his body - decals pinned to his bones, so they go where he
-- goes and stay on him - round each cut he bleeds from (its stump) and each open fracture, then running on from there,
-- down the limb toward its lower end, a little further every `run_every` s (`run_max` to a wound); and, lying in blood on
-- the floor or standing in it, a smear on that part of him from underneath (`smear_every` s apart, `smear_max` all told).
-- Each as deep as the limb is thick, so it wraps round it. On him till he is healed (with the rest of the gore).
-- (as patches - see below - not decals: decals on him need him to take decals, and then every decal of the world's -
-- drains, gravel, rubbish - showed on him too, "other things are portraying onto the charater", 2026-11-10. He takes
-- none, as STORROR has him.)
M.BODY_BLOOD = { on = true, run_every = 1.1, run_max = 6, run_step = 0.14, size = { 4.5, 7.5 }, run_size = { 3.0, 5.0 },
                 smear_every = 0.5, smear_max = 30, smear_per_bone = 4, lie_gap = 6.0, max = 90 }
local LIMB_R = { pelvis = 13.0, spine_03 = 13.0, spine_05 = 12.0, head = 10.0, neck_01 = 6.0, clavicle_l = 6.0, clavicle_r = 6.0,
                 upperarm_l = 5.5, upperarm_r = 5.5, lowerarm_l = 4.5, lowerarm_r = 4.5, hand_l = 3.5, hand_r = 3.5,
                 thigh_l = 8.5, thigh_r = 8.5, calf_l = 6.5, calf_r = 6.5, foot_l = 5.0, foot_r = 5.0 }
local SMEAR_BONES = { "pelvis", "spine_03", "spine_05", "head", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
                      "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }
local body = nil      -- { pawn, list = { comps }, wounds = { [key] = w }, smears = { [bone] = n }, n_smear, smear_t }
local function body_of(pawn)
    local pa = pawn:GetAddress()
    if body and body.pawn == pa then return body end
    body = { pawn = pa, list = {}, wounds = {}, smears = {}, n_smear = 0, smear_t = 0.0 }
    return body
end
-- a splat on his `bone`: its middle `c` (world), pressed along `x` (world), `sy` cm along `u`, `sz` across, `depth` deep
local function body_splat(world, pawn, B, bone, c, x, u, sy, sz, depth, kind)
    if #B.list >= M.BODY_BLOOD.max then return nil end
    local mid = decal_mid(world, string.format("gore_bdecal_splat_%02d", kind))
    if not mid then return nil end
    local ok, d = pcall(function()
        local rot = KML():MakeRotFromXY(V(x), V(u))
        return GS():SpawnDecalAttached(mid, { X = depth, Y = sy, Z = sz }, pawn.Mesh, FName(bone), V(c), rot, 1, 0.0)
    end)
    if not (ok and d and d:IsValid()) then return nil end
    pcall(function() d:SetSortOrder(2) end)
    pcall(function() d:SetFadeScreenSize(0.0) end)
    B.list[#B.list + 1] = d
    return d
end
-- a way square to `a`
local function square_to(a)
    local ref = (abs(a[3]) < 0.9) and { 0.0, 0.0, 1.0 } or { 1.0, 0.0, 0.0 }
    return unit(cross(a, ref))
end
-- the wounds he bleeds from now: { key, bone (the limb it is on), from, to (that limb's ends, world), at (0..1 along it) }
local function wounds_now(pawn, mesh)
    local out = {}
    local s = st
    if s and s.pieces then
        for id, part in pairs(s.pieces) do
            local S = part.P.stump
            if S then
                local ok, a, b = pcall(function() return at(mesh, S.from), at(mesh, S.at) end)
                if ok then out[#out + 1] = { key = "cut:" .. id, bone = S.from, from = a, to = b, at = 0.92, r = S.w or 6.0 } end
            end
        end
    end
    for _, f in ipairs(fracs.list or {}) do
        if f.wound and f.tip then
            local ok, a, b, w = pcall(function()
                local p = f.wound:K2_GetComponentLocation()
                return at(mesh, f.bone), at(mesh, f.tip), { p.X, p.Y, p.Z }
            end)
            if ok then
                local d = sub(b, a)
                local L2 = d[1] * d[1] + d[2] * d[2] + d[3] * d[3]
                local t = L2 > 1.0 and max(0.05, min(0.95, ((w[1] - a[1]) * d[1] + (w[2] - a[2]) * d[2] + (w[3] - a[3]) * d[3]) / L2)) or 0.5
                out[#out + 1] = { key = "frac:" .. f.region, bone = f.bone, from = a, to = b, at = t, r = LIMB_R[f.bone] or 6.0 }
            end
        end
    end
    return out
end
-- ------------------------------------------------------------ blood on him: patches
-- (the other half of "Both", 2026-11-10: blood on his shirt and skin, which no colour of theirs can stain - the shirt's
-- tint is its print's.) A patch is a piece of a tube round one of his limbs (or his trunk, his head) - `r` cm out from its
-- bone, a little over its surface - cut to a splat of blood, pinned to that bone: round each wound, running down the limb
-- from it, and on the side of him lying in blood. One mesh a bone, all of its patches in it, made again as one is added.
-- (Parts torn off are left out. Taken off as he is healed.)
-- (off: patches stood off his clothes, "bloodstains on body are all wrong should actually be on the shirt", 2026-11-10 -
-- the blood goes into his clothes' own pictures instead)
M.PATCH = { on = false, lift = 0.35, around = 9, along = 4, max_bone = 8 }
local PATCH_R = { pelvis = 15.5, spine_03 = 15.0, spine_05 = 14.5, neck_01 = 6.0, head = 9.5,
                  clavicle_l = 7.0, clavicle_r = 7.0, upperarm_l = 6.8, upperarm_r = 6.8, lowerarm_l = 4.2, lowerarm_r = 4.2,
                  hand_l = 3.0, hand_r = 3.0, thigh_l = 9.5, thigh_r = 9.5, calf_l = 7.5, calf_r = 7.5, foot_l = 5.5, foot_r = 5.5 }
local PATCH_CHILD = { pelvis = "spine_02", spine_03 = "spine_04", spine_05 = "neck_01", neck_01 = "head", head = "head",
                      clavicle_l = "upperarm_l", clavicle_r = "upperarm_r", upperarm_l = "lowerarm_l", upperarm_r = "lowerarm_r",
                      lowerarm_l = "hand_l", lowerarm_r = "hand_r", hand_l = "middle_01_l", hand_r = "middle_01_r",
                      thigh_l = "calf_l", thigh_r = "calf_r", calf_l = "foot_l", calf_r = "foot_r", foot_l = "ball_l", foot_r = "ball_r" }
local patches = nil   -- { pawn, actor, bones = { [bone] = { pmc, list = { patch } } } }
local function patches_of(world, pawn)
    local pa = pawn:GetAddress()
    if patches and patches.pawn == pa and patches.world == world:GetAddress() then return patches end
    local a = spawn_actor(world, pawn:K2_GetActorLocation(), 0.0)
    if not a then return nil end
    pcall(function() a:SetActorEnableCollision(false) end)
    patches = { pawn = pa, world = world:GetAddress(), actor = a, bones = {} }
    return patches
end
-- a bone's frame: where its child is (along it), and two ways square to that - all in the bone's own space
local function bone_frame(mesh, bone)
    local T = mesh:GetSocketTransform(FName(bone), 0)
    local child = PATCH_CHILD[bone] or bone
    local cp = mesh:GetSocketLocation(FName(child))
    local lc = KML():InverseTransformLocation(T, cp)
    local ax = { lc.X, lc.Y, lc.Z }
    local L = len(ax)
    if L < 1.0 then ax, L = { 1.0, 0.0, 0.0 }, 10.0 else ax = mul(ax, 1.0 / L) end
    local e1 = square_to(ax)
    local e2 = cross(ax, e1)
    return T, ax, e1, e2, L
end
-- a world way as an angle round the bone (0 along e1)
local function angle_of(T, ax, e1, e2, wdir)
    local d = KML():InverseTransformDirection(T, V(wdir))
    local v = { d.X, d.Y, d.Z }
    return math.atan(v[1] * e2[1] + v[2] * e2[2] + v[3] * e2[3], v[1] * e1[1] + v[2] * e1[2] + v[3] * e1[3])
end
-- (the splat sheet's shapes as grids - Scripts/gore_masks.lua, by tools/splat_masks.py - a patch's mesh cut to its splat:
-- the lit material cuts no picture out, and drawn unlit, through the see-through widget material, the blood on him was
-- flat, "blood stains on charater are flat", 2026-11-10. Lit and wet now, as the blood is, its shape its mesh's own.)
local MASKS = nil
local function masks()
    if MASKS == nil then
        local f = loadfile(lib.MOD_DIR .. "Scripts\\gore_masks.lua")
        local ok, t = false, nil
        if f then ok, t = pcall(f) end
        MASKS = (ok and type(t) == "table") and t or false
    end
    return MASKS or nil
end
local function mask_at(m, u, v)
    local N = #m
    local x, y = u * (N - 1), v * (N - 1)
    local i0, j0 = math.floor(x), math.floor(y)
    local i1, j1 = min(N - 1, i0 + 1), min(N - 1, j0 + 1)
    local fx, fy = x - i0, y - j0
    local r0, r1 = m[j0 + 1], m[j1 + 1]
    local a = r0[i0 + 1] + (r0[i1 + 1] - r0[i0 + 1]) * fx
    local b = r1[i0 + 1] + (r1[i1 + 1] - r1[i0 + 1]) * fx
    return a + (b - a) * fy
end
M.PATCH_LOOK = { color = { R = 0.085, G = 0.0015, B = 0.0022, A = 1.0 }, rough = 0.22, grid_u = 14, grid_v = 12, edge = 0.5 }
local patch_mid_e = nil
local function patch_mid(world)
    local ok, yes = pcall(same, patch_mid_e)
    if ok and yes then return patch_mid_e.obj end
    local parent = load_mat("/InterchangeAssets/gltf/M_Default.M_Default")
    if not parent then return nil end
    mid_n = mid_n + 1
    local mid = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(world, parent,
        FName(string.format("ARBloodOn_%d_%d", os.time(), mid_n)), 0)
    if not (mid and mid:IsValid()) then return nil end
    local L = M.PATCH_LOOK
    pcall(function() mid:SetVectorParameterValue(FName("BaseColorFactor"), L.color) end)
    pcall(function() mid:SetScalarParameterValue(FName("MetallicFactor"), 0.0) end)
    pcall(function() mid:SetScalarParameterValue(FName("RoughnessFactor"), L.rough) end)
    patch_mid_e = { obj = mid, name = mid:GetFName():ToString() }
    return mid
end
local function patch_build(world, P, bone)
    local Bp = P.bones[bone]
    if not Bp or not Bp.pmc then return end
    local PA, L = M.PATCH, M.PATCH_LOOK
    local MS = masks()
    local verts, idx, nrms, uvs, cols = {}, {}, {}, {}, {}
    local W = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
    local NU, NV, T = L.grid_u, L.grid_v, L.edge
    for _, p in ipairs(Bp.list) do
        local m = MS and MS[p.kind]
        -- (a point of the patch, at grid place gu, gv - fractions allowed)
        local function pt(gu, gv)
            local th = p.th - p.dth + 2.0 * p.dth * gu / (NU - 1)
            local t = p.t0 + (p.t1 - p.t0) * gv / (NV - 1)
            local cs, sn = math.cos(th), math.sin(th)
            local out = { p.e1[1] * cs + p.e2[1] * sn, p.e1[2] * cs + p.e2[2] * sn, p.e1[3] * cs + p.e2[3] * sn }
            local q = add(mul(p.ax, t), mul(out, p.r + PA.lift))
            local k = #verts + 1
            verts[k] = { X = q[1], Y = q[2], Z = q[3] }
            nrms[k] = { X = out[1], Y = out[2], Z = out[3] }
            uvs[k] = { X = gu / (NU - 1), Y = gv / (NV - 1) }
            cols[k] = W
            return k - 1
        end
        local F = {}
        for j = 0, NV - 1 do
            F[j] = {}
            for i = 0, NU - 1 do F[j][i] = m and mask_at(m, i / (NU - 1), j / (NV - 1)) or 1.0 end
        end
        local CX, CY = { 0, 1, 1, 0 }, { 0, 0, 1, 1 }
        for j = 0, NV - 2 do
            for i = 0, NU - 2 do
                local fs = { F[j][i], F[j][i + 1], F[j + 1][i + 1], F[j + 1][i] }
                if fs[1] >= T or fs[2] >= T or fs[3] >= T or fs[4] >= T then
                    local poly = {}
                    for q = 1, 4 do
                        local r_ = (q % 4) + 1
                        local ga, gb = fs[q] >= T, fs[r_] >= T
                        if ga then poly[#poly + 1] = pt(i + CX[q], j + CY[q]) end
                        if ga ~= gb then
                            local tt = (T - fs[q]) / (fs[r_] - fs[q])
                            poly[#poly + 1] = pt(i + CX[q] + (CX[r_] - CX[q]) * tt, j + CY[q] + (CY[r_] - CY[q]) * tt)
                        end
                    end
                    for q = 2, #poly - 1 do
                        local mm = #idx
                        idx[mm + 1], idx[mm + 2], idx[mm + 3] = poly[1], poly[q], poly[q + 1]
                        idx[mm + 4], idx[mm + 5], idx[mm + 6] = poly[1], poly[q + 1], poly[q]
                    end
                end
            end
        end
    end
    if #idx == 0 then return end
    pcall(create_section, Bp.pmc, 0, verts, idx, nrms, uvs, cols, false)
    local mid = patch_mid(world)
    if mid then pcall(function() Bp.pmc:SetMaterial(0, mid) end) end
end
-- a patch on `bone`: centred `tc` of the way along it, round angle `th` (`dth` each way; math.pi: all round), `h` cm long,
-- the sheet's splat `kind`
local function patch_add(world, pawn, bone, tc, th, dth, h, kind)
    local PA = M.PATCH
    if not PA.on or not PATCH_R[bone] then return false end
    local P = patches_of(world, pawn)
    if not P then return false end
    local mesh = pawn.Mesh
    local Bp = P.bones[bone]
    if not Bp then
        local ok, pmc = pcall(function()
            local c = P.actor:AddComponentByClass(StaticFindObject("/Script/ProceduralMeshComponent.ProceduralMeshComponent"), true, IDENT, false)
            c:SetCollisionEnabled(0)
            c:SetCastShadow(false)
            c:SetReceivesDecals(false)
            c:K2_AttachToComponent(mesh, FName(bone), 2, 2, 2, false)
            return c
        end)
        if not (ok and pmc) then return false end
        Bp = { pmc = pmc, list = {} }
        P.bones[bone] = Bp
    end
    if #Bp.list >= PA.max_bone then return false end
    local okf, T, ax, e1, e2, L = pcall(bone_frame, mesh, bone)
    if not okf then return false end
    local gx, gy = M.SPLAT_GRID and M.SPLAT_GRID[1] or 4, M.SPLAT_GRID and M.SPLAT_GRID[2] or 8
    local col, row = (kind - 1) % gx, math.floor((kind - 1) / gx)
    local tcm = tc * L
    Bp.list[#Bp.list + 1] = { ax = ax, e1 = e1, e2 = e2, r = PATCH_R[bone], th = th, dth = dth,
        t0 = tcm - h * 0.5, t1 = tcm + h * 0.5, kind = kind }
    patch_build(world, P, bone)
    return true
end
-- a patch whose round middle faces world way `wdir`
local function patch_toward(world, pawn, bone, tc, wdir, size, kind)
    local okf, T, ax, e1, e2, L = pcall(bone_frame, pawn.Mesh, bone)
    if not okf then return false end
    local th = angle_of(T, ax, e1, e2, wdir)
    local r = PATCH_R[bone] or 6.0
    return patch_add(world, pawn, bone, tc, th, min(math.pi, (size * 0.5) / r), size, kind)
end
local function patches_clear()
    local P = patches
    patches = nil
    if not P then return end
    for _, Bp in pairs(P.bones) do pcall(function() Bp.pmc:K2_DetachFromComponent(1, 1, 1) end) end
    destroy(P.actor)
end
M.patches_clear = patches_clear

local function body_tick(world, dt)
    local BB = M.BODY_BLOOD
    if not BB.on then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local mesh = pawn.Mesh
    local B = body_of(pawn)
    local now = os.clock()
    -- round each wound, and running on from it
    for _, w in ipairs(wounds_now(pawn, mesh)) do
        local W = B.wounds[w.key]
        local axis = unit(sub(w.to, w.from))
        local r = LIMB_R[w.bone] or w.r
        if not W then
            W = { n = 0, t = now, at = w.at }
            B.wounds[w.key] = W
            local c = add(w.from, mul(sub(w.to, w.from), w.at))
            local sz = rnd(BB.size[1], BB.size[2])
            patch_add(world, pawn, w.bone, w.at, 0.0, math.pi, sz * 1.3, math.random(1, 2))
        elseif W.n < BB.run_max and now - W.t > BB.run_every then
            W.t = now
            -- (down the limb: toward whichever of its ends is lower now)
            local dir = (w.from[3] < w.to[3]) and -1.0 or 1.0
            local na = W.at + dir * BB.run_step * rnd(0.6, 1.2)
            if na > 0.04 and na < 0.98 then
                W.at, W.n = na, W.n + 1
                local c = add(w.from, mul(sub(w.to, w.from), na))
                local sz = rnd(BB.run_size[1], BB.run_size[2])
                patch_toward(world, pawn, w.bone, na, { 0.0, 0.0, -1.0 }, sz * 1.6, STREAKS[math.random(#STREAKS)])
            else
                W.n = BB.run_max
            end
        end
    end
    -- lying (or standing) in blood: a smear on the part of him that is in it (not on parts of him torn off)
    local gone = {}
    if st and st.pieces then for id in pairs(st.pieces) do for _, rg in ipairs(M.regions_of(id)) do gone[rg] = true end end end
    local Pt = paint
    if not (Pt and Pt.spots and #Pt.spots > 0) or B.n_smear >= BB.smear_max or now - B.smear_t < BB.smear_every then return end
    B.smear_t = now
    for _, bn in ipairs(SMEAR_BONES) do
        if (B.smears[bn] or 0) < BB.smear_per_bone and not gone[bn] then
            local okp, p = pcall(function() return at(mesh, bn) end)
            if okp and p then
                local r = LIMB_R[bn] or 6.0
                for _, sp in ipairs(Pt.spots) do
                    local dx, dy, dz = p[1] - sp[1], p[2] - sp[2], p[3] - sp[3]
                    if dz > -r and dz < r + BB.lie_gap and dx * dx + dy * dy < (sp[4] + r * 0.5) ^ 2 then
                        B.smears[bn] = (B.smears[bn] or 0) + 1
                        B.n_smear = B.n_smear + 1
                        local sz = r * rnd(1.0, 1.6)
                        patch_toward(world, pawn, bn, 0.5, { 0.0, 0.0, -1.0 }, sz * 1.5, math.random(1, 2))
                        break
                    end
                end
            end
        end
    end
end
local function body_clear()
    pcall(patches_clear)
    local B = body
    body = nil
    if not B then return end
    for _, d in ipairs(B.list) do decal_drop(d) end
end
M.body_clear = body_clear

-- ------------------------------------------------------------ blood on him: soaked into his shirt and his skin
-- ("bloodstains on body are all wrong should actually be on the shirt", "pants and skin also", 2026-11-10.) His shirt's
-- print picture and his skin's colour picture - each the whole of it, laid out once (his pants' is a cloth repeated 16
-- times over them: nothing can be put in one place on them) - are drawn into pictures of the mod's own in the game
-- (render targets), and splotches of blood drawn over those as he gets bloodier: SOAK `levels` layers
-- (textures gore_soak_shirt_N / gore_soak_skin_N, tools/soak_art.py), each over the last, by the stain each has had (the
-- STAIN counts below: wounds over it, lying in blood). The mod's pictures then are his shirt's and his skin's; his own put
-- back as he is healed.
-- (drawn on a canvas - BeginDrawCanvasToRenderTarget, its pictures drawn as they are, alpha and all: drawn by a material
-- the alpha was lost, and a shirt whose print is a logo on a see-through picture went all black, its blood white, "on a
-- white shirt blood is white and shirt turns black?", 2026-11-10)
M.SOAK = { on = true, levels = 6, res = 1024,
           garments = { TorsoCloth = { slot = 0, param = "PrintColor", art = "gore_soak_shirt_%d" },
                        CharacterMesh0 = { slot = 0, param = "BaseColor", art = "gore_soak_skin_%d" },
                        LegsCloth = { slot = 0, param = "PrintColor", art = "gore_soak_pants_%d", pants = true } } }
local WIDGET_T = "/Engine/EngineMaterials/Widget3DPassThrough_Translucent.Widget3DPassThrough_Translucent"
local soak = nil    -- { pawn, g = { [garment] = { comp, mid, orig, rt, drawn, keep = { mids } } } }
local function KRLib() return StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary") end
-- pictures drawn on `rt`, each { texture, blend } - blend 0 copied as it is (alpha too), 2 laid over by its alpha
local function canvas_draw(world, rt, list)
    local KRL = KRLib()
    local canvas, size, ctx = {}, {}, {}
    local okb = pcall(function() KRL:BeginDrawCanvasToRenderTarget(world, rt, canvas, size, ctx) end)
    if not (okb and ctx.RenderTarget) then return false end
    for _, d in ipairs(list) do
        if d[1] then
            pcall(function()
                canvas.Canvas:K2_DrawTexture(d[1], { X = 0, Y = 0 }, { X = size.X, Y = size.Y }, { X = 0, Y = 0 }, { X = 1, Y = 1 },
                    { R = 1, G = 1, B = 1, A = 1 }, d[2], 0.0, { X = 0.5, Y = 0.5 })
            end)
        end
    end
    pcall(function() KRL:EndDrawCanvasToRenderTarget(world, ctx) end)
    return true
end
-- (nothing of his kept from one call to the next but addresses: his material is looked up on him each time, and touched
-- only while it is still the mod's - STORROR puts his outfit's own back as it resets him, the mod's then freed, and
-- setting his picture back on it crashed the game, 22:41 2026-11-10)
local function find_comp(pawn, name)
    local found = nil
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
            local o = c:get()
            if o and o:IsValid() and o:GetFName():ToString() == name then found = o end
        end
    end)
    return found
end
-- his `name`'s material now, if it is the mod's: the material, the record
local function soak_mine(pawn, name)
    local G = soak and soak.pawn == pawn:GetAddress() and soak.g[name]
    if not G then return nil, nil end
    local comp = find_comp(pawn, name)
    if not comp then return nil, G end
    local m = nil
    pcall(function() m = comp:GetMaterial(G.slot) end)
    if m and m:IsValid() and m:GetAddress() == G.mid_addr then return m, G end
    return nil, G
end
-- (his pants: their colour picture is a cloth repeated 16 times over them - nothing can be put in one place on it - so
-- each of their materials is swapped for STORROR's own printed cloth, MI_ClothAlphaPrint: the same cloth - his pants' own
-- pictures and tint, repeated as theirs were - with a print over it, laid out once over the whole of them; the print the
-- mod's picture, see-through but for the blood. "why pants not getting bloody", "got to be some way to do it", 2026-11-10)
local PANTS_MAT = "/SPP/SPPCharacter/Clothing/Materials/MI_ClothAlphaPrint.MI_ClothAlphaPrint"
local PANTS_TEX = { ColorFabric = "BaseColor", RoughnessFabric = "Roughness", MetallicFabric = "Metallic",
                    AOFabric = "AmbientOcclusion", NormalFabric = "Normal" }
-- (their picture cleared to the blood's own colour, all see-through: over clear black, the blood's soft edges drew dark)
local PANTS_CLEAR = { R = 0.179, G = 0.0009, B = 0.0014, A = 0.0 }
local function pants_garment(world, pawn, name, spec)
    local comp = find_comp(pawn, name)
    if not comp then return nil end
    local base = load_mat(PANTS_MAT)
    if not base then return nil end
    local flat = load_mat("/Engine/EngineMaterials/DefaultNormal.DefaultNormal")
    local n = 0
    pcall(function() n = comp:GetNumMaterials() end)
    local addrs, first, first_slot = {}, nil, 0
    for i = 0, n - 1 do
        local src = nil
        pcall(function() src = comp:GetMaterial(i) end)
        if src and src:IsValid() then
            local tex = {}
            for to, from in pairs(PANTS_TEX) do
                local t = nil
                pcall(function() t = src:K2_GetTextureParameterValue(FName(from)) end)
                if t and t:IsValid() then tex[to] = t end
            end
            if tex.ColorFabric then
                local tint, ns, uva = nil, nil, nil
                pcall(function() tint = src:K2_GetVectorParameterValue(FName("Tint")) end)
                pcall(function() ns = src:K2_GetScalarParameterValue(FName("NormalStrength")) end)
                pcall(function() uva = src:K2_GetScalarParameterValue(FName("UV Amount")) end)
                if not uva or uva <= 0.0 then uva = 16.0 end
                mid_n = mid_n + 1
                local mid = nil
                pcall(function() mid = comp:CreateDynamicMaterialInstance(i, base, FName(string.format("ARSoakPants_%d_%d_%d", i, os.time(), mid_n))) end)
                if mid and mid:IsValid() then
                    for k, t in pairs(tex) do pcall(function() mid:SetTextureParameterValue(FName(k), t) end) end
                    for _, k in ipairs({ "U Amount", "V Amount", "UV Amount" }) do pcall(function() mid:SetScalarParameterValue(FName(k), uva) end) end
                    if ns and ns > 0.0 then pcall(function() mid:SetScalarParameterValue(FName("NormalStrength"), ns) end) end
                    if tint and (tint.R + tint.G + tint.B + tint.A) > 0.0 then pcall(function() mid:SetVectorParameterValue(FName("Tint"), tint) end) end
                    if flat then pcall(function() mid:SetTextureParameterValue(FName("PrintNormal"), flat) end) end
                    addrs[i] = mid:GetAddress()
                    if not first then first, first_slot = mid, i end
                end
            end
        end
    end
    if not first then return nil end
    log("gore: his pants on the print cloth (%d of %d materials)", (function() local c = 0; for _ in pairs(addrs) do c = c + 1 end; return c end)(), n)
    return { slot = first_slot, mid_addr = first:GetAddress(), slots = addrs, param = spec.param, art = spec.art, drawn = 0,
             pants = true, clear = PANTS_CLEAR }, first
end
local function soak_garment(world, pawn, name)
    local pa = pawn:GetAddress()
    if not (soak and soak.pawn == pa) then soak = { pawn = pa, g = {} } end
    local m0, G = soak_mine(pawn, name)
    if m0 then return G, m0 end
    -- (his material is his outfit's own again - or never was the mod's: made the mod's now, from scratch)
    local spec = M.SOAK.garments[name]
    if spec.pants then
        local Gp, mp = pants_garment(world, pawn, name, spec)
        if Gp then soak.g[name] = Gp end
        return Gp, mp
    end
    local comp = find_comp(pawn, name)
    if not comp then return nil end
    local m = comp:GetMaterial(spec.slot)
    if not (m and m:IsValid()) then return nil end
    local mid = m
    if m:GetClass():GetFName():ToString() ~= "MaterialInstanceDynamic" then
        mid_n = mid_n + 1
        mid = comp:CreateDynamicMaterialInstance(spec.slot, m, FName(string.format("ARSoak_%s_%d_%d", name, os.time(), mid_n)))
    end
    if not (mid and mid:IsValid()) then return nil end
    local orig = nil
    pcall(function() orig = mid:K2_GetTextureParameterValue(FName(spec.param)) end)
    if not (orig and orig:IsValid()) then return nil end
    G = { slot = spec.slot, mid_addr = mid:GetAddress(), orig = orig, param = spec.param, art = spec.art, drawn = 0 }
    soak.g[name] = G
    return G, mid
end
-- the picture set on his `name` - on each of his pants' materials, that are still the mod's
local function soak_set_all(pawn, name, G, mid, rt)
    if not G.pants then pcall(function() mid:SetTextureParameterValue(FName(G.param), rt) end); return end
    local comp = find_comp(pawn, name)
    if not comp then return end
    for i, addr in pairs(G.slots) do
        local m = nil
        pcall(function() m = comp:GetMaterial(i) end)
        if m and m:IsValid() and m:GetAddress() == addr then pcall(function() m:SetTextureParameterValue(FName(G.param), rt) end) end
    end
end
-- his `name` the mod's, its picture made (his own drawn in, if it has one) and set on it: its record, or nil
-- (a picture of the mod's made afresh each time it starts over: one no material holds is freed)
local function soak_start(world, pawn, name)
    local G, mid = soak_garment(world, pawn, name)
    if not (G and mid) then return nil end
    if not G.started then
        local clear = G.clear or { R = 0, G = 0, B = 0, A = 0 }
        local ok, rt = pcall(function() return KRLib():CreateRenderTarget2D(world, M.SOAK.res, M.SOAK.res, 3, clear, false, false) end)
        if not (ok and rt and rt:IsValid()) then return nil end
        G.rt = rt
        if G.orig then
            if not canvas_draw(world, G.rt, { { G.orig, 0 } }) then return nil end
        else
            pcall(function() KRLib():ClearRenderTarget2D(world, G.rt, clear) end)
        end
        soak_set_all(pawn, name, G, mid, G.rt)
        G.started = true
    end
    return G
end
local SOAK_SAY = { TorsoCloth = "shirt", CharacterMesh0 = "skin", LegsCloth = "pants" }
-- his `name` soaked to level `L` (0..1)
-- (the soak's pictures loaded beforehand and kept: loaded as the blood soaked in, 18 of them as he was blown apart, 8-10 ms
-- each from its file, the game stood still 150 ms - "the blood dismemberment and gore need optimized bad", 2026-11-11.
-- Loaded one at a time while nothing is going on, each held by a hidden picture on the screen so the engine never lets
-- one go)
M.SOAKHOLD = { on = true, widget = nil, canvas = nil, held = {}, done = false }
function M.SOAKHOLD.step(world)
    local H = M.SOAKHOLD
    if not H.on or H.done then return end
    for _, spec in pairs(M.SOAK.garments) do
        for k = 1, M.SOAK.levels do
            local file = string.format(spec.art, k)
            local ok, yes = pcall(same, tex_cache[file])
            if not (ok and yes and H.held[file]) then
                local t = texture(world, file)
                if not t then H.held[file] = true; return end
                if not (H.widget and H.widget:IsValid()) then
                    local pc = lib.controller()
                    if not pc then return end
                    local w = StaticConstructObject(StaticFindObject("/Script/UMG.UserWidget"), pc, FName("None"))
                    local tree = StaticConstructObject(StaticFindObject("/Script/UMG.WidgetTree"), w, FName("None"))
                    w.WidgetTree = tree
                    local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, FName("None"))
                    tree.RootWidget = canvas
                    pcall(function() w:SetVisibility(1) end)
                    w:AddToViewport(-50)
                    H.widget, H.canvas = w, canvas
                end
                local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), H.canvas, FName("None"))
                pcall(function() img:SetBrushFromTexture(t, false) end)
                pcall(function() img:SetVisibility(1) end)
                H.canvas:AddChildToCanvas(img)
                H.held[file] = true
                return
            end
        end
    end
    H.done = true
    log("gore: the soak's pictures all loaded and held")
end
local function soak_show(world, pawn, name, L)
    local S = M.SOAK
    if not S.on or not S.garments[name] then return end
    local want = math.floor(min(1.0, L) * S.levels + 0.0001)
    local G = soak and soak.pawn == pawn:GetAddress() and soak.g[name]
    if want <= ((G and G.drawn) or 0) then return end
    G = soak_start(world, pawn, name)
    if not G then return end
    local list = {}
    for k = G.drawn + 1, want do list[#list + 1] = { texture(world, string.format(G.art, k)), 2 } end
    if not canvas_draw(world, G.rt, list) then return end
    G.drawn = want
    log("gore: blood soaked into his %s (%d of %d)", SOAK_SAY[name] or name, want, S.levels)
end
local function soak_clear()
    local S = soak
    if not S then return end
    local pawn = lib.pawn()
    for name, G in pairs(S.g) do
        if pawn and S.pawn == pawn:GetAddress() then
            local m = soak_mine(pawn, name)
            if m then
                if G.orig then pcall(function() m:SetTextureParameterValue(FName(G.param), G.orig) end)
                -- (his pants stay on the print cloth - their own materials were let go - their picture cleared)
                elseif G.rt and G.started then pcall(function() KRLib():ClearRenderTarget2D(lib.world(), G.rt, G.clear) end) end
            end
        end
        G.drawn, G.rt, G.started = 0, nil, false
    end
end
M.soak_clear = soak_clear

-- ------------------------------------------------------------ blood on him: his clothes stained
-- ("I want blood to get on the player" - decals on him would bring the world's decals with them, so: "Both", 2026-11-10 -
-- his clothes stained, and patches of blood on him.) Each piece of his clothes - shirt, pants, shoes - takes on the
-- blood's colour by how much it has had: `cut` at once as a part over it comes off, `wound` a second while a wound over it
-- bleeds, `lie` a second while it lies in blood on the floor; `most` of the way to `blood` at the very worst. Made his own
-- (a material of the mod's for each of its own, its colour settings moved) and put back as he is healed.
-- (its counts only: no colour of his clothes moved - "remove whatevers making the pants completely red", 2026-11-10 - they
-- drive the SOAK above)
M.STAIN = { on = true, every = 0.4, cut = 0.22, wound = 0.025, lie = 0.06, most = 0.8,
            blood = { R = 0.26, G = 0.02, B = 0.02, A = 1.0 } }
local GARMENT_OF = { pelvis = "LegsCloth", spine_01 = "TorsoCloth", spine_02 = "TorsoCloth", spine_03 = "TorsoCloth",
                     spine_04 = "TorsoCloth", spine_05 = "TorsoCloth", clavicle_l = "TorsoCloth", clavicle_r = "TorsoCloth",
                     upperarm_l = "TorsoCloth", upperarm_r = "TorsoCloth", neck_01 = "TorsoCloth",
                     thigh_l = "LegsCloth", thigh_r = "LegsCloth", calf_l = "LegsCloth", calf_r = "LegsCloth",
                     foot_l = "Feet", foot_r = "Feet",
                     lowerarm_l = "CharacterMesh0", lowerarm_r = "CharacterMesh0", hand_l = "CharacterMesh0", hand_r = "CharacterMesh0" }
local TINT_PARAMS = { --[[ LegsCloth = { "Tint" }, ]] Feet = { "diffuse_color_1", "diffuse_color_2", "B_diffuse_color_1", "C_color" } }
local stain = nil     -- { pawn, level = { [garment] = 0..1 }, shown = {}, slots = { [garment] = { { mid, orig } } }, seen = {}, t }
local function stain_of(pawn)
    local pa = pawn:GetAddress()
    if stain and stain.pawn == pa then return stain end
    stain = { pawn = pa, level = {}, shown = {}, slots = {}, seen = {}, t = 0.0 }
    return stain
end
-- the garment's materials made the mod's own, their colours as they were
local function garment_slots(pawn, S, g)
    local sl = S.slots[g]
    if sl then
        local ok = true
        for _, e in ipairs(sl) do if not pcall(function() return e.mid:IsValid() end) or not e.mid:IsValid() then ok = false end end
        if ok then return sl end
    end
    sl = {}
    pcall(function()
        for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.PrimitiveComponent"))) do
            local o = c:get()
            if o and o:IsValid() and o:GetFName():ToString() == g then
                for i = 0, o:GetNumMaterials() - 1 do
                    local m = o:GetMaterial(i)
                    if m and m:IsValid() then
                        local mid = m
                        if m:GetClass():GetFName():ToString() ~= "MaterialInstanceDynamic" then
                            mid_n = mid_n + 1
                            mid = o:CreateDynamicMaterialInstance(i, m, FName(string.format("ARStain_%d_%d", os.time(), mid_n)))
                        end
                        if mid and mid:IsValid() then
                            local orig = {}
                            for _, pn in ipairs(TINT_PARAMS[g] or {}) do
                                local okv, v = pcall(function() return mid:K2_GetVectorParameterValue(FName(pn)) end)
                                if okv and v then orig[pn] = { R = v.R, G = v.G, B = v.B, A = v.A } end
                            end
                            sl[#sl + 1] = { mid = mid, orig = orig }
                        end
                    end
                end
            end
        end
    end)
    S.slots[g] = sl
    return sl
end
local function stain_show(pawn, S, g)
    local L = min(1.0, S.level[g] or 0.0)
    if abs(L - (S.shown[g] or 0.0)) < 0.015 then return end
    S.shown[g] = L
    local k = L * M.STAIN.most
    local b = M.STAIN.blood
    for _, e in ipairs(garment_slots(pawn, S, g)) do
        for pn, o in pairs(e.orig) do
            pcall(function()
                e.mid:SetVectorParameterValue(FName(pn), { R = o.R + (b.R - o.R) * k, G = o.G + (b.G - o.G) * k, B = o.B + (b.B - o.B) * k, A = o.A })
            end)
        end
    end
end
local function stain_add(S, bone, amount)
    local g = GARMENT_OF[bone]
    if g then S.level[g] = min(1.0, (S.level[g] or 0.0) + amount) end
    -- (his skin under his shirt - the band of stomach that shows - gets some of his shirt's)
    if g == "TorsoCloth" then S.level.CharacterMesh0 = min(1.0, (S.level.CharacterMesh0 or 0.0) + amount * 0.4) end
end
local function stain_tick(world, dt)
    local SG = M.STAIN
    if not SG.on or not M.bleeding_on() then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local S = stain_of(pawn)
    S.t = S.t + dt
    if S.t < SG.every then return end
    local step = S.t
    S.t = 0.0
    local mesh = pawn.Mesh
    -- (each wound: at once as it is first seen, then while it bleeds)
    for _, w in ipairs(wounds_now(pawn, mesh)) do
        if not S.seen[w.key] then S.seen[w.key] = true; stain_add(S, w.bone, SG.cut) end
        stain_add(S, w.bone, SG.wound * step)
    end
    -- (lying or standing in blood)
    local Pt = paint
    if Pt and Pt.spots and #Pt.spots > 0 then
        for _, bn in ipairs(SMEAR_BONES) do
            if GARMENT_OF[bn] then
                local okp, p = pcall(function() return at(mesh, bn) end)
                if okp and p then
                    local r = LIMB_R[bn] or 6.0
                    for _, sp in ipairs(Pt.spots) do
                        local dx, dy, dz = p[1] - sp[1], p[2] - sp[2], p[3] - sp[3]
                        if dz > -r and dz < r + M.BODY_BLOOD.lie_gap and dx * dx + dy * dy < (sp[4] + r * 0.5) ^ 2 then
                            stain_add(S, bn, SG.lie * step)
                            break
                        end
                    end
                end
            end
        end
    end
    for g in pairs(TINT_PARAMS) do if S.level[g] then stain_show(pawn, S, g) end end
    for g in pairs(M.SOAK.garments) do if S.level[g] then pcall(soak_show, world, pawn, g, S.level[g]) end end
end
-- (washed out: his clothes' colours put back)
local function stain_clear()
    pcall(soak_clear)
    local S = stain
    stain = nil
    if not S then return end
    for g, sl in pairs(S.slots) do
        for _, e in ipairs(sl) do
            for pn, o in pairs(e.orig) do pcall(function() if e.mid:IsValid() then e.mid:SetVectorParameterValue(FName(pn), o) end end) end
        end
    end
end
M.stain_clear = stain_clear
-- ------------------------------------------------------------ drops landing on him
-- ("can you make the blood drops actually land on it?", 2026-11-10.) A drop in the air `after` s and more meets him - his
-- trunk, his arms, his legs, as capsules round their bones - and stops there; on his shirt a splat is drawn into it where
-- it met him, by where that is on its picture (found by tinting its quarters: the front its bottom left, the back its
-- bottom right, his right sleeve the top left, his left the top right; collar at a panel's top, hem at its bottom); on
-- his bare arms, the blood in his skin a little more. On his pants (since gore v26 - their print picture: one leg each
-- half of it, mirrored, the waist at the top and the cuff at the bottom - found by a grid of colours over it) where on the
-- leg it met.
M.ONHIM = { on = true, after = 0.15, size = { 22.0, 46.0 },
            trunk_r = 16.0, uarm_r = 7.5, larm_r = 5.5, hand_r = 4.5, thigh_r = 9.5, calf_r = 7.5,
            front = { 0.03, 0.47 }, back = { 0.53, 0.97 }, panel_v = { 0.36, 0.96 }, sleeve_v = { 0.04, 0.28 },
            sleeve_r = { 0.06, 0.44 }, sleeve_l = { 0.56, 0.94 },
            skin_larm_l = { 0.05, 0.45 }, skin_larm_r = { 0.55, 0.95 }, skin_larm_v = { 0.28, 0.48 },
            skin_hand_l = { 0.28, 0.47 }, skin_hand_r = { 0.53, 0.72 }, skin_hand_v = { 0.04, 0.22 },
            -- (each leg its half of the picture - his right the left half, his left the right - mirrored: `front` the
            -- column of the half that is the leg's front, 1 or 2, the back the other; found by blood on one strip)
            pants_r = { 0.0, 0.5, front = 1 }, pants_l = { 0.5, 1.0, front = 2 },
            pants_thigh_v = { 0.04, 0.5 }, pants_calf_v = { 0.5, 0.96 } }
local HIT_CAPS = {
    { "trunk", "pelvis", "spine_05", "trunk_r" },
    { "uarm_r", "upperarm_r", "lowerarm_r", "uarm_r" }, { "uarm_l", "upperarm_l", "lowerarm_l", "uarm_r" },
    { "larm_r", "lowerarm_r", "hand_r", "larm_r" }, { "larm_l", "lowerarm_l", "hand_l", "larm_r" },
    { "hand_r", "hand_r", "middle_01_r", "hand_r" }, { "hand_l", "hand_l", "middle_01_l", "hand_r" },
    { "thigh_l", "thigh_l", "calf_l", "thigh_r" }, { "thigh_r", "thigh_r", "calf_r", "thigh_r" },
    { "calf_l", "calf_l", "foot_l", "calf_r" }, { "calf_r", "calf_r", "foot_r", "calf_r" },
}
local HIT_BONES = { "pelvis", "spine_05", "clavicle_l", "clavicle_r", "upperarm_r", "upperarm_l", "lowerarm_r", "lowerarm_l",
                    "hand_r", "hand_l", "middle_01_r", "middle_01_l", "thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l" }
-- the nearest points of segment p-q and segment a-b: their gap, how far along a-b (0..1)
local function seg_gap(p, q, a, b)
    local d1 = sub(q, p)
    local d2 = sub(b, a)
    local r = sub(p, a)
    local A, E, F = dot(d1, d1), dot(d2, d2), dot(d2, r)
    local s_, t_ = 0.0, 0.0
    if A <= 1e-6 and E <= 1e-6 then return len(r), 0.0 end
    if A <= 1e-6 then t_ = max(0.0, min(1.0, F / E))
    else
        local C = dot(d1, r)
        if E <= 1e-6 then s_ = max(0.0, min(1.0, -C / A))
        else
            local Bv = dot(d1, d2)
            local den = A * E - Bv * Bv
            s_ = (den > 1e-6) and max(0.0, min(1.0, (Bv * F - C * E) / den)) or 0.0
            t_ = (Bv * s_ + F) / E
            if t_ < 0.0 then t_ = 0.0; s_ = max(0.0, min(1.0, -C / A))
            elseif t_ > 1.0 then t_ = 1.0; s_ = max(0.0, min(1.0, (Bv - C) / A)) end
        end
    end
    local c1 = add(p, mul(d1, s_))
    local c2 = add(a, mul(d2, t_))
    return len(sub(c1, c2)), t_, c1
end
-- his bones' places this frame, while drops are about
local function body_now(pawn)
    local mesh = pawn.Mesh
    local P = {}
    for _, bn in ipairs(HIT_BONES) do
        local ok, v = pcall(function() return at(mesh, bn) end)
        if ok and v then P[bn] = v end
    end
    if not (P.pelvis and P.spine_05 and P.clavicle_l and P.clavicle_r) then return nil end
    local up = unit(sub(P.spine_05, P.pelvis))
    local right = unit(sub(P.clavicle_r, P.clavicle_l))
    P._up, P._right, P._fwd = up, right, unit(cross(right, up))
    return P
end
-- a splat drawn into his shirt (or his skin, `name`) at u, v (0..1 of its picture)
local function shirt_splat(world, pawn, u, v, name)
    local S = M.SOAK
    if not S.on then return end
    local G = soak_start(world, pawn, name or "TorsoCloth")
    if not G then return end
    local tex = texture(world, "gore_soak_splats")
    if not tex then return end
    local KRL = KRLib()
    local canvas, size, ctx = {}, {}, {}
    local okb = pcall(function() KRL:BeginDrawCanvasToRenderTarget(world, G.rt, canvas, size, ctx) end)
    if not (okb and ctx.RenderTarget) then return end
    local H = M.ONHIM
    local px = rnd(H.size[1], H.size[2]) * (size.X / 1024.0)
    local kind = math.random(1, 2)
    local gx, gy = 4, 8
    local cu, cv = ((kind - 1) % gx) / gx, math.floor((kind - 1) / gx) / gy
    pcall(function()
        canvas.Canvas:K2_DrawTexture(tex, { X = u * size.X - px * 0.5, Y = v * size.Y - px * 0.5 }, { X = px, Y = px },
            { X = cu, Y = cv }, { X = 1.0 / gx, Y = 1.0 / gy }, { R = 1, G = 1, B = 1, A = 1 }, 2, rnd(0.0, 360.0), { X = 0.5, Y = 0.5 })
    end)
    pcall(function() KRL:EndDrawCanvasToRenderTarget(world, ctx) end)
end
-- a drop meeting him between p and q: where on him, or nil
local function hit_him(P, p, q)
    local H = M.ONHIM
    for _, c in ipairs(HIT_CAPS) do
        local a, b = P[c[2]], P[c[3]]
        if a and b then
            local gap, t, at_ = seg_gap(p, q, a, b)
            if gap < (H[c[4]] or 6.0) then return c[1], t, at_, a, b end
        end
    end
    return nil
end
local function on_him(world, pawn, P, part, t, hp, a, b)
    local H = M.ONHIM
    if part == "trunk" then
        local axis = unit(sub(b, a))
        local rel = sub(hp, add(a, mul(axis, t * len(sub(b, a)))))
        local front = dot(rel, P._fwd) >= 0.0
        local lat = max(-1.0, min(1.0, dot(rel, P._right) / H.trunk_r))
        local v = H.panel_v[2] - (H.panel_v[2] - H.panel_v[1]) * max(0.0, min(1.0, t))
        local R = front and H.front or H.back
        local mid_u, half = (R[1] + R[2]) * 0.5, (R[2] - R[1]) * 0.5
        local u = mid_u + (front and lat or -lat) * half * 0.9
        pcall(shirt_splat, world, pawn, u, v)
    elseif part == "uarm_r" or part == "uarm_l" then
        local R = (part == "uarm_r") and H.sleeve_r or H.sleeve_l
        local u = rnd(R[1], R[2])
        local v = H.sleeve_v[1] + (H.sleeve_v[2] - H.sleeve_v[1]) * max(0.0, min(1.0, t))
        pcall(shirt_splat, world, pawn, u, v)
    elseif part == "larm_r" or part == "larm_l" then
        -- (his skin's picture, found by a grid of colours over it: the forearms its second row - his left in its left
        -- half, his right in its right - the elbow at its bottom, the wrist at its top; the hands the top row's middle)
        local R = (part == "larm_l") and H.skin_larm_l or H.skin_larm_r
        local v = H.skin_larm_v[2] - (H.skin_larm_v[2] - H.skin_larm_v[1]) * max(0.0, min(1.0, t))
        pcall(shirt_splat, world, pawn, rnd(R[1], R[2]), v, "CharacterMesh0")
    elseif part == "hand_r" or part == "hand_l" then
        local R = (part == "hand_l") and H.skin_hand_l or H.skin_hand_r
        pcall(shirt_splat, world, pawn, rnd(R[1], R[2]), rnd(H.skin_hand_v[1], H.skin_hand_v[2]), "CharacterMesh0")
    elseif part == "thigh_l" or part == "thigh_r" or part == "calf_l" or part == "calf_r" then
        -- (his pants: his leg's half of their picture, its back or its front by which side of the leg it met)
        local half = (part:sub(-1) == "l") and H.pants_l or H.pants_r
        local axis = unit(sub(b, a))
        local rel = sub(hp, add(a, mul(axis, t * len(sub(b, a)))))
        local front = dot(rel, P._fwd) >= 0.0
        local w = (half[2] - half[1]) * 0.5
        local second = (front and half.front == 2) or (not front and half.front == 1)
        local c0 = half[1] + (second and w or 0.0)
        local V = part:match("^thigh") and H.pants_thigh_v or H.pants_calf_v
        local v = V[1] + (V[2] - V[1]) * max(0.0, min(1.0, t))
        pcall(shirt_splat, world, pawn, c0 + w * rnd(0.15, 0.85), v, "LegsCloth")
    end
end

M._onhim = { body_now = body_now, hit_him = hit_him, on_him = on_him }

-- drops made ahead, `n` a frame, once the copies are ready
local function prewarm(world, n)
    local B = M.BLOOD
    local D = drop_list(world)
    for _ = 1, n do
        if #D.list < B.max then
            local a = sprite(world, false, "gore_blood_tear")
            if not a then return end
            D.list[#D.list + 1] = { actor = a }
        else
            return
        end
    end
end

M.PREP_EVERY = 0.1
local prep_t, sig_t = 0.0, 0.0
-- (ZERO GRAVITY, MOON GRAVITY - ragdoll.lua changes the world's gravity, so his torn-off parts go by it of themselves:
-- the blood's drops, worked out here, by the same; a part's own gravity left off by the first way put back on)
local function grav_tick()
    local A = _G.AR
    if not (A and A.GRAV) then return end
    M.BLOOD.gravity = A.GRAV.g
    if not (st and st.pieces) then return end
    for _, part in pairs(st.pieces) do
        local box = part.box
        if box and box:IsValid() and not box:IsGravityEnabled() then box:SetEnableGravity(true) end
    end
end
function M.tick(dt, enabled)
    pcall(grav_tick)
    local c0 = os.clock()
    local s = st
    local world = lib.world()
    if not world then return end
    dt = min(dt or 0.016, 0.1)
    pcall(fractures_tick, world)
    if not s then
        -- (ahead of a tear: the copies made a few frames apart while he is about)
        local pawn = enabled and lib.pawn() or nil
        if pawn then
            prep_t = prep_t + dt
            sig_t = sig_t + dt
            if sig_t > 3.0 then
                sig_t = 0.0
                if prep and prep.world == world:GetAddress() and prep.sig ~= sig_of(pawn) then
                    log("gore: his clothes changed - the copies made again")
                    prep_drop()
                end
            end
            if prep_t >= M.PREP_EVERY then
                prep_t = 0.0
                local ok, more = pcall(prep_step, world, pawn)
                if not (ok and more) then pcall(prewarm, world, M.BLOOD.prewarm); pcall(M.SOAKHOLD.step, world) end
            end
        end
        if not drops then return end
    end
    if s and s.world == world:GetAddress() then
        s.t = s.t + dt
        if s.torso then pcall(s.torso.posed) end
        -- blood from every cut: spurts with his heartbeat, each fading from when it was cut
        local B = M.BLOOD
        local beat = sin(s.t * B.beat * 2.0 * pi)
        local pulse = B.low + (1.0 - B.low) * (beat > 0.0 and beat * beat or 0.0)
        for _, e in ipairs(s.emitters) do
            local age = s.t - e.t0
            -- (BLEED FOREVER, on the RAGDOLL tab: never stops, eased off to `floor` and kept there)
            local forever = _G.ARMENU and _G.ARMENU.bleed_forever and _G.ARMENU.bleed_forever()
            local fade = (age < B.life) and max(B.floor, 1.0 - age / B.life) or (forever and B.floor or 0.0)
            if fade > 0.0 or e.burst > 0 then
                local ok, pos, dir = pcall(function()
                    if e.stump then
                        local p = e.pose:GetSocketLocation(e.at)
                        local q = e.pose:GetSocketLocation(e.from)
                        return { p.X, p.Y, p.Z }, unit({ p.X - q.X, p.Y - q.Y, p.Z - q.Z })
                    end
                    local p = e.part.pose:GetSocketLocation(e.at)
                    local d = KML():TransformDirection(e.part.box:K2_GetComponentToWorld(), V(e.dl))
                    return { p.X, p.Y, p.Z }, unit({ d.X, d.Y, d.Z })
                end)
                if ok and pos then
                    local speed = e.stump and B.speed[1] or B.speed[2]
                    local iv = nil
                    if e.stump then iv = vel_of(s.body, e.at)
                    elseif e.part then
                        local okv, v = pcall(function() return e.part.box:GetPhysicsLinearVelocity(FName("None")) end)
                        if okv and v then iv = { v.X * M.INHERIT, v.Y * M.INHERIT, v.Z * M.INHERIT } end
                    end
                    if e.burst > 0 then
                        if e.stump then bled(e.burst, e.region) end
                        for _ = 1, e.burst do emit(world, e, pos, dir, speed * 1.3, nil, iv) end
                        e.burst = 0
                    end
                    e.acc = e.acc + (e.stump and B.rate or B.end_rate) * fade * pulse * dt
                    while e.acc >= 1.0 do
                        e.acc = e.acc - 1.0
                        if e.stump then bled(1, e.region) end
                        emit(world, e, pos, dir, speed * (0.5 + 0.5 * pulse), nil, iv)
                    end
                end
            end
        end
    end
    pcall(body_tick, world, dt)
    pcall(stain_tick, world, dt)
    drops_tick(world, dt)
    pcall(puddles_tick, world, dt)
    paint_flush(world, false)
    if s and s.world == world:GetAddress() then
        pcall(body_pool_tick, world, s, dt)
        local ms = (os.clock() - c0) * 1000.0
        s.cost.n, s.cost.sum, s.cost.top = s.cost.n + 1, s.cost.sum + ms, max(s.cost.top, ms)
    end
end

-- (the map gone: what was kept of it dropped untouched)
function M.forget()
    M.SOAKHOLD.widget, M.SOAKHOLD.canvas, M.SOAKHOLD.held, M.SOAKHOLD.done = nil, nil, {}, false
    st, drops, prep, paint, body_pool, puddles, body, stain, patches, soak = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    fracs, bone_mid = { world = nil, list = {} }, nil
    tex_cache, mid_cache, dmid_cache = {}, {}, {}
end
-- (a reload of this file with the map the same: what this copy made put back and taken away first)
function M.unload()
    pcall(M.fractures_clear)
    pcall(M.clear)
    pcall(prep_drop)
    pcall(paint_wipe)
    if drops then for _, d in ipairs(drops.list) do destroy(d.actor) end end
    st, drops, prep, paint, body_pool = nil, nil, nil, nil, nil
end
function M.debug() return st, drops, prep, paint end
return M
