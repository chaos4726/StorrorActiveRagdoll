-- STORROR Active Ragdoll: multiplayer, peer to peer through Steam ("remove the multiplayer and switch it for steam peer to
-- peer", "same as SM64 but obviously don't make it connect to sm64", "moves, ragdolls and gore", 2026-11-11). STORROR's
-- own multiplayer needs its servers, which can't be reached.
--
-- bin\arnet.dll does the networking (Steam lobbies to find each other - the ragdoll mod's own, data "armp", never
-- SM64Map's - and Steam's peer-to-peer messages to play: no server of anyone's); this loads it, tells it what to do, and
-- sends it this player's state 20 times a second: his map, where his body is and how 24 of its bones lie - on his feet,
-- falling, lying in a ragdoll - whether he is down, and the parts of him cut off. Every other player on the same map is
-- drawn as a copy of the athlete (his own body, head, clothes and shoes), posed from their bones and eased between their
-- samples; their cut-off parts gone from it, its stumps bleeding. Their name over them. No collision: nothing of the
-- game's touches it. The files between this and the DLL are in the mod's net\ folder (arnet.cpp says what each holds).
local lib = _G.ARLIB
local log = lib.log

local M = { VERSION = 1 }

local NET = lib.MOD_DIR .. "net\\"
-- (in bin\, not dlls\: UE4SS takes a mod with a dlls folder for a C++ mod)
local DLL = lib.MOD_DIR .. "bin\\arnet.dll"
local IDENT = { Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 }, Translation = { X = 0.0, Y = 0.0, Z = 0.0 }, Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 } }
local ONE = { X = 1.0, Y = 1.0, Z = 1.0 }
local EPS = { X = 0.001, Y = 0.001, Z = 0.001 }

