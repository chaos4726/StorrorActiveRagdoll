-- STORROR Active Ragdoll: the x-ray skeleton ("skate 3 skeleton", 2026-11-11). His real bones - BodyParts3D's anatomy
-- (xray_bones.lua, fitted to his skeleton by xray_build/fit.py; see CREDITS.txt) - each piece a procedural mesh fixed to the
-- bone of his body it moves with, so the skeleton moves as he does, ragdolled or not. A broken bone red, one put out orange;
-- a part cut off carries its bones with it on gore's flying copy of the part.
-- Seen through his body: the bones drawn in front of it - the engine's first-person drawing, pulled toward the camera by
-- its FirstPersonScale (`ONTOP.scale`) - only while his body is there to be seen through.
--   X-RAY ON BREAKS (the RAGDOLL tab): from a bone of his breaking until he stands up.
--   X-RAY BODY: all the while he's down.        X-RAY ALWAYS ON: all the time.
--   REMOVE PLAYER: his body (and gore's copies of him) hidden while the bones show - bones drawn as anything else then.
-- (Tried and dropped: plain cylinders for bones - "looks like shit"; a half see-through body - no material of the game's
-- draws his skin and clothes see-through, and drawn every other frame he never showed; slowing the game at a break - the
-- mod's pushes, worked by the real second, threw him off the ground.)
local lib = _G.ARLIB
local log = lib.log
local M = { VERSION = 14 }

local MAT = "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"   -- its "Color" a parameter
local PMC = "/Script/ProceduralMeshComponent.ProceduralMeshComponent"
local COLOR = { [0] = { R = 0.9, G = 0.87, B = 0.8, A = 1.0 }, [1] = { R = 1.0, G = 0.45, B = 0.05, A = 1.0 },
                [2] = { R = 1.0, G = 0.04, B = 0.03, A = 1.0 } }
M.MOMENT = { cooldown = 3.0 }
-- (`scale` 0.7: pulled 30% of the way to the camera - enough to clear his body (0.9 was not); at 0.2 the engine's motion
-- smoothing, not knowing the pull, smeared bones moving against the camera - "moving camera makes dismembered bones get all
-- fuzzy", 2026-11-11)
M.ONTOP = { scale = 0.7 }

local function asset(path)
    local a = StaticFindObject(path)
    if not (a and a:IsValid()) then pcall(function() a = LoadAsset(path) end) end
    return (a and a:IsValid()) and a or nil
end
local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- create_section's arguments by CreateMeshSection_LinearColor's own parameter names (as gore.lua does)
local sig = nil
local function create_section(pmc, id, verts, idx, nrms, uvs, cols)
    if sig == nil then
        sig = false
        local fn = StaticFindObject(PMC .. ":CreateMeshSection_LinearColor")
        if fn and fn:IsValid() then
            local names = {}
            local ok = pcall(function() fn:ForEachProperty(function(prop) names[#names + 1] = prop:GetFName():ToString() end) end)
            if ok and #names > 0 then sig = names end
        end
    end
    local args
    if sig then
        args = {}
        for i, name in ipairs(sig) do
            local n = name:lower()
            if n == "sectionindex" then args[i] = id
            elseif n == "vertices" then args[i] = verts
            elseif n == "triangles" then args[i] = idx
            elseif n == "normals" then args[i] = nrms
            elseif n == "uv0" then args[i] = uvs
            elseif n == "vertexcolors" then args[i] = cols
            elseif n:sub(1, 1) == "b" then args[i] = false
            else args[i] = {} end
        end
    else
        args = { id, verts, idx, nrms, uvs, {}, {}, {}, cols, {}, false, false }
    end
    pmc:CreateMeshSection_LinearColor(table.unpack(args, 1, #args))
end

-- ------------------------------------------------------------ the skeleton, made a STORROR bone's worth a frame
local SK = nil              -- { pawn, items = { { comp, part, col, bone, on } }, todo, shown, fp, removed, tick_opt, gore_hidden }
local PART_OF = { pelvis = "chest", spine_01 = "chest", spine_02 = "chest", spine_03 = "chest", spine_04 = "chest", spine_05 = "chest",
                  neck_01 = "head", neck_02 = "head", head = "head", ball_l = "foot_l", ball_r = "foot_r",
                  clavicle_l = "chest", clavicle_r = "chest" }
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local DATA = nil
local function data()
    if DATA == nil then
        local f, e = loadfile(lib.MOD_DIR .. "Scripts/xray_bones.lua")
        local ok, d = false, nil
        if f then ok, d = pcall(f) end
        DATA = (ok and type(d) == "table") and d or false
        if not DATA then log("x-ray: no bone data (%s)", tostring(e or d)) end
    end
    return DATA or nil
end
-- one STORROR bone's bones, a mesh fixed to it
local function make_piece(pawn, bone, d)
    local mesh = pawn.Mesh
    local mat, cls = asset(MAT), StaticFindObject(PMC)
    if not (mat and cls and cls:IsValid()) then return nil end
    local c = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not alive(c) then return nil end
    pcall(function() c:SetMobility(2) end)
    c:SetCollisionEnabled(0)
    pcall(function() c:SetCastShadow(false) end)
    pcall(function() c:SetReceivesDecals(false) end)
    c:K2_AttachToComponent(mesh, FName(bone), 2, 2, 2, false)
    local verts, nrms, uvs, cols, idx = {}, {}, {}, {}, {}
    local V, N, T = d.v, d.n, d.t
    local n = #V // 3
    for i = 1, n do
        local k = (i - 1) * 3
        verts[i] = { X = V[k + 1], Y = V[k + 2], Z = V[k + 3] }
        nrms[i] = { X = N[k + 1], Y = N[k + 2], Z = N[k + 3] }
        uvs[i] = { X = 0.0, Y = 0.0 }
        cols[i] = WHITE
    end
    -- (both faces: the winding is the model's, its handedness not the engine's)
    for i = 1, #T, 3 do
        local a, b, cc = T[i], T[i + 1], T[i + 2]
        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, b, cc
        idx[#idx + 1], idx[#idx + 2], idx[#idx + 3] = a, cc, b
    end
    create_section(c, 0, verts, idx, nrms, uvs, cols)
    local mid = c:CreateDynamicMaterialInstance(0, mat, FName("None"))
    if mid then mid:SetVectorParameterValue(FName("Color"), COLOR[0]) end
    if SK and SK.fp then pcall(function() c:SetFirstPersonPrimitiveType(1) end) end
    c:SetVisibility(false, false)
    return { comp = c, part = PART_OF[bone] or bone, col = 0, n = n, bone = bone }
end
local function build(pawn)
    local d = data()
    local todo = {}
    if d then
        for bone in pairs(d) do if type(d[bone]) == "table" and d[bone].v then todo[#todo + 1] = bone end end
        table.sort(todo)
    end
    return { pawn = pawn:GetAddress(), items = {}, todo = todo, shown = false, made = 0 }
end
local function build_step(pawn)
    if not SK or #SK.todo == 0 then return true end
    local bone = table.remove(SK.todo, 1)
    local d = data()
    local ok, it = pcall(function()
        if pawn.Mesh:GetBoneIndex(FName(bone)) < 0 then return nil end
        return make_piece(pawn, bone, d[bone])
    end)
    if ok and it then
        SK.items[#SK.items + 1] = it
        SK.made = SK.made + it.n
        if SK.shown then pcall(function() it.comp:SetVisibility(true, false) end) end
    elseif not ok and not M.build_err then
        M.build_err = true
        log("x-ray: %s's bones not made (%s)", bone, tostring(it))
    end
    if #SK.todo == 0 then log("x-ray: his skeleton made - %d pieces, %d points", #SK.items, SK.made) end
    return #SK.todo == 0
end

-- ------------------------------------------------------------ shown, drawn in front, his body hidden
local function body_comps(pawn)
    local out = {}
    pcall(function()
        local arr = pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.MeshComponent"))
        for i = 1, #arr do
            local c = arr[i]:get()
            if c and c:IsValid() then out[#out + 1] = c end
        end
    end)
    return out
end
local function mine_set()
    local mine = {}
    for _, it in ipairs(SK.items) do pcall(function() mine[it.comp:GetAddress()] = true end) end
    return mine
end
local cam_saved = nil      -- { { cam, enable, scale } }
local function cams_on(pawn, on)
    if on then
        if cam_saved then return end
        cam_saved = {}
        pcall(function()
            local arr = pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.CameraComponent"))
            for i = 1, #arr do
                local c = arr[i]:get()
                if c and c:IsValid() then
                    cam_saved[#cam_saved + 1] = { c, c.bEnableFirstPersonScale, c.FirstPersonScale }
                    c.bEnableFirstPersonScale = true
                    c.FirstPersonScale = M.ONTOP.scale
                end
            end
        end)
    else
        for _, e in ipairs(cam_saved or {}) do
            pcall(function() if e[1]:IsValid() then e[1].bEnableFirstPersonScale = e[2]; e[1].FirstPersonScale = e[3] end end)
        end
        cam_saved = nil
    end
end
-- (drawn in front - first-person, the camera's scale on - only while his body is there to see them through: with REMOVE
-- PLAYER nothing hides them, and drawn as anything else they don't smear as the camera moves - "still fizzy", 2026-11-11)
function M.fp_mode(pawn, on)
    if not SK then return end
    if (SK.fp and true or false) == on then return end
    SK.fp = on
    cams_on(pawn, on)
    for _, it in ipairs(SK.items) do pcall(function() it.comp:SetFirstPersonPrimitiveType(on and 1 or 0) end) end
end
local function show(pawn, on)
    if not SK or SK.shown == on then return end
    SK.shown = on
    if not on then M.fp_mode(pawn, false) end
    for _, it in ipairs(SK.items) do pcall(function() it.comp:SetVisibility(on and it.col ~= 3, false) end) end
end
-- (REMOVE PLAYER: his body - every mesh of his but the skeleton's - hidden while the skeleton shows; put back as it was. His
-- body animated though not drawn: STORROR's "only tick the pose when drawn" left it, and the bones on it, in the T-pose -
-- "its just tposing", 2026-11-11)
function M.remove_body(pawn, on)
    if not SK then return end
    if on == (SK.removed and true or false) then return end
    if on then
        local mine = mine_set()
        SK.removed = {}
        pcall(function()
            SK.tick_opt = pawn.Mesh.VisibilityBasedAnimTickOption
            pawn.Mesh.VisibilityBasedAnimTickOption = 0
        end)
        for _, c in ipairs(body_comps(pawn)) do
            pcall(function()
                if not mine[c:GetAddress()] and c:IsVisible() then c:SetVisibility(false, false); SK.removed[#SK.removed + 1] = c end
            end)
        end
    else
        for _, c in ipairs(SK.removed or {}) do pcall(function() if c:IsValid() then c:SetVisibility(true, false) end end) end
        SK.removed = nil
        if SK.tick_opt ~= nil then
            pcall(function() pawn.Mesh.VisibilityBasedAnimTickOption = SK.tick_opt end)
            SK.tick_opt = nil
        end
    end
end
-- (gore's state: its parts torn off - each its own actor, a copy of him, with `pose` - and its copy of his body)
local function gore_st()
    local G = _G.ARGORE
    if not (G and debug and debug.getupvalue and G.gone) then return nil end
    for i = 1, 40 do
        local n, v = debug.getupvalue(G.gone, i)
        if not n then break end
        if n == "st" then return type(v) == "table" and v or nil end
    end
    return nil
end
local function gore_pieces()
    local G = _G.ARGORE
    if G and G.pieces then local ok, p = pcall(G.pieces); return ok and p or nil end
    local s = gore_st()
    return s and s.pieces or nil
end
-- (REMOVE PLAYER and gore: gore's copies of him hidden too while his body is - else his body came back on every part cut
-- off, "body showing back up on dismemebered limbs", 2026-11-11; put back as they were. The bones on them are his own and
-- stay seen)
function M.remove_gore(on)
    if not SK then return end
    if on then
        local G = gore_st()
        if not G then return end
        SK.gore_hidden = SK.gore_hidden or {}
        local acts = {}
        for _, piece in pairs(G.pieces or {}) do if piece.actor then acts[#acts + 1] = piece.actor end end
        if G.torso and G.torso.actor then acts[#acts + 1] = G.torso.actor end
        for _, a in ipairs(acts) do
            pcall(function()
                if a:IsValid() and not a.bHidden then
                    a:SetActorHiddenInGame(true)
                    SK.gore_hidden[#SK.gore_hidden + 1] = a
                end
            end)
        end
    else
        for _, a in ipairs(SK.gore_hidden or {}) do pcall(function() if a:IsValid() then a:SetActorHiddenInGame(false) end end) end
        SK.gore_hidden = nil
    end
end
-- (anything of his shown again since - gore puts his body and head back as he gets up)
local function keep_removed(pawn)
    local mine = mine_set()
    local had = {}
    for _, c in ipairs(SK.removed or {}) do pcall(function() had[c:GetAddress()] = true end) end
    for _, c in ipairs(body_comps(pawn)) do
        pcall(function()
            if not mine[c:GetAddress()] and c:IsVisible() then
                c:SetVisibility(false, false)
                if SK.removed and not had[c:GetAddress()] then SK.removed[#SK.removed + 1] = c end
            end
        end)
    end
    pcall(function() if pawn.Mesh.VisibilityBasedAnimTickOption ~= 0 then pawn.Mesh.VisibilityBasedAnimTickOption = 0 end end)
end

-- ------------------------------------------------------------ each bone's colour, and where it is
-- (a part torn off: its bones go with it, fixed to the same bones of gore's copy of the part that flies off - "make bones
-- still show on severed limbs", 2026-11-11)
local function piece_pose(part, pieces)
    local G = _G.ARGORE
    if not (pieces and G and G.regions_of) then return nil end
    for pid, piece in pairs(pieces) do
        local ok, regs = pcall(G.regions_of, pid)
        if ok and regs then
            for _, rg in ipairs(regs) do
                if rg == part and piece.pose and alive(piece.pose) then return piece.pose end
            end
        end
    end
    return nil
end
local function paint(parts)
    -- (his skull and neck out of sight while the camera is in his head - drawn in front, they filled the screen in first person)
    local cam_in_head = false
    pcall(function()
        local cl = lib.controller().PlayerCameraManager:GetCameraLocation()
        local hp = lib.pawn().Mesh:GetSocketLocation(FName("head"))
        local dx, dy, dz = cl.X - hp.X, cl.Y - hp.Y, cl.Z - hp.Z
        cam_in_head = dx * dx + dy * dy + dz * dz < 45.0 * 45.0
    end)
    local pieces = gore_pieces()
    local pawn = lib.pawn()
    for _, it in ipairs(SK.items) do
        local e = parts and parts[it.part]
        local s = e and e.state or 0
        -- (torn off: onto the flying part, seen, red; back onto him once the part is gone or he's whole again)
        if s == 3 then
            local pose = piece_pose(it.part, pieces)
            if pose then
                if it.on ~= pose then
                    pcall(function() it.comp:K2_AttachToComponent(pose, FName(it.bone), 2, 2, 2, false) end)
                    it.on = pose
                end
                s = 2
            end
        end
        if it.on and (s ~= 2 or not alive(it.on)) and not (e and e.state == 3 and piece_pose(it.part, pieces) == it.on) then
            pcall(function() it.comp:K2_AttachToComponent(pawn.Mesh, FName(it.bone), 2, 2, 2, false) end)
            it.on = nil
        end
        if it.part == "head" and cam_in_head and not it.on then s = 3 end
        pcall(function()
            if s == 3 then
                if it.col ~= 3 then it.comp:SetVisibility(false, false); it.col = 3 end
            else
                if it.col == 3 and SK.shown then it.comp:SetVisibility(true, false) end
                if it.col ~= s then
                    local mid = it.comp:GetMaterial(0)
                    if mid then mid:SetVectorParameterValue(FName("Color"), COLOR[s] or COLOR[0]) end
                    it.col = s
                end
            end
        end)
    end
end

-- ------------------------------------------------------------ every frame
local was = {}                -- each part's state last frame
local moment = false          -- (shown since a bone broke, till he stands up)
local last_moment = -99.0
local paint_t, gore_t = 0.0, 0.0
function M.tick(dt)
    local Mn = _G.ARMENU
    local on_breaks = Mn and Mn.xray_breaks and Mn.xray_breaks()
    local on_body = Mn and Mn.xray_body and Mn.xray_body()
    local on_always = Mn and Mn.xray_always and Mn.xray_always()
    local remove = Mn and Mn.remove_player and Mn.remove_player()
    local pawn = lib.pawn()
    local R = _G.AR
    if not (pawn and R and R.state and R.parts) then return end
    local st = R.state()
    local down = st and st.down
    local parts = R.parts()
    local now = os.clock()
    if SK and SK.pawn ~= pawn:GetAddress() then SK = nil end
    -- (made beforehand, while he stands - a piece a frame: no stall as a bone breaks)
    if (on_breaks or on_body or on_always) and not SK and now - (M.build_t or -99.0) > 5.0 then
        M.build_t = now
        local ok, r = pcall(build, pawn)
        SK = ok and r or nil
        if not ok then log("x-ray: no skeleton (%s)", tostring(r)) end
    end
    if SK and #SK.todo > 0 then pcall(build_step, pawn) end
    -- (a bone just broken while he's down: shown till he stands up - "stay until the player stands up")
    local fresh = false
    for id, e in pairs(parts or {}) do
        local s = e.state or 0
        if s == 2 and (was[id] or 0) < 2 then fresh = true end
        was[id] = s
    end
    if fresh and down and on_breaks and SK and not moment and now - last_moment > M.MOMENT.cooldown then
        moment, last_moment = true, now
    end
    if moment and not down then moment = false end
    if not SK then return end
    local want = moment or (down and on_body) or on_always
    if want and not SK.shown then paint(parts) end
    show(pawn, want and true or false)
    M.remove_body(pawn, SK.shown and remove and true or false)
    M.fp_mode(pawn, SK.shown and not remove and true or false)
    if SK.shown and remove then
        gore_t = gore_t - dt
        if gore_t <= 0.0 then
            gore_t = 0.1
            pcall(M.remove_gore, true)
            pcall(keep_removed, pawn)
        end
    elseif SK.gore_hidden then
        pcall(M.remove_gore, false)
    end
    if SK.shown then
        paint_t = paint_t - dt
        if paint_t <= 0.0 then paint_t = 0.1; paint(parts) end
    end
end

-- (the skeleton's state, for a look from the dev channel)
function M.debug() return SK end
-- (a new map: the skeleton was the old pawn's)
function M.forget()
    cam_saved = nil
    SK, was, moment = nil, {}, false
end
function M.unload()
    local pawn = lib.pawn()
    if pawn then
        pcall(M.fp_mode, pawn, false)
        pcall(M.remove_gore, false)
        pcall(M.remove_body, pawn, false)
        pcall(cams_on, pawn, false)
        pcall(show, pawn, false)
    end
    if SK then for _, it in ipairs(SK.items) do pcall(function() if it.comp:IsValid() then it.comp:K2_DestroyComponent(it.comp) end end) end end
    SK = nil
end
return M