M.RATE = 20.0                 -- states sent a second
M.DELAY = 0.12                -- s: the others drawn this far behind their latest, eased between their samples
M.STALE = 3.0                 -- s: a player not heard from this long isn't drawn
M.MAX_DRAWN = 16              -- the most other players drawn at once
M.MIRROR = false              -- (testing alone: this player's own state drawn as another, M.MIRROR_SIDE cm to his right)
M.MIRROR_SIDE = 250.0
M.status = { state = "off", members = {}, list = {}, listdone = 0 }

local started, callbacks_on = false, false
local fn_callbacks = nil

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- ------------------------------------------------------------------------------------------- the DLL

local function start()
    if started then return true end
    local f, err = package.loadlib(DLL, "arnet_start")
    if not f then log("multiplayer: couldn't load arnet.dll (%s)", tostring(err)); return false end
    local ok, e2 = pcall(f)
    if not ok then log("multiplayer: arnet_start failed (%s)", tostring(e2)); return false end
    fn_callbacks = package.loadlib(DLL, "arnet_callbacks")
    started = true
    log("multiplayer: arnet.dll started")
    return true
end
M.start = start

local function cmd(line)
    if not start() then return end
    local f = io.open(NET .. "cmd.txt", "a")
    if f then f:write(line, "\n"); f:close() end
end

-- passworded lobbies: a 7-digit code's hash in the lobby's data ("lock"); a joiner from the list let in only with the
-- code that makes the same hash. (A friend's invite, or Steam's "Join Game", needs none: the host asked them.)
local function lock_of(code)
    local h = 2166136261                                   -- FNV-1a, 32 bits, over the mod's word and the code
    for c in ("armp-lock:" .. tostring(code)):gmatch(".") do h = ((h ~ c:byte()) * 16777619) & 0xffffffff end
    return string.format("%08x", h)
end
M.lock_of = lock_of

function M.host(public, code)
    cmd("lock " .. (code and lock_of(code) or "-"))
    cmd(public and "host public" or "host friends")
end
function M.list() cmd("list") end
function M.join(id, code)
    if not (id and tostring(id):match("^%d+$")) then return false end
    for _, l in ipairs(M.status.list or {}) do
        if l.id == tostring(id) and l.lock and l.lock ~= "" and lock_of(code or "") ~= l.lock then return false end
    end
    cmd("join " .. tostring(id))
    return true
end
function M.leave() cmd("leave") end
-- Steam overlay's invite window, asked from the game's thread (from the DLL's own it showed nothing), or one friend
-- invited by Steam's own lobby invite, no overlay
local fn_invite = nil
function M.invite()
    if not start() then return end
    if fn_invite == nil then fn_invite = package.loadlib(DLL, "arnet_invite") or false end
    if fn_invite then pcall(fn_invite) else cmd("invite") end
end
function M.invite_friend(id) if id and tostring(id):match("^%d+$") then cmd("invite " .. tostring(id)) end end
function M.in_lobby() return M.status.state == "in_lobby" end
function M.others() local n = 0; for _, m in ipairs(M.status.members) do if m.id ~= M.status.me then n = n + 1 end end; return n end

-- an event to every other player (reliable), or to one (`to`)
function M.send_event(kind, text, to)
    if not M.in_lobby() then return end
    local f = io.open(NET .. "out_events.txt", "a")
    if f then f:write(to and ("to=" .. to .. "|") or "", kind, "|", text or "", "\n"); f:close() end
end
M.on_event = {}               -- kind -> function(from_id, text)

local function read_status()
    local f = io.open(NET .. "status.txt", "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    if not text or text == "" then return end
    local s = { members = {}, list = {}, listdone = 0 }
    for line in text:gmatch("[^\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k == "member" then
            local id, name = v:match("^(%d+)|(.*)$")
            if id then s.members[#s.members + 1] = { id = id, name = name } end
        elseif k == "list" then
            local id, name, n, max, rest = v:match("^(%d+)|([^|]*)|(%d+)|(%-?%d+)|(.*)$")
            local scene, lock = (rest or ""):match("^([^|]*)|(.*)$")
            if id then
                s.list[#s.list + 1] = { id = id, name = name, n = tonumber(n), max = tonumber(max), scene = scene or rest, lock = lock or "" }
            end
        elseif k == "friend" then
            local id, name, here = v:match("^(%d+)|([^|]*)|(%d)$")
            if id then s.friends = s.friends or {}; s.friends[#s.friends + 1] = { id = id, name = name, here = here == "1" } end
        elseif k == "listdone" then
            s.listdone = tonumber(v) or 0
        elseif k then
            s[k] = v
        end
    end
    local was = M.status.state
    M.status = s
    if s.state ~= was then log("multiplayer: %s%s", tostring(s.state), (s.error and s.error ~= "") and (" (" .. s.error .. ")") or "") end
end

-- ------------------------------------------------------------------------------------- base64 (no | or line breaks)

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64I = {}
for i = 1, 64 do B64I[B64:byte(i)] = i - 1 end
local function b64(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        b, c = b or 0, c or 0
        local v = a * 65536 + b * 256 + c
        local k = #out
        out[k + 1] = B64:sub((v >> 18) + 1, (v >> 18) + 1)
        out[k + 2] = B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
        out[k + 3] = (i + 1 <= n) and B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) or "="
        out[k + 4] = (i + 2 <= n) and B64:sub((v & 63) + 1, (v & 63) + 1) or "="
    end
    return table.concat(out)
end
local function unb64(s)
    local out = {}
    for i = 1, #s - 3, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local va, vb, vc, vd = B64I[a] or 0, B64I[b] or 0, B64I[c], B64I[d]
        local v = (va << 18) | (vb << 12) | ((vc or 0) << 6) | (vd or 0)
        out[#out + 1] = string.char((v >> 16) & 255)
        if vc then out[#out + 1] = string.char((v >> 8) & 255) end
        if vd then out[#out + 1] = string.char(v & 255) end
    end
    return table.concat(out)
end

-- ------------------------------------------------------------------------------------------- his state

-- the bones sent: his trunk, head, arms and legs (the rest - fingers, face - follow them on the copy)
M.BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "head",
            "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
            "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r" }
local POS, Q = 50.0, 32767.0
local function clamp16(v) v = math.floor(v + 0.5); if v > 32767 then return 32767 elseif v < -32767 then return -32767 end return v end
local fnames = {}
for i, b in ipairs(M.BONES) do fnames[i] = FName(b) end
local POSE_FMT = "<fffhhhh" .. string.rep("hhhhhhh", #M.BONES)

-- his pose now, packed: where his body is (cm) and its turn, and each bone's place and turn in the body's space
local function my_pose(pawn)
    local mesh = pawn.Mesh
    if not alive(mesh) then return nil end
    local w = mesh:K2_GetComponentToWorld()
    local vals = { w.Translation.X, w.Translation.Y, w.Translation.Z,
                   clamp16(w.Rotation.X * Q), clamp16(w.Rotation.Y * Q), clamp16(w.Rotation.Z * Q), clamp16(w.Rotation.W * Q) }
    for i = 1, #fnames do
        local b = mesh:GetSocketTransform(fnames[i], 2)               -- (RTS_Component)
        local p, q = b.Translation, b.Rotation
        local k = #vals
        vals[k + 1], vals[k + 2], vals[k + 3] = clamp16(p.X * POS), clamp16(p.Y * POS), clamp16(p.Z * POS)
        vals[k + 4], vals[k + 5], vals[k + 6], vals[k + 7] = clamp16(q.X * Q), clamp16(q.Y * Q), clamp16(q.Z * Q), clamp16(q.W * Q)
    end
    return string.pack(POSE_FMT, table.unpack(vals))
end
local function unpack_pose(data)
    local ok, t = pcall(function() return table.pack(string.unpack(POSE_FMT, data)) end)
    if not ok then return nil end
    return t
end

-- the parts of him cut off (the damage figure's, as the ragdoll has them), for the copy others draw
local CUT_ROOT = { head = "neck_01" }      -- (the bone each part comes off at: its own, but his head at his neck)
local CUT_PARENT = { upperarm_l = "clavicle_l", upperarm_r = "clavicle_r", lowerarm_l = "upperarm_l", lowerarm_r = "upperarm_r",
                     hand_l = "lowerarm_l", hand_r = "lowerarm_r", thigh_l = "pelvis", thigh_r = "pelvis", calf_l = "thigh_l",
                     calf_r = "thigh_r", foot_l = "calf_l", foot_r = "calf_r", head = "spine_05" }
local function my_cuts()
    local R = _G.AR
    if not (R and R.damage) then return "" end
    local ok, parts = pcall(R.damage)
    if not (ok and parts) then return "" end
    local out = {}
    for id, e in pairs(parts) do if e.state == 3 and CUT_PARENT[id] then out[#out + 1] = id end end
    table.sort(out)
    return table.concat(out, ",")
end
local function my_down()
    local R = _G.AR
    if not (R and R.state) then return false end
    local ok, s = pcall(R.state)
    return ok and s and s.down or false
end

-- ------------------------------------------------------------------------------------------- the others

local P = {}                  -- by Steam id: { actor, body, text, name, samples, off, cuts = { [region] = t0 }, bleed = {} }
M.fail_t = {}

local function drop(id)
    local p = P[id]
    if not p then return end
    P[id] = nil
    pcall(function() if p.actor:IsValid() then p.actor:K2_DestroyActor() end end)
end
function M.drop_all() for id in pairs(P) do drop(id) end end

-- another player's figure: the athlete's body, head, clothes and shoes copied from his own, posed by their bones; their
-- name over it
local function make(id, name, pawn)
    local world = lib.world()
    if not world then return nil end
    local KML = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local l = pawn:K2_GetActorLocation()
    local a = nil
    pcall(function()
        a = world:SpawnActor(StaticFindObject("/Script/Engine.StaticMeshActor"), { X = l.X, Y = l.Y, Z = l.Z - 5000.0 }, { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 })
    end)
    if not alive(a) then return nil end
    pcall(function() a.RootComponent:SetMobility(2) end)
    pcall(function() a:SetActorEnableCollision(false) end)
    local function comps(cls)
        local out = {}
        pcall(function() for _, c in ipairs(pawn:K2_GetComponentsByClass(StaticFindObject(cls))) do out[#out + 1] = c:get() end end)
        return out
    end
    local body_src = pawn.Mesh
    if not alive(body_src) then pcall(function() a:K2_DestroyActor() end); return nil end
    local body = nil
    pcall(function()
        body = a:AddComponentByClass(StaticFindObject("/Script/Engine.PoseableMeshComponent"), true, IDENT, false)
        body:SetSkinnedAssetAndUpdate(body_src:GetSkinnedAsset(), true)
        body:K2_AttachToComponent(a.RootComponent, FName("None"), 1, 1, 1, false)
        for i = 0, body:GetNumMaterials() - 1 do pcall(function() body:SetMaterial(i, body_src:GetMaterial(i)) end) end
        pcall(function() body:SetCastShadow(true) end)
        pcall(function() body:SetCollisionEnabled(0) end)
        body:CopyPoseFromSkeletalComponent(body_src)
    end)
    if not alive(body) then pcall(function() a:K2_DestroyActor() end); return nil end
    local src_t = body_src:K2_GetComponentToWorld()
    -- his head, clothes and shoes: on the body where his are on his, led by it
    local function follow(c, src)
        c:K2_AttachToComponent(body, FName("None"), 1, 1, 1, false)
        c:K2_SetRelativeTransform(KML:MakeRelativeTransform(src:K2_GetComponentToWorld(), src_t), false, {}, true)
        for i = 0, c:GetNumMaterials() - 1 do pcall(function() c:SetMaterial(i, src:GetMaterial(i)) end) end
        pcall(function() c:SetCastShadow(true) end)
        pcall(function() c:SetCollisionEnabled(0) end)
        c:SetLeaderPoseComponent(body, true, false)
    end
    for _, src in ipairs(comps("/Script/Engine.SkeletalMeshComponent")) do
        if src:GetAddress() ~= body_src:GetAddress() and src:GetOwner():GetAddress() == pawn:GetAddress() then
            pcall(function()
                local asset = src:GetSkinnedAsset()
                if not alive(asset) then return end
                local c = a:AddComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"), true, IDENT, false)
                c:SetSkinnedAssetAndUpdate(asset, true)
                follow(c, src)
                pcall(function() c.VisibilityBasedAnimTickOption = 0 end)
            end)
        end
    end
    local ccls = StaticFindObject("/Script/ChaosClothAssetEngine.ChaosClothComponent")
    if alive(ccls) then
        for _, src in ipairs(comps("/Script/ChaosClothAssetEngine.ChaosClothComponent")) do
            pcall(function()
                local asset = src:GetAsset()
                if not alive(asset) then return end
                local c = a:AddComponentByClass(ccls, true, IDENT, false)
                c:SetAsset(asset)
                follow(c, src)
                pcall(function() c:SetEnableSimulation(false) end)
            end)
        end
    end
    local p = { actor = a, body = body, name = name, samples = {}, off = nil, cuts = {}, bleed = {} }
    pcall(function()
        local t = a:AddComponentByClass(StaticFindObject("/Script/Engine.TextRenderComponent"), false, IDENT, false)
        t:SetText(FText(name ~= "" and name or "Player"))
        t:SetHorizontalAlignment(1)          -- (centred)
        t:SetWorldSize(18.0)
        t:SetTextRenderColor({ R = 255, G = 255, B = 255, A = 255 })
        pcall(function() t:SetCastShadow(false) end)
        p.text = t
    end)
    log("multiplayer: %s drawn", name)
    return p
end

-- a sample: { st (their clock), d (the unpacked pose) }; the pose at their clock `t`, eased between the two either side
local function pose_at(p, t)
    local s = p.samples
    if #s == 0 then return nil end
    if t <= s[1].st then return s[1].d, s[1].d, 0.0 end
    for i = #s - 1, 1, -1 do
        if s[i].st <= t then
            local a, b = s[i], s[i + 1]
            local k = (b.st > a.st) and math.min(1.0, (t - a.st) / (b.st - a.st)) or 1.0
            return a.d, b.d, k
        end
    end
    local last = s[#s].d
    return last, last, 0.0
end
local function qlerp(a, b, o, k)
    local ax, ay, az, aw = a[o] / Q, a[o + 1] / Q, a[o + 2] / Q, a[o + 3] / Q
    local bx, by, bz, bw = b[o] / Q, b[o + 1] / Q, b[o + 2] / Q, b[o + 3] / Q
    if ax * bx + ay * by + az * bz + aw * bw < 0.0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
    local x, y, z, w = ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k, aw + (bw - aw) * k
    local l = math.sqrt(x * x + y * y + z * z + w * w)
    if l < 1e-6 then return 0.0, 0.0, 0.0, 1.0 end
    return x / l, y / l, z / l, w / l
end

-- their stumps bleeding: as his own do, for the gore's `life` from when the cut was first seen (BLEED FOREVER: on)
M.PUPPET_BLEED = { rate = 22.0, floor = 0.35 }
local function bleed_tick(p, dt)
    local G = _G.ARGORE
    if not (G and G.puppet_bleed) or not next(p.cuts) then return end
    local life = (G.BLOOD and G.BLOOD.life) or 120.0
    local forever = _G.ARMENU and _G.ARMENU.bleed_forever and _G.ARMENU.bleed_forever()
    local now = os.clock()
    for region, t0 in pairs(p.cuts) do
        -- (a part inside one cut off higher up: it bleeds from that one's stump, not its own)
        local par = CUT_PARENT[region]
        local inner = false
        for other in pairs(p.cuts) do if other ~= region and (CUT_ROOT[other] or other) == par then inner = true end end
        local age = now - t0
        local fade = (age < life) and math.max(M.PUPPET_BLEED.floor, 1.0 - age / life) or (forever and M.PUPPET_BLEED.floor or 0.0)
        if not inner and fade > 0.0 then
            p.bleed[region] = (p.bleed[region] or 0.0) + M.PUPPET_BLEED.rate * fade * dt
            local n = math.floor(p.bleed[region])
            if n >= 1 then
                p.bleed[region] = p.bleed[region] - n
                pcall(function()
                    local at = p.body:GetSocketLocation(FName(CUT_ROOT[region] or region))
                    local from = p.body:GetSocketLocation(FName(par))
                    local dx, dy, dz = at.X - from.X, at.Y - from.Y, at.Z - from.Z
                    local l = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if l < 1e-3 then dx, dy, dz, l = 0.0, 0.0, 1.0, 1.0 end
                    G.puppet_bleed({ at.X, at.Y, at.Z }, { dx / l, dy / l, dz / l }, math.min(n, 4))
                end)
            end
        end
    end
end

local function draw(p, now, side, dt)
    if not p.off then return end
    local a, b, k = pose_at(p, now - p.off - M.DELAY)
    if not a then return end
    local bx = a[1] + (b[1] - a[1]) * k
    local by = a[2] + (b[2] - a[2]) * k
    local bz = a[3] + (b[3] - a[3]) * k
    local qx, qy, qz, qw = qlerp(a, b, 4, k)
    if side then bx, by = bx + side[1], by + side[2] end            -- (the mirror: moved to his right)
    local body = p.body
    pcall(function()
        body:K2_SetWorldTransform({ Rotation = { X = qx, Y = qy, Z = qz, W = qw }, Translation = { X = bx, Y = by, Z = bz }, Scale3D = ONE }, false, {}, true)
    end)
    for j, fn in ipairs(fnames) do
        local o = 8 + (j - 1) * 7
        local px = (a[o] + (b[o] - a[o]) * k) / POS
        local py = (a[o + 1] + (b[o + 1] - a[o + 1]) * k) / POS
        local pz = (a[o + 2] + (b[o + 2] - a[o + 2]) * k) / POS
        local x, y, z, w = qlerp(a, b, o + 3, k)
        pcall(function()
            body:SetBoneTransformByName(fn, { Rotation = { X = x, Y = y, Z = z, W = w }, Translation = { X = px, Y = py, Z = pz }, Scale3D = ONE }, 1)
        end)
    end
    -- (their parts cut off: shrunk into their stumps, as the gore's copy of his own body does)
    for region in pairs(p.cuts) do
        pcall(function() body:SetBoneScaleByName(FName(CUT_ROOT[region] or region), EPS, 1) end)
    end
    pcall(bleed_tick, p, dt)
    -- the name over the head, turned to the camera
    if p.text then
        pcall(function()
            local hx, hy, hz = bx, by, bz + 200.0
            local hd = body:GetSocketLocation(FName("head"))
            hx, hy, hz = hd.X, hd.Y, hd.Z + 40.0
            local cam = lib.controller().PlayerCameraManager:GetCameraLocation()
            local yaw = math.deg(math.atan(cam.Y - hy, cam.X - hx))
            p.text:K2_SetWorldLocationAndRotation({ X = hx, Y = hy, Z = hz }, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, false, {}, true)
        end)
    end
end

-- a state line from another player (or the mirror): S|1|<map>|<their clock>|<pose>|<pvp 0/1>|<down 0/1>|<cuts>
M.peer_scene, M.peer_pvp, M.peer_down = {}, {}, {}
function M.scene_of(id) return M.peer_scene[id] end
local function heard(id, name, line, now, pawn, scene)
    local sc, st, data, pv, dn, cuts = line:match("^S|1|([^|]*)|([%d%.%-]+)|([^|]+)|?(%d?)|?(%d?)|?(.*)$")
    if not sc then return end
    M.peer_scene[id] = sc
    M.peer_pvp[id] = pv == "1"
    M.peer_down[id] = dn == "1"
    st = tonumber(st)
    if sc ~= scene or not st then
        if P[id] then drop(id) end
        return
    end
    local p = P[id]
    if not p then
        if (M.fail_t[id] or -10.0) > now - 2.0 then return end    -- (a figure that wouldn't make: again in 2 s)
        local n = 0
        for _ in pairs(P) do n = n + 1 end
        if n >= M.MAX_DRAWN then return end
        p = make(id, name, pawn)
        if not p then M.fail_t[id] = now; return end
        P[id] = p
    end
    -- (their parts cut off: each as first seen; healed - none - all back)
    local seen = {}
    for c in (cuts or ""):gmatch("[^,]+") do
        if CUT_PARENT[c] then seen[c] = true; if not p.cuts[c] then p.cuts[c] = now end end
    end
    for c in pairs(p.cuts) do if not seen[c] then p.cuts[c] = nil; p.bleed[c] = nil end end
    p.heard = now
    local s = p.samples
    if #s > 0 and st <= s[#s].st then return end           -- (the same one again, or an old one)
    local d = unpack_pose(unb64(data))
    if not d then return end
    s[#s + 1] = { st = st, d = d }
    while #s > 8 do table.remove(s, 1) end
    -- (their clock against ours: the least lag seen, let out slowly so a slow spell is forgotten)
    local off = now - st
    if not p.off or off < p.off then p.off = off else p.off = p.off + (off - p.off) * 0.01 end
end

-- going to a friend: put beside them, on the same map (placed, not teleported: STORROR takes a teleport for a landing)
function M.go_to(id)
    local p = P[id]
    local pawn = lib.pawn()
    if not (p and pawn) then return false end
    local ok = pcall(function()
        local l = p.body:GetSocketLocation(FName("pelvis"))
        local r = p.actor:GetActorRightVector()
        pawn:K2_SetActorLocation({ X = l.X + r.X * 90.0, Y = l.Y + r.Y * 90.0, Z = l.Z + 40.0 }, false, {}, true)
    end)
    if ok then log("multiplayer: beside %s", p.name or "a friend") end
    return ok
end

-- ------------------------------------------------------------------------------------------- PvP
-- (as SM64Map's: PVP ON/OFF on the ONLINE screen, off at first. With it on for both, his punch or kick on a friend in
-- front of him knocks the friend down - the friend's own game puts him into his ragdoll, thrown the way it hit)
local PVP_FILE = lib.MOD_DIR .. "mp_settings.txt"
local pvp = nil
function M.pvp()
    if pvp == nil then
        pvp = false
        local f = io.open(PVP_FILE, "r")
        if f then pvp = (f:read("*a") or ""):find("pvp=1", 1, true) ~= nil; f:close() end
    end
    return pvp
end
function M.set_pvp(v)
    local on = (tonumber(v) or 0) >= 0.5
    if on == M.pvp() then return end
    pvp = on
    local f = io.open(PVP_FILE, "w")
    if f then f:write("pvp=", on and "1" or "0", "\n"); f:close() end
    log("multiplayer: PvP %s", on and "on" or "off")
end
M.PUNCH = { reach = 160.0, up = 130.0, push = 700.0, lift = 300.0, wait = 0.15 }
local punch_seen, punch_due = nil, nil
local function punch_tick(pawn, now)
    if not M.pvp() then return end
    local R = _G.AR
    local name = R and R.montage and R.montage(pawn) or ""
    local hit = name:lower():find("punch") or name:lower():find("kick") or name:lower():find("strike")
    if hit and name ~= punch_seen then punch_due = { t = now + M.PUNCH.wait } end
    punch_seen = hit and name or nil
    local d = punch_due
    if not (d and now >= d.t) then return end
    punch_due = nil
    local l, f = pawn:K2_GetActorLocation(), pawn:GetActorForwardVector()
    for id, p in pairs(P) do
        if id ~= "mirror" and M.peer_pvp[id] then
            local ok, t = pcall(function() return p.body:GetSocketLocation(FName("spine_03")) end)
            if ok and t then
                local dx, dy, dz = t.X - l.X, t.Y - l.Y, t.Z - l.Z
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < M.PUNCH.reach and math.abs(dz) < M.PUNCH.up and (dist < 1.0 or (dx * f.X + dy * f.Y) / dist > 0.2) then
                    local nx, ny = dist > 1.0 and dx / dist or f.X, dist > 1.0 and dy / dist or f.Y
                    M.send_event("hit", string.format("%.3f|%.3f", nx, ny), id)
                    log("multiplayer: hit %s", p.name or id)
                end
            end
        end
    end
end
-- a friend's punch or kick on him: knocked down that way, if PvP is on here too
M.on_event.hit = function(from, body)
    if not M.pvp() then return end
    local nx, ny = body:match("^([%d%.%-]+)|([%d%.%-]+)$")
    nx, ny = tonumber(nx), tonumber(ny)
    local R = _G.AR
    if not (nx and ny and R and R.knock) then return end
    pcall(R.knock, { x = nx * M.PUNCH.push, y = ny * M.PUNCH.push, z = M.PUNCH.lift })
    log("multiplayer: hit by a friend")
end

-- ------------------------------------------------------------------------------------------- each tick

local status_t, send_t, read_t = 0.0, 0.0, 0.0
local last_scene = nil
local function scene_now()
    local w = lib.world()
    if not w then return nil end
    local ok, n = pcall(function() return w:GetFName():ToString() end)
    return ok and n or nil
end
M.scene_now = scene_now

function M.tick(dt)
    if not started then start() end
    if not started then return end
    local now = os.clock()
    if now - status_t > 0.25 then
        status_t = now
        read_status()
        if not callbacks_on and fn_callbacks and M.status.state ~= "off" then
            callbacks_on = true
            pcall(fn_callbacks)
        end
    end
    local scene = scene_now()
    if scene ~= last_scene then
        last_scene = scene
        M.drop_all()
        if scene and M.in_lobby() then cmd("scene " .. scene) end
    end
    local lobby = M.in_lobby() and M.status.lobby or nil
    if lobby ~= M.joined_lobby then
        M.joined_lobby = lobby
        M.peer_scene, M.peer_pvp, M.peer_down = {}, {}, {}
        if scene and lobby then cmd("scene " .. scene) end
    end
    local pawn = lib.pawn()
    if pawn and scene then pcall(punch_tick, pawn, now) end
    local live = (M.in_lobby() and M.others() > 0) or M.MIRROR
    if not (pawn and scene and live) then
        if next(P) then M.drop_all() end
        return
    end
    -- his state, 20 times a second
    if now - send_t >= 1.0 / M.RATE then
        send_t = now
        local ok, data = pcall(my_pose, pawn)
        if ok and data then
            local line = string.format("S|1|%s|%.3f|%s|%s|%s|%s", scene, now, b64(data), M.pvp() and "1" or "0", my_down() and "1" or "0", my_cuts())
            if M.in_lobby() and M.others() > 0 then
                local f = io.open(NET .. "me.txt", "w")
                if f then f:write(line, "\n"); f:close() end
            end
            if M.MIRROR then M.mirror_line = line end
        end
    end
    -- the others' states, as the DLL has them
    if now - read_t >= 1.0 / 30.0 then
        read_t = now
        local seen = {}
        if M.in_lobby() then
            local f = io.open(NET .. "peers.txt", "r")
            local text = f and f:read("*a")
            if f then f:close() end
            for line in (text or ""):gmatch("[^\n]+") do
                local id, age, name, rest = line:match("^(%d+)|(%d+)|([^|]*)|(.*)$")
                if id and tonumber(age) < M.STALE * 1000 then
                    seen[id] = true
                    heard(id, name, rest, now, pawn, scene)
                end
            end
        end
        if M.MIRROR and M.mirror_line then
            seen.mirror = true
            heard("mirror", "Mirror", M.mirror_line, now, pawn, scene)
        end
        for id in pairs(P) do if not seen[id] then drop(id) end end
    end
    -- events
    if M.in_lobby() then
        local taken = NET .. "in_events.take"
        if os.rename(NET .. "in_events.txt", taken) then
            local f = io.open(taken, "r")
            local text = f and f:read("*a")
            if f then f:close() end
            os.remove(taken)
            for line in (text or ""):gmatch("[^\n]+") do
                local from, kind, body = line:match("^(%d+)|([^|]+)|?(.*)$")
                local h = from and M.on_event[kind]
                if h then pcall(h, from, body) end
            end
        end
    end
    for id, p in pairs(P) do
        if id == "mirror" then
            local side = { 0.0, 0.0 }
            pcall(function()
                local r = pawn:GetActorRightVector()
                side = { r.X * M.MIRROR_SIDE, r.Y * M.MIRROR_SIDE }
            end)
            pcall(draw, p, now, side, dt)
        else
            pcall(draw, p, now, nil, dt)
        end
    end
end

-- (a new map: its figures went with the old one)
function M.forget() P = {}; last_scene = nil end
function M.unload() M.drop_all() end
return M
