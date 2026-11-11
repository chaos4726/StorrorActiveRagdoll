-- STORROR Active Ragdoll: the ragdoll itself (main.lua runs M.tick every frame).
--
-- Everything here acts only while STORROR's own ragdoll has him (its "Ragdoll" montage playing, after a bail), and does
-- what Lincoln Margison's two videos do to a ragdoll ("watch this video and do exactly what he does with the storror
-- model", 2026-11-10; notes in VIDEO_NOTES.md):
--   SOFT LIMITS   - each joint slows as it nears the end of its range, as muscles and tendons at full stretch would,
--                   instead of running into the end at full speed and bouncing off it (STORROR's joints have soft limits
--                   already, but so lightly damped that they bounce: their range ends moved in a little and damped);
--   TENSION       - every joint gently pulled toward the Neutral Body Posture, the pose a body floats into in
--                   microgravity (NASA): legs bent at hip and knee, feet pointed, shoulders rolled forward, arms forward,
--                   elbows bent, head a little forward;
--   LIMB IMPACT   - at every impact the shoulders and legs get a spin too, randomized per limb: arms thrown the way the
--                   force goes, legs the other way (the feet held back by the ground);
--   FALL ANIMATION- the body pulled a little toward STORROR's own falling flail while it is a ragdoll, the flail played
--                   faster while he goes up and slower as he comes down;
--   PROTECT HEAD  - falling fast with the ground close, he blends toward covering his head with his knees drawn up;
--   DISLOCATION   - a joint that runs past the end of its range fast enough dislocates: its range is widened and its
--                   pull moved to where it broke, so it stays hyper-extended for good, with a jolt to the limb, STORROR's
--                   bone-break sound and a line on the screen ("Dislocated: Right elbow").
local lib = _G.ARLIB
local M = { VERSION = 226 }
-- (`verbose`: the dev readouts - his mind every few s, each jump, each stop - in the log again)
M.LOG = { verbose = false }
local log = lib.log
local sqrt, abs, min, max, random, acos, atan, deg, rad = math.sqrt, math.abs, math.min, math.max, math.random, math.acos, math.atan, math.deg, math.rad

-- the numbers (the dev channel can change any of them live)
M.CFG = {
    -- (`limit_k` 4 -> 10: STORROR's joints are soft springs - 50 to 1000 - and he folded far past their ends, a leg over his
    -- head; "body gets contorted in very weird ways its not natural", 2026-11-10)
    soft_limits = true, limit_scale = 0.85, limit_k = 10.0, limit_damp = 1.3,   -- (range ends x0.8; spring x2; damping x critical)
    tension = true, tension_hz = 1.0, tension_spine_hz = 2.5, tension_head_hz = 3.0, tension_damp = 1.0,
    -- (`limb_impact` off, 2026-11-11: his arms and legs flung about at a blow by a turn given to each alone - a spin from
    -- nowhere; the blow itself moves them)
    limb_impact = false, impact_deg = 520.0, impact_rand = 0.45, impact_from_v = 250.0,
    head_rest = 0.0,      -- (his neck's tone lying on the ground: none - at a sixth of it his head still stood up off the floor)
    -- (all his tone lying on the ground, of what it is in the air - his breathing's hold on his back too: at full tone the
    -- posture held him half sat up, "like hes in the middle of trying to stand on his own", flopping only as he tired,
    -- "he ragdolls after about 30 seconds", 2026-11-10)
    ground_tone = 0.5,    -- (0.25 let him fold up anyhow)
    ground_reach = 125.0,
    -- (`fall_anim` and `stagger` off, 2026-11-11 - "he stops spinning", "bodys doing some weird ass lean?": both pulled each
    -- part of him toward an animation's pose by Unreal's Physical Animation, whose pull is against a target the engine
    -- moves, not against the part above - nothing pulled back: a turn of all of him from outside. Each part's target is
    -- set from the part above a frame late, so in a tumble it held every part back against the spin. His own muscles -
    -- the controls between each part and the one above, all inside him - hold his pose instead)
    fall_anim = false, fall_k = 260.0, rate_up = 1.6, rate_down = 0.55, ground_fade = 0.5,
    protect = true, protect_hz = 6.0, protect_vz = -380.0, protect_t = 0.55, protect_in = 5.0, protect_out = 1.5,
    -- (the ragdoll taking him from the top down, as the video's active ragdoll: the upper body let go over `stagger_up` s,
    -- the legs held to the animation a little longer, let go from `stagger_legs_from` to `stagger_legs` s)
    stagger = false, stagger_k = 2500.0, stagger_up = 0.22, stagger_legs_from = 0.12, stagger_legs = 0.45,
    -- (a thud for each hard blow: from `thud_from` cm/s, at most one every `thud_every` s)
    thuds = true, thud_from = 650.0, thud_every = 0.12,
    dislocate = false, dislocate_over = 35.0, dislocate_rate = 500.0, dislocate_jolt = 420.0, dislocate_grace = 0.12,
}

-- (25, 2026-11-11: at 4 his arms stayed 50-70 degrees from where they were meant to be in a tumble, at 25 within 4-8;
-- his spine, neck and head the same, or his chest twisted on his hips, one hand up and one down, his head turned)
M.CFG.air_arm_hz, M.CFG.air_arm_stun_hz, M.CFG.air_clav_hz = 25.0, 6.0, 80.0
M.POSE_MOST = {}
M.MIRROR_ARMS = false
-- (all of the air's own arm work off - its tone, its raised pose, the mirroring, the clamp, the shoulders' widening: "it looks
-- terrible just return it to its original look", 2026-11-11. Kept here, empty, should it be wanted again)
M.AIR_ARMS = {}
M.USE_AIR_POSE = false
local FN = setmetatable({}, { __index = function(t, k) local v = FName(k); t[k] = v; return v end })

-- ------------------------------------------------------------------ vector and quaternion helpers
local function v3(x, y, z) return { x = x, y = y, z = z } end
local function vadd(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
local function vsub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function vmul(a, k) return { x = a.x * k, y = a.y * k, z = a.z * k } end
local function vdot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vlen(a) return sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vnorm(a) local l = vlen(a); if l < 1e-6 then return v3(0.0, 0.0, 0.0) end; return vmul(a, 1.0 / l) end
local function vcross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
-- (sums of vectors with weights, normalized: mix(a, ka, b, kb, ...))
local function mix(...)
    local a = { ... }
    local v = v3(0.0, 0.0, 0.0)
    for i = 1, #a, 2 do v.x, v.y, v.z = v.x + a[i].x * a[i + 1], v.y + a[i].y * a[i + 1], v.z + a[i].z * a[i + 1] end
    return vnorm(v)
end
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function qinv(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end
local function qrot(q, v)
    local u = v3(q.x, q.y, q.z)
    local t = vmul(vcross(u, v), 2.0)
    return vadd(vadd(v, vmul(t, q.w)), vcross(u, t))
end
-- (the turn taking direction u onto v the short way)
local function qarc(u, v)
    local d = vdot(u, v)
    if d < -0.9999 then
        local ax = vnorm(v3(0.0, -u.z, u.y))
        if vlen(ax) < 0.5 then ax = v3(0.0, 0.0, 1.0) end
        return { x = ax.x, y = ax.y, z = ax.z, w = 0.0 }
    end
    local c = vcross(u, v)
    local q = { x = c.x, y = c.y, z = c.z, w = 1.0 + d }
    local n = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end
local function qnlerp(a, b, t)
    local s = (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) < 0.0 and -1.0 or 1.0
    local q = { x = a.x + (b.x * s - a.x) * t, y = a.y + (b.y * s - a.y) * t, z = a.z + (b.z * s - a.z) * t, w = a.w + (b.w * s - a.w) * t }
    local n = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end
-- (Unreal's FQuat::Rotator)
local function q2rot(q)
    local R2D = 180.0 / math.pi
    local sing = q.z * q.x - q.w * q.y
    local yy, yx = 2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    if sing < -0.4999995 then
        local yaw = atan(yy, yx) * R2D
        return { Pitch = -90.0, Yaw = yaw, Roll = -yaw - 2.0 * atan(q.x, q.w) * R2D }
    elseif sing > 0.4999995 then
        local yaw = atan(yy, yx) * R2D
        return { Pitch = 90.0, Yaw = yaw, Roll = yaw - 2.0 * atan(q.x, q.w) * R2D }
    end
    return { Pitch = math.asin(2.0 * sing) * R2D, Yaw = atan(yy, yx) * R2D,
             Roll = atan(-2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)) * R2D }
end
local function fv(u) return { X = u.x, Y = u.y, Z = u.z } end
local function rnd(a, b) return a + (b - a) * random() end

-- ------------------------------------------------------------------ the skeleton: the controlled joints
-- (each joint between a body and its parent body in STORROR's ragdoll, m_med_nrw_ragdoll; tip: the bone its length runs
-- to, for its direction; kind: what pose wants of it. Parents before children.)
local CHAIN = {
    { b = "spine_02", p = "pelvis", tip = "spine_03", kind = "spine" },
    { b = "spine_03", p = "spine_02", tip = "spine_04", kind = "spine" },
    { b = "spine_04", p = "spine_03", tip = "spine_05", kind = "spine" },
    { b = "spine_05", p = "spine_04", tip = "neck_01", kind = "spine" },
    { b = "neck_01", p = "spine_05", tip = "head", kind = "neck" },
    { b = "head", p = "neck_01", kind = "head" },
}
local NAMES = { clavicle = "collarbone", upperarm = "shoulder", lowerarm = "elbow", hand = "wrist", thigh = "hip", calf = "knee", foot = "ankle" }
for _, s in ipairs({ "l", "r" }) do
    local function b(n) return n .. "_" .. s end
    for _, e in ipairs({
        { b = b("clavicle"), p = "spine_05", tip = b("upperarm"), kind = "clav" },
        { b = b("upperarm"), p = b("clavicle"), tip = b("lowerarm"), kind = "upper" },
        { b = b("lowerarm"), p = b("upperarm"), tip = b("hand"), kind = "fore" },
        { b = b("hand"), p = b("lowerarm"), tip = b("middle_01"), kind = "hand" },
        { b = b("thigh"), p = "pelvis", tip = b("calf"), kind = "thigh" },
        { b = b("calf"), p = b("thigh"), tip = b("foot"), kind = "calf" },
        { b = b("foot"), p = b("calf"), tip = b("ball"), kind = "foot" },
    }) do
        e.s = s
        e.label = (s == "l" and "Left " or "Right ") .. NAMES[e.b:match("^(%a+)_")]
        CHAIN[#CHAIN + 1] = e
    end
end
local BY_BONE = {}
local LABELS = { neck_01 = "Neck", head = "Head", spine_02 = "Lower back", spine_03 = "Back", spine_04 = "Back", spine_05 = "Upper back" }
for _, e in ipairs(CHAIN) do BY_BONE[e.b] = e; e.label = e.label or LABELS[e.b] or e.b end

-- What each pose wants of each kind of bone: its direction in the torso's frame (r: his right, f: forward, u: up the
-- spine; o: out to its own side), or, for the spine, neck and head, a lean forward on top of the reference pose.
local POSES = {
    -- The Neutral Body Posture (NASA's microgravity posture, which the video loosely follows). Elbows and knees bend round
    -- their own hinge (STORROR's ragdoll lets them bend no other way), by `hinge` degrees; the feet point a little along
    -- the shin (`pd`: the parent's direction)
    nbp = {
        spine = function(F, d) return mix(d, 1.0, F.f, 0.07) end,
        neck = function(F, d) return mix(d, 1.0, F.f, 0.2) end,
        head = function(F, d) return mix(d, 1.0, F.f, 0.22) end,
        clav = function(F, d) return mix(d, 1.0, F.f, 0.22) end,
        upper = function(F, d, o) return mix(o, 0.5, F.f, 0.55, F.u, -0.55) end,
        fore = { hinge = 70.0 },
        thigh = function(F, d, o) return mix(o, 0.14, F.f, 0.77, F.u, -0.64) end,
        calf = { hinge = 50.0 },
        foot = function(F, d, o, pd) return mix(d, 1.0, pd, 0.3) end,
    },
    -- Protecting the head: hands over it, elbows up in front, knees drawn up, chin tucked, back curled
    protect = {
        spine = function(F, d) return mix(d, 1.0, F.f, 0.18) end,
        neck = function(F, d) return mix(d, 1.0, F.f, 0.35) end,
        head = function(F, d) return mix(d, 1.0, F.f, 0.35) end,
        clav = function(F, d) return mix(d, 1.0, F.f, 0.2, F.u, 0.12) end,
        upper = function(F, d, o) return mix(o, 0.45, F.f, 0.55, F.u, 0.7) end,
        fore = { hinge = 120.0 },
        -- (his legs a little bent, not drawn up to his chest - "legs should only be brought up to chest when arms reach for them", 2026-11-10)
        thigh = function(F, d, o) return mix(o, 0.15, F.f, 0.6, F.u, -0.8) end,
        calf = { hinge = 60.0 },
        foot = function(F, d, o, pd) return mix(d, 1.0, pd, 0.3) end,
    },
}

-- Falling, covering his face for the impact: forearms crossed tight over it, elbows together in front, chin tucked, his
-- legs only a little bent ("covering face for impact", "a face cover one", 2026-11-11)
POSES.cover = {
    spine = function(F, d) return mix(d, 1.0, F.f, 0.22) end,
    neck = function(F, d) return mix(d, 1.0, F.f, 0.5) end,
    head = function(F, d) return mix(d, 1.0, F.f, 0.5) end,
    clav = function(F, d) return mix(d, 1.0, F.f, 0.35, F.u, 0.15) end,
    upper = function(F, d, o) return mix(o, -0.2, F.f, 0.75, F.u, 0.6) end,
    fore = { hinge = 155.0 },
    thigh = function(F, d, o) return mix(o, 0.1, F.f, 0.3, F.u, -0.95) end,
    calf = { hinge = 35.0 },
    foot = function(F, d, o, pd) return mix(d, 1.0, pd, 0.3) end,
}
-- A cannonball: knees pulled hard up to his chest, back curled round them, arms wrapped round his shins, chin down ("make a
-- cannon ball one", 2026-11-11)
-- (its knees no higher than his own pain's curl: drawn past his hips' range, the joints fought their limits all through the
-- fall and he rose into the air - "the tuck fall actually makes the player fly", "I mean literally flying", 2026-11-11)
POSES.ball = {
    spine = function(F, d) return mix(d, 1.0, F.f, 0.32) end,
    neck = function(F, d) return mix(d, 1.0, F.f, 0.45) end,
    head = function(F, d) return mix(d, 1.0, F.f, 0.45) end,
    clav = function(F, d) return mix(d, 1.0, F.f, 0.25) end,
    upper = function(F, d, o) return mix(o, 0.15, F.f, 0.85, F.u, -0.2) end,
    fore = { hinge = 90.0 },
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.8, F.u, 0.42) end,
    calf = { hinge = 135.0 },
    foot = function(F, d, o, pd) return mix(d, 1.0, pd, 0.5) end,
}
-- Diving: arms straight out over his head, his body long, legs together, toes pointed ("diving", 2026-11-11)
POSES.dive = {
    spine = function(F, d) return mix(d, 1.0, F.f, -0.06) end,
    neck = function(F, d) return mix(d, 1.0, F.f, -0.1) end,
    head = function(F, d) return mix(d, 1.0, F.f, -0.1) end,
    clav = function(F, d) return mix(d, 1.0, F.u, 0.25) end,
    upper = function(F, d, o) return mix(o, 0.1, F.u, 1.0, F.f, 0.25) end,
    fore = { hinge = 8.0 },
    thigh = function(F, d, o) return mix(o, 0.05, F.u, -1.0, F.f, -0.04) end,
    calf = { hinge = 6.0 },
    foot = function(F, d, o, pd) return mix(d, 1.0, pd, 0.9) end,
}

-- In the air: both arms up and out, spread, a little bent at the elbow ("bring both arms up", 2026-11-11); as high as his
-- shoulders' range lets them (POSE_MOST)
POSES.air = setmetatable({
    upper = function(F, d, o) return mix(o, 0.85, F.u, 0.5, F.f, 0.15) end,
    fore = { hinge = 20.0 },
}, { __index = POSES.nbp })
-- More falls ("make more falling poses", 2026-11-11): STARFISH - all four limbs spread wide; PENCIL - arms tight at his sides,
-- legs straight together; SUPERMAN - arms out ahead over his head, legs straight back; SEATED - as in a chair; FETAL - curled
-- up tight, hugging himself; BRACE - arms out in front for the ground
POSES.starfish = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, -0.05) end,
    upper = function(F, d, o) return mix(o, 1.0, F.u, 0.15, F.f, 0.05) end,
    fore = { hinge = 10.0 },
    thigh = function(F, d, o) return mix(o, 0.55, F.u, -0.85) end,
    calf = { hinge = 10.0 },
}, { __index = POSES.nbp })
POSES.pencil = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.0) end,
    upper = function(F, d, o) return mix(o, 0.15, F.u, -1.0) end,
    fore = { hinge = 5.0 },
    thigh = function(F, d, o) return mix(o, 0.03, F.u, -1.0) end,
    calf = { hinge = 3.0 },
}, { __index = POSES.nbp })
POSES.superman = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, -0.08) end,
    head = function(F, d) return mix(d, 1.0, F.f, -0.15) end,
    upper = function(F, d, o) return mix(F.f, 1.0, F.u, 0.35, o, 0.25) end,
    fore = { hinge = 10.0 },
    thigh = function(F, d, o) return mix(F.u, -1.0, F.f, -0.25, o, 0.08) end,
    calf = { hinge = 10.0 },
}, { __index = POSES.nbp })
POSES.seated = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.12) end,
    upper = function(F, d, o) return mix(o, 0.6, F.f, 0.5, F.u, -0.4) end,
    fore = { hinge = 60.0 },
    thigh = function(F, d, o) return mix(F.f, 1.0, o, 0.12, F.u, -0.1) end,
    calf = { hinge = 90.0 },
}, { __index = POSES.nbp })
POSES.fetal = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.3) end,
    neck = function(F, d) return mix(d, 1.0, F.f, 0.4) end,
    head = function(F, d) return mix(d, 1.0, F.f, 0.4) end,
    upper = function(F, d, o) return mix(o, 0.2, F.f, 0.9, F.u, 0.1) end,
    fore = { hinge = 120.0 },
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.8, F.u, 0.42) end,
    calf = { hinge = 130.0 },
}, { __index = POSES.nbp })
POSES.brace = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.1) end,
    upper = function(F, d, o) return mix(F.f, 0.9, F.u, -0.5, o, 0.3) end,
    fore = { hinge = 25.0 },
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.35, F.u, -0.9) end,
    calf = { hinge = 30.0 },
}, { __index = POSES.nbp })
-- Still more ("make more poses", 2026-11-11), some one-sided - `R(F, o)`: is this his right side. RUNNER - running in the
-- air, an arm and the other leg forward; SCISSOR - legs split, one ahead, one back; SKYDIVER - arched belly down, arms
-- and knees bent; PINWHEEL - one arm up, one down, legs spread; HEADHOLD - hands behind his head; PIKE - folded at the
-- hips, legs out straight ahead; ARCH - bent back, arms and legs behind; KNEEL - knees bent hard under him; HUG - arms
-- wrapped across his chest
local function R(F, o) return vdot(o, F.r) > 0.0 end
POSES.runner = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.1) end,
    upper = function(F, d, o) if R(F, o) then return mix(F.f, 0.8, F.u, -0.3, o, 0.2) end return mix(F.f, -0.6, F.u, -0.6, o, 0.25) end,
    fore = { hinge = 85.0 },
    thigh = function(F, d, o) if R(F, o) then return mix(F.f, -0.5, F.u, -0.85, o, 0.05) end return mix(F.f, 0.85, F.u, -0.3, o, 0.05) end,
    calf = { hinge = 70.0 },
}, { __index = POSES.nbp })
POSES.scissor = setmetatable({
    upper = function(F, d, o) return mix(o, 1.0, F.u, 0.1) end,
    fore = { hinge = 15.0 },
    thigh = function(F, d, o) if R(F, o) then return mix(F.f, 0.9, F.u, -0.4, o, 0.1) end return mix(F.f, -0.6, F.u, -0.8, o, 0.1) end,
    calf = { hinge = 20.0 },
}, { __index = POSES.nbp })
POSES.skydiver = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, -0.12) end,
    head = function(F, d) return mix(d, 1.0, F.f, -0.2) end,
    upper = function(F, d, o) return mix(o, 1.0, F.f, 0.15, F.u, 0.25) end,
    fore = { hinge = 90.0 },
    thigh = function(F, d, o) return mix(o, 0.35, F.u, -0.9, F.f, -0.15) end,
    calf = { hinge = 80.0 },
}, { __index = POSES.nbp })
POSES.pinwheel = setmetatable({
    upper = function(F, d, o) if R(F, o) then return mix(o, 0.6, F.u, 0.8) end return mix(o, 0.6, F.u, -0.8) end,
    fore = { hinge = 10.0 },
    thigh = function(F, d, o) return mix(o, 0.6, F.u, -0.8) end,
    calf = { hinge = 10.0 },
}, { __index = POSES.nbp })
POSES.headhold = setmetatable({
    neck = function(F, d) return mix(d, 1.0, F.f, 0.3) end,
    upper = function(F, d, o) return mix(o, 0.7, F.u, 0.6, F.f, -0.1) end,
    fore = { hinge = 140.0 },
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.3, F.u, -0.9) end,
    calf = { hinge = 30.0 },
}, { __index = POSES.nbp })
POSES.pike = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.25) end,
    upper = function(F, d, o) return mix(F.f, 0.9, F.u, -0.2, o, 0.15) end,
    fore = { hinge = 5.0 },
    thigh = function(F, d, o) return mix(F.f, 1.0, F.u, 0.05, o, 0.05) end,
    calf = { hinge = 5.0 },
}, { __index = POSES.nbp })
POSES.arch = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, -0.2) end,
    neck = function(F, d) return mix(d, 1.0, F.f, -0.3) end,
    head = function(F, d) return mix(d, 1.0, F.f, -0.3) end,
    upper = function(F, d, o) return mix(F.f, -0.6, o, 0.6, F.u, -0.5) end,
    fore = { hinge = 10.0 },
    thigh = function(F, d, o) return mix(F.f, -0.4, F.u, -0.9, o, 0.05) end,
    calf = { hinge = 40.0 },
}, { __index = POSES.nbp })
POSES.kneel = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.05) end,
    upper = function(F, d, o) return mix(o, 0.5, F.f, 0.4, F.u, -0.6) end,
    fore = { hinge = 45.0 },
    thigh = function(F, d, o) return mix(F.u, -0.6, F.f, 0.75, o, 0.12) end,
    calf = { hinge = 125.0 },
}, { __index = POSES.nbp })
POSES.hug = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.15) end,
    upper = function(F, d, o) return mix(F.f, 0.9, o, -0.1, F.u, -0.1) end,
    fore = { hinge = 130.0 },
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.35, F.u, -0.9) end,
    calf = { hinge = 40.0 },
}, { __index = POSES.nbp })
-- The legs in pain: curled up to the chest, and kicked out (the kicking goes between the two; the rest of him as in the
-- neutral posture)
POSES.curl = setmetatable({
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.8, F.u, 0.45) end,
    calf = { hinge = 140.0 },
}, { __index = POSES.nbp })
-- (reaching his own shin or foot: the knee drawn right up to his chest, the heel in, his back curled hard forward - he
-- sits up into it - "still cant reach his feet when trying to grab", 2026-11-10)
POSES.reach = setmetatable({
    spine = function(F, d) return mix(d, 1.0, F.f, 0.38) end,
    neck = function(F, d) return mix(d, 1.0, F.f, 0.5) end,
    thigh = function(F, d, o) return mix(o, 0.08, F.f, 0.55, F.u, 0.85) end,
    calf = { hinge = 150.0 },
}, { __index = POSES.nbp })
-- (a kick drawn in: the knee about half way up and bent, well short of his chest - from his resting bend his kicks hardly
-- showed, 2026-11-10)
POSES.draw = setmetatable({
    thigh = function(F, d, o) return mix(o, 0.12, F.f, 0.85, F.u, -0.5) end,
    calf = { hinge = 100.0 },
}, { __index = POSES.nbp })
POSES.kick = setmetatable({
    thigh = function(F, d, o) return mix(o, 0.1, F.f, 0.95, F.u, -0.2) end,
    calf = { hinge = 15.0 },
}, { __index = POSES.nbp })

-- ------------------------------------------------------------------ the reference pose and the poses' targets
-- (worked out once per body mesh, from its skeleton's reference pose: each joint's target, the child's turn relative to
-- its parent, for each pose. Constant: a pose is the same relative to the parent whatever the body is doing.)
local poses = nil         -- { mesh = address, targets = { nbp = { [bone] = q }, protect = {...} } }
local function ref_pose(mesh)
    local cs = {}         -- [bone] = { q = component-space rotation, p = position }
    local function get(name)
        if cs[name] then return cs[name] end
        local idx = mesh:GetBoneIndex(FN[name])
        if not idx or idx < 0 then return nil end
        local t = mesh:GetRefPoseTransform(idx)
        local lq = { x = t.Rotation.X, y = t.Rotation.Y, z = t.Rotation.Z, w = t.Rotation.W }
        local lp = v3(t.Translation.X, t.Translation.Y, t.Translation.Z)
        local parent = mesh:GetParentBone(FN[name])
        local pn = parent and parent:ToString() or "None"
        local r
        if pn == "None" or pn == "" then
            r = { q = lq, p = lp }
        else
            local pr = get(pn)
            if not pr then return nil end
            r = { q = qmul(pr.q, lq), p = vadd(pr.p, qrot(pr.q, lp)) }
        end
        cs[name] = r
        return r
    end
    return get
end
local lim_load, joint_over        -- (below: the joints' limits, and how far past them a joint is)
local function build_poses(mesh)
    local get = ref_pose(mesh)
    local pel, chest = get("pelvis"), get("spine_05")
    local cl, cr = get("clavicle_l"), get("clavicle_r")
    if not (pel and chest and cl and cr) then return nil, "no reference pose" end
    local F = { u = vnorm(vsub(chest.p, pel.p)) }
    local r = vsub(cr.p, cl.p)
    F.r = vnorm(vsub(r, vmul(F.u, vdot(r, F.u))))
    F.f = vcross(F.r, F.u)
    -- (forward is the way his toes point)
    local foot, ball = get("foot_l"), get("ball_l")
    if foot and ball and vdot(vsub(ball.p, foot.p), F.f) < 0.0 then F.f = vmul(F.f, -1.0) end
    local out = { F = F, targets = {}, missing = {} }
    -- (the hinges: each elbow's and knee's own axis - its joint's twist axis, in the child bone's frame - and the way it
    -- bends: toward the end of its range with more room from the reference pose, where the arm and leg are straight)
    local L = lim_load(mesh)
    local refq = setmetatable({}, { __index = function(t, k) local r = get(k); return r and r.q end })
    local hinge = {}
    for _, e in ipairs(CHAIN) do
        local j = L and L.list[e.b]
        if j and (e.kind == "fore" or e.kind == "calf") then
            local _, _, tw = joint_over(mesh, j, refq)
            local up, down = j.orig.tw - tw, j.orig.tw + tw
            hinge[e.b] = { x1 = j.frame.x1, sign = up >= down and 1.0 or -1.0, room = max(up, down) }
        end
    end
    out.hinge = hinge
    for name, want in pairs(POSES) do
        local Q = { pelvis = pel.q }                  -- (each bone's turn in the pose, component space)
        local D = {}                                  -- (each bone's direction in it)
        local T = {}
        for _, e in ipairs(CHAIN) do
            local rb, rp = get(e.b), get(e.p)
            if rb and rp and Q[e.p] then
                local carry = qmul(Q[e.p], qinv(rp.q))       -- (the parent's change from the reference, carried down)
                local qc = qmul(carry, rb.q)
                local d
                if e.tip then
                    local rt = get(e.tip)
                    d = rt and vnorm(qrot(carry, vsub(rt.p, rb.p))) or nil
                else
                    d = vnorm(qrot(carry, F.u))               -- (the head: its up)
                end
                local o = (e.s == "l") and vmul(F.r, -1.0) or F.r
                local fn = want[e.kind]
                local h = hinge[e.b]
                if type(fn) == "table" and fn.hinge and h then
                    -- (bent round its hinge, never past its range: 8 degrees short of its end at most)
                    local a = rad(min(fn.hinge, h.room - 8.0) * h.sign) * 0.5
                    local ax = vnorm(qrot(qc, h.x1))
                    local sn = math.sin(a)
                    Q[e.b] = qmul({ x = ax.x * sn, y = ax.y * sn, z = ax.z * sn, w = math.cos(a) }, qc)
                    D[e.b] = d and vnorm(qrot(qmul(Q[e.b], qinv(qc)), d)) or nil
                elseif d and type(fn) == "function" then
                    local w = fn(F, d, o, D[e.p] or F.u)
                    Q[e.b] = qmul(qarc(d, w), qc)
                    D[e.b] = w
                else
                    Q[e.b] = qc
                    D[e.b] = d
                end
                T[e.b] = qmul(qinv(Q[e.p]), Q[e.b])
                -- (the shoulder and the collarbone kept inside their range: each pose's arm was past the shoulder's end - a
                -- 58 degree cone round his reference pose - and his muscle pulled it into the end, the arm stopping
                -- wherever the end let it, one up and one back, 50-70 degrees from where it was meant to be - "one hand up
                -- one hand down still", 2026-11-11. A pose's turn there no more than `POSE_MOST` from the reference)
                local most = M.POSE_MOST[e.kind]
                if most and not (name == "air" and e.kind == "upper") then
                    local R0 = (e.kind == "upper" and M.joint_zero(mesh, e.b)) or qmul(qinv(rp.q), rb.q)
                    local Dq = qmul(qinv(R0), T[e.b])
                    if Dq.w < 0.0 then Dq = { x = -Dq.x, y = -Dq.y, z = -Dq.z, w = -Dq.w } end
                    local ang = 2.0 * math.acos(min(1.0, Dq.w))
                    local lim = rad(most)
                    if ang > lim then
                        local k = math.sin(lim * 0.5) / math.sin(ang * 0.5)
                        T[e.b] = qmul(R0, { x = Dq.x * k, y = Dq.y * k, z = Dq.z * k, w = math.cos(lim * 0.5) })
                        Q[e.b] = qmul(Q[e.p], T[e.b])
                    end
                end
            else
                out.missing[e.b] = true
            end
        end
        -- (his left arm the mirror of his right, every pose - "can you just have the left arm mirror the right arm",
        -- 2026-11-11: each left part's turn the right one's reflected through the middle of him, put onto the left
        -- bone's own frame - its reference turn against the right's reflected)
        if M.MIRROR_ARMS then
            local n = F.r
            local function mir(q)
                local d = q.x * n.x + q.y * n.y + q.z * n.z
                return { w = q.w, x = -(q.x - 2.0 * d * n.x), y = -(q.y - 2.0 * d * n.y), z = -(q.z - 2.0 * d * n.z) }
            end
            for _, k in ipairs({ "clavicle", "upperarm", "lowerarm", "hand" }) do
                local bl, br = k .. "_l", k .. "_r"
                local rl, rr, el = get(bl), get(br), BY_BONE[bl]
                if rl and rr and el and Q[br] and Q[bl] and Q[el.p] then
                    Q[bl] = qmul(mir(Q[br]), qmul(qinv(mir(rr.q)), rl.q))
                    T[bl] = qmul(qinv(Q[el.p]), Q[bl])
                end
            end
        end
        out.targets[name] = T
        out.Qs = out.Qs or {}
        out.Qs[name] = Q
    end
    -- (the way his face looks, in the head bone's own frame)
    local rh = get("head")
    if rh then out.face_local = vnorm(qrot(qinv(rh.q), F.f)) end
    out.chest_fwd_local = vnorm(qrot(qinv(chest.q), F.f))
    out.chest_right_local = vnorm(qrot(qinv(chest.q), F.r))
    out.mesh = mesh:GetAddress()
    return out
end

-- ------------------------------------------------------------------ the joints' limits (soft limits; dislocation)
-- (STORROR's ragdoll physics asset: its constraint templates' profiles, kept as they came, changed from those, and put on
-- his live joints with SetConstraintProfileForAll / SetConstraintProfile - each copies the template's profile in)
local lim = nil           -- { pa, list = { [joint] = { t = template, orig = {...}, frame = {...} } } }
local function physics_asset(mesh)
    local pa = nil
    pcall(function() pa = mesh.PhysicsAssetOverride end)
    if not (pa and pa:IsValid()) then pcall(function() pa = mesh:GetPhysicsAsset() end) end
    if not (pa and pa:IsValid()) then pcall(function() pa = mesh.SkeletalMesh.PhysicsAsset end) end
    if pa and pa:IsValid() then return pa end
    return nil
end
-- (each joint's own zero - its two frames lined up, the middle of its range - as the child's turn from its parent. The
-- physics asset's shoulders sit 60 and 66 degrees from the skeleton's reference pose - its arms set down in an A, the
-- skeleton's out in a T - so a pose's arm, reckoned from the reference, was past the shoulder's end: "one hand up one
-- hand down still", 2026-11-11)
M.JOINT0 = { addr = nil, q = {} }
function M.joint_zero(mesh, bone)
    local J = M.JOINT0
    local pa = physics_asset(mesh)
    if not pa then return nil end
    if J.addr ~= pa:GetAddress() then
        J.addr, J.q = pa:GetAddress(), {}
        local function qmat(a, b)
            local x, y = { a.X, a.Y, a.Z }, { b.X, b.Y, b.Z }
            local z = { x[2] * y[3] - x[3] * y[2], x[3] * y[1] - x[1] * y[3], x[1] * y[2] - x[2] * y[1] }
            local m00, m01, m02, m10, m11, m12, m20, m21, m22 = x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3]
            local tr = m00 + m11 + m22
            if tr > 0.0 then
                local k = sqrt(tr + 1.0) * 2.0
                return { w = 0.25 * k, x = (m21 - m12) / k, y = (m02 - m20) / k, z = (m10 - m01) / k }
            elseif m00 > m11 and m00 > m22 then
                local k = sqrt(1.0 + m00 - m11 - m22) * 2.0
                return { w = (m21 - m12) / k, x = 0.25 * k, y = (m01 + m10) / k, z = (m02 + m20) / k }
            elseif m11 > m22 then
                local k = sqrt(1.0 + m11 - m00 - m22) * 2.0
                return { w = (m02 - m20) / k, x = (m01 + m10) / k, y = 0.25 * k, z = (m12 + m21) / k }
            end
            local k = sqrt(1.0 + m22 - m00 - m11) * 2.0
            return { w = (m10 - m01) / k, x = (m02 + m20) / k, y = (m12 + m21) / k, z = 0.25 * k }
        end
        pcall(function()
            pa.ConstraintSetup:ForEach(function(_, e)
                local c = e:get()
                if c and c:IsValid() then
                    local d = c.DefaultInstance
                    J.q[d.ConstraintBone1:ToString()] = qmul(qmat(d.PriAxis2, d.SecAxis2), qinv(qmat(d.PriAxis1, d.SecAxis1)))
                end
            end)
        end)
    end
    return J.q[bone]
end
function lim_load(mesh)
    local pa = physics_asset(mesh)
    if not pa then return nil end
    if lim and lim.addr == pa:GetAddress() then return lim end
    local L = { pa = pa, addr = pa:GetAddress(), list = {} }
    pa.ConstraintSetup:ForEach(function(i, e)
        local t = e:get()
        if not (t and t:IsValid()) then return end
        local ci = t.DefaultInstance
        local p = ci.ProfileInstance
        local j = ci.JointName:ToString()
        if j:find("^UserConstraint") then return end
        local c, tw = p.ConeLimit, p.TwistLimit
        -- (STORROR's own values, read once a game: kept where a reload of this file finds them - read again after this
        -- mod had changed them, they were scaled down again at every reload, his joints a third of their range and
        -- stiff after seven, 2026-11-10)
        _G.AR_LIM_ORIG = _G.AR_LIM_ORIG or {}
        local key = t:GetAddress()
        local orig = _G.AR_LIM_ORIG[key]
        if not orig then
            orig = { s1 = c.Swing1LimitDegrees, s2 = c.Swing2LimitDegrees, tw = tw.TwistLimitDegrees,
                     ck = c.Stiffness, cd = c.Damping, tk = tw.Stiffness, td = tw.Damping, csoft = c.bSoftConstraint, tsoft = tw.bSoftConstraint,
                     m1 = c.Swing1Motion, m2 = c.Swing2Motion, mt = tw.TwistMotion }
            _G.AR_LIM_ORIG[key] = orig
        end
        L.list[j:lower()] = {
            t = t, joint = j,
            orig = orig,
            frame = { x1 = v3(ci.PriAxis1.X, ci.PriAxis1.Y, ci.PriAxis1.Z), y1 = v3(ci.SecAxis1.X, ci.SecAxis1.Y, ci.SecAxis1.Z),
                      x2 = v3(ci.PriAxis2.X, ci.PriAxis2.Y, ci.PriAxis2.Z), y2 = v3(ci.SecAxis2.X, ci.SecAxis2.Y, ci.SecAxis2.Z) },
            child = ci.ConstraintBone1:ToString(), parent = ci.ConstraintBone2:ToString(),
        }
    end)
    lim = L
    return L
end
-- (less than it was - hips +50, shoulders +40, knees +30: a knee's bend is its twist, the same both ways, so widened it
    -- bent backwards too; with his feet no longer reached for, his knees are left as STORROR has them, 2026-11-10)
M.WIDEN = { thigh = { s1 = 20.0, s2 = 5.0 }, upperarm = { s1 = 20.0, s2 = 20.0 } }   -- (calf: the knee's bend; "he also still cant reach his foot")
-- (a joint's template set: soft and damped, its range ends moved in - or, dislocated, widened)
local function lim_write(j, soft, wide)
    local o = j.orig
    local p = j.t.DefaultInstance.ProfileInstance
    local c, tw = p.ConeLimit, p.TwistLimit
    local C = M.CFG
    local sc = soft and C.limit_scale or 1.0
    -- (hips and shoulders opened toward a body's own range: STORROR's let the thigh forward only ~70 deg and the arm up
    -- 45 - his knees could not come up to his chest in pain, nor his elbows up round his head)
    local kind = j.joint:lower():match("^(%a+)_")
    local wv = soft and M.WIDEN[kind] or nil
    c.Swing1LimitDegrees = min(175.0, o.s1 * sc + (wide and wide.s or 0.0) + (wv and wv.s1 or 0.0))
    c.Swing2LimitDegrees = min(175.0, o.s2 * sc + (wide and wide.s or 0.0) + (wv and wv.s2 or 0.0))
    tw.TwistLimitDegrees = min(175.0, o.tw * sc + (wide and wide.t or 0.0) + (wv and wv.tw or 0.0))
    if soft then
        local ck, tk = o.ck * C.limit_k, o.tk * C.limit_k
        c.bSoftConstraint, tw.bSoftConstraint = true, true
        c.Stiffness, tw.Stiffness = ck, tk
        c.Damping, tw.Damping = 2.0 * sqrt(ck) * C.limit_damp, 2.0 * sqrt(tk) * C.limit_damp
    else
        c.bSoftConstraint, tw.bSoftConstraint = o.csoft, o.tsoft
        c.Stiffness, c.Damping, tw.Stiffness, tw.Damping = o.ck, o.cd, o.tk, o.td
    end
end
local dis = {}            -- [joint] = { label, t, wide = { s, t }, target = q }  (dislocated)
-- (a leg he reaches down for: its hip and knee let go further while he does - STORROR's hip stops the knee well short of
-- his chest and the knee short of a full bend, and his hands came no nearer his foot than 41 cm, 2026-11-10)
local reach_wide = {}     -- [joint] = { s, t }
local function lim_apply(mesh, only)
    local L = lim_load(mesh)
    if not L then return false end
    local soft = M.CFG.soft_limits
    for name, j in pairs(L.list) do
        if not only or only == name then
            local w = dis[name] and dis[name].wide or nil
            local rw = reach_wide[name]
            if rw then w = { s = (w and w.s or 0.0) + rw.s, t = (w and w.t or 0.0) + rw.t } end
            pcall(lim_write, j, soft, w)
        end
    end
    if only then
        pcall(function() mesh:SetConstraintProfile(FN[L.list[only].joint], FN["None"], true) end)
    else
        pcall(function() mesh:SetConstraintProfileForAll(FN["None"], true) end)
    end
    return true
end
-- (in the air his shoulders' range widened, so his arms can go up over his head: the physics asset's shoulders reach no
-- higher than level - "bring both arms up", 2026-11-11. Back to their own range on the ground)
-- (`t` 40: the asset's left shoulder lifts only with more twist than its own range; at +60 the twist wrung his left shoulder
-- into his chest - "the left arms shoulder is sinking into the body", 2026-11-11)
M.AIR_SHOULDER = { s = 130.0, t = 40.0 }
function M.air_shoulders(mesh, on)
    if on and not M.USE_AIR_POSE then on = false end
    for _, jn in ipairs({ "upperarm_l", "upperarm_r" }) do
        if on then reach_wide[jn] = { s = M.AIR_SHOULDER.s, t = M.AIR_SHOULDER.t, air = true }
        elseif reach_wide[jn] and reach_wide[jn].air then reach_wide[jn] = nil end
        pcall(lim_apply, mesh, jn)
    end
end
local function lim_restore(mesh)
    if not lim then return end
    for _, j in pairs(lim.list) do pcall(lim_write, j, false, nil) end
    if mesh then pcall(function() mesh:SetConstraintProfileForAll(FN["None"], true) end) end
end

local st = { down = false }
-- ------------------------------------------------------------------ the parts' states (the figure on the screen)
-- Four states for each part of him (the user, 2026-11-10: "healthy white, dislocated orange, broken red the limbs in this
-- part should be completely limp, severed black this is where the gore mod come in"), each from the speed of the blow
-- that part takes ("damage by speed of impact if its over 50mph the body explodes all limbs dead, if its over 30 the
-- limbs affected will be severed, over 15 broken, over 10 dislocated", then "above 70mph player explodes, above 50
-- severed, 30 above broken above 15 dislocated", 2026-11-10):
--   0 healthy;
--   1 dislocated - hit at over `dislocate_mph`: its joint put out, bent past its range, for good;
--   2 broken     - hit at over `break_mph`;
--   3 severed    - hit at over `sever_mph`: torn off (gore.lua), and what is inside it with it.
-- His body (the chest) hit at over `explode_mph`: it explodes - every limb and the head torn off.
-- A blow: the part itself striking something - a surface within `contact` cm of it the way it was going - at the speed it
-- had INTO that surface, less what it still has (its speed along the surface, sliding or swept sideways, is no blow; a limb
-- jerked to a stop by the rest of him, with nothing at it, is not hit - "hit registation is wack", 2026-11-10: a 39 mph
-- landing had every joint of him "hit" at 21 mph within a tenth of a second, his neck among them). States only get worse while he is down; he is healed of all
-- of it as he gets up, and as the game puts him somewhere - a waypoint, a respawn ("when the player stands back up or
-- teleports back to waypoint heal the player", 2026-11-10).
-- (dislocated - "fracture" - from 10 mph: "make fractures happen above 10mph", 2026-11-10; it was 15)
M.DAMAGE = { dislocate_mph = 10.0, break_mph = 30.0, sever_mph = 50.0, explode_mph = 70.0, contact = 25.0, window = 0.05,
             skip = 0.05, gore = true, max_blow = 9000.0, jump = 120.0, jump_quiet = 0.3, teleport = 400.0,
             -- (settled - his hips under `still_v` cm/s for `still_t` s - his own writhing, kicking and rocking are no blows,
             -- till his hips move faster than `move_v` again: lying there he kept "dislocating" his chest and shoulders on
             -- the floor by his own flailing - "make damage more precise again", 2026-11-10)
             still_v = 160.0, still_t = 0.25, move_v = 320.0,
             -- (his head: put out - his neck, and so dead - only past `head_dead_mph`; past break_mph it breaks, and he is
             -- dazed; under that it only shakes him. At the 15 mph of the rest of him, a third of his falls killed him and
             -- he lay there: "charaters making no attempt to even move sometimes", 2026-11-10)
             head_dead_mph = 45.0,
             -- (a cut only with his body moving `sever_body` of sever_mph or more a moment before: a foot or a hand alone
             -- read over 50 mph - the physics flicking it, his body all but still - "sometimes at very slow speed limbs get
             -- severed", 2026-11-10. Such a blow breaks it)
             sever_body = 0.55 }
local MPH = 44.704        -- (cm/s in a mile an hour)
M.STATES = { [0] = "healthy", "dislocated", "broken", "severed" }
-- (a break of a long bone open, now and then: `chance` of them; of those, `bone_p` with the bone out)
M.FRACTURE = { chance = 0.65, bone_p = 0.85, parts = { upperarm = true, lowerarm = true, thigh = true, calf = true } }
local REGIONS = { head = { "head" }, chest = { "spine_03", "pelvis" } }          -- (the bodies read for each part)
local REGION_JOINTS = { head = { "neck_01", "head" }, chest = { "spine_02", "spine_03", "spine_04", "spine_05", "clavicle_l", "clavicle_r" } }
local JOINT_REGION = {}
for _, sd in ipairs({ "l", "r" }) do
    JOINT_REGION["clavicle_" .. sd] = "chest"
    for _, n in ipairs({ "upperarm", "lowerarm", "hand", "thigh", "calf", "foot" }) do
        local id = n .. "_" .. sd
        REGIONS[id], REGION_JOINTS[id], JOINT_REGION[id] = { id }, { id }, id
    end
end
local parts = {}          -- [part] = { d = damage, state = 0..3, up = s up since it last got worse }
for id in pairs(REGIONS) do parts[id] = { d = 0.0, state = 0, up = 0.0 } end
-- How much of its strength each state leaves a part ("make discated limbs move at 80% and broken at 60%", 2026-11-10 -
-- broken parts were limp before): its pull toward each pose, its share of the falling animation, its kicks, its hold.
-- weak: each joint of a hurt part, its share; limp: the joints with none left (a part torn off).
M.STRENGTH = { [0] = 1.0, [1] = 0.8, [2] = 0.6, [3] = 0.0 }
local weak, limp, limp_rev = {}, {}, 0
local function limp_update()
    local w, l = {}, {}
    for id, e in pairs(parts) do
        local f = M.STRENGTH[e.state] or 1.0
        if f < 1.0 then
            for _, j in ipairs(REGION_JOINTS[id]) do
                w[j] = min(w[j] or 1.0, f)
                if w[j] <= 0.0 then l[j] = true end
            end
        end
    end
    weak, limp = w, l
    limp_rev = limp_rev + 1
end
local function share(j) return weak[j] or 1.0 end
-- HP taken at once by each injury, of 100 (gore.lua's hp: his blood lost besides): a dislocation ("fracture") 3, a break 5,
-- a cut 10 - "make fractures take 3 hp for each fracture", "broken is 5 and severed is 10", 2026-11-10
M.HP_COST = { [1] = 3, [2] = 5, [3] = 10 }
local function take_hp(sv, id)
    -- (SCALING DAMAGE: the hits take each part's HP by its size - a hand's 3 HP gone at once to a fracture's flat 3, and the
    -- next touch took it off, "do a better job on damage scaling", 2026-11-11; a cut still costs its own)
    if sv < 3 and M.scaling_on and M.scaling_on() then return end
    local G, c = _G.ARGORE, M.HP_COST[sv]
    if G and G.take_hp and c then pcall(G.take_hp, c, id) end
end
-- (EXPLODE: any hurt - a joint put out by how far it bent, too - blows him apart; the blow of it below)
-- (NO EXPLOSIONS, on the RAGDOLL tab: never blown apart, whatever the speed - the hit breaks and cuts as any other blow;
-- over EXPLODE too - "add an option called no expolsions", 2026-11-11)
-- (SEVERED LIMBS off: nothing cut off - and so no blowing apart either, which is all of him cut off at once)
-- (SCALING DAMAGE, on the RAGDOLL tab)
function M.scaling_on() local Mn = _G.ARMENU; return Mn ~= nil and Mn.scaling_damage ~= nil and Mn.scaling_damage() end
-- (DAMAGE ON FEET, on the RAGDOLL tab: hurt while not a ragdoll - its own switch, apart from SCALING DAMAGE)
function M.feet_damage_on() local Mn = _G.ARMENU; return not (Mn and Mn.damage_on_feet and not Mn.damage_on_feet()) end
function M.no_sever() local Mn = _G.ARMENU; return Mn ~= nil and Mn.severed_limbs ~= nil and not Mn.severed_limbs() end
function M.no_explode() local Mn = _G.ARMENU; return (Mn ~= nil and Mn.no_explosions ~= nil and Mn.no_explosions()) or M.no_sever() end
-- (BONES STICKING OUT off: an open break's wound, never its bone)
function M.bones_out() local Mn = _G.ARMENU; return not (Mn and Mn.bones_out and not Mn.bones_out()) end
function M.explode_on() local Mn = _G.ARMENU; return Mn ~= nil and Mn.explode_mode ~= nil and Mn.explode_mode() and not M.no_explode() end
local function set_state(id, sv)
    local e = parts[id]
    if not e or sv <= e.state then return false end
    if sv > 0 and M.explode_on() and st.rag and not st.rag.exploded and M._explode then
        local pawn = lib.pawn()
        if pawn then pcall(M._explode, pawn, st.rag, M.DAMAGE.explode_mph); return true end
    end
    e.state, e.up, e.worse_t = sv, 0.0, os.clock()
    take_hp(sv, id)
    limp_update()
    if M.on_injury then pcall(M.on_injury, id, sv) end
    return true
end
function M.damage() return parts, st and st.down or false end
-- His sounds, kept in hand ("the audios terrible", 2026-11-10 - a crack for every break, six in 50 ms; a thud as often as
-- every 0.12 s; a grunt every second or two; all flat in the ears): each from where it happens on him; a bone's crack at
-- most every `crack_gap` s, a dislocation a quieter, higher pop; a part hitting something by what it is - his body and head
-- a heavy landing, a limb a slap - its loudness by the speed of it, each part at most every `hit_gap_part` s and him every
-- `hit_gap`; groans rare and low, only in real pain; his clothes rustling as he writhes.
-- (his sounds of pain off - "just meant the sound the charater makes when 'in pain'", 2026-11-10: `groans` brings them
-- back; `on` is all of it)
M.AUDIO = { on = true, groans = false, crack_gap = 0.25, hit_gap_part = 0.2, hit_gap = 0.08, pop_vol = 0.45, pop_pitch = { 1.15, 1.3 },
            groan_every = { 3.0, 7.0 }, groan_from = 35.0, groan_vol = { 0.3, 0.55 }, groan_pitch = { 0.78, 0.9 },
            rustle = false,   -- (his clothes' rustle as he writhed, every second or so: "weird cloth sound keeps being spammer throughout", 2026-11-10)
            rustle_every = { 0.7, 1.5 }, rustle_vol = 0.3 }
local function snd(...) if M.AUDIO.on then return lib.sound(...) end return false end
local HEAVY = { head = true, chest = true, thigh_l = true, thigh_r = true, calf_l = true, calf_r = true }
local function at_bone(mesh, b)
    local ok, v = pcall(function() return mesh:GetSocketLocation(FN[b]) end)
    if ok and v then return { X = v.X, Y = v.Y, Z = v.Z } end
    return nil
end
local function crack(r, mesh, bone, pop)
    local A = M.AUDIO
    r.snd = r.snd or {}
    if r.t - (r.snd.crack or -9.0) < A.crack_gap then return end
    r.snd.crack = r.t
    local where = mesh and at_bone(mesh, bone or "spine_03") or nil
    if pop then snd("crack", A.pop_vol, where, A.pop_pitch[1] + (A.pop_pitch[2] - A.pop_pitch[1]) * random())
    else snd("crack", 1.0, where) end
end
local function hit_sound(r, mesh, id, bone, mph)
    local A = M.AUDIO
    r.snd = r.snd or {}
    r.snd.part = r.snd.part or {}
    if r.t - (r.snd.hit or -9.0) < A.hit_gap or r.t - (r.snd.part[id] or -9.0) < A.hit_gap_part then return end
    r.snd.hit, r.snd.part[id] = r.t, r.t
    snd(HEAVY[id] and "thud" or "slap", min(1.0, 0.2 + mph / 60.0), at_bone(mesh, bone))
end
-- healed, all of him: every part healthy, every joint back in its range, the parts torn off back on him
local function heal_all(pawn, why)
    local any = next(dis) ~= nil
    for _, e in pairs(parts) do if e.state > 0 then any = true end end
    local G = _G.ARGORE
    if G and G.active and G.active() then pcall(G.clear); any = true end
    if G and G.fractures_clear then pcall(G.fractures_clear) end
    if G and G.body_clear then pcall(G.body_clear) end
    if G and G.stain_clear then pcall(G.stain_clear) end
    if M.stand_stop then pcall(M.stand_stop, pawn, why) end
    st.crawl_mode, st.crawl_regrab, st.crawl_kept = nil, nil, nil
    -- (his blood given back: HP full, alive again)
    if st.bled_out then any = true end
    st.bled_out, st.hp_why = nil, nil
    if G and G.blood_reset then pcall(G.blood_reset) end
    if M.jump_end and pawn then M.jump_end(pawn, nil) end
    if M.limbs_set and pawn then M.limbs_set(pawn, nil) end
    if not any then return false end
    dis = {}
    for _, e in pairs(parts) do e.d, e.state, e.up, e.wear, e.hit_t, e.scale_said = 0.0, 0, 0.0, nil, nil, nil end
    st.sever_queue = nil
    limp_update()
    if pawn then pcall(lim_apply, pawn.Mesh) end
    if M.on_heal then pcall(M.on_heal) end
    log("healed (%s)", why or "?")
    return true
end

-- ------------------------------------------------------------------ while he is down
local function montage(pawn)
    local name, mt = "", nil
    pcall(function()
        local ai = pawn.Mesh:GetAnimInstance()
        if not (ai and ai:IsValid()) then return end
        local m = ai:GetCurrentActiveMontage()
        if m and m:IsValid() then name, mt = m:GetFName():ToString(), m end
    end)
    return name, mt
end
M.montage = montage
local function is_down(pawn)
    local name = montage(pawn)
    if name:find("Getup") then return false end
    if name:find("Ragdoll") then return true end
    local mode = -1
    pcall(function() mode = pawn.CharacterMovement.MovementMode end)
    return st.down and mode == 0
end

-- the controls (tension, the protect pose, dislocated joints' new pull): one Physics Control per joint, made as he goes
-- down, gone as he gets up
local function ctl_end(r)
    if r and r.pc then pcall(function() if r.pc:IsValid() then r.pc:K2_DestroyComponent(r.pc) end end) end
end
local function strength_of(kind)
    local C = M.CFG
    if not C.tension then return 0.0 end
    if kind == "spine" then return C.tension_spine_hz end
    if kind == "neck" or kind == "head" then return C.tension_head_hz end
    return C.tension_hz
end
local function ctl_start(pawn, r)
    local mesh = pawn.Mesh
    if not (poses and poses.mesh == mesh:GetAddress()) then
        local okp, P, why = pcall(build_poses, mesh)
        if not okp or not P then log("no poses (%s)", tostring(okp and why or P)); return false end
        poses = P
    end
    local cls = StaticFindObject("/Script/PhysicsControl.PhysicsControlComponent")
    if not (cls and cls:IsValid()) then return false end
    local pc = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not (pc and pc:IsValid()) then return false end
    r.pc, r.ctl = pc, {}
    local nbp = poses.targets.nbp
    for _, e in ipairs(CHAIN) do
        if nbp[e.b] then
            local hz = strength_of(e.kind)
            local data = { bEnabled = true, LinearStrength = 0.0, LinearDampingRatio = 1.0, LinearExtraDamping = 0.0, MaxForce = 0.0,
                AngularStrength = hz, AngularDampingRatio = M.CFG.tension_damp, AngularExtraDamping = 0.0, MaxTorque = 0.0,
                LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
                -- (each pull between the part and its parent, equal and opposite, as a muscle's: on the part alone it was a
                -- push from outside him, and with writhing's targets always moving those added up and spun him round on the
                -- ground - "spinning on the ground?", 2026-11-10)
                bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = false }
            local q = (dis[e.b] and dis[e.b].target) or nbp[e.b]
            local target = { TargetPosition = { X = 0, Y = 0, Z = 0 }, TargetVelocity = { X = 0, Y = 0, Z = 0 },
                TargetOrientation = q2rot(q), TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
            local okc, nm = pcall(function()
                return pc:CreateControl(mesh, FN[e.p], mesh, FN[e.b], data, target, FN["ActiveRagdoll"], "ar_" .. e.b)
            end)
            if okc and nm then
                r.ctl[e.b] = { name = nm, e = e, hz = hz, w = 0.0 }
                pcall(function() pc:SetControlTargetOrientation(nm, q2rot(q), 0.0, true, false, true, false) end)
            end
        end
    end
    return true
end
-- (the protect pose blended in by w: each joint's target between the neutral pose and protect, its strength between the
-- tension's and protect's; written only when w has moved)
local function ctl_blend(r, w)
    if not (r.pc and poses) then return end
    if abs(w - (r.blend_w or -1.0)) < 0.04 and not (w == 0.0 and r.blend_w ~= 0.0) and r.limp_rev == limp_rev then return end
    r.blend_w, r.limp_rev = w, limp_rev
    local A = (M.USE_AIR_POSE and not r.grounded and poses.targets.air) or poses.targets.nbp
    local B = (r.air_pose and poses.targets[r.air_pose]) or poses.targets.protect
    for bone, c in pairs(r.ctl) do
      if not (r.ovr and r.ovr[bone]) then
        local d = dis[bone]
        local q = qnlerp(A[bone], B[bone] or A[bone], w)
        local phz = (r.air_pose and r.air_pose ~= "protect" and r.air_mode_t and r.air_mode_t.hz) or M.CFG.protect_hz
        local hz = c.hz + (phz - c.hz) * w
        hz = hz * share(bone) * (r.brain and r.brain.tone or 1.0)
        if r.dead or r.lifeless or (r.stun_until and r.t < r.stun_until) then hz = 0.0 end
        if r.wake_t and r.t - r.wake_t < M.STUN.wake then hz = hz * max(0.0, (r.t - r.wake_t) / M.STUN.wake) end
        -- (in the air his arms held to his pose: at the limbs' tone, 1 Hz, a tumble flung an arm up over his head and it
        -- stayed there - "one arm up one arm down", 2026-11-11. Stunned, a little of it; dead, none)
        if not r.grounded and M.AIR_ARMS[c.e.kind] and not (r.dead or r.lifeless) and not weak[bone] and not dis[bone] then
            hz = max(hz, (r.stun_until and r.t < r.stun_until) and M.CFG.air_arm_stun_hz or M.CFG.air_arm_hz)
            -- (his collarbones held hard in the air: the raised arm's pull rolled his left one down and back 35 degrees,
            -- past its soft end - "the left arms shoulder is sinking into the body", 2026-11-11)
            if c.e.kind == "clav" then hz = max(hz, M.CFG.air_clav_hz) end
        end
        -- (lying on the ground, his neck let go: held at its tone it kept his head up off the floor, chin to his chest - "fix
        -- whatever it is thats pushing his head up", 2026-11-10. Looking about, holding, an act: their own pull, not this)
        if r.grounded then hz = hz * ((bone == "neck_01" or bone == "head") and M.CFG.head_rest or M.CFG.ground_tone) end
        c.hz_now = hz
        if M.SMOOTH.on then
            c.q_want, c.hz_want = q, hz
            if hz <= 0.0 then
                c.hz_cur = 0.0
                pcall(function() r.pc:SetControlAngularData(c.name, 0.0, M.CFG.tension_damp, 0.0, 0.0, true, true, false) end)
            end
        else
            pcall(function()
                r.pc:SetControlTargetOrientation(c.name, q2rot(q), 0.0, true, false, true, false)
                r.pc:SetControlAngularData(c.name, hz, M.CFG.tension_damp, 0.0, 0.0, true, true, false)
            end)
        end
      end
    end
end
-- (each joint eased toward what it is to be - its target turned `rate` of the way a second, its pull too - not set at
-- once: the falls' poses snapped into place, "make the poses fire smoothly as well its super rigid", 2026-11-11. Going
-- limp is at once)
M.SMOOTH = { on = true, rate = 5.0, hz_rate = 6.0 }
function M.ctl_smooth(r, dt)
    local S = M.SMOOTH
    if not (S.on and r.pc and r.ctl) then return end
    local k, kh = min(1.0, S.rate * dt), min(1.0, S.hz_rate * dt)
    for bone, c in pairs(r.ctl) do
        local ov = r.ovr and r.ovr[bone]
        if c.q_want and (ov == nil or ov == "flail") then
            local qw, hw = c.q_want, c.hz_want or 0.0
            local qc, hc = c.q_cur, c.hz_cur or hw
            local moved = qc == nil
            qc = qc or qw
            if abs(qc.x * qw.x + qc.y * qw.y + qc.z * qw.z + qc.w * qw.w) < 0.99999 then qc = qnlerp(qc, qw, k); moved = true end
            if hw <= 0.0 then
                if hc ~= 0.0 then moved = true end
                hc = 0.0
            elseif abs(hw - hc) > 0.05 then hc = hc + (hw - hc) * kh; moved = true end
            c.q_cur, c.hz_cur = qc, hc
            if moved then
                pcall(function()
                    r.pc:SetControlTargetOrientation(c.name, q2rot(qc), 0.0, true, false, true, false)
                    r.pc:SetControlAngularData(c.name, hc, M.CFG.tension_damp, 0.0, 0.0, true, true, false)
                end)
            end
        end
    end
end

-- the falling animation's pull (Unreal's Physical Animation toward STORROR's flail, each joint relative to its parent;
-- never the pelvis: with no parent of its own it would be driven to the flail's pose in the world and right him)
local function pa_data(k)
    return { bIsLocalSimulation = true, OrientationStrength = k, AngularVelocityStrength = k * 0.1, PositionStrength = 0.0,
             VelocityStrength = 0.0, MaxLinearForce = 0.0, MaxAngularForce = 0.0 }
end
local phys = { comp = nil, addr = nil, k = -1.0 }
local function phys_comp(pawn)
    local addr = pawn:GetAddress()
    if phys.comp and phys.addr == addr then
        local ok, yes = pcall(function() return phys.comp:IsValid() end)
        if ok and yes then return phys.comp end
    end
    phys.comp, phys.k = nil, -1.0
    local g = _G.AR_PHYSANIM
    if g and g.addr == addr then
        local ok, yes = pcall(function() return g.comp:IsValid() end)
        if ok and yes then phys.comp, phys.addr = g.comp, addr; return g.comp end
    end
    local cls = StaticFindObject("/Script/Engine.PhysicalAnimationComponent")
    if not (cls and cls:IsValid()) then return nil end
    local c = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
    if not (c and c:IsValid()) then return nil end
    c:SetSkeletalMeshComponent(pawn.Mesh)
    phys.comp, phys.addr = c, addr
    _G.AR_PHYSANIM = { comp = c, addr = addr }
    return c
end
-- (the pull's component taken off him whenever he is not a ragdoll - and just before STORROR resets him: kept on, it
-- crashed the game - "crash", 2026-11-10: the dump had this component's own tick reading his body's physics, which a
-- reset - SimpleReset on a get-up, the waypoint - had made afresh under it. Made again at his next fall.)
local function phys_drop(why)
    local c = phys.comp or (_G.AR_PHYSANIM and _G.AR_PHYSANIM.comp)
    phys.comp, phys.addr, phys.k = nil, nil, -1.0
    _G.AR_PHYSANIM = nil
    if not c then return end
    local ok, e = pcall(function() if c:IsValid() then c:K2_DestroyComponent(c) end end)
    if why then log("the fall animation's pull taken off (%s)%s", why, ok and "" or (": " .. tostring(e))) end
end
local function phys_set(pawn, k)
    if abs(k - phys.k) < 5.0 and not (k == 0.0 and phys.k ~= 0.0) and phys.limp_rev == limp_rev then return end
    if k <= 0.0 and not (phys.comp or (_G.AR_PHYSANIM and _G.AR_PHYSANIM.comp)) then phys.k, phys.limp_rev = 0.0, limp_rev; return end
    local c = phys_comp(pawn)
    if not c then return end
    pcall(function()
        c:ApplyPhysicalAnimationSettingsBelow(FN["pelvis"], pa_data(k), false)
        c:ApplyPhysicalAnimationSettings(FN["pelvis"], pa_data(0.0))
        if k > 0.0 then for j, f in pairs(weak) do c:ApplyPhysicalAnimationSettings(FN[j], pa_data(k * f)) end end
    end)
    phys.k, phys.limp_rev = k, limp_rev
end

-- ------------------------------------------------------------------ reading the body (once a frame)
local fr = nil
local function rot(mesh, n)
    local q = fr.q[n]
    if not q then
        local r = mesh:GetSocketQuaternion(FN[n])
        q = { x = r.X, y = r.Y, z = r.Z, w = r.W }
        fr.q[n] = q
    end
    return q
end
local function pos(mesh, n)
    local p = fr.p[n]
    if not p then
        local r = mesh:GetSocketLocation(FN[n])
        p = v3(r.X, r.Y, r.Z)
        fr.p[n] = p
    end
    return p
end
local KSL = nil
local NO_COLOR = { R = 0, G = 0, B = 0, A = 0 }
-- (a ball of radius r swept from a to b, him left out: the way what it meets faces, and how far along it is - a narrow
-- thing off his middle, a bin, met where a line from his middle would pass it by)
local SOLID_TYPES = { 0, 1, 4, 5 }   -- (world static, world dynamic, physics bodies, destructibles: anything solid but people)
local function sweep_hit(pawn, a, b, r, solid)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ok, res = pcall(function()
        if solid then
            return KSL:SphereTraceSingleForObjects(lib.world(), fv(a), fv(b), r, SOLID_TYPES, false, { pawn }, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
        end
        return KSL:SphereTraceSingle(lib.world(), fv(a), fv(b), r, 0, false, { pawn }, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    if not (ok and res) then return nil end
    local okh, nx, ny, nz, d = pcall(function() return hit.ImpactNormal.X, hit.ImpactNormal.Y, hit.ImpactNormal.Z, hit.Distance end)
    if not (okh and nx) then return nil end
    return v3(nx, ny, nz), d
end
-- (what is on the line from a to b, him left out: the way its surface faces, and how far along the line it is)
local function ray_hit(pawn, a, b)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ok, r = pcall(function()
        return KSL:LineTraceSingle(lib.world(), fv(a), fv(b), 0, true, { pawn }, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    if not (ok and r) then return nil end
    local okh, nx, ny, nz, d = pcall(function() return hit.ImpactNormal.X, hit.ImpactNormal.Y, hit.ImpactNormal.Z, hit.Distance end)
    if not (okh and nx) then return nil end
    return v3(nx, ny, nz), d
end
local function ray(pawn, a, b)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local ok, r = pcall(function()
        return KSL:LineTraceSingle(lib.world(), fv(a), fv(b), 0, true, { pawn }, 0, {}, true, NO_COLOR, NO_COLOR, 0.0)
    end)
    return ok and r and true or false
end

-- (a part of him turned by his own muscle: all inside him - the trunk it hangs from turned back by the same angular
-- momentum the other way, so all of him turns no more than before. A kick to one part alone was a turn from nowhere -
-- "no random spin", "An object at rest stays at rest ...", 2026-11-11. Against the trunk, not the part above: a light
-- collarbone given an upper arm's kick back was flung)
M.TRUNK_OF = { head = "spine_05", neck_01 = "spine_05", clavicle_l = "spine_05", clavicle_r = "spine_05", upperarm_l = "spine_05",
               upperarm_r = "spine_05", lowerarm_l = "spine_05", lowerarm_r = "spine_05", hand_l = "spine_05", hand_r = "spine_05",
               thigh_l = "pelvis", thigh_r = "pelvis", calf_l = "pelvis", calf_r = "pelvis", foot_l = "pelvis", foot_r = "pelvis",
               spine_05 = "pelvis", spine_04 = "pelvis", spine_03 = "pelvis", spine_02 = "pelvis", spine_01 = "pelvis" }
function M.twist(mesh, bn, dw_deg, against)
    local pn = against or M.TRUNK_OF[bn]
    if not pn or pn == bn then return end
    local k = math.pi / 180.0
    pcall(function()
        local J = mesh:ScaleByMomentOfInertia({ X = dw_deg.x * k, Y = dw_deg.y * k, Z = dw_deg.z * k }, FN[bn])
        local jx, jy, jz = J.X, J.Y, J.Z
        mesh:AddAngularImpulseInRadians({ X = jx, Y = jy, Z = jz }, FN[bn], false)
        mesh:AddAngularImpulseInRadians({ X = -jx, Y = -jy, Z = -jz }, FN[pn], false)
    end)
end

-- ------------------------------------------------------------------ limb impact
-- (an impact along dir (a unit vector), k its size 0..1.5: arms swung the way it goes, legs the other way, each limb by
-- its own random amount and a little off-line, so no two move alike)
function M.limb_impact(pawn, dir, k)
    local C = M.CFG
    if not C.limb_impact then return end
    local mesh = pawn.Mesh
    fr = fr or { q = {}, p = {} }
    for _, s in ipairs({ "l", "r" }) do
        for _, limb in ipairs({ { "upperarm_" .. s, "lowerarm_" .. s, 1.0 }, { "thigh_" .. s, "calf_" .. s, -0.75 } }) do
            local a, b = pos(mesh, limb[1]), pos(mesh, limb[2])
            local along = vnorm(vsub(b, a))
            local want = vmul(dir, limb[3])
            local axis = vcross(along, want)
            if vlen(axis) < 0.05 then axis = vcross(along, v3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1))) end
            axis = vnorm(vadd(vnorm(axis), v3(rnd(-1, 1) * C.impact_rand, rnd(-1, 1) * C.impact_rand, rnd(-1, 1) * C.impact_rand)))
            local mag = C.impact_deg * k * rnd(0.6, 1.4)
            M.twist(mesh, limb[1], vmul(axis, mag))
        end
    end
end

-- ------------------------------------------------------------------ dislocation
-- (each joint's angles in its constraint's frames: the swing of the child's twist axis away from the parent's, split into
-- the two swing directions, and the twist about it - how far past the end of its range it has gone)
function joint_over(mesh, j, Q)
    local qc, qp
    if Q then qc, qp = Q[j.child:lower()] or Q[j.child], Q[j.parent:lower()] or Q[j.parent] else qc, qp = rot(mesh, j.child), rot(mesh, j.parent) end
    if not (qc and qp) then return 0.0, 0.0, 0.0 end
    local f = j.frame
    local x1, y1 = qrot(qc, f.x1), qrot(qc, f.y1)
    local x2, y2 = qrot(qp, f.x2), qrot(qp, f.y2)
    local z2 = vcross(x2, y2)
    local a, b, c = vdot(x1, x2), vdot(x1, y2), vdot(x1, z2)
    local s1, s2 = deg(atan(b, a)), deg(atan(c, a))
    local o = j.orig
    local over_s = 0.0
    if o.m1 ~= 0 or o.m2 ~= 0 then
        local L1, L2 = max(o.s1, 1.0), max(o.s2, 1.0)
        if o.m1 == 0 then L1 = 180.0 end
        if o.m2 == 0 then L2 = 180.0 end
        local e = sqrt((s1 / L1) ^ 2 + (s2 / L2) ^ 2)
        local sw = deg(acos(max(-1.0, min(1.0, a))))
        if e > 1.0 then over_s = sw * (1.0 - 1.0 / e) end
    end
    -- (the twist: the child's second axis against the parent's, once the swing is taken off)
    local y2s = qrot(qarc(x2, x1), y2)
    local tw = deg(atan(vdot(vcross(y2s, y1), x1), vdot(y2s, y1)))
    local over_t = (o.mt ~= 0) and max(0.0, abs(tw) - o.tw) or 0.0
    return over_s, over_t, tw
end
local DISLOC = { "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "clavicle_l", "clavicle_r" }
-- (a blow's dislocation: bent `push` degrees further, its range `wide` wider, and the joint loose - drifting toward where
-- it was put out with a pull of only `hz`, free to swing about there: held hard at its broken angle it stood stiff, "dislocations
-- should still be able to move", 2026-11-10 - as the video's, "free to move in that hyper-extension zone")
M.DISLOCATE = { push = 30.0, wide = 15.0, hz = 0.35, over = 10.0 }
local function dislocate(pawn, r, bone, over_s, over_t, why)
    local e = BY_BONE[bone]
    local mesh = pawn.Mesh
    -- (its new pull: the joint as it is now, past its end - so it stays hyper-extended, never back in its range)
    local q = qmul(qinv(rot(mesh, e.p)), rot(mesh, bone))
    local wide = { s = over_s > 0.0 and min(30.0, over_s + M.DISLOCATE.over) or 0.0, t = over_t > 0.0 and min(30.0, over_t + M.DISLOCATE.over) or 0.0 }
    if over_s <= 0.0 and over_t <= 0.0 then
        -- (from a blow: bent on the way it was turning, past where it is, and its range opened to let it)
        local ax = nil
        pcall(function()
            local wc = mesh:GetPhysicsAngularVelocityInDegrees(FN[bone])
            local wp = mesh:GetPhysicsAngularVelocityInDegrees(FN[e.p])
            ax = v3(wc.X - wp.X, wc.Y - wp.Y, wc.Z - wp.Z)
        end)
        if not ax or vlen(ax) < 20.0 then ax = v3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)) end
        local axp = vnorm(qrot(qinv(rot(mesh, e.p)), vnorm(ax)))
        local h = rad(M.DISLOCATE.push) * 0.5
        local sn = math.sin(h)
        q = qmul({ x = axp.x * sn, y = axp.y * sn, z = axp.z * sn, w = math.cos(h) }, q)
        wide = { s = M.DISLOCATE.wide, t = M.DISLOCATE.wide }
    end
    dis[bone] = { label = e.label, t = os.clock(), target = q, wide = wide }
    lim_apply(mesh, bone)
    local c = r.ctl and r.ctl[bone]
    if c then
        pcall(function()
            r.pc:SetControlTargetOrientation(c.name, q2rot(q), 0.0, true, false, true, false)
            r.pc:SetControlAngularData(c.name, c.hz * (M.STRENGTH[1] or 0.8), M.CFG.tension_damp, 0.0, 0.0, true, true, false)
        end)
    end
    -- (the jolt: the limb's two parts kicked apart round the joint, the way it was going)
    pcall(function()
        local wc = mesh:GetPhysicsAngularVelocityInDegrees(FN[bone])
        local wp = mesh:GetPhysicsAngularVelocityInDegrees(FN[e.p])
        local ax = vnorm(v3(wc.X - wp.X, wc.Y - wp.Y, wc.Z - wp.Z))
        local j = M.CFG.dislocate_jolt
        if r.dead or r.lifeless then j = 0.0 end      -- (limp: no kick of his own - it flung him)
        M.twist(mesh, bone, vmul(ax, j))
    end)
    crack(r, mesh, bone, true)
    local reg = JOINT_REGION[bone]
    if reg then
        set_state(reg, 1)
        r.quiet = r.quiet or {}
        r.quiet[reg] = r.t + 0.15
    end
    log("dislocated: %s (%s)", e.label, why or string.format("past its range by %.0f / %.0f deg", over_s, over_t))
    if _G.ARHUD then pcall(_G.ARHUD.dislocated, M.dislocated()) end
end
function M.dislocated()
    local list = {}
    for _, d in pairs(dis) do list[#list + 1] = d end
    table.sort(list, function(a, b) return a.t < b.t end)
    local names = {}
    for i, d in ipairs(list) do names[i] = d.label end
    return names
end
local function dislocation_tick(pawn, r)
    local C = M.CFG
    if not (C.dislocate and lim) then return end
    if r.t < C.dislocate_grace or r.t < (r.quiet_all or 0.0) then return end
    local mesh = pawn.Mesh
    for _, bone in ipairs(DISLOC) do
        local j = lim.list[bone]
        if j and not dis[bone] then
            local ok, os_, ot = pcall(joint_over, mesh, j)
            if ok then
                local over = max(os_, ot)
                local m = r.max_over[bone]
                if not m or over > m then r.max_over[bone] = over end
                if over > C.dislocate_over then
                    local okw, rate = pcall(function()
                        local wc = mesh:GetPhysicsAngularVelocityInDegrees(FN[bone])
                        local wp = mesh:GetPhysicsAngularVelocityInDegrees(FN[j.parent])
                        return vlen(v3(wc.X - wp.X, wc.Y - wp.Y, wc.Z - wp.Z))
                    end)
                    if okw and rate > C.dislocate_rate then dislocate(pawn, r, bone, os_, ot) end
                end
            end
        end
    end
end


-- ------------------------------------------------------------------ falling, on his feet and as a ragdoll
-- ("fix the falling speed of the player to be more realistic, it seems like it stops getting faster after falling for 4
-- seconds", 2026-11-10: the engine's terminal velocity, 4000 cm/s - 90 mph - reached in under 3 s at STORROR's gravity of
-- 1500 cm/s/s, then flat.) Air drag instead, as on a falling body: a pull against his speed growing with its square, so
-- he keeps getting faster, by less and less, toward `terminal` (a person falling belly down, 120 mph); the engine's own
-- cap raised to `cap`, out of the way. Only once he is falling faster than `from`: a jump is left as it was.
M.FALL = { on = true, terminal = 5400.0, cap = 6500.0, from = 300.0 }
-- (NEWTONS LAW on the RAGDOLL tab: no air's drag - gravity alone, faster and faster - to `newton_cap`, 400 mph; and his spin
-- carried into the ragdoll and held through the air - M.CARRY, M.KEEPSPIN. "make the fall speed cap out at 400mph. combine
-- the 400mph and normal spinning in the settings and call it newtons law", 2026-11-11)
M.FALL.newton_cap = 400.0 * 44.704
function M.newton() local Mn = _G.ARMENU; return not (Mn and Mn.newtons_law and not Mn.newtons_law()) end
M.GRIP = { on = true, below = 80.0, k = 6.0, slide_mu = 0.6,
    -- (his turning held too: lying there, his trunk turning slower than `turn_below` deg/s about the up, braked - `turn_k` a
    -- second; "slides or spins" on the ground, 2026-11-10)
    turn_below = 90.0, turn_k = 8.0,
    -- (a hard landing - coming down faster than `limp_vz` cm/s - and the fall animation's pull and the protect pose let go at
    -- once: held for half a second more, he lay "stiff on ground at first upon landing", 2026-11-10)
    limp_vz = 450.0 }
local fall = { t = 0.0, top = 0.0, vol = nil, g = 1500.0 }
local function drag_dv(sp, g, dt)          -- (the speed taken off in dt, falling at sp)
    local T = M.FALL.terminal
    return g * (sp / T) * (sp / T) * dt
end
function M.fall_end(pawn, why)
    if fall.t > 1.5 then log("fell %.1f s, %.0f mph at the most (%s)", fall.t, fall.top / 44.704, why) end
    fall.t, fall.top = 0.0, 0.0
end
local function fall_tick(pawn, dt)
    local F = M.FALL
    if not F.on then return end
    local cm = pawn.CharacterMovement
    -- (the engine's cap raised, once for each physics volume he is in)
    pcall(function()
        local vol = cm:GetPhysicsVolume()
        if vol and vol:IsValid() and vol:GetAddress() ~= fall.vol then
            fall.vol = vol:GetAddress()
            if vol.TerminalVelocity < F.cap then
                log("terminal velocity %.0f -> %.0f cm/s (air drag takes over)", vol.TerminalVelocity, F.cap)
                vol.TerminalVelocity = F.cap
            end
            fall.newton = nil
        end
        local nw = M.newton()
        if vol and vol:IsValid() and fall.newton ~= nw then
            fall.newton = nw
            vol.TerminalVelocity = nw and F.newton_cap or F.cap
            local gz = cm:GetGravityZ()
            if gz < -1.0 then fall.g = -gz end
        end
    end)
    local mode = cm.MovementMode
    local v = cm.Velocity
    local vx, vy, vz = v.X, v.Y, v.Z
    if (mode == 3 or mode == 5) and vz < -F.from then
        local sp = sqrt(vx * vx + vy * vy + vz * vz)
        if not M.newton() then
            local k = max(0.0, 1.0 - drag_dv(sp, M.GRAV.base, dt) / sp)
            cm.Velocity = { X = vx * k, Y = vy * k, Z = vz * k }
        end
        fall.t = fall.t + dt
        if sp > fall.top then fall.top = sp end
    elseif fall.t > 0.0 then
        M.fall_end(pawn, string.format("landed, mode %d", mode))
    end
end
-- (the ragdoll falling, through the air only: STORROR's damping of his bodies given back for the fall as a whole, then the
-- same drag as on his feet. Every body of its ragdoll is damped 0.7 a second - as through thick air: a ragdoll could fall
-- no faster than 1500 / 0.7 = 2100 cm/s, 48 mph, and was near it within a second or two - "in ragdoll state you fall way
-- slower for some reason", 2026-11-10. Given back on all his bodies alike, by his hips' speed: the limbs still swing
-- against each other as damped as before.)
-- (by the speed of all of him - his bodies' speeds weighed by their mass - not his hips': spinning fast, a cannonball, his
-- hips swung up and down round his middle, and the drag, the square of their speed, held him up the more on the way down
-- than it took off on the way up - he fell at 580 cm/s/s, "the tuck fall actually makes the player fly", 2026-11-11.
-- And his turn as a whole given back too - the turn of his trunk, carried by every part of him round his middle - with
-- its own damping: given back only his speed, a flip's turn died away in a moment, "when the body is spinning forward the
-- body should keep spinning forward during ragdoll right now it kinda just stops all momentum", 2026-11-11. His limbs'
-- swings against each other stay as damped as before.)
M.COM = { bones = { "pelvis", "spine_03", "spine_05", "head", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
                    "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }, mass = { addr = nil } }
function M.COM.of(mesh)
    local C = M.COM
    local addr = mesh:GetAddress()
    if C.mass.addr ~= addr then C.mass = { addr = addr } end
    local sx, sy, sz, sm, px, py, pz = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    local P = {}
    for _, bn in ipairs(C.bones) do
        local m = C.mass[bn]
        if m == nil then
            local ok, v = pcall(function() return mesh:GetBoneMass(FN[bn], true) end)
            m = (ok and v and v > 0.1) and v or 0.0
            C.mass[bn] = m
        end
        if m > 0.0 then
            local ok, u, q = pcall(function() return mesh:GetPhysicsLinearVelocity(FN[bn]), mesh:GetSocketLocation(FN[bn]) end)
            if ok and u and q then
                sx, sy, sz, sm = sx + u.X * m, sy + u.Y * m, sz + u.Z * m, sm + m
                px, py, pz = px + q.X * m, py + q.Y * m, pz + q.Z * m
                P[bn] = { p = v3(q.X, q.Y, q.Z), v = v3(u.X, u.Y, u.Z), m = m }
            end
        end
    end
    if sm <= 0.0 then return nil end
    return v3(sx / sm, sy / sm, sz / sm), v3(px / sm, py / sm, pz / sm), P
end
-- his turn as a whole, rad/s: his angular momentum about his middle over his inertia there - his parts' swings against
-- each other cancel in it, only the turn of all of him is left. `Lw`: a momentum of one's own to turn into a turn instead
function M.COM.turn(vc, c0, P, Lw)
    local Lx, Ly, Lz = 0.0, 0.0, 0.0
    local Ixx, Iyy, Izz, Ixy, Ixz, Iyz = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    for _, b in pairs(P) do
        local rx, ry, rz = b.p.x - c0.x, b.p.y - c0.y, b.p.z - c0.z
        local ux, uy, uz = b.v.x - vc.x, b.v.y - vc.y, b.v.z - vc.z
        local m = b.m
        Lx, Ly, Lz = Lx + m * (ry * uz - rz * uy), Ly + m * (rz * ux - rx * uz), Lz + m * (rx * uy - ry * ux)
        local rr = rx * rx + ry * ry + rz * rz
        Ixx, Iyy, Izz = Ixx + m * (rr - rx * rx), Iyy + m * (rr - ry * ry), Izz + m * (rr - rz * rz)
        Ixy, Ixz, Iyz = Ixy - m * rx * ry, Ixz - m * rx * rz, Iyz - m * ry * rz
    end
    local Lm = v3(Lx, Ly, Lz)
    if Lw then Lx, Ly, Lz = Lw.x, Lw.y, Lw.z end
    -- (the inertia's inverse, by its cofactors)
    local a, b2, c, d, e, f = Ixx, Ixy, Ixz, Iyy, Iyz, Izz
    local A = d * f - e * e
    local B = -(b2 * f - c * e)
    local C = b2 * e - c * d
    local det = a * A + b2 * B + c * C
    if abs(det) < 1e-6 then return nil end
    local D = a * f - c * c
    local E = -(a * e - b2 * c)
    local F = a * d - b2 * b2
    local wx = (A * Lx + B * Ly + C * Lz) / det
    local wy = (B * Lx + D * Ly + E * Lz) / det
    local wz = (C * Lx + E * Ly + F * Lz) / det
    return v3(wx, wy, wz), Lm
end
M.SPIN_HOLD = { k = 10.0, least = 3.0e4, reset = 0.35 }
local function fall_ragdoll(mesh, vel, r, dt)
    if not M.FALL.on then return end
    local vc = M.COM.of(mesh)
    vel = vc or vel
    local sp = vlen(vel)
    if sp < 1.0 then return end
    -- (only the air's drag here: STORROR's damping of every part of him is undone at all times he is down - M.UNDAMP)
    local drag = (sp >= M.FALL.from) and drag_dv(sp, M.GRAV.base, M.pdt(dt)) / sp or 0.0
    if M.newton() then drag = (sp > M.FALL.newton_cap) and (1.0 - M.FALL.newton_cap / sp) or 0.0 end
    if drag > 1e-7 then pcall(function() mesh:AddImpulseToAllBodiesBelow(fv(vmul(vel, -drag)), FN["pelvis"], true, true) end) end
end
-- His whole body's turn as he goes down ("he stops spinning", 2026-11-11): on his feet, each frame, the turn of all of him
-- as his animation moves him - his parts' places frame to frame, weighed by their mass: his angular momentum over his
-- inertia, so a run's sway (his hips one way, his shoulders the other) comes to nothing and a flip to all of its turn. As
-- the ragdoll begins, if his body has less turn than that, it is given the rest - a turn of all of him round his middle.
M.ANIMSPIN = { on = false, least = 60.0, most = 1500.0, keep = 0.85, prev = nil, W = nil, vc = nil,
               mass = { pelvis = 8.24, spine_03 = 3.69, spine_05 = 5.16, head = 5.53, upperarm_l = 2.34, upperarm_r = 2.34,
                        lowerarm_l = 2.43, lowerarm_r = 2.43, thigh_l = 2.78, thigh_r = 2.78, calf_l = 3.41, calf_r = 3.41,
                        foot_l = 1.82, foot_r = 1.82 } }
function M.ANIMSPIN.track(pawn, dt)
    local A = M.ANIMSPIN
    if not A.on or dt <= 1e-4 then return end
    local mesh = pawn.Mesh
    local now = {}
    for bn in pairs(A.mass) do
        local ok, q = pcall(function() return mesh:GetSocketLocation(FN[bn]) end)
        if ok and q then now[bn] = v3(q.X, q.Y, q.Z) end
    end
    local prev = A.prev
    A.prev = now
    if not prev then return end
    local P, sm, cx, cy, cz, vx, vy, vz = {}, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    for bn, m in pairs(A.mass) do
        local a, b = prev[bn], now[bn]
        if a and b then
            local v = vmul(vsub(b, a), 1.0 / dt)
            P[bn] = { p = b, v = v, m = m }
            sm = sm + m
            cx, cy, cz = cx + b.x * m, cy + b.y * m, cz + b.z * m
            vx, vy, vz = vx + v.x * m, vy + v.y * m, vz + v.z * m
        end
    end
    if sm <= 0.0 then return end
    local vc = v3(vx / sm, vy / sm, vz / sm)
    -- (a jump of all of him - a teleport, a reset - is no motion of his)
    if vlen(vc) > 6000.0 then A.W, A.vc = nil, nil; return end
    local W = M.COM.turn(vc, v3(cx / sm, cy / sm, cz / sm), P)
    if not W then return end
    -- (eased a little over frames: a frame's step of a bone is uneven)
    A.W = A.W and vadd(vmul(A.W, 0.5), vmul(W, 0.5)) or W
    A.vc = vc
end
function M.ANIMSPIN.give(pawn, r)
    local A = M.ANIMSPIN
    if not A.on then return end
    local Wa = r.anim_W
    local mesh = pawn.Mesh
    local vc, c0, P = M.COM.of(mesh)
    if not vc then return end
    local Wp = M.COM.turn(vc, c0, P)
    if not Wp then return end
    local d = 180.0 / math.pi
    local la, lp = Wa and vlen(Wa) * d or 0.0, vlen(Wp) * d
    if la < A.least then
        log("spin as he went down: %.0f deg/s in his animation, %.0f in the ragdoll - nothing to give", la, lp)
        return
    end
    -- (along the animation's turn, how much the ragdoll already has)
    local along = vdot(Wp, vnorm(Wa)) * d
    if along >= la * A.keep then
        log("spin as he went down: %.0f deg/s in his animation, %.0f in the ragdoll - kept as it is", la, lp)
        return
    end
    local dW = vsub(Wa, Wp)
    local l = vlen(dW) * d
    if l > A.most then dW = vmul(dW, A.most / l) end
    for bn, b in pairs(P) do
        pcall(function()
            mesh:SetPhysicsLinearVelocity(fv(vcross(dW, vsub(b.p, c0))), true, FN[bn])
            mesh:SetPhysicsAngularVelocityInDegrees(fv(vmul(dW, d)), true, FN[bn])
        end)
    end
    log("spin as he went down: %.0f deg/s in his animation, %.0f in the ragdoll - given %.0f", la, lp, min(l, A.most))
end

-- (the engine's own step: it simulates at most `PHYS_DT` s a frame - STORROR's physics settings, MaxPhysicsDeltaTime 0.1 -
-- so on a slower frame, a gore cut's 165 ms, what is given back or taken off by the second is reckoned on that much, no
-- more: on the whole frame, more damping was given back than the engine took)
M.PHYS_DT = 0.1
function M.pdt(dt) return min(dt, M.PHYS_DT) end
-- No brake of STORROR's on him ("the momentum is wrong, its like the inertia doesnt carry or it slowly disappates", "An
-- object at rest stays at rest, and an object in motion stays in motion ... unless acted upon by an unbalanced force",
-- 2026-11-11): every body of his ragdoll is damped by STORROR - his speed 0.7 a second, his turning 1.0 a second, as if
-- through syrup - and given back only in part, only well up in the air, his tumbles died away. Undone now on every body,
-- every frame he is down, on the ground and in the air alike: what slows him is the ground's friction, what he hits and
-- the air. (A part all but still is left damped - `least_v` cm/s, `least_w` deg/s - so he comes to rest.)
M.UNDAMP = { on = true, least_v = 15.0, least_w = 15.0, addr = nil, bones = nil }
function M.UNDAMP.tick(mesh, r, dt)
    local U = M.UNDAMP
    if not U.on then return end
    -- (with his spin held, its give-back is the hold's: his speed given back as a whole there, in the same pass - this
    -- loop over every part cost 0.85 ms a frame; "smooth but laggy", 2026-11-11)
    if M.KEEPSPIN.on and M.newton() and not r.grounded then return end
    local pa = physics_asset(mesh)
    if not pa then return end
    if U.addr ~= pa:GetAddress() then
        U.addr, U.bones = pa:GetAddress(), {}
        pcall(function()
            pa.SkeletalBodySetups:ForEach(function(i, e)
                local bs = e:get()
                if bs and bs:IsValid() then
                    U.bones[#U.bones + 1] = { name = FName(bs.BoneName:ToString()), lin = bs.DefaultInstance.LinearDamping,
                                              ang = bs.DefaultInstance.AngularDamping }
                end
            end)
        end)
        log("undamped: %d bodies of his ragdoll", #U.bones)
    end
    local lv, lw, pdt = U.least_v * U.least_v, U.least_w * U.least_w, M.pdt(dt)
    for _, bd in ipairs(U.bones) do
        local cl, ca = (bd.lin or 0.0) * pdt, (bd.ang or 0.0) * pdt
        local bl, ba = cl / max(0.05, 1.0 - cl), ca / max(0.05, 1.0 - ca)
        pcall(function()
            if bl > 0.0 then
                local v = mesh:GetPhysicsLinearVelocity(bd.name)
                if v.X * v.X + v.Y * v.Y + v.Z * v.Z > lv then
                    mesh:SetPhysicsLinearVelocity({ X = v.X * bl, Y = v.Y * bl, Z = v.Z * bl }, true, bd.name)
                end
            end
            if ba > 0.0 then
                local w = mesh:GetPhysicsAngularVelocityInDegrees(bd.name)
                if w.X * w.X + w.Y * w.Y + w.Z * w.Z > lw then
                    mesh:SetPhysicsAngularVelocityInDegrees({ X = w.X * ba, Y = w.Y * ba, Z = w.Z * ba }, true, bd.name)
                end
            end
        end)
    end
end
-- His angular momentum, booked ("he stops spinning", "bodys doing some weird ass lean?", "bumping off the side of a building
-- and for about 3 seconds it sends him flying then all speed stops for no reason", 2026-11-11): all of him - every body of
-- his ragdoll by its own centre of mass, its speed, and its own turn through its own inertia - about the centre of all of
-- him. In the air only something from outside him can change it. Taken as his tick begins (after the engine's step) and
-- as it ends (after all this mod does to him), and what changed it booked: to this mod, or to the engine's step - that
-- split by his muscles on, limp, or holding - a sudden change (`jump` of it) being something he met. Logged each `every` s
-- in the air and as he comes down, as factors: x1.00 is none of it lost or gained.
M.LEDGER = { on = false, every = 1.0, jump = 0.08, jump_abs = 3.0e4, addr = nil, names = nil, mass = nil, sim = nil, sim_t = -99.0 }
function M.LEDGER.measure(mesh)
    local G = M.LEDGER
    local addr = mesh:GetAddress()
    if G.addr ~= addr or not G.names then
        local pa = physics_asset(mesh)
        if not pa then return nil end
        G.addr, G.names, G.mass, G.sim, G.sim_t = addr, {}, {}, {}, -99.0
        pa.SkeletalBodySetups:ForEach(function(_, e)
            local bs = e:get()
            if bs and bs:IsValid() then G.names[#G.names + 1] = FName(bs.BoneName:ToString()) end
        end)
        for i, n in ipairs(G.names) do
            local ok, m = pcall(function() return mesh:GetBoneMass(n, true) end)
            G.mass[i] = (ok and m and m > 0.0) and m or 0.0
        end
    end
    local now = os.clock()
    if now - G.sim_t > 0.25 then
        G.sim_t = now
        for i, n in ipairs(G.names) do
            local ok, y = pcall(function() return mesh:IsSimulatingPhysics(n) end)
            G.sim[i] = (ok and y) and true or false
        end
    end
    local B, sm, cx, cy, cz, px, py, pz = {}, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    for i, n in ipairs(G.names) do
        local m = G.mass[i]
        if m > 0.0 and G.sim[i] then
            local ok, c, v, J = pcall(function()
                local w = mesh:GetPhysicsAngularVelocityInRadians(n)
                return mesh:GetCenterOfMass(n), mesh:GetPhysicsLinearVelocity(n), mesh:ScaleByMomentOfInertia({ X = w.X, Y = w.Y, Z = w.Z }, n)
            end)
            if ok and c and v and J then
                B[#B + 1] = { m, c.X, c.Y, c.Z, v.X, v.Y, v.Z, J.X, J.Y, J.Z, n }
                sm = sm + m
                cx, cy, cz = cx + c.X * m, cy + c.Y * m, cz + c.Z * m
                px, py, pz = px + v.X * m, py + v.Y * m, pz + v.Z * m
            end
        end
    end
    if sm <= 0.0 then return nil end
    cx, cy, cz, px, py, pz = cx / sm, cy / sm, cz / sm, px / sm, py / sm, pz / sm
    local Lx, Ly, Lz = 0.0, 0.0, 0.0
    for _, b in ipairs(B) do
        local m, rx, ry, rz = b[1], b[2] - cx, b[3] - cy, b[4] - cz
        local ux, uy, uz = b[5] - px, b[6] - py, b[7] - pz
        Lx = Lx + m * (ry * uz - rz * uy) + b[8]
        Ly = Ly + m * (rz * ux - rx * uz) + b[9]
        Lz = Lz + m * (rx * uy - ry * ux) + b[10]
    end
    return { L = v3(Lx, Ly, Lz), V = v3(px, py, pz), n = #B, B = B, C = v3(cx, cy, cz) }
end
function M.LEDGER.new() return { t = 0.0, n = 0, mod = 0.0, mods = 0.0, live = 0.0, lives = 0.0, live_t = 0.0, limp = 0.0, limps = 0.0,
    limp_t = 0.0, hold = 0.0, hold_t = 0.0, jumps = 0, jump = 0.0, rs = 0.0, rn = 0, slow = 0, srs = 0.0, dtmax = 0.0, ms = 0.0 } end
-- (a change dL as shares of L: along it - its gain, or a loss - and across it, turning its way)
function M.LEDGER.part(dL, L)
    local l2 = vdot(L, L)
    if l2 < 1.0 then return 0.0, 0.0 end
    local a = vdot(dL, L) / l2
    return a, vlen(vsub(dL, vmul(L, a))) / sqrt(l2)
end
function M.LEDGER.line(z, head)
    local e = math.exp
    return string.format("%s this mod x%.2f (across %.0f%%); the engine's step: muscles on x%.2f in %.1f s (holding %.1f s x%.2f), limp x%.2f in %.1f s, across %.0f%%; %d sudden (something he met) x%.2f; frames up to %.0f ms",
        head, e(z.mod), 100.0 * z.mods, e(z.live), z.live_t, z.hold_t, e(z.hold), e(z.limp), z.limp_t, 100.0 * (z.lives + z.limps),
        z.jumps, e(z.jump), 1000.0 * z.dtmax)
end
function M.LEDGER.begin_(pawn, r, dt)
    local G = M.LEDGER
    if not G.on then return end
    if r.grounded then r.lg_b = nil; G.flush(r); return end
    local t0 = os.clock()
    local A = G.measure(pawn.Mesh)
    local B = r.lg_b
    r.lg_a, r.lg_b = A, nil
    if not (A and B) then return end
    local q = r.lg
    if not q then q = G.new(); q.L0, q.t0 = B.L, r.t - dt; r.lg, r.lg_s = q, G.new() end
    local s = r.lg_s
    local dL = vsub(A.L, B.L)
    local a, sd = G.part(dL, B.L)
    local jump = vlen(dL) > G.jump * vlen(B.L) + G.jump_abs
    for _, z in ipairs({ q, s }) do
        z.t, z.n, z.dtmax = z.t + dt, z.n + 1, max(z.dtmax, dt)
        if jump then z.jumps, z.jump = z.jumps + 1, z.jump + a
        elseif B.limp then z.limp, z.limps, z.limp_t = z.limp + a, z.limps + sd, z.limp_t + dt
        else
            z.live, z.lives, z.live_t = z.live + a, z.lives + sd, z.live_t + dt
            if B.hold then z.hold, z.hold_t = z.hold + a, z.hold_t + dt end
        end
    end
    -- (the engine's own time in the frame, from his fall - gravity and its damping on all of him - against the frame's;
    -- while he is still slow, gravity the most of it)
    if not jump and vlen(B.V) < 1000.0 and dt > 1e-4 then
        local ev = v3(-0.7 * B.V.x, -0.7 * B.V.y, -(r.g or 1500.0) - 0.7 * B.V.z)
        local el = vlen(ev)
        if el > 300.0 then
            local ratio = vdot(vsub(A.V, B.V), ev) / (el * el * dt)
            if dt > M.PHYS_DT + 0.005 then q.slow, q.srs = q.slow + 1, q.srs + ratio else q.rn, q.rs = q.rn + 1, q.rs + ratio end
        end
    end
    q.L1 = A.L
    if s.t >= G.every then
        log("%s", G.line(s, string.format("spin ledger, %.1f s into the air, L %.0fk, %.0f cm/s - its last %.1f s:", r.t - q.t0,
            vlen(A.L) / 1000.0, vlen(A.V), s.t)))
        r.lg_s = G.new()
    end
    q.ms = q.ms + (os.clock() - t0) * 1000.0
end
function M.LEDGER.finish_(pawn, r, dt)
    local G = M.LEDGER
    if not G.on then return end
    if r.grounded then r.lg_a, r.lg_b = nil, nil; return end
    local t0 = os.clock()
    local A = r.lg_a
    r.lg_a = nil
    local B = G.measure(pawn.Mesh)
    if not B then return end
    B.limp = (r.dead or r.lifeless or (r.stun_until and r.t < r.stun_until)) and true or false
    B.hold = r.hold ~= nil
    r.lg_b = B
    local q, s = r.lg, r.lg_s
    if A and q and s then
        local a, sd = G.part(vsub(B.L, A.L), A.L)
        q.mod, q.mods, s.mod, s.mods = q.mod + a, q.mods + sd, s.mod + a, s.mods + sd
    end
    if q then q.ms = q.ms + (os.clock() - t0) * 1000.0 end
end
function M.LEDGER.flush(r)
    local q = r.lg
    r.lg, r.lg_s = nil, nil
    if not q or q.t < 0.3 then return end
    local L0, L1 = vlen(q.L0), vlen(q.L1 or q.L0)
    local turned = 0.0
    if L0 > 1.0 and L1 > 1.0 then turned = deg(math.acos(max(-1.0, min(1.0, vdot(q.L0, q.L1) / (L0 * L1))))) end
    log("%s", M.LEDGER.line(q, string.format("spin ledger, down after %.1f s in the air: L %.0fk -> %.0fk (its way turned %.0f deg); the engine's time %.2f of the frames' (%d%s); %.2f ms a frame to book -",
        q.t, L0 / 1000.0, L1 / 1000.0, turned, q.rn > 0 and q.rs / q.rn or 0.0, q.rn,
        q.slow > 0 and string.format(", over %.0f ms: %.2f in %d", M.PHYS_DT * 1000.0, q.srs / q.slow, q.slow) or "", q.ms / max(1, q.n))))
end
function M.LEDGER.begin(pawn, r, dt)
    local ok, e = pcall(M.LEDGER.begin_, pawn, r, dt)
    if not ok and not M.LEDGER.err then M.LEDGER.err = true; log("spin ledger failed (%s)", tostring(e)) end
end
function M.LEDGER.finish(pawn, r, dt)
    local ok, e = pcall(M.LEDGER.finish_, pawn, r, dt)
    if not ok and not M.LEDGER.err then M.LEDGER.err = true; log("spin ledger failed (%s)", tostring(e)) end
end
-- His motion carried into the ragdoll ("still not spinning correctly", 2026-11-11): STORROR's ragdoll begins from his
-- animation's pose with his parts all but still, and he was given only his speed as a whole - a flip's turn was gone the
-- moment he went down (his angular momentum a second into a fall 20k-90k; a flip's is 300k-600k). On his feet every part's
-- motion is tracked frame to frame - where it goes and how it turns - and the first frame down each part of the ragdoll
-- is given exactly the motion it had: all of him going on as he was, his spin with it. (A trip's own knock is left as it
-- was.)
M.CARRY = { on = true, names = nil, addr = nil, prev = nil, vel = nil, t = -99.0, most_w = 1800.0 }
function M.CARRY.track(pawn, dt)
    local K = M.CARRY
    if not K.on or dt <= 1e-4 then return end
    local mesh = pawn.Mesh
    local addr = mesh:GetAddress()
    if K.addr ~= addr or not K.names then
        local pa = physics_asset(mesh)
        if not pa then return end
        K.addr, K.names, K.prev, K.vel = addr, {}, nil, nil
        pa.SkeletalBodySetups:ForEach(function(_, e)
            local bs = e:get()
            if bs and bs:IsValid() and bs.PhysicsType ~= 1 then K.names[#K.names + 1] = FName(bs.BoneName:ToString()) end
        end)
    end
    local now = {}
    for _, n in ipairs(K.names) do
        local ok, t = pcall(function() return mesh:GetSocketTransform(n, 0) end)
        if ok and t then
            local p, q = t.Translation, t.Rotation
            now[#now + 1] = { n = n, p = v3(p.X, p.Y, p.Z), q = { x = q.X, y = q.Y, z = q.Z, w = q.W } }
        end
    end
    local prev = K.prev
    K.prev = now
    if not prev or #prev ~= #now then return end
    local vel, big = {}, 0.0
    for i, b in ipairs(now) do
        local a = prev[i]
        local v = vmul(vsub(b.p, a.p), 1.0 / dt)
        local dq = qmul(b.q, qinv(a.q))
        if dq.w < 0.0 then dq = { x = -dq.x, y = -dq.y, z = -dq.z, w = -dq.w } end
        local sn = sqrt(dq.x * dq.x + dq.y * dq.y + dq.z * dq.z)
        local w = v3(0.0, 0.0, 0.0)
        if sn > 1e-7 then w = vmul(v3(dq.x, dq.y, dq.z), 2.0 * atan(sn, dq.w) / (sn * dt)) end
        vel[i] = { n = b.n, v = v, w = w }
        if vlen(v) > big then big = vlen(v) end
    end
    -- (a jump of all of him - a teleport, a reset, a pose snapped - is no motion of his: not kept)
    if big > 6000.0 then K.vel = nil; return end
    K.vel, K.t = vel, os.clock()
end
function M.CARRY.take()
    local K = M.CARRY
    local v = (K.on and M.newton() and K.vel and os.clock() - K.t < 0.15) and K.vel or nil
    K.prev, K.vel = nil, nil
    return v
end
function M.CARRY.give_(pawn, r)
    local vel = r.carry_anim
    r.carry_anim = nil
    if not vel then return end
    local mesh = pawn.Mesh
    local wmax = M.CARRY.most_w * math.pi / 180.0
    local n = 0
    for _, b in ipairs(vel) do
        pcall(function()
            if not mesh:IsSimulatingPhysics(b.n) then return end
            local c, so = mesh:GetCenterOfMass(b.n), mesh:GetSocketLocation(b.n)
            local w = b.w
            local wl = vlen(w)
            if wl > wmax then w = vmul(w, wmax / wl) end
            -- (the bone's motion at its centre of mass: its speed, and its turn about the bone)
            local v = vadd(b.v, vcross(w, v3(c.X - so.X, c.Y - so.Y, c.Z - so.Z)))
            mesh:SetPhysicsLinearVelocity(fv(v), false, b.n)
            mesh:SetPhysicsAngularVelocityInRadians(fv(w), false, b.n)
            n = n + 1
        end)
    end
    st.push = nil                       -- (his own motion, all of it: no speed of the capsule's laid over it)
    local m = M.LEDGER.measure(mesh)
    -- (his speed as a whole no less than he really had: in a fall his animation's bones lagged his body's going - 720
    -- cm/s of 2140 carried, "sometimes momentum doesnt carry when the ragdoll starts", 2026-11-11. What is missing given
    -- to all of him alike, his turn and his limbs' swings as they were)
    local iv = r.impact_v
    if m and iv and vlen(iv) > 150.0 and vlen(m.V) < 0.85 * vlen(iv) then
        local dv = vsub(iv, m.V)
        pcall(function() mesh:AddImpulseToAllBodiesBelow(fv(dv), FN["pelvis"], true, true) end)
        log("his speed made up to %.0f cm/s as he went down (his animation carried %.0f)", vlen(iv), vlen(m.V))
    end
    log("his motion carried into the ragdoll: %d parts, all of him at %.0f cm/s, angular momentum %.0fk", n, m and vlen(m.V) or -1.0,
        m and vlen(m.L) / 1000.0 or -1.0)
end
function M.CARRY.give(pawn, r)
    local ok, e = pcall(M.CARRY.give_, pawn, r)
    if not ok then log("carrying his motion failed (%s)", tostring(e)) end
end
-- His spin held in the air ("didnt work", 2026-11-11): his motion is carried into the ragdoll, but in the air the engine's
-- own step still took 50-90% of his angular momentum a second - its joints' corrections, its damping, his muscles' pulls -
-- where nothing outside him acts (booked by M.LEDGER). So it is held, as Newton has it: in the air his angular momentum -
-- all of him, about his middle, exactly - is kept at what it was as he left the ground; each frame whatever the engine's
-- step took or added is put back as a turn of all of him round his middle. Something he meets - a sudden change in it -
-- is taken as the new one; on the ground none of it, the ground's friction slows him. His shape still changes his turn's
-- pace: tucked he turns faster, spread out slower - the same angular momentum.
-- (`max_w`: the turn held at most, deg/s, as all of him - 14 bumps down a building wound him up to 1800k, a blur of
-- 1000 deg/s that flung his arms over his head and behind his back, "spazzing in the air", 2026-11-11)
-- (`reg`, `most_dw`, 2026-11-11 - "body gets very glitchy at high speeds stuttering and glitching and basically teleporting":
-- his parts as points, stretched out straight he had next to no inertia about his length, and a little to give back about
-- it became a huge turn - a body flung at 18000 cm/s. Each part's own girth added as `reg` of the mean, and the turn given
-- in a frame no more than `most_dw` deg/s)
-- (`touch`: s after anything touches him - STORROR's own mesh-hit callbacks - that his spin is left to what he touches, and
-- taken afresh after: held against a wall he slid down, the hold fought its friction every frame and he went wild -
-- "if you hit the building the player starts bugging out like crazy", 2026-11-11)
-- (`jump` 0.45, `jump_abs` 1.2e5, 2026-11-11: what he meets is known from STORROR's hit callbacks now (`touch`); a sudden
-- change taken as a hit was more often his pose slamming his limbs into their ends - 17 "hits" in a fall with 0.4 s of
-- touching, his spin dropped each time - "some of the poses are stopping the momentum from working")
-- (`never_less`: in the air nothing slows his spin - what he touches or hits may turn its way or add to it, never take from
-- it; `max_w` 1440 and `most_dw` 2000, only a stop against a runaway blur - "can you stop any source from slowing the
-- players spin down", 2026-11-11)
M.KEEPSPIN = { on = true, never_less = true, rate0 = 4.0, rate_most = 8.0, jump = 0.45, jump_abs = 1.2e5, least = 1.5e4, gain = 0.9, max_w = 1440.0, reg = 0.2, most_dw = 2000.0, touch = 0.25 }
if not _G.AR_HIT_HOOKS then
    _G.AR_HIT_HOOKS = true
    for _, fn in ipairs({ "OnMeshCollisionDetected", "PhysicsImpactCallback" }) do
        pcall(RegisterHook, "/Script/HumanEmotion.ParkourComponent:" .. fn, function()
            local A = _G.AR
            if A and A.KEEPSPIN then A.KEEPSPIN.touch_t = os.clock() end
        end)
    end
end
function M.KEEPSPIN.tick_(pawn, r, dt)
    local K = M.KEEPSPIN
    if not K.on or not M.newton() then r.ks = nil; return end
    if r.grounded then M.KEEPSPIN.said(r); r.ks_acc = 0.0; return end
    -- (every other frame, the time between taken whole: the measure and the writes cost a ms a frame)
    r.ks_acc = (r.ks_acc or 0.0) + dt
    r.ks_flip = not r.ks_flip
    if r.ks_flip then return end
    dt, r.ks_acc = r.ks_acc, 0.0
    local mesh = pawn.Mesh
    local m = M.LEDGER.measure(mesh)
    if not m then return end
    -- (STORROR's damping of his speed, 0.7 a second, given back on all of him alike)
    local cl = 0.7 * M.pdt(dt)
    local bl = cl / max(0.05, 1.0 - cl)
    local gv = vmul(m.V, bl)
    local function give_speed() pcall(function() mesh:AddImpulseToAllBodiesBelow(fv(gv), FN["pelvis"], true, true) end) end
    local ks = r.ks
    if not ks then r.ks = { L = m.L, L0 = vlen(m.L), t0 = r.t, t = 0.0, back = 0.0, jumps = 0 }; give_speed(); return end
    ks.t = ks.t + dt
    -- (touching something: what it does to his spin is his, but the engine's own drain - learned in the air as `rate` a
    -- second - still given back; taken as it was, every graze let the drain take his spin, 204k down to 42k in a fall -
    -- "momentum is gone please bring it back", 2026-11-11)
    ks.rate = ks.rate or K.rate0
    local Lkeep = vlen(ks.L)
    local touching_now = os.clock() - (K.touch_t or -99.0) < K.touch
    if touching_now then
        ks.touched = (ks.touched or 0.0) + dt
        ks.L = vmul(m.L, 1.0 + min(K.rate_most, ks.rate) * dt)
        if K.never_less then local l = vlen(ks.L); if l > 1.0 and l < Lkeep then ks.L = vmul(ks.L, Lkeep / l) end end
    end
    -- (his inertia about his middle - his parts as points, near enough; what is left over is put back the next frame)
    local C = m.C
    local a, b, c, d, e, f = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    for _, q in ipairs(m.B) do
        local w, rx, ry, rz = q[1], q[2] - C.x, q[3] - C.y, q[4] - C.z
        a, d, f = a + w * (ry * ry + rz * rz), d + w * (rx * rx + rz * rz), f + w * (rx * rx + ry * ry)
        b, c, e = b - w * rx * ry, c - w * rx * rz, e - w * ry * rz
    end
    local rg = K.reg * (a + d + f) / 3.0
    a, d, f = a + rg, d + rg, f + rg
    local A_, B_, C_ = d * f - e * e, c * e - b * f, b * e - c * d
    local det = a * A_ + b * B_ + c * C_
    if abs(det) < 1e-6 then give_speed(); return end
    local D_, E_, F_ = a * f - c * c, b * c - a * e, a * d - b * b
    local Lr = vlen(ks.L)
    local dL = vsub(ks.L, m.L)
    -- (he met something: his spin is what it is now)
    if vlen(dL) > K.jump * Lr + K.jump_abs then
        ks.L, ks.jumps = m.L, ks.jumps + 1
        if K.never_less then local l = vlen(ks.L); if l > 1.0 and l < Lkeep then ks.L = vmul(ks.L, Lkeep / l) end end
        Lr = vlen(ks.L)
        dL = vsub(ks.L, m.L)
    end
    if Lr < K.least and vlen(m.L) < K.least then ks.L = m.L; give_speed(); return end
    -- (no faster than `max_w` as all of him: the held spin cut down to it)
    local L = ks.L
    local ox = (A_ * L.x + B_ * L.y + C_ * L.z) / det
    local oy = (B_ * L.x + D_ * L.y + E_ * L.z) / det
    local oz = (C_ * L.x + E_ * L.y + F_ * L.z) / det
    local ow = sqrt(ox * ox + oy * oy + oz * oz) * 180.0 / math.pi
    if ow > K.max_w then
        ks.L = vmul(L, K.max_w / ow)
        if not ks.capped then ks.capped = true; log("spin held to %.0f deg/s (it was %.0f)", K.max_w, ow) end
        Lr = vlen(ks.L)
        dL = vsub(ks.L, m.L)
    end
    local g = K.gain / det
    local wx = (A_ * dL.x + B_ * dL.y + C_ * dL.z) * g
    local wy = (B_ * dL.x + D_ * dL.y + E_ * dL.z) * g
    local wz = (C_ * dL.x + E_ * dL.y + F_ * dL.z) * g
    local wl = sqrt(wx * wx + wy * wy + wz * wz) * 180.0 / math.pi
    if wl > K.most_dw then local k = K.most_dw / wl; wx, wy, wz = wx * k, wy * k, wz * k end
    for _, q in ipairs(m.B) do
        local rx, ry, rz = q[2] - C.x, q[3] - C.y, q[4] - C.z
        pcall(function()
            mesh:SetPhysicsLinearVelocity({ X = wy * rz - wz * ry + gv.x, Y = wz * rx - wx * rz + gv.y, Z = wx * ry - wy * rx + gv.z }, true, q[11])
            mesh:SetPhysicsAngularVelocityInRadians({ X = wx, Y = wy, Z = wz }, true, q[11])
        end)
    end
    if Lr > 1.0 then
        local fr_ = vdot(dL, ks.L) / (Lr * Lr)
        ks.back = ks.back + fr_
        -- (the drain's pace, learned while nothing touches him)
        if not touching_now and dt > 1e-3 then ks.rate = max(0.0, ks.rate + (fr_ / dt - ks.rate) * min(1.0, 2.0 * dt)) end
    end
end
-- (for "charaters still doing the wierd one arm up one arm down pose", 2026-11-11: each arm's way in his trunk's frame, every
-- `every` s in the air - up, forward, out to its own side - with what holds it)
M.POSELOG = { on = false, every = 0.5, t = 0.0 }
function M.POSELOG.tick(pawn, r, dt)
    local Q = M.POSELOG
    if not Q.on or r.grounded then return end
    Q.t = Q.t + dt
    if Q.t < Q.every then return end
    Q.t = 0.0
    local mesh = pawn.Mesh
    local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
    local rt = vnorm(vsub(pos(mesh, "clavicle_r"), pos(mesh, "clavicle_l")))
    local fw = vnorm(vcross(rt, up))
    local out = {}
    for _, sd in ipairs({ "l", "r" }) do
        local o = (sd == "r") and 1.0 or -1.0
        local h = vsub(pos(mesh, "hand_" .. sd), pos(mesh, "spine_03"))
        local ov = r.ovr and (r.ovr["upperarm_" .. sd] or r.ovr["lowerarm_" .. sd])
        local hurt = {}
        for _, k in ipairs({ "upperarm_", "lowerarm_", "hand_" }) do
            local e = parts[k .. sd]
            if e and e.state > 0 then hurt[#hurt + 1] = k .. M.STATES[e.state] end
            if dis[k .. sd] then hurt[#hurt + 1] = k .. "out" end
            if weak[k .. sd] then hurt[#hurt + 1] = k .. "limp" end
        end
        local cu, cl = r.ctl and r.ctl["upperarm_" .. sd], r.ctl and r.ctl["lowerarm_" .. sd]
        -- (where his muscle wants the upper arm - its target, from his collarbone as it is now - against where it is)
        local aim = ""
        pcall(function()
            local T = poses and ((not r.grounded and poses.targets.air) or poses.targets.nbp)["upperarm_" .. sd]
            if not T then return end
            local qc, qu = rot(mesh, "clavicle_" .. sd), rot(mesh, "upperarm_" .. sd)
            local now = qmul(qinv(qc), qu)
            local dq = abs(now.x * T.x + now.y * T.y + now.z * T.z + now.w * T.w)
            local ld = qrot(qinv(qu), vsub(pos(mesh, "lowerarm_" .. sd), pos(mesh, "upperarm_" .. sd)))
            local want = vnorm(qrot(qmul(qc, T), ld))
            local is = vnorm(vsub(pos(mesh, "lowerarm_" .. sd), pos(mesh, "upperarm_" .. sd)))
            aim = string.format(" | its aim up %+.2f fwd %+.2f out %+.2f, it is up %+.2f fwd %+.2f out %+.2f, %.0f deg off",
                vdot(want, up), vdot(want, fw), o * vdot(want, rt), vdot(is, up), vdot(is, fw), o * vdot(is, rt), deg(2.0 * math.acos(min(1.0, dq))))
        end)
        out[#out + 1] = string.format("%s hand fwd %+.0f out %+.0f up %+.0f cm, pull %.1f/%.1f Hz%s%s", sd, vdot(h, fw), o * vdot(h, rt), vdot(h, up),
            cu and cu.hz_now or -1.0, cl and cl.hz_now or -1.0, #hurt > 0 and (" " .. table.concat(hurt, ",")) or "", ov and (" [" .. tostring(ov) .. "]") or "") .. aim
    end
    -- (every joint against its target: the furthest off, to find what twists him)
    local offs = {}
    pcall(function()
        local A, B = (not r.grounded and poses.targets.air) or poses.targets.nbp, (r.air_pose and poses.targets[r.air_pose]) or poses.targets.protect
        for bone, c in pairs(r.ctl or {}) do
            local T = A[bone] and qnlerp(A[bone], B[bone] or A[bone], r.w or 0.0)
            if T and not (r.ovr and r.ovr[bone]) then
                local now = qmul(qinv(rot(mesh, c.e.p)), rot(mesh, bone))
                local dq = abs(now.x * T.x + now.y * T.y + now.z * T.z + now.w * T.w)
                offs[#offs + 1] = { bone, deg(2.0 * math.acos(min(1.0, dq))), c.hz_now or -1.0 }
            end
        end
        table.sort(offs, function(x, y) return x[2] > y[2] end)
    end)
    local worst = {}
    for i = 1, min(6, #offs) do worst[#worst + 1] = string.format("%s %.0f (%.0f)", offs[i][1], offs[i][2], offs[i][3]) end
    out[#out + 1] = "furthest off: " .. table.concat(worst, ", ")
    -- (each elbow from its shoulder in his chest bone's own axes: mirrored arms match in two and are opposite in one)
    pcall(function()
        local qc = qinv(rot(mesh, "spine_05"))
        local e = {}
        for _, sd in ipairs({ "l", "r" }) do
            local d = qrot(qc, vsub(pos(mesh, "lowerarm_" .. sd), pos(mesh, "upperarm_" .. sd)))
            e[#e + 1] = string.format("%s %+.0f %+.0f %+.0f", sd, d.x, d.y, d.z)
        end
        out[#out + 1] = "elbows in the chest's axes: " .. table.concat(e, " / ")
        -- (each upper arm's twist about itself, from its joint's zero, and how far its shoulder sits from the collarbone)
        local tw = {}
        for _, sd in ipairs({ "l", "r" }) do
            local ub, cb = "upperarm_" .. sd, "clavicle_" .. sd
            local qu, qcl = rot(mesh, ub), rot(mesh, cb)
            local R0 = M.joint_zero(mesh, ub)
            local D = qmul(qinv(R0), qmul(qinv(qcl), qu))
            local a = vnorm(qrot(qinv(qu), vsub(pos(mesh, "lowerarm_" .. sd), pos(mesh, ub))))
            local t = deg(2.0 * atan(D.x * a.x + D.y * a.y + D.z * a.z, D.w))
            if t > 180.0 then t = t - 360.0 elseif t < -180.0 then t = t + 360.0 end
            tw[#tw + 1] = string.format("%s twist %+.0f, shoulder %.1f cm from its collarbone", sd, t, vlen(vsub(pos(mesh, ub), pos(mesh, cb))))
        end
        out[#out + 1] = table.concat(tw, " / ")
    end)
    log("arms in the air, %.1f s down: %s; protect %.2f, %s, %s", r.t, table.concat(out, " | "), r.w or 0.0,
        (r.stun_until and r.t < r.stun_until) and "stunned" or "awake", r.hold and "holding" or "not holding")
end
-- (STORROR's sliding sound left on: a wall slide cut short - WALL SLIDE off, down he went - never came to its end, and its
-- loop went on and on with him standing still - "also wierd noise playing", 2026-11-11. Stopped as he goes down, and
-- whenever it plays while he stands still)
M.SLIDESND = { t = 0.0 }
function M.SLIDESND.stop(pawn, why)
    pcall(function()
        for _, e in pairs(pawn:K2_GetComponentsByClass(StaticFindObject("/Script/Engine.AudioComponent"))) do
            local c = (type(e) == "userdata" and e.IsValid and e:IsValid()) and e or (e.get and e:get())
            if c and c:IsValid() and c:GetFName():ToString() == "SlidingChannel" and c:IsPlaying() then
                c:Stop()
                log("STORROR's sliding sound stopped (%s)", why)
            end
        end
    end)
end
function M.SLIDESND.tick(pawn, dt)
    local S = M.SLIDESND
    S.t = S.t + dt
    if S.t < 0.5 then return end
    S.t = 0.0
    local v = pawn:GetVelocity()
    if v.X * v.X + v.Y * v.Y + v.Z * v.Z < 60.0 * 60.0 then M.SLIDESND.stop(pawn, "playing while he stood still") end
end
-- (his bleeding thinned while he moves fast - over `from` cm/s each stump at `k` of its rate and its spurts: a cut high up
-- had every stump streaming drops and splats down the building, the game from 15 to 25 ms a frame, and at 100 mph the
-- stutter showed - "after the body looses a limb or something while high up starts bugging out", 2026-11-11)
M.BLOODSPEED = { from = 1500.0, k = 0.25, burst_k = 0.35, base = nil }
function M.BLOODSPEED.tick(pawn, r)
    local G = _G.ARGORE
    if not (G and G.BLOOD) then return end
    local S = M.BLOODSPEED
    if not S.base then S.base = { rate = G.BLOOD.rate, end_rate = G.BLOOD.end_rate, burst = G.BLOOD.burst } end
    local fast = false
    if r then
        local u = pawn.Mesh:GetPhysicsLinearVelocity(FN["pelvis"])
        fast = (u.X * u.X + u.Y * u.Y + u.Z * u.Z) > S.from * S.from
    end
    local k, kb = fast and S.k or 1.0, fast and S.burst_k or 1.0
    G.BLOOD.rate, G.BLOOD.end_rate = S.base.rate * k, S.base.end_rate * k
    G.BLOOD.burst = math.max(1, math.floor(S.base.burst * kb + 0.5))
end
function M.KEEPSPIN.said(r)
    local ks = r.ks
    r.ks = nil
    if not ks or ks.t < 0.3 then return end
    log("spin held in the air %.1f s: angular momentum %.0fk as he left the ground, %.0fk as he came down; the engine's step took %.0f%% of it a second, given back; %d times he met something, %.1f s touching something (not held)",
        ks.t, ks.L0 / 1000.0, vlen(ks.L) / 1000.0, 100.0 * ks.back / ks.t, ks.jumps, ks.touched or 0.0)
end
function M.KEEPSPIN.tick(pawn, r, dt)
    local ok, e = pcall(M.KEEPSPIN.tick_, pawn, r, dt)
    if not ok and not M.KEEPSPIN.err then M.KEEPSPIN.err = true; log("holding his spin failed (%s)", tostring(e)) end
end
-- (his ragdoll's bodies' damping, from its physics asset: the hips')
local lin_damp_of = { addr = nil, v = 0.0 }
local function body_damping(mesh)
    local pa = physics_asset(mesh)
    if not pa then return 0.0 end
    if lin_damp_of.addr == pa:GetAddress() then return lin_damp_of.v end
    local v = 0.0
    pcall(function()
        pa.SkeletalBodySetups:ForEach(function(i, e)
            local b = e:get()
            if b and b:IsValid() and b.BoneName:ToString():lower() == "pelvis" then
                v = b.DefaultInstance.LinearDamping
                M.COM.ang_damp = b.DefaultInstance.AngularDamping
            end
        end)
    end)
    lin_damp_of.addr, lin_damp_of.v = pa:GetAddress(), v
    return v
end

-- ------------------------------------------------------------------ holding his injuries, kicking in pain, spasms, death
-- (the user, 2026-11-10: "holding injurys, it should be importance based, a severed limb first charater will try to hold
-- it for 4 seconds then give up, broken limbs and dislocated will just be held for 10 seconds, legs will always kick in
-- pain if the body gets hurt legs raise to chest, if the heads dislocated players considered dead nothing will happen";
-- "for the first 3 seconds of a limb being severed if a arm is there make it spasm")
--   HOLD: the most important injury not yet held its time - severed before broken before dislocated, the latest first -
--     held for M.HOLD[state] s, then the next. An arm's is held with the other hand, a leg's, the chest's or the head's with
--     both, each arm with its share of strength (M.STRENGTH); a hand on an arm cut through holds nothing. The hold is a spring between the hand and the place (on the
--     part, or a severed part's stump), pulling both; that arm's own pull let go while it holds.
--   KICK: hurt, his legs kick for `pain` s from the last hurt, drawn up to his chest and kicking out (`kick_reach` of the
--     way), out of step with each other, each leg with its share of strength; a leg cut through does not.
--   SPASM: what is left of an arm, `spasm_t` s from a part of it torn off: jerked about.
--   DEAD: his head put out or off, or his body blown apart: nothing pulls, nothing moves of itself.
-- (`extra` 0, was 1: Physics Control's extra damping is against the world, not his own body - a hand holding a hurt was held
-- back as if in syrup, and all of him with it: his turn and his speed in the air stopped whenever he held an injury, "the
-- body stops all momentum completely randomly", 2026-11-11 - caught by the spin watch, every jump with a hold on)
M.HOLD = { [3] = 4.0, [2] = 10.0, [1] = 10.0, belly_gap = 9.0, hz = 9.0, damp = 1.0, extra = 0.0, arm_hz = 0.6, spread = 5.0, look_hz = 6.0, reach_hz = 6.0,
           max_force = 9000.0, approach = 18.0, approach_t = 0.45, close = 12.0, far_k = 1.5, face_gap = 6.5, palm_hz = 8.0, far_max_force = 40000.0,
           -- (a shin or a foot: his foot dragged up in front of his belly - `foot_fwd` cm out from his chest, `foot_down` cm
           -- down toward his hips - and his chest down to it, no cap on either pull; still short of it after `boost_after` s,
           -- every `boost_every` s both pulls half as strong again, `boost_max` times as strong at most. His hands came within
           -- 34-53 cm of a foot and no nearer - "I can see the charater trying to reach his feet and failing still", 2026-11-10)
           foot_hz = 0.0, foot_max_force = 40000.0, hip_wide = 0.0, knee_wide = 0.0, spin_w = 150.0, spin_t = 0.5, foot_fwd = 30.0, foot_down = 28.0, boost_after = 1.0, boost_every = 0.7,
           boost_max = 1.0, boost_gap = 12.0, wild_v = 400.0, wild_w = 400.0,
           pain = 10.0, kick_hz = 1.6, kick_reach = 0.75, kick_strength = 7.0,
           spasm_t = 3.0, spasm_every = { 0.05, 0.14 }, spasm_deg = 700.0 }
-- His mind ("I also want a slightly random thought process on how the charater decides what he does", 2026-11-10): what
-- he does is chosen, not ruled. A hurt registers after a moment's shock (`react` s). He thinks every `think` s - at once
-- when a hurt has just registered - and picks by weighted chance among the hurts he has hands for: each weighs by how bad
-- it is (`weight`, severed most), more while fresh (x1 + `fresh`, fading over `fresh_t` s), times a random 0.6-1.4; what
-- he already holds weighs `keep` times more while it has time left; and leaving them all be for now weighs `idle`. Each
-- hold lasts its time (M.HOLD) give or take `jitter`; a leg, the chest or the head is now and then held with one hand
-- (`one_hand`). His legs kick in bursts (`kick_burst` s) with short pauses (`kick_pause`), each burst its own pace and
-- reach; and now and then (`rest_p` a thought) he catches his breath, still for `rest_t` s.
-- (`rehold`: s after a hurt was held as long as it needed before it is on his mind again, for `rehold_k` of its time)
M.MIND = { rehold = { 6.0, 14.0 }, rehold_k = 0.6, think = { 0.5, 1.3 }, react = { 0.15, 0.5 }, weight = { [1] = 1.5, [2] = 4.0, [3] = 10.0 }, fresh = 1.5, fresh_t = 3.0,
           keep = 2.5, idle = 0.8, jitter = 0.2, one_hand = 0.3, rest_p = 0.1, rest_t = { 0.8, 2.0 },
           kick_burst = { 1.5, 4.0 }, kick_pause = { 0.3, 1.0 }, kick_hz = { 1.2, 2.2 }, kick_reach = { 0.5, 0.9 },
           -- (which legs a burst kicks: both, or one alone; a broken leg joins in only now and then; a leg he holds, never -
           -- "like say its only one leg that kicks and another leg thats broken stays still while the player holds it")
           both_legs = 0.5, broken_kicks = 0.3, held_hz = 0.5,
           -- (a leg he holds is brought up to his hands - knee drawn to his chest, his back curled forward a little: lying
           -- flat, his hands could not reach a shin or a foot - "should also make the player bring legs up so arms can reach
           -- them", 2026-11-10; `lift_hz` for the leg, `curl_hz` for his back)
           lift_hz = 6.5, curl_hz = 4.0, sit_hz = 11.0, reach_lift_hz = 10.0,
           reach_commit = 2.5, head_first = 0.05, min_hold = 2.5, ball_t = 10.0, ball_hip = 45.0, face_kick_hz = 2.2, face_kick_reach = 0.9,
           -- (how much each part of him matters: his head and body before his limbs - "holds should be based on importance
           -- of a limb such as the head and body coming before limbs", 2026-11-10)
           part = { head = 3.0, chest = 2.5, thigh = 1.3, upperarm = 1.2, calf = 1.1, lowerarm = 1.0, hand = 0.9, foot = 0.9 },
           -- (what he holds, he mostly keeps: `stay` of his thoughts while it has time left, unless something at least
           -- `switch_over` times as important comes up - with ten hurts each a tenth of his mind, he changed hands every second)
           stay = 0.8, switch_over = 2.0 }
local ARM = { l = { "upperarm_l", "lowerarm_l", "hand_l" }, r = { "upperarm_r", "lowerarm_r", "hand_r" } }
local ARM_JOINTS = { l = { "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l" }, r = { "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r" } }
local SIDE_NAME = { l = "left", r = "right" }
local function arm_free(sd) for _, id in ipairs(ARM[sd]) do if parts[id].state >= 3 then return false end end; return true end
local function leg_free(sd) return parts["thigh_" .. sd].state < 3 and parts["calf_" .. sd].state < 3 end
local function arm_share(sd) local f = 1.0; for _, id in ipairs(ARM[sd]) do f = min(f, share(id)) end; return f end
local function is_dead(r) local h = parts.head.state; return r.exploded or h == 1 or h == 3 or st.bled_out end
local function ovr_write(r, bone, q, hz)
    local c = r.ctl and r.ctl[bone]
    if not (c and r.pc) then return end
    hz = hz * (r.brain and r.brain.tone or 1.0)
    pcall(function()
        if q then r.pc:SetControlTargetOrientation(c.name, q2rot(q), 0.0, true, false, true, false) end
        r.pc:SetControlAngularData(c.name, hz, M.CFG.tension_damp, 0.0, 0.0, true, true, false)
    end)
end

-- an injury to remember (`regs`: a severed part's regions - the first is where it was cut; the rest went with it)
local function note_injury(r, id, sv, regs)
    r.inj = r.inj or {}
    r.pain_until = r.t + M.HOLD.pain
    if id == "chest" then r.ball_until = max(r.ball_until or 0.0, r.t + M.MIND.ball_t) end
    local e = r.inj[id]
    if not e then e = { id = id, state = 0 }; r.inj[id] = e end
    if sv > e.state then
        local Mi = M.MIND
        if M.brain_injury then pcall(M.brain_injury, r, id, sv) end
        e.state, e.done, e.t = sv, false, r.t
        e.left = (M.HOLD[sv] or 10.0) * rnd(1.0 - Mi.jitter, 1.0 + Mi.jitter)
        e.react_at, e.seen = r.t + rnd(Mi.react[1], Mi.react[2]), false
        e.one_hand = random() < Mi.one_hand
    end
    if regs then
        for i = 2, #regs do local o = r.inj[regs[i]]; if o then o.done, o.gone = true, true end end
    end
    -- (a part of an arm off: what is left of that arm spasms)
    if sv == 3 then
        local sd = id:match("_(%a)$")
        local kind = id:match("^(%a+)_")
        local left = nil
        if kind == "hand" then left = { "lowerarm_" .. sd, "upperarm_" .. sd }
        elseif kind == "lowerarm" then left = { "upperarm_" .. sd } end
        if left then
            r.spasm = r.spasm or {}
            r.spasm[sd] = { till = r.t + M.HOLD.spasm_t, next = r.t, bones = left }
        end
    end
end
function M.on_injury(id, sv, regs)
    local r = st.rag
    if r and not r.dead then note_injury(r, id, sv, regs) end
end

local function hands_for(id)
    local sd = id:match("_(%a)$")
    if id:match("^upperarm_") or id:match("^lowerarm_") or id:match("^hand_") then
        local o = (sd == "l") and "r" or "l"
        return arm_free(o) and { o } or {}
    end
    local out = {}
    for _, h in ipairs({ "l", "r" }) do if arm_free(h) then out[#out + 1] = h end end
    return out
end
-- (how far each part's surface is from its bone, cm: where the hand rests on it)
local PART_RADIUS = { head = 12.0, chest = 13.5, upperarm = 5.5, lowerarm = 4.5, hand = 3.5, thigh = 8.5, calf = 6.5, foot = 5.0, elbow = 5.0 }
-- where an injury is held: the body it is on, the place (world), and the way along the part
local function hold_spot(mesh, e)
    -- (a knee: where his thigh meets his shin, on the thigh, along it)
    local ksd = e.id:match("^knee_(%a)$")
    if ksd then
        local W = pos(mesh, "calf_" .. ksd)
        return "thigh_" .. ksd, W, vnorm(vsub(W, pos(mesh, "thigh_" .. ksd)))
    end
    -- (an elbow: where his upper arm meets his forearm, on the upper arm, along it)
    local esd = e.id:match("^elbow_(%a)$")
    if esd then
        local W = pos(mesh, "lowerarm_" .. esd)
        return "upperarm_" .. esd, W, vnorm(vsub(W, pos(mesh, "upperarm_" .. esd)))
    end
    if e.state == 3 then
        local G = _G.ARGORE
        local P = G and G.part_for and G.part_for(e.id)
        if not P then return nil end
        local ce = BY_BONE[P.root]
        if not ce then return nil end
        local W = pos(mesh, P.root)
        return ce.p, W, vnorm(vsub(W, pos(mesh, ce.p)))
    end
    -- (his chest: up his spine_04 toward spine_05, about 35 cm above his pelvis - spine_02's middle was 13 cm up, at his
    -- groin, "he currently holds near the groin which is incorrect", 2026-11-11)
    local bone = (e.id == "chest") and "spine_04" or e.id
    local ce = BY_BONE[bone]
    local W = pos(mesh, bone)
    local axis = v3(0.0, 0.0, 1.0)
    -- (his head held at his face: up from the base of his skull to the middle of it)
    if e.id == "head" then
        local up = vnorm(vsub(W, pos(mesh, "neck_01")))
        return bone, vadd(W, vmul(up, 9.0)), up
    end
    -- (a foot held at the ankle, along the shin; a shin above its middle: nearer his hands)
    local sd = e.id:match("^foot_(%a)$")
    if sd then
        return bone, W, vnorm(vsub(W, pos(mesh, "calf_" .. sd)))
    end
    if ce and ce.tip then
        local q = pos(mesh, ce.tip)
        axis = vnorm(vsub(q, W))
        W = vadd(W, vmul(vsub(q, W), e.id:match("^calf_") and 0.4 or (e.id == "chest" and 0.15 or 0.5)))
    end
    return bone, W, axis
end
local function hold_stop(r, why)
    local h = r.hold
    if not h then return end
    r.hold = nil
    -- (DestroyControl(Name, bApplyToControlsWithName, bApplyToSetsWithName): called with the name alone it failed every
    -- time, unseen - no hold's pull was ever taken off, and his hands went on being pulled to every place they'd held, on
    -- after he died: "the hands are still getting pulled to the face after death", 2026-11-11)
    for _, nm in ipairs(h.ctl) do
        pcall(function() r.pc:DestroyControl(nm, true, false) end)
    end
    if h.foot_ctl then pcall(function() r.pc:DestroyControl(h.foot_ctl, true, false) end) end
    if h.wide then
        for _, jn in ipairs(h.wide) do reach_wide[jn] = nil end
        pcall(function() local pw = lib.pawn(); if pw then for _, jn in ipairs(h.wide) do lim_apply(pw.Mesh, jn) end end end)
    end
    for _, sd in ipairs(h.sides) do
        for _, b in ipairs(ARM_JOINTS[sd]) do if r.ovr[b] == "hold" then r.ovr[b] = nil end end
    end
    for _, b in ipairs({ "neck_01", "head" }) do if r.ovr[b] == "look" then r.ovr[b] = nil end end
    for _, b in ipairs(h.held_bones or {}) do if r.ovr[b] == "held" then r.ovr[b] = nil end end
    r.blend_w = -1.0
    log("let go of his %s (%s)%s", h.e.id, why, h.best and string.format(" - his hands came within %.0f cm of it", h.best) or "")
end
local function hold_start(pawn, r, e)
    -- (no reaching for a hurt in the air: falling at 100 mph and turning, every hold was let go as "too wild" a moment
    -- later, a hand up and a hand down - "charaters still doing the wierd one arm up one arm down pose", 2026-11-11)
    if not r.grounded then return end
    local mesh = pawn.Mesh
    -- (a hurt foot held by its lower leg - "okay no more grabbing feet, only the lower leg", 2026-11-10: reaching his feet
    -- spun him and threw him about. `e` stays the hurt for his mind; `se` is what his hands go to)
    -- (any hurt of a leg held at its knee - "remove the hands holding onto legs make it only hold the knees", 2026-11-10 -
    -- a leg cut off at the thigh, at its stump)
    local se = e
    local lsd = e.id:match("^thigh_(%a)$") or e.id:match("^calf_(%a)$") or e.id:match("^foot_(%a)$")
    if lsd and e.state < 3 then
        if parts["thigh_" .. lsd].state == 3 then return false end
        se = { id = "knee_" .. lsd, state = 0 }
    elseif lsd and e.state == 3 and not e.id:match("^thigh_") then
        if parts["thigh_" .. lsd].state == 3 then return false end
        se = { id = "knee_" .. lsd, state = 0 }
    end
    -- (an arm held by the other hand at its elbow, never its hand - "when arms try to grab eachother make them grab at the
    -- elbow not hands", 2026-11-10; the upper arm cut off, no elbow: at its stump)
    local asd = e.id:match("^upperarm_(%a)$") or e.id:match("^lowerarm_(%a)$") or e.id:match("^hand_(%a)$")
    if asd and parts["upperarm_" .. asd].state < 3 then se = { id = "elbow_" .. asd, state = 0 } end
    local hands = hands_for(e.id)
    if e.one_hand and #hands > 1 then hands = { hands[math.random(1, #hands)] } end
    if #hands == 0 or not r.pc then return false end
    local parent, W, axis = hold_spot(mesh, se)
    if not parent then return false end
    local pp, pq = pos(mesh, parent), rot(mesh, parent)
    local H = M.HOLD
    -- (the hands on the part's front surface, never in it, and brought there from in front of it: pulled straight to a
    -- place inside the part, they went through his body to get there - "hands go through body when reaching for broken
    -- body part", 2026-11-10. Front: his chest's forward, square to the part; the head held at its sides.)
    local fwd, right = v3(0.0, 0.0, 1.0), v3(1.0, 0.0, 0.0)
    if poses and poses.chest_fwd_local then
        local qc = rot(mesh, "spine_05")
        fwd, right = vnorm(qrot(qc, poses.chest_fwd_local)), vnorm(qrot(qc, poses.chest_right_local))
    end
    local function square(v) local k = vdot(v, axis); local u = vsub(v, vmul(axis, k)); return vlen(u) > 0.2 and vnorm(u) or nil end
    local radius = PART_RADIUS[se.id:match("^(%a+)") or se.id] or 6.0
    local far_part = se.id:match("^calf_")
    local data = { bEnabled = true, LinearStrength = H.hz, LinearDampingRatio = H.damp, LinearExtraDamping = H.extra,
        MaxForce = H.max_force, AngularStrength = 0.0, AngularDampingRatio = 1.0, AngularExtraDamping = 0.0, MaxTorque = 0.0,
        LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
        bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = false }
    local h = { e = e, ctl = {}, sides = {}, parent = parent, loc = qrot(qinv(pq), vsub(W, pp)), t0 = r.t }
    for i, sd in ipairs(hands) do
        local off = (#hands == 2) and ((i == 1) and -H.spread or H.spread) or 0.0
        local out = nil
        -- (the head held over his face, a hand to each side of it - "arms should go on face", 2026-11-10)
        if se.id == "head" then
            local face = fwd
            if poses and poses.face_local then face = vnorm(qrot(rot(mesh, "head"), poses.face_local)) end
            out = square(face)
        else out = square(fwd) end
        out = out or square(vsub(pos(mesh, "hand_" .. sd), W)) or fwd
        local base = vadd(W, vmul(axis, off))
        -- (on his face the two hands side by side, each over its own half - 6 cm apart they lay in each other and the
        -- parts kept apart fought the hold: "hands also go through eachother", 2026-11-10)
        if se.id == "head" then base = vadd(W, vmul(right, (#hands == 2) and ((sd == "l") and -H.face_gap or H.face_gap) or 0.0)) end
        -- (his stomach held with the hands side by side, each on its own side - one above the other in the middle, the arms
        -- crossed and the wrists bent back: "hands are messed up when holding stomach", 2026-11-11)
        if se.id == "chest" then base = vadd(W, vmul(right, (#hands == 2) and ((sd == "l") and -H.belly_gap or H.belly_gap) or 0.0)) end
        local loc = qrot(qinv(pq), vsub(vadd(base, vmul(out, radius)), pp))
        local near = qrot(qinv(pq), vsub(vadd(base, vmul(out, radius + H.approach)), pp))
        local target = { TargetPosition = fv(near), TargetVelocity = { X = 0, Y = 0, Z = 0 },
            TargetOrientation = { Pitch = 0, Yaw = 0, Roll = 0 }, TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
        r.hold_n = (r.hold_n or 0) + 1
        -- (a hurt arm holds on with its share of its strength)
        data.LinearStrength = H.hz * arm_share(sd) * (far_part and H.far_k or 1.0)
        data.MaxForce = H.max_force
        local okc, nm = pcall(function()
            return r.pc:CreateControl(mesh, FN[parent], mesh, FN["hand_" .. sd], data, target, FN["ActiveRagdollHold"], "ar_hold_" .. r.hold_n)
        end)
        if okc and nm then
            h.ctl[#h.ctl + 1] = nm
            h.sides[#h.sides + 1] = sd
            h.final = h.final or {}
            h.final[nm] = { loc = loc, near = near, side = sd }
            -- (that arm's own pull let go, so the hand gets there)
            for _, b in ipairs(ARM_JOINTS[sd]) do
                r.ovr[b] = "hold"
                ovr_write(r, b, poses and poses.targets.nbp[b], H.arm_hz * share(b))
            end
        elseif not okc and not r.hold_err then
            r.hold_err = true
            log("holding failed (%s)", tostring(nm))
        end
    end
    if #h.ctl == 0 then return false end
    h.far = far_part and true or false
    local fleg = se.id:match("^calf_(%a)$")
    if far_part and fleg and M.HOLD.hip_wide > 0.0 then
        h.wide = { "thigh_" .. fleg, "calf_" .. fleg }
        reach_wide["thigh_" .. fleg] = { s = M.HOLD.hip_wide, t = 0.0 }
        reach_wide["calf_" .. fleg] = { s = 0.0, t = M.HOLD.knee_wide }
        for _, jn in ipairs(h.wide) do pcall(lim_apply, mesh, jn) end
    end
    if far_part and fleg and poses and poses.chest_fwd_local and M.HOLD.foot_hz > 0.0 then
        local sp = "spine_03"
        local spp, sq = pos(mesh, sp), rot(mesh, sp)
        local upv = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
        local Wt = vadd(spp, vadd(vmul(fwd, H.foot_fwd), vmul(upv, -H.foot_down)))
        local fdata = { bEnabled = true, LinearStrength = H.foot_hz, LinearDampingRatio = 1.0, LinearExtraDamping = 0.0,
            MaxForce = H.foot_max_force, AngularStrength = 0.0, AngularDampingRatio = 1.0, AngularExtraDamping = 0.0, MaxTorque = 0.0,
            LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
            bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = false }
        local ftarget = { TargetPosition = fv(qrot(qinv(sq), vsub(Wt, spp))), TargetVelocity = { X = 0, Y = 0, Z = 0 },
            TargetOrientation = { Pitch = 0, Yaw = 0, Roll = 0 }, TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
        r.hold_n = (r.hold_n or 0) + 1
        local okf, fnm = pcall(function()
            return r.pc:CreateControl(mesh, FN[sp], mesh, FN["foot_" .. fleg], fdata, ftarget, FN["ActiveRagdollHold"], "ar_hold_" .. r.hold_n)
        end)
        if okf and fnm then h.foot_ctl = fnm end
    end
    -- (a leg he holds is brought up to his hands, and held still there: no kicks, no writhing)
    local leg = se.id:match("^thigh_(%a)$") or se.id:match("^calf_(%a)$") or se.id:match("^knee_(%a)$")
    if leg and poses then
        h.leg, h.held_bones = leg, {}
        local N, Pr = poses.targets.nbp, poses.targets.protect
        local far = far_part
        local C = (far and poses.targets.reach) or poses.targets.curl
        for _, b in ipairs({ "thigh_" .. leg, "calf_" .. leg, "foot_" .. leg }) do
            r.ovr[b] = "held"
            h.held_bones[#h.held_bones + 1] = b
            local up = b:match("^thigh") or b:match("^calf")
            ovr_write(r, b, up and C[b] or N[b], (up and (far and M.MIND.reach_lift_hz or M.MIND.lift_hz) or M.MIND.held_hz) * share(b))
        end
        -- (his back and neck curled to bring his hands down to it: hard for a shin or a foot, far from his hands - for
        -- those he sits up into it)
        local S = (far and poses.targets.reach) or Pr
        for _, b in ipairs({ "spine_02", "spine_03", "spine_04", "spine_05", far and "neck_01" or nil }) do
            if r.ovr[b] == nil or r.ovr[b] == "writhe" or r.ovr[b] == "breath" then
                r.ovr[b] = "held"
                h.held_bones[#h.held_bones + 1] = b
                ovr_write(r, b, S[b] or N[b], (far and M.MIND.sit_hz or M.MIND.curl_hz) * share(b))
            end
        end
    end
    -- (an arm held at its elbow keeps still, its own reaching let go: only the holding hand goes to it - "only one should
    -- be going for the elbow hold at a time as well", 2026-11-10)
    local harm = se.id:match("^elbow_(%a)$")
    if harm and poses then
        h.held_bones = h.held_bones or {}
        local N = poses.targets.nbp
        for _, b in ipairs({ "upperarm_" .. harm, "lowerarm_" .. harm, "hand_" .. harm }) do
            if parts[b] and parts[b].state < 3 and N[b] then
                r.ovr[b] = "held"
                h.held_bones[#h.held_bones + 1] = b
                ovr_write(r, b, N[b], M.MIND.held_hz * share(b))
            end
        end
    end
    r.hold = h
    r.blend_w = -1.0
    local names = {}
    for _, sd in ipairs(h.sides) do names[#names + 1] = SIDE_NAME[sd] end
    log("holding his %s (%s, %.0f s left) with the %s hand%s", e.id, M.STATES[e.state], e.left, table.concat(names, " and "),
        #names > 1 and "s" or "")
    return true
end

local function spasm_tick(pawn, r)
    if not r.spasm or not r.grounded then return end           -- (in the air no jerks of his own: "spazzing in the air", 2026-11-11)
    local mesh = pawn.Mesh
    local H = M.HOLD
    for sd, sp in pairs(r.spasm) do
        if r.t > sp.till then
            r.spasm[sd] = nil
        elseif r.t >= sp.next then
            sp.next = r.t + rnd(H.spasm_every[1], H.spasm_every[2])
            for _, b in ipairs(sp.bones) do
                if parts[b] and parts[b].state < 3 then
                    local ax = vnorm(v3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)))
                    local k = H.spasm_deg * rnd(0.5, 1.0)
                    M.twist(mesh, b, vmul(ax, k))
                    r.quiet = r.quiet or {}
                    r.quiet[b] = r.t + 0.12                  -- (its own jerks are no blows)
                end
            end
        end
    end
end

local function kick_tick(r)
    local H = M.HOLD
    local Mi = M.MIND
    -- (his head hurt and his hands on his face: both legs kicking hard and fast, on and on - "legs should kick on head
    -- damage", "especially when arms reach for face", 2026-11-10)
    -- (his chest held too: "make feet kick on chest hold", 2026-11-11)
    local face = (r.hold ~= nil and r.hold.e ~= nil and (r.hold.e.id == "head" or r.hold.e.id == "chest"))
    local pain = (r.t < (r.pain_until or -1.0)) or face      -- (true or false, never nil: nil logged "the kicking stops" every frame)
    pain = pain and (r.grounded and true or false)           -- (no kicking in the air: "spazzing in the air", 2026-11-11)
    if pain ~= (r.kicking or false) then
        r.kicking = pain
        log(pain and "kicking in pain" or "the kicking stops")
    end
    -- (in bursts, each its own pace and reach, short pauses between; none while he catches his breath)
    local kb = r.kb
    if face and not (kb and kb.face) then kb = nil end
    if not kb or r.t >= kb.till then
        local burst = not (kb and kb.on)
        -- (his feelings: frantic in shock, restless by nature, slower and smaller as he tires, longer pauses tired)
        local b = r.brain
        local fr = b and (1.0 + 0.6 * b.shock / 100.0) * b.restless or 1.0
        local en = b and (0.45 + 0.55 * b.energy / 100.0) or 1.0
        local pause = rnd(Mi.kick_pause[1], Mi.kick_pause[2]) * (b and (1.0 + 2.0 * (1.0 - b.energy / 100.0)) or 1.0)
        kb = { on = burst, till = r.t + (burst and rnd(Mi.kick_burst[1], Mi.kick_burst[2]) * en or pause),
               hz = rnd(Mi.kick_hz[1], Mi.kick_hz[2]) * fr, reach = min(0.95, rnd(Mi.kick_reach[1], Mi.kick_reach[2]) * en), legs = {} }
        local one = (random() < 0.5) and "l" or "r"
        for _, sd in ipairs({ "l", "r" }) do
            local yes = (random() < Mi.both_legs) or sd == one
            if parts["thigh_" .. sd].state == 2 or parts["calf_" .. sd].state == 2 then yes = yes and random() < Mi.broken_kicks end
            kb.legs[sd] = yes
        end
        if face then
            kb.on, kb.face = true, true
            kb.till = r.t + rnd(Mi.kick_burst[1], Mi.kick_burst[2])
            kb.hz = max(kb.hz, Mi.face_kick_hz) * rnd(0.9, 1.15)
            kb.reach = max(kb.reach, Mi.face_kick_reach)
            for _, sd in ipairs({ "l", "r" }) do kb.legs[sd] = parts["thigh_" .. sd].state < 2 and parts["calf_" .. sd].state < 2 end
        end
        r.kb = kb
    end
    local on = pain and kb.on and (face or not (r.rest_until and r.t < r.rest_until))
    -- (kicked out from his legs' resting bend, never drawn up to his chest first - "legs should only be brought up to chest when arms reach for them", 2026-11-10)
    local C, K = poses and poses.targets.draw, poses and poses.targets.kick
    if not (C and K) then return end
    r.kick_phase = r.kick_phase or rnd(0.0, 6.28)
    for i, sd in ipairs({ "l", "r" }) do
        local th, ca = "thigh_" .. sd, "calf_" .. sd
        local free = function(b) local w = r.ovr[b]; return w == nil or w == "kick" or w == "writhe" or (face and w == "ball") end
        local go = on and leg_free(sd) and not limp[th] and not limp[ca] and kb.legs[sd] and not (r.hold and r.hold.leg == sd)
            and free(th) and free(ca) and not (r.brain and r.brain.out)
        if go then
            local ph = r.kick_phase + ((i == 2) and math.pi or 0.0)
            local k = kb.reach * (0.5 + 0.5 * math.sin(2.0 * math.pi * kb.hz * r.t + ph))
            for _, b in ipairs({ th, ca }) do
                if C[b] and K[b] then
                    r.ovr[b] = "kick"
                    ovr_write(r, b, qnlerp(C[b], K[b], k), H.kick_strength * share(b))
                end
            end
        else
            for _, b in ipairs({ th, ca }) do
                if r.ovr[b] == "kick" then r.ovr[b] = nil; r.blend_w = -1.0 end
            end
        end
    end
end

-- his head turned to look at what his hands hold ("make the head try to turn in the direction of where the hands are
-- trying to hold", 2026-11-10): the turn from where his face looks to the place, half of it by his neck, the rest by his
-- head, aimed afresh each frame as the place moves
local function look_tick(pawn, r)
    local h = r.hold
    if not (h and h.parent and poses and poses.face_local) then return end
    if limp["neck_01"] or limp["head"] then return end
    local mesh = pawn.Mesh
    local spot = vadd(pos(mesh, h.parent), qrot(rot(mesh, h.parent), h.loc))
    local want = vnorm(vsub(spot, pos(mesh, "head")))
    local qh, qn, qs = rot(mesh, "head"), rot(mesh, "neck_01"), rot(mesh, "spine_05")
    local cur = vnorm(qrot(qh, poses.face_local))
    local turn = qarc(cur, want)
    local half = qnlerp({ x = 0.0, y = 0.0, z = 0.0, w = 1.0 }, turn, 0.5)
    local neck_w = qmul(half, qn)
    local head_w = qmul(turn, qh)
    r.ovr["neck_01"], r.ovr["head"] = "look", "look"
    ovr_write(r, "neck_01", qmul(qinv(qs), neck_w), M.HOLD.look_hz * share("neck_01"))
    ovr_write(r, "head", qmul(qinv(neck_w), head_w), M.HOLD.look_hz * share("head"))
end

-- writhing ("parts that are healthy should writhe on the ground instead of sitting still, like the players hips and
-- shoulders right now", 2026-11-10): lying hurt on the ground, alive, every healthy part not kicking, holding or looking
-- moves of itself - each joint turned off its resting pose by an angle and about an axis that both wander, slowly and on
-- their own beat (`hz`, `amp` degrees each), pulled there at `strength` Hz; and now and then his whole body rocks one way
-- and the other about his spine (`rock_deg` deg/s, every `rock_every` s).
M.WRITHE = { on = true, after = 0.5, strength = 6.5, hz = { 0.3, 0.85 }, rock_deg = 0.0, rock_every = { 0.7, 1.4 },   -- (rock off: a push from outside, it slid him along)
             amp = { spine_02 = 15.0, spine_03 = 15.0, spine_04 = 13.0, spine_05 = 11.0, clavicle_l = 25.0, clavicle_r = 25.0,
                     neck_01 = 18.0, head = 15.0, upperarm_l = 45.0, upperarm_r = 45.0, lowerarm_l = 25.0, lowerarm_r = 25.0,
                     hand_l = 28.0, hand_r = 28.0, thigh_l = 18.0, thigh_r = 18.0, calf_l = 18.0, calf_r = 18.0,   -- (legs less: at 38 a knee swung up to his chest - "legs should only be brought up to chest when arms reach for them", 2026-11-10)
                     foot_l = 22.0, foot_r = 22.0 } }
local JOINT_OF = {}
for id, js in pairs(REGION_JOINTS) do for _, j in ipairs(js) do JOINT_OF[j] = id end end
local function writhe_stop(r)
    if not r.writhing then return end
    r.writhing = false
    for b, why in pairs(r.ovr) do if why == "writhe" then r.ovr[b] = nil end end
    r.blend_w = -1.0
    log("lies still")
end
local function writhe_tick(pawn, r, dt)
    local W = M.WRITHE
    local hurt = false
    for _, e in pairs(parts) do if e.state > 0 then hurt = true; break end end
    local b = r.brain
    local feel = b and b.felt or 50.0
    local on = W.on and hurt and not r.dead and r.t > W.after and (r.air or 1.0) < 0.3 and poses ~= nil
        and not (r.rest_until and r.t < r.rest_until) and not (b and b.out) and feel > 8.0
    if not on then writhe_stop(r); return end
    if not r.writhing then r.writhing = true; log("writhing") end
    -- (his clothes rustling as he writhes)
    if M.AUDIO.rustle and r.t >= (r.rustle_t or 0.0) then
        r.rustle_t = r.t + rnd(M.AUDIO.rustle_every[1], M.AUDIO.rustle_every[2])
        snd("cloth", M.AUDIO.rustle_vol * (0.5 + 0.5 * min(1.0, feel / 100.0)), at_bone(pawn.Mesh, "spine_03"))
    end
    local A = poses.targets.nbp
    r.wr = r.wr or {}
    local t = r.t
    for j, amp in pairs(W.amp) do
        local why = r.ovr[j]
        local region = JOINT_OF[j]
        local healthy = region and parts[region] and parts[region].state == 0
        if healthy and A[j] and (why == nil or why == "writhe" or why == "breath") then
            local w = r.wr[j]
            if not w then
                w = { f = {}, p = {} }
                for i = 1, 4 do w.f[i], w.p[i] = rnd(W.hz[1], W.hz[2]) * 2.0 * math.pi, rnd(0.0, 2.0 * math.pi) end
                r.wr[j] = w
            end
            local ax = vnorm(v3(math.sin(t * w.f[1] + w.p[1]), math.sin(t * w.f[2] + w.p[2]), math.sin(t * w.f[3] + w.p[3])))
            local ang = rad(amp) * (0.55 + 0.45 * math.sin(t * w.f[4] + w.p[4]))
                * (b and (0.35 + 0.65 * min(1.0, feel / 100.0)) * b.restless or 1.0)
            local h = ang * 0.5
            local sn = math.sin(h)
            local off = { x = ax.x * sn, y = ax.y * sn, z = ax.z * sn, w = math.cos(h) }
            r.ovr[j] = "writhe"
            ovr_write(r, j, qmul(off, A[j]), W.strength * (b and (0.75 + 0.25 * b.energy / 100.0) or 1.0))
        elseif why == "writhe" then
            r.ovr[j] = nil
            r.blend_w = -1.0
        end
    end
    -- his body rocked about his spine, one way then the other
    if W.rock_deg > 0.0 and t >= (r.rock_next or 0.0) then
        r.rock_next = t + rnd(W.rock_every[1], W.rock_every[2])
        r.rock_sign = -(r.rock_sign or 1.0)
        local mesh = pawn.Mesh
        local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
        local k = W.rock_deg * rnd(0.6, 1.0) * r.rock_sign
        pcall(function()
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k)), FN["pelvis"], true)
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k * 0.8)), FN["spine_03"], true)
        end)
        r.quiet["chest"] = max(r.quiet["chest"] or 0.0, t + 0.1)
    end
end

-- ------------------------------------------------------------------ more for him to do on the ground
-- ("should add more for him to do when on the ground I dont know what but he's lacking severly", 2026-11-10.) Acts his mind
-- can pick (each a few seconds, his limbs aimed by world directions every frame, `act_hz` their pull):
--   LOOK      - turns his head slowly about, at one place and another around him;
--   REACH UP  - an arm lifted to the sky, held, let drop;
--   POUND     - a fist raised and brought down on the ground, again and again;
--   ROLL      - off his front onto a side or his back: a knee drawn up, an arm swung over, his body turned;
--   CRAWL     - on his front, dragging himself along by one arm then the other (each pull, a hand on the ground, moves him on
--               `crawl_step` cm/s - his own arms too weak to drag a body);
--   ALL FOURS - pushed up onto his hands and knees, wobbling, then down again (held up `lift` of his weight by help);
--   SIT       - sat up, his hands on his knees, a few seconds, then back down (held up `lift` too);
-- and all the while: his BREATHING - his chest rising and falling, slow at rest, panting hurt or spent - and, badly hurt,
-- small TWITCHES of his limbs.
M.ACTS = { act_hz = 7.0, rollabout_t = { 3.0, 5.0 }, rollabout_swing = { 0.6, 1.0 }, rollabout_deg = 170.0, look_t = { 3.0, 5.0 }, reach_t = { 2.0, 3.5 }, pound_n = { 2, 4 }, pound_cycle = 0.9, roll_t = { 1.2, 1.8 },
           roll_deg = 220.0, crawl_t = { 4.0, 8.0 }, crawl_cycle = 1.2, crawl_step = 70.0, fours_t = { 2.5, 4.5 }, sit_t = { 3.0, 5.0 },
           lift = 0.7, breath = { calm = 0.25, pant = 0.75, deg = 3.0, deg_pant = 6.0 }, twitch_from = 55.0, twitch_every = { 0.4, 1.6 },
           twitch_deg = { 150.0, 320.0 } }
local UP, DOWN = v3(0.0, 0.0, 1.0), v3(0.0, 0.0, -1.0)
-- (his body's frame now: up his spine, his right, his front)
local function body_frame(mesh)
    local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
    local right = vnorm(vsub(pos(mesh, "clavicle_r"), pos(mesh, "clavicle_l")))
    local fwd = (poses and poses.chest_fwd_local) and vnorm(qrot(rot(mesh, "spine_05"), poses.chest_fwd_local)) or vcross(right, up)
    return up, right, fwd
end
-- (a part aimed: its bone pointed the way wanted, by the joint above it, for this act)
local function aim_seg(r, mesh, bone, tip, parent, want, hz, tag)
    local why = r.ovr[bone]
    if why ~= nil and why ~= "writhe" and why ~= "kick" and why ~= "breath" and why ~= tag then return end
    if limp[bone] or not BY_BONE[bone] then return end
    local cur = vnorm(vsub(pos(mesh, tip), pos(mesh, bone)))
    if vlen(want) < 0.5 then return end
    local q = qmul(qinv(rot(mesh, parent)), qmul(qarc(cur, want), rot(mesh, bone)))
    r.ovr[bone] = tag
    ovr_write(r, bone, q, hz * share(bone))
end
local function aim_arm(r, mesh, sd, upper, fore, hz, tag)
    aim_seg(r, mesh, "upperarm_" .. sd, "lowerarm_" .. sd, "clavicle_" .. sd, upper, hz, tag)
    aim_seg(r, mesh, "lowerarm_" .. sd, "hand_" .. sd, "upperarm_" .. sd, fore or upper, hz, tag)
end
local function aim_leg(r, mesh, sd, thigh, calf, hz, tag)
    aim_seg(r, mesh, "thigh_" .. sd, "calf_" .. sd, "pelvis", thigh, hz, tag)
    aim_seg(r, mesh, "calf_" .. sd, "foot_" .. sd, "thigh_" .. sd, calf or thigh, hz, tag)
end
-- (his head turned to look at a place: half by his neck, the rest by his head)
local function look_at(r, mesh, spot, hz, tag)
    if not (poses and poses.face_local) or limp["neck_01"] or limp["head"] then return end
    for _, b in ipairs({ "neck_01", "head" }) do
        local why = r.ovr[b]
        if why ~= nil and why ~= "breath" and why ~= "writhe" and why ~= tag then return end
    end
    local want = vnorm(vsub(spot, pos(mesh, "head")))
    local qh, qn, qs = rot(mesh, "head"), rot(mesh, "neck_01"), rot(mesh, "spine_05")
    local turn = qarc(vnorm(qrot(qh, poses.face_local)), want)
    local half = qnlerp({ x = 0.0, y = 0.0, z = 0.0, w = 1.0 }, turn, 0.5)
    local neck_w = qmul(half, qn)
    r.ovr["neck_01"], r.ovr["head"] = tag, tag
    ovr_write(r, "neck_01", qmul(qinv(qs), neck_w), hz * share("neck_01"))
    ovr_write(r, "head", qmul(qinv(neck_w), qmul(turn, qh)), hz * share("head"))
end
-- (a body part held up by help: `k` of gravity taken off it each frame - only with the ground under him: in the air, tucked
-- and tumbling, his mind took him for lying on his back and sat him up, and the lift held him up in the air -
-- "charaters flying", "I mean literally flying", 2026-11-11)
local function lift(mesh, r, bones, k, dt)
    if not r.grounded then return end
    local g = (r.g or 1500.0) * k * dt
    for _, b in ipairs(bones) do pcall(function() mesh:AddImpulse({ X = 0.0, Y = 0.0, Z = g }, FN[b], true) end) end
end
local function free_arm(r)
    local list = {}
    for _, sd in ipairs({ "l", "r" }) do
        local busy = r.hold and (r.hold.sides[1] == sd or r.hold.sides[2] == sd)
        if arm_free(sd) and parts["upperarm_" .. sd].state < 2 and not busy then list[#list + 1] = sd end
    end
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end
local function act_stop(r, why)
    local a = r.act
    r.act = nil
    if not a then return end
    for b, w in pairs(r.ovr) do if w == "act" then r.ovr[b] = nil end end
    r.blend_w = -1.0
    log("%s: %s", a.name, why or "done")
end
local ACT = {}
ACT.look = function(pawn, r, a, mesh, t)
    if not a.spot or t >= (a.next or 0.0) then
        a.next = t + rnd(1.0, 1.6)
        local h = pos(mesh, "head")
        local ang = rnd(0.0, 2.0 * math.pi)
        a.spot = vadd(h, v3(math.cos(ang) * 100.0, math.sin(ang) * 100.0, rnd(-10.0, 50.0)))
    end
    look_at(r, mesh, a.spot, M.ACTS.act_hz * 0.6, "act")
end
ACT.reach = function(pawn, r, a, mesh, t)
    if t > a.len * 0.65 then
        for _, b in ipairs({ "upperarm_" .. a.side, "lowerarm_" .. a.side }) do if r.ovr[b] == "act" then r.ovr[b] = nil end end
        return
    end
    local up, right, fwd = body_frame(mesh)
    aim_arm(r, mesh, a.side, vnorm(vadd(UP, vmul(fwd, 0.25))), vnorm(vadd(UP, vmul(fwd, 0.4))), M.ACTS.act_hz, "act")
end
ACT.pound = function(pawn, r, a, mesh, t)
    local c = M.ACTS.pound_cycle
    local up, right, fwd = body_frame(mesh)
    local out = vmul(right, (a.side == "r") and 1.0 or -1.0)
    if (t % c) < c * 0.5 then
        aim_arm(r, mesh, a.side, vnorm(vadd(UP, vmul(out, 0.5))), vnorm(vadd(UP, vmul(out, 0.2))), M.ACTS.act_hz, "act")
    else
        aim_arm(r, mesh, a.side, vnorm(vadd(DOWN, vmul(out, 0.6))), DOWN, M.ACTS.act_hz * 1.8, "act")
    end
end
ACT.roll = function(pawn, r, a, mesh, t)
    local up, right, fwd = body_frame(mesh)
    if not a.pushed then
        a.pushed = true
        pcall(function()
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, M.ACTS.roll_deg * a.dir)), FN["pelvis"], true)
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, M.ACTS.roll_deg * 0.9 * a.dir)), FN["spine_03"], true)
        end)
        r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.2)
    end
    -- (the knee on the far side drawn up, the arm on that side swung over)
    local far = (a.dir > 0) and "l" or "r"
    local over = vmul(right, (far == "l") and 1.0 or -1.0)
    aim_leg(r, mesh, far, vnorm(vadd(vmul(fwd, 0.5), vmul(up, -0.85))), vnorm(vadd(vmul(up, -1.0), vmul(fwd, -0.3))), M.ACTS.act_hz, "act")
    aim_arm(r, mesh, far, vnorm(vadd(over, vmul(UP, 0.4))), over, M.ACTS.act_hz, "act")
end
-- (rolling about on the floor in pain, side to side, curled up - "can you also add him rolling on the floor as an option",
-- 2026-11-10: one of the things he may choose, more the more it hurts and the more he has in him. A part he holds he keeps
-- holding as he rolls)
ACT.rollabout = function(pawn, r, a, mesh, t)
    local A = M.ACTS
    local up, right, fwd = body_frame(mesh)
    if t >= (a.next or 0.0) then
        a.dir = -(a.dir or ((random() < 0.5) and -1.0 or 1.0))
        a.next = t + rnd(A.rollabout_swing[1], A.rollabout_swing[2])
        local k = A.rollabout_deg * rnd(0.8, 1.2) * (r.brain and (0.5 + 0.5 * r.brain.energy / 100.0) or 1.0)
        pcall(function()
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k * a.dir)), FN["pelvis"], true)
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k * 0.9 * a.dir)), FN["spine_03"], true)
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k * 0.8 * a.dir)), FN["spine_05"], true)
        end)
        r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.25)
    end
    -- (his arms in to his body, his legs a little bent - not up to his chest)
    for _, sd in ipairs({ "l", "r" }) do
        if leg_free(sd) then
            aim_leg(r, mesh, sd, vnorm(vadd(vmul(fwd, 0.45), vmul(up, -0.9))), vnorm(vadd(vmul(up, -1.0), vmul(fwd, -0.35))), A.act_hz, "act")
        end
        local over = vmul(right, (sd == "l") and 1.0 or -1.0)
        aim_arm(r, mesh, sd, vnorm(vadd(vmul(fwd, 0.7), vmul(up, -0.4))), vnorm(vadd(over, vmul(fwd, 0.3))), A.act_hz, "act")
    end
end
ACT.crawl = function(pawn, r, a, mesh, t)
    local up, right, fwd = body_frame(mesh)
    -- (the way he crawls: the way his head is, along the ground)
    local ahead = vnorm(v3(up.x, up.y, 0.0))
    local c = M.ACTS.crawl_cycle
    local cyc = math.floor(t / c)
    local ph = (t % c) / c
    local sd = (cyc % 2 == 0) and "l" or "r"
    local other = (sd == "l") and "r" or "l"
    if ph < 0.5 then
        -- (reaching on ahead)
        aim_arm(r, mesh, sd, vnorm(vadd(ahead, vmul(DOWN, 0.35))), vnorm(vadd(ahead, vmul(DOWN, 0.2))), M.ACTS.act_hz, "act")
    else
        -- (pulling: the arm brought down and back under him; a hand on the ground drags him on)
        aim_arm(r, mesh, sd, vnorm(vadd(DOWN, vmul(ahead, -0.5))), DOWN, M.ACTS.act_hz * 1.3, "act")
        if parts["hand_" .. sd].state < 3 and ray(pawn, pos(mesh, "hand_" .. sd), vadd(pos(mesh, "hand_" .. sd), v3(0, 0, -18))) then
            local k = M.ACTS.crawl_step * (r.brain and (0.5 + 0.5 * r.brain.energy / 100.0) or 1.0) * (1.0 / (c * 0.5)) * (1.0 / 60.0)
            pcall(function() mesh:AddImpulseToAllBodiesBelow(fv(vmul(ahead, k)), FN["pelvis"], true, true) end)
        end
    end
    aim_arm(r, mesh, other, vnorm(vadd(DOWN, vmul(ahead, 0.2))), DOWN, M.ACTS.act_hz * 0.5, "act")
    look_at(r, mesh, vadd(pos(mesh, "head"), vmul(ahead, 150.0)), M.ACTS.act_hz * 0.5, "act")
end
ACT.fours = function(pawn, r, a, mesh, t)
    local up, right, fwd = body_frame(mesh)
    local back = vnorm(v3(-up.x, -up.y, 0.0))
    for _, sd in ipairs({ "l", "r" }) do
        aim_arm(r, mesh, sd, DOWN, DOWN, M.ACTS.act_hz * 1.3, "act")
        aim_leg(r, mesh, sd, DOWN, back, M.ACTS.act_hz * 1.2, "act")
    end
    -- (held up a while, wobbling as his strength gives)
    local k = M.ACTS.lift * (r.brain and (0.5 + 0.5 * r.brain.energy / 100.0) or 1.0) * (0.85 + 0.15 * math.sin(t * 7.0))
    lift(mesh, r, { "spine_03", "pelvis", "spine_05" }, k, a.dt or 0.016)
    r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.1)
end
ACT.sit = function(pawn, r, a, mesh, t)
    for _, b in ipairs({ "spine_02", "spine_03", "spine_04", "spine_05", "neck_01" }) do
        local why = r.ovr[b]
        if (why == nil or why == "writhe" or why == "breath" or why == "act") and poses then
            r.ovr[b] = "act"
            ovr_write(r, b, poses.targets.protect[b], M.ACTS.act_hz * 1.2 * share(b))
        end
    end
    -- (his hands on his knees)
    for _, sd in ipairs({ "l", "r" }) do
        local sh = pos(mesh, "upperarm_" .. sd)
        local kn = pos(mesh, "calf_" .. sd)
        local d = vnorm(vsub(kn, sh))
        aim_arm(r, mesh, sd, d, d, M.ACTS.act_hz * 0.8, "act")
    end
    lift(mesh, r, { "spine_05", "spine_04" }, M.ACTS.lift * 0.8, a.dt or 0.016)
    r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.1)
end
-- (nothing of his own done in the air: his acts - a roll, a crawl, sitting up - push or turn all of him, and in the air
-- that is a push from nowhere - "if you fall in the air you cant move your body right? so explain to me how the body stops
-- all momentum completely randomly", 2026-11-11. Begun only on the ground; one under way stops as he leaves it)
local function act_start(r, name, len, extra)
    if not r.grounded then return end
    act_stop(r, "another")
    r.act = { name = name, t0 = r.t, till = r.t + len, len = len }
    if extra then for k, v in pairs(extra) do r.act[k] = v end end
    if name ~= "look" and name ~= "rollabout" and r.hold then hold_stop(r, "busy with something else") end
    log("thinks: %s", name)
end
local function act_tick(pawn, r, dt)
    local a = r.act
    if not a then return end
    if not r.grounded and (r.air or 0.0) > 0.5 then act_stop(r, "in the air"); return end
    if r.t > a.till then act_stop(r, "done"); return end
    a.dt = dt
    local f = ACT[a.name]
    if f then
        local ok, e = pcall(f, pawn, r, a, pawn.Mesh, r.t - a.t0)
        if not ok then act_stop(r, "failed: " .. tostring(e)) end
    end
end
-- his breathing: his chest and shoulders rising and falling on parts nothing else moves
local function breath_tick(pawn, r)
    local A = M.ACTS.breath
    local b = r.brain
    if not (b and poses) or b.out then return end
    local need = min(1.0, (b.felt / 100.0 + (1.0 - b.energy / 100.0)) * 0.6 + b.shock / 200.0)
    local hz = A.calm + (A.pant - A.calm) * need
    r.breath_ph = (r.breath_ph or 0.0) + 2.0 * math.pi * hz * (r.breath_dt or 0.016)
    local amp = rad(A.deg + (A.deg_pant - A.deg) * need) * math.sin(r.breath_ph)
    local mesh = pawn.Mesh
    local right = vnorm(vsub(pos(mesh, "clavicle_r"), pos(mesh, "clavicle_l")))
    for _, bn in ipairs({ "spine_03", "spine_04", "spine_05", "clavicle_l", "clavicle_r" }) do
        local why = r.ovr[bn]
        if (why == nil or why == "breath") and poses.targets.nbp[bn] then
            -- (the turn about his right, in the parent's frame: chest up and down)
            local e = BY_BONE[bn]
            local ax = vnorm(qrot(qinv(rot(mesh, e.p)), right))
            local k = (bn:match("^clavicle")) and -0.7 or 1.0
            local h = amp * k * 0.5
            local sn = math.sin(h)
            r.ovr[bn] = "breath"
            ovr_write(r, bn, qmul({ x = ax.x * sn, y = ax.y * sn, z = ax.z * sn, w = math.cos(h) }, poses.targets.nbp[bn]),
                3.0 * share(bn) * (r.grounded and M.CFG.ground_tone or 1.0))
        end
    end
end
-- twitches: badly hurt, a limb jerked now and then
local function twitch_tick(pawn, r)
    if not r.grounded then return end                        -- (no twitches in the air: "spazzing in the air", 2026-11-11)
    local A, b = M.ACTS, r.brain
    if not b or b.out or b.felt < A.twitch_from then return end
    if r.t < (r.twitch_t or 0.0) then return end
    r.twitch_t = r.t + rnd(A.twitch_every[1], A.twitch_every[2]) / (0.5 + b.felt / 100.0)
    local list = {}
    for _, bn in ipairs({ "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "calf_l", "calf_r", "foot_l", "foot_r" }) do
        local reg = JOINT_REGION[bn]
        if reg and parts[reg] and parts[reg].state < 3 and r.ovr[bn] ~= "hold" and r.ovr[bn] ~= "held" then list[#list + 1] = bn end
    end
    if #list == 0 then return end
    local bn = list[math.random(1, #list)]
    local ax = vnorm(v3(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)))
    M.twist(pawn.Mesh, bn, vmul(ax, rnd(A.twitch_deg[1], A.twitch_deg[2])))
    local reg = JOINT_REGION[bn]
    if reg then r.quiet[reg] = max(r.quiet[reg] or 0.0, r.t + 0.12) end
end

-- ------------------------------------------------------------------ crawling, his legs gone
-- ("need a crawling animation for when both lower legs are removed", 2026-11-10.) Both legs gone below the knee (or higher),
-- keeping his injuries: he cannot stand - put down and kept down (no getting up, STORROR's or his own) - and moves by the
-- stick, crawling: turned toward the way it points from the camera (`turn` deg/s at most), rolled onto his front if he lies
-- on his back, dragging himself along by one arm then the other (`cycle` s), each pull with a hand on the ground taking him
-- on toward `speed` cm/s (less by his hurt pace). Without the stick he lies there.
-- ("make the crawling faster", 2026-11-10: was 85 cm/s, 1.1 s a pull, 90 deg/s, drawn on at 5)
-- ("crawling is still very slow": he was drawn on only while a hand pulled with that hand within 20 cm of the ground -
-- 25-30 cm/s. Now all through the stroke, `reach_k` of it while a hand reaches, and his drag on the ground made up for
-- (`drag` cm/s/s). On his back, with the stick: rolled over, his whole body turned about its length at `roll_speed`
-- deg/s for up to `roll_time` s - "if player ends up on back needs a way to flip over", 2026-11-10)
-- (drawn on by his upper body - chest, head and arms, `lead` of the pull, the whole of him `rest` of it - so his head
-- leads and the rest of him trails behind: pushed all alike he slid the stick's way side-on or feet first, "head should
-- be out front while crawling", 2026-11-10; his turning twice as firm, the upper chest turned too. The roll stopped once
-- he is on his side - pushed on till his front, it went on over onto his back again)
M.CRAWL = { speed = 200.0, turn = 160.0, turn_k = 0.5, cycle = 0.75, hz = 11.0, pull = 9.0, reach_k = 0.6, drag = 700.0,
            lead = 1.6, rest = 0.3, roll_every = 1.2, roll_speed = 320.0, roll_time = 0.5 }
local ROLL_BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "head", "clavicle_l",
                     "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l",
                     "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }
local limbs_want = nil   -- (set where it is defined, below)
local facing = nil       -- (likewise)
local function legs_gone()
    local function gone(sd) return parts["thigh_" .. sd].state == 3 or parts["calf_" .. sd].state == 3 end
    return gone("l") and gone("r")
end
local function stick_dir()
    local pc = lib.controller()
    if not pc then return nil end
    local x, y = 0.0, 0.0
    pcall(function() x = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftX") }); y = pc:GetInputAnalogKeyState({ KeyName = FName("Gamepad_LeftY") }) end)
    local function down(k) local ok, v = pcall(function() return pc:IsInputKeyDown({ KeyName = FName(k) }) end); return ok and v end
    if down("W") then y = y + 1.0 end
    if down("S") then y = y - 1.0 end
    if down("D") then x = x + 1.0 end
    if down("A") then x = x - 1.0 end
    if x * x + y * y < 0.09 then return nil end
    local cam = 0.0
    pcall(function() cam = pc:GetControlRotation().Yaw end)
    local yaw = rad(cam + deg(atan(x, y)))
    return v3(math.cos(yaw), math.sin(yaw), 0.0)
end
local function crawl_tick(pawn, r, dt)
    if not r.grounded then return end           -- (crawling only on the ground: its pulls and rolls push all of him)
    local C = M.CRAWL
    local mesh = pawn.Mesh
    local dir = stick_dir()
    if not dir then
        if r.crawling then r.crawling = false; for b, w in pairs(r.ovr) do if w == "crawlmode" then r.ovr[b] = nil end end; r.blend_w = -1.0 end
        r.crawl_rolling = nil
        return
    end
    if not r.crawling then
        r.crawling, r.crawl_t0 = true, r.t
        if r.hold then hold_stop(r, "crawling") end
        if r.act then act_stop(r, "crawling") end
        r.curl, r.struggle = nil, nil
    end
    if r.mind then r.mind.next = max(r.mind.next, r.t + 0.5) end           -- (his mind on crawling while he crawls)
    -- (on his back: rolled over onto his front - all of him turned about his length, the way the stick leans; a turn of
    -- his pelvis and chest alone, 240 deg/s once, never got him over)
    local face = facing(mesh)
    if not r.crawl_rolling and face == "up" and r.t - (r.crawl_roll or -9.0) > C.roll_every then
        local upv = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
        local side = vdot(dir, vnorm(vcross(upv, v3(0.0, 0.0, 1.0))))
        local sgn = (side > 0.1) and 1.0 or (side < -0.1) and -1.0 or ((random() < 0.5) and -1.0 or 1.0)
        r.crawl_rolling = { t0 = r.t, sgn = sgn }
        r.crawl_roll = r.t
        log("crawling: on his back - rolling over")
    end
    if r.crawl_rolling then
        local R = r.crawl_rolling
        if r.t - R.t0 > C.roll_time or (face ~= "up" and r.t - R.t0 > 0.1) then
            r.crawl_rolling = nil
            r.crawl_roll = r.t
        else
            local c = pos(mesh, "spine_02")
            local axis = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
            local w = vmul(axis, rad(C.roll_speed) * R.sgn)
            local g = min(1.0, 10.0 * dt)
            for _, b in ipairs(ROLL_BONES) do
                pcall(function()
                    local v = vcross(w, vsub(pos(mesh, b), c))
                    mesh:AddImpulse(fv(vmul(v, g)), FN[b], true)
                    mesh:AddAngularImpulseInDegrees(fv(vmul(axis, C.roll_speed * R.sgn * g)), FN[b], true)
                end)
            end
        end
    end
    -- (turned toward it: his head the way he crawls)
    local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
    local head = vnorm(v3(up.x, up.y, 0.0))
    local diff = deg(atan(head.x * dir.y - head.y * dir.x, head.x * dir.x + head.y * dir.y))
    local want_rate = max(-C.turn, min(C.turn, diff * 2.5))
    pcall(function()
        local w = mesh:GetPhysicsAngularVelocityInDegrees(FN["pelvis"])
        local k = (want_rate - w.Z) * (C.turn_k or 0.25)
        mesh:AddAngularImpulseInDegrees({ X = 0.0, Y = 0.0, Z = k }, FN["pelvis"], true)
        mesh:AddAngularImpulseInDegrees({ X = 0.0, Y = 0.0, Z = k }, FN["spine_03"], true)
        mesh:AddAngularImpulseInDegrees({ X = 0.0, Y = 0.0, Z = k }, FN["spine_05"], true)
    end)
    -- (his arms: one reaching on ahead, then pulling down and back under him; the other bracing)
    local t = r.t - r.crawl_t0
    local cyc = math.floor(t / C.cycle)
    local ph = (t % C.cycle) / C.cycle
    local sd = (cyc % 2 == 0) and "l" or "r"
    local other = (sd == "l") and "r" or "l"
    if ph < 0.5 then
        aim_arm(r, mesh, sd, vnorm(vadd(dir, vmul(DOWN, 0.35))), vnorm(vadd(dir, vmul(DOWN, 0.2))), C.hz, "crawlmode")
    else
        aim_arm(r, mesh, sd, vnorm(vadd(DOWN, vmul(dir, -0.5))), DOWN, C.hz * 1.3, "crawlmode")
    end
    -- (him drawn on toward his crawling pace - his hurt pace with it - all through the stroke, harder as a hand pulls; an
    -- arm left to pull with, and not while he rolls over)
    if (parts["lowerarm_l"].state < 3 or parts["lowerarm_r"].state < 3) and not r.crawl_rolling then
        local w = limbs_want and limbs_want() or { rate = 1.0 }
        local target = C.speed * max(0.4, w.rate) * (r.brain and (0.6 + 0.4 * r.brain.energy / 100.0) or 1.0)
        local okv, u = pcall(function() return mesh:GetPhysicsLinearVelocity(FN["spine_05"]) end)
        if okv and u then
            local along = u.X * dir.x + u.Y * dir.y
            if along < target then
                local k = ((target - along) * min(1.0, C.pull * dt) + C.drag * dt) * ((ph < 0.5) and C.reach_k or 1.0)
                pcall(function()
                    mesh:AddImpulseToAllBodiesBelow(fv(vmul(dir, k * C.lead)), FN["spine_04"], true, true)
                    mesh:AddImpulseToAllBodiesBelow(fv(vmul(dir, k * C.rest)), FN["pelvis"], true, true)
                end)
            end
        end
    end
    aim_arm(r, mesh, other, vnorm(vadd(DOWN, vmul(dir, 0.2))), DOWN, C.hz * 0.5, "crawlmode")
    look_at(r, mesh, vadd(pos(mesh, "head"), vmul(dir, 150.0)), C.hz * 0.5, "crawlmode")
    for _, b in ipairs({ "lowerarm_l", "lowerarm_r", "hand_l", "hand_r" }) do
        local reg = JOINT_REGION[b]
        if reg then r.quiet[reg] = max(r.quiet[reg] or 0.0, r.t + 0.1) end
    end
end

-- (healed: what he was doing about his injuries ends too)
function M.on_heal()
    local r = st.rag
    if not r then return end
    hold_stop(r, "healed")
    r.inj, r.pain_until, r.spasm, r.dead, r.exploded = {}, nil, nil, false, nil
    r.curl, r.struggle, r.brain = nil, nil, nil
    act_stop(r, "healed")
    for b, why in pairs(r.ovr or {}) do r.ovr[b] = nil end
    r.blend_w = -1.0
end
-- ------------------------------------------------------------------ his brain: what he feels, what he does about it
-- ("can you give him a more advanced brain?", 2026-11-10.) What he feels, moment to moment:
--   PAIN       - each hurt adds to it (`pain_add` by how bad, x how much that part matters, / his toughness), each blow a
--                little; it eases `pain_fade` a second, never below what his hurts still give (`pain_floor` of it);
--   SHOCK      - the adrenaline of a hard hit (`shock_per` its mph), fading `shock_fade` a second: it masks pain
--                (`shock_mask`) and makes him frantic;
--   ENERGY     - kicking, holding, writhing and struggling spend it; resting and lying quiet bring it back;
--   CONSCIOUSNESS - blows to the head knock it down (`ko_per` mph past `ko_from`, a broken head `ko_broken`); it comes
--                back `wake` a second. Under `out_below` he is out cold - all his muscle at `out_tone`, nothing of his own;
--                under `dazed_below`, dazed, his muscle and doings slack.
-- And who he is, drawn for each fall: tough (pain), restless (kicks and writhing), stubborn (tries to get up).
-- What he does - picked by weighted chance each time he thinks (M.MIND), among: holding a hurt (as before, weighed up by
-- how much it all hurts), curling up on his side (`curl_w`, more the more it hurts and the more hurts), struggling to get
-- up (`struggle_w`: stubborn, with energy, not too hurt, awake - pushing up off his front or sitting up off his back, then
-- falling back, spent), catching his breath (`rest_w`, more the more tired), or leaving it be. He grunts with the pain.
M.BRAIN = { pain_add = { [1] = 14.0, [2] = 26.0, [3] = 45.0 }, pain_blow = 0.35, pain_fade = 1.5, pain_floor = 0.4,
            shock_per = 1.6, shock_fade = 9.0, shock_mask = 0.6,
            -- (a third as fast as it was, and never under `energy_floor`: he was spent in ten seconds and lay still - "not reacting enough sometime just completely sits still, its also jank as hell", 2026-11-10)
            spend = { kick = 1.3, hold = 0.4, writhe = 0.5, struggle = 4.0, curl = 0.3 }, rest_gain = 10.0, idle_gain = 2.0, energy_floor = 30.0,
            ko_from = 18.0, ko_per = 1.6, ko_broken = 45.0, wake = 9.0, out_below = 25.0, dazed_below = 65.0, out_tone = 0.12,
            curl_w = 3.0, curl_t = { 3.0, 7.0 }, curl_hz = 6.5, roll_deg = 160.0,
            struggle_w = 1.5, struggle_t = { 1.2, 2.5 }, struggle_hz = 9.0, struggle_tired = { 1.0, 2.5 },
            rest_w = 2.0, groan_every = { 1.2, 3.5 }, log_every = 2.5 }
local function brain_new()
    return { pain = 0.0, shock = 0.0, energy = rnd(75.0, 100.0), con = 100.0, tone = 1.0, felt = 0.0, out = false, dazed = false,
             tough = rnd(0.7, 1.3), restless = rnd(0.7, 1.3), stubborn = rnd(0.5, 1.5), floor = 0.0, log_t = -99.0, groan_t = 0.0 }
end
function M.brain_injury(r, id, sv)
    local B, b = M.BRAIN, r.brain
    if not b then return end
    local add = (B.pain_add[sv] or 10.0) * (M.MIND.part[id:match("^(%a+)") or id] or 1.0) / 1.5 / b.tough
    b.pain = min(100.0, b.pain + add)
    b.floor = min(80.0, b.floor + add * B.pain_floor)
    if id == "head" and sv >= 2 then b.con = min(b.con, 100.0 - B.ko_broken) end
end
function M.brain_blow(r, id, mph)
    local B, b = M.BRAIN, r.brain
    if not b then return end
    b.shock = min(100.0, max(b.shock, mph * B.shock_per))
    b.pain = min(100.0, b.pain + max(0.0, mph - 10.0) * B.pain_blow / b.tough)
    if id == "head" and mph > B.ko_from then b.con = max(0.0, b.con - (mph - B.ko_from) * B.ko_per) end
end
-- which way his chest faces: "down" on his front, "up" on his back, else "side"
facing = function(mesh)
    if not (poses and poses.chest_fwd_local) then return "side" end
    local f = qrot(rot(mesh, "spine_05"), poses.chest_fwd_local)
    if f.z < -0.5 then return "down" elseif f.z > 0.5 then return "up" end
    return "side"
end
local function clear_ovr(r, tag)
    for bn, why in pairs(r.ovr) do if why == tag then r.ovr[bn] = nil end end
    r.blend_w = -1.0
end
local function brain_tick(pawn, r, dt)
    local B, b = M.BRAIN, r.brain
    b.shock = max(0.0, b.shock - B.shock_fade * dt)
    b.pain = max(b.floor, b.pain - B.pain_fade * dt)
    b.felt = b.pain * (1.0 - B.shock_mask * b.shock / 100.0)
    local spend = 0.0
    if r.kicking and r.kb and r.kb.on then spend = spend + B.spend.kick end
    if r.hold then spend = spend + B.spend.hold end
    if r.writhing then spend = spend + B.spend.writhe end
    if r.struggle then spend = spend + B.spend.struggle end
    if r.curl then spend = spend + B.spend.curl end
    if r.rest_until and r.t < r.rest_until then spend = spend - B.rest_gain elseif spend == 0.0 then spend = -B.idle_gain end
    b.energy = max(B.energy_floor or 0.0, min(100.0, b.energy - spend * dt))
    b.con = min(100.0, b.con + B.wake * dt)
    local was_out, was_dazed = b.out, b.dazed
    b.out = b.con < B.out_below
    b.dazed = not b.out and b.con < B.dazed_below
    local tone = 1.0
    if b.out then tone = B.out_tone
    elseif b.dazed then tone = 0.5 + 0.5 * (b.con - B.out_below) / (B.dazed_below - B.out_below) end
    if abs(tone - b.tone) > 0.05 then b.tone = tone; r.blend_w = -1.0 end
    if b.out and not was_out then
        log("knocked out (awake %.0f)", b.con)
        hold_stop(r, "knocked out")
        r.curl, r.struggle = nil, nil
        if r.act then for bn, w in pairs(r.ovr) do if w == "act" then r.ovr[bn] = nil end end; r.act = nil end
        clear_ovr(r, "curl"); clear_ovr(r, "struggle")
    elseif was_out and not b.out then log("comes to, dazed")
    elseif was_dazed and not b.dazed and not b.out then log("his head clears") end
    if M.LOG.verbose and r.t - b.log_t > B.log_every then
        b.log_t = r.t
        log("mind: pain %.0f (feels %.0f), shock %.0f, energy %.0f, awake %.0f%s", b.pain, b.felt, b.shock, b.energy, b.con,
            b.out and " - out cold" or (b.dazed and " - dazed" or ""))
    end
    -- (he grunts with the pain)
    if M.AUDIO.groans and not b.out and b.felt > M.AUDIO.groan_from and r.t >= b.groan_t then
        b.groan_t = r.t + rnd(M.AUDIO.groan_every[1], M.AUDIO.groan_every[2]) / (0.6 + b.felt / 100.0)
        local A = M.AUDIO
        local mesh = pawn.Mesh
        snd("grunt", A.groan_vol[1] + (A.groan_vol[2] - A.groan_vol[1]) * min(1.0, b.felt / 100.0), at_bone(mesh, "head"),
            A.groan_pitch[1] + (A.groan_pitch[2] - A.groan_pitch[1]) * random())
    end
end
-- curled up on his side: knees to his chest, back rounded, arms in (those not holding), rolled onto a side as it begins
-- Curled up into a ball, his body hurt ("stomach should take priority over limbs if stomach takes damage player should curl
-- into a ball", "not curling into a ball on body damage", 2026-11-10): for `ball_t` s after a hurt to his body - whatever
-- his hands are doing - both knees drawn up to his chest (his hips let go `ball_hip` deg further for it: they stopped his
-- knees well short), his back rounded, his head tucked, his arms round his stomach unless his hands already hold it; rolled
-- onto his side first if he lay on his back.
local function ball_end(pawn, r)
    r.ball = nil
    for b, w in pairs(r.ovr) do if w == "ball" then r.ovr[b] = nil end end
    r.blend_w = -1.0
    for _, jn in ipairs({ "thigh_l", "thigh_r" }) do reach_wide[jn] = nil end
    pcall(function() lim_apply(pawn.Mesh, "thigh_l"); lim_apply(pawn.Mesh, "thigh_r") end)
    log("uncurls from the ball")
end
local function ball_tick(pawn, r)
    local on = r.ball_until and r.t < r.ball_until and not r.dead and not (r.brain and r.brain.out) and poses ~= nil
    if not on then
        if r.ball then ball_end(pawn, r) end
        return
    end
    local mesh = pawn.Mesh
    if not r.ball then
        r.ball = { t0 = r.t }
        for _, jn in ipairs({ "thigh_l", "thigh_r" }) do
            reach_wide[jn] = { s = M.MIND.ball_hip, t = 0.0 }
            pcall(lim_apply, mesh, jn)
        end
        -- (on his back: rolled onto his side)
        if poses.chest_fwd_local then
            local f = qrot(rot(mesh, "spine_05"), poses.chest_fwd_local)
            if f.z > 0.5 then
                local upv = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
                local k = M.BRAIN.roll_deg * ((random() < 0.5) and -1.0 or 1.0)
                if r.grounded then pcall(function()
                    mesh:AddAngularImpulseInDegrees(fv(vmul(upv, k)), FN["pelvis"], true)
                    mesh:AddAngularImpulseInDegrees(fv(vmul(upv, k * 0.8)), FN["spine_03"], true)
                end) end
                r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.2)
            end
        end
        log("curls up into a ball - his body hurts")
    end
    local C, Pr = poses.targets.curl, poses.targets.protect
    local function take(b) local w = r.ovr[b]; return w == nil or w == "ball" or w == "writhe" or w == "kick" or w == "breath" or w == "curl" end
    -- (his legs left to kick while he holds his chest)
    local chest_held = r.hold and r.hold.e and r.hold.e.id == "chest"
    for _, sd in ipairs({ "l", "r" }) do
        if leg_free(sd) and not chest_held then
            for _, b in ipairs({ "thigh_" .. sd, "calf_" .. sd }) do
                if take(b) and C[b] then r.ovr[b] = "ball"; ovr_write(r, b, C[b], M.MIND.lift_hz * share(b)) end
            end
        end
    end
    for _, b in ipairs({ "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "head" }) do
        if take(b) and Pr[b] then r.ovr[b] = "ball"; ovr_write(r, b, Pr[b], M.MIND.curl_hz * 1.5 * share(b)) end
    end
    -- (his arms round his stomach)
    local belly = vmul(vadd(pos(mesh, "spine_02"), pos(mesh, "spine_03")), 0.5)
    if poses.chest_fwd_local then belly = vadd(belly, vmul(vnorm(qrot(rot(mesh, "spine_03"), poses.chest_fwd_local)), 14.0)) end
    for _, sd in ipairs({ "l", "r" }) do
        local ub, lb = "upperarm_" .. sd, "lowerarm_" .. sd
        if take(ub) and take(lb) and arm_free(sd) then
            local sh = pos(mesh, ub)
            local d = vnorm(vsub(belly, sh))
            local over = vnorm(vsub(belly, pos(mesh, "hand_" .. sd)))
            aim_arm(r, mesh, sd, d, vnorm(vadd(d, over)), M.MIND.curl_hz * 1.5, "ball")
        end
    end
end

local function curl_tick(pawn, r)
    local c = r.curl
    if not c then return end
    if r.t > c.till then
        r.curl = nil
        clear_ovr(r, "curl")
        log("uncurls")
        return
    end
    local mesh = pawn.Mesh
    if not c.rolled then
        c.rolled = true
        local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
        local k = M.BRAIN.roll_deg * c.side * (r.brain and (0.5 + 0.5 * r.brain.energy / 100.0) or 1.0)
        if r.grounded then pcall(function()
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k)), FN["pelvis"], true)
            mesh:AddAngularImpulseInDegrees(fv(vmul(up, k * 0.8)), FN["spine_03"], true)
        end) end
        r.quiet["chest"] = max(r.quiet["chest"] or 0.0, r.t + 0.15)
    end
    local C, Pr = poses.targets.curl, poses.targets.protect
    local hz = M.BRAIN.curl_hz * (r.brain and (0.5 + 0.5 * r.brain.energy / 100.0) or 1.0)
    for _, bn in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "head",
                          "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r" }) do
        local why = r.ovr[bn]
        if why == nil or why == "writhe" or why == "kick" or why == "curl" then
            -- (his legs left at their resting bend: up to his chest only for his hands - "legs should only be brought up to chest when arms reach for them", 2026-11-10)
            local q = (bn:match("^thigh") or bn:match("^calf")) and poses.targets.nbp[bn] or Pr[bn]
            if q then
                r.ovr[bn] = "curl"
                ovr_write(r, bn, q, hz * share(bn))
            end
        end
    end
end
-- struggling to get up: off his front, his arms pushed straight down at the ground under his shoulders; off his back, his
-- back curled hard to sit up and his arms pushing at the ground beside him; then he falls back, spent
local function struggle_tick(pawn, r)
    local s_ = r.struggle
    if not s_ then return end
    local mesh = pawn.Mesh
    if r.t > s_.till then
        r.struggle = nil
        clear_ovr(r, "struggle")
        r.rest_until = r.t + rnd(M.BRAIN.struggle_tired[1], M.BRAIN.struggle_tired[2])
        if r.brain then r.brain.energy = max(0.0, r.brain.energy - 15.0) end
        log("falls back, spent")
        return
    end
    local hz = M.BRAIN.struggle_hz * (r.brain and (0.4 + 0.6 * r.brain.energy / 100.0) or 1.0)
    local down = v3(0.0, 0.0, -1.0)
    local fwd = (poses and poses.chest_fwd_local) and vnorm(qrot(rot(mesh, "spine_05"), poses.chest_fwd_local)) or v3(1.0, 0.0, 0.0)
    -- (each arm aimed: its upper arm and forearm both the way wanted, as the hand pushes the ground)
    for _, sd in ipairs({ "l", "r" }) do
        if parts["upperarm_" .. sd].state < 3 and parts["lowerarm_" .. sd].state < 3 and not (r.hold and (r.hold.sides[1] == sd or r.hold.sides[2] == sd)) then
            local want = (s_.face == "down") and vnorm(vadd(down, vmul(fwd, 0.25))) or vnorm(vadd(down, vmul(fwd, -0.35)))
            for _, pair in ipairs({ { "upperarm_" .. sd, "lowerarm_" .. sd, "clavicle_" .. sd }, { "lowerarm_" .. sd, "hand_" .. sd, "upperarm_" .. sd } }) do
                local bn, tip, par = pair[1], pair[2], pair[3]
                local why = r.ovr[bn]
                if why == nil or why == "writhe" or why == "kick" or why == "curl" or why == "struggle" then
                    local cur = vnorm(vsub(pos(mesh, tip), pos(mesh, bn)))
                    local q = qmul(qinv(rot(mesh, par)), qmul(qarc(cur, want), rot(mesh, bn)))
                    r.ovr[bn] = "struggle"
                    ovr_write(r, bn, q, hz * share(bn))
                end
            end
        end
    end
    if s_.face == "up" then
        for _, bn in ipairs({ "spine_02", "spine_03", "spine_04", "spine_05", "neck_01" }) do
            local why = r.ovr[bn]
            if why == nil or why == "writhe" or why == "curl" or why == "struggle" then
                r.ovr[bn] = "struggle"
                ovr_write(r, bn, poses.targets.protect[bn], hz * share(bn))
            end
        end
    end
end

-- Stunned by a hard hit: all of him limp for a moment - no muscle, no hold, no kick, no act - then he comes to and his
-- mind takes it from there ("for some reason he doesnt fully ragdoll when he first hit the ground", 2026-11-10: he was
-- kicking in the very instant he hit). A blow of `from_mph` or more, or a hard landing: `t0` s, and `per_mph` more for each
-- mph over, `max` at most.
M.STUN = { from_mph = 20.0, t0 = 0.6, per_mph = 0.02, max = 1.5,
           wake = 0.6 }   -- (his muscles come back over this long: all at once they snapped him round)
local function stun(r, mph, why)
    local S = M.STUN
    if not r or r.dead or mph < S.from_mph then return end
    local till = r.t + min(S.max, S.t0 + S.per_mph * (mph - S.from_mph))
    if r.stun_until and r.t < r.stun_until then
        if till > r.stun_until then r.stun_until = till end
        return
    end
    r.stun_until = till
    if r.hold then hold_stop(r, "stunned") end
    if r.act then act_stop(r, "stunned") end
    r.ovr, r.curl, r.struggle, r.spasm = {}, nil, nil, nil
    r.blend_w = -1.0
    log("stunned by %s (%.0f mph): limp for %.1f s", why or "a blow", mph, till - r.t)
end
M.stun = function(r, mph, why) pcall(stun, r, mph, why) end
local function behaviors_tick(pawn, r, dt)
    r.ovr = r.ovr or {}
    -- (dead the moment he is, stunned or not - completely limp: "remember the body should be going completely limp on
    -- death", 2026-11-11; stunned, it waited for him to come to)
    if not r.dead and is_dead(r) then
        r.dead = true
        hold_stop(r, "dead")
        r.spasm, r.ovr, r.blend_w = nil, {}, -1.0
        r.curl, r.struggle, r.fl = nil, nil, nil
        log("dead (%s) - completely limp", r.exploded and "blown apart" or (parts.head.state == 3 and "his head off")
            or ((parts.head.state == 1) and "his neck put out") or "bled out")
    end
    -- (stunned: nothing of his own yet)
    if r.stun_until and not r.dead then
        if r.t < r.stun_until then return end
        r.stun_until = nil
        r.blend_w = -1.0
        r.wake_t = r.t
        log("comes to")
    end
    if not r.dead and is_dead(r) then
        r.dead = true
        hold_stop(r, "dead")
        r.spasm, r.ovr, r.blend_w = nil, {}, -1.0
        r.curl, r.struggle = nil, nil
        log("dead (%s) - nothing more of his own", r.exploded and "blown apart" or (parts.head.state == 3 and "his head off")
            or ((parts.head.state == 1) and "his neck put out") or "bled out")
    end
    if r.dead then return end
    -- (LIVE RAGDOLL off: nothing of his own - what he was doing let go, once - but crawling, legless: the player's)
    if r.lifeless then
        if not r.was_lifeless then
            r.was_lifeless = true
            if r.hold then hold_stop(r, "live ragdoll off") end
            if r.act then act_stop(r, "live ragdoll off") end
            r.spasm, r.curl, r.struggle = nil, nil, nil
            for b, w in pairs(r.ovr) do if w ~= "crawlmode" then r.ovr[b] = nil end end
            r.blend_w = -1.0
            log("live ragdoll off: he lies as he falls")
        end
        if st.crawl_mode then
            local okcr, ecr = pcall(crawl_tick, pawn, r, dt)
            if not okcr and not r.crawl_err then r.crawl_err = true; log("crawling failed (%s)", tostring(ecr)) end
        end
        return
    end
    if r.was_lifeless then r.was_lifeless = nil; r.blend_w = -1.0 end
    r.brain = r.brain or brain_new()
    local okbr, ebr = pcall(brain_tick, pawn, r, dt)
    if not okbr and not r.br_err then r.br_err = true; log("his mind failed (%s)", tostring(ebr)) end
    spasm_tick(pawn, r)
    if r.brain.out then return end
    -- his mind: a hurt registers after its shock; he thinks now and then - at once when one has just registered - and
    -- picks by weighted chance
    local Mi = M.MIND
    r.mind = r.mind or { next = 0.0 }
    for _, e in pairs(r.inj or {}) do
        if not e.done and not e.seen and r.t >= (e.react_at or 0.0) then e.seen = true; r.mind.next = min(r.mind.next, r.t) end
    end
    -- (a hold whose arm is gone ends at once)
    if r.hold then
        for _, sd in ipairs(r.hold.sides) do if not arm_free(sd) then hold_stop(r, "that arm is gone"); break end end
    end
    if r.t >= r.mind.next then
        r.mind.next = r.t + rnd(Mi.think[1], Mi.think[2])
        -- (each hurt's weight in his mind: how bad, which part of him, how fresh; his legs hardly at all while his head hurts -
        -- "head damage should take priority over leg damage as well", 2026-11-10)
        -- (and his arms and legs hardly at all while his stomach hurts - "stomach should take priority over limbs if stomach takes damage player should curl into a ball", 2026-11-10)
        -- (a hurt held as long as it needed comes back to him after a while: with all of them held, nothing was left on his
        -- mind and he lay there doing nothing - "sometimes ragdoll does nothing just sits there", 2026-11-10)
        for _, e in pairs(r.inj or {}) do
            if e.done and not e.gone and e.done_t and r.t - e.done_t > (e.rehold or Mi.rehold[1]) then
                e.done, e.done_t = false, nil
                e.left = (M.HOLD[e.state] or 10.0) * Mi.rehold_k * rnd(1.0 - Mi.jitter, 1.0 + Mi.jitter)
            end
        end
        local head_hurt, chest_hurt = false, false
        for _, e in pairs(r.inj or {}) do
            if not e.done and e.seen then
                if e.id == "head" then head_hurt = true elseif e.id == "chest" then chest_hurt = true end
            end
        end
        local function score(e)
            local leg = e.id:match("^thigh_") or e.id:match("^calf_") or e.id:match("^foot_")
            local limb = leg or e.id:match("^upperarm_") or e.id:match("^lowerarm_") or e.id:match("^hand_")
            return (Mi.weight[e.state] or 1.0) * (Mi.part[e.id:match("^(%a+)") or e.id] or 1.0)
                * (1.0 + Mi.fresh * math.exp(-(r.t - e.t) / Mi.fresh_t))
                * (((head_hurt and leg) or (chest_hurt and limb)) and Mi.head_first or 1.0)
        end
        -- (by importance: only the worst kind of hurt he has is held - severed, then broken, then fractured - chance
        -- choosing only among those: "holds should happen by importance, severed first broken then fractures", 2026-11-11)
        -- (and by place before that: his face, then his chest, then his limbs - "also face comes before chest and then
        -- limbs next", 2026-11-11)
        local function rank(e) return ((e.id == "head") and 30 or (e.id == "chest") and 20 or 10) + (e.state or 0) end
        local top = 0
        for _, e in pairs(r.inj or {}) do
            if not e.gone and not e.done and e.seen and #hands_for(e.id) > 0 and rank(e) > top then top = rank(e) end
        end
        local cur = r.hold and r.hold.e or nil
        local stay = false
        if cur and rank(cur) < top then
            -- (a worse hurt than the one held: let go of it)
        elseif cur and not cur.done and cur.left > 0.5 then
            local cs, alt = score(cur), 0.0
            for _, e in pairs(r.inj or {}) do
                if e ~= cur and not e.done and e.seen and #hands_for(e.id) > 0 then alt = max(alt, score(e)) end
            end
            stay = alt < cs * Mi.switch_over and random() < Mi.stay
        end
        local opts, total = {}, 0.0
        local b, B = r.brain, M.BRAIN
        local feel = min(1.0, b.felt / 100.0)
        local busy = r.curl or r.struggle or (r.act and r.act.name ~= "look")
        local n_hurt = 0
        for _, e in pairs(r.inj or {}) do
            if not e.gone then n_hurt = n_hurt + 1 end      -- (held or not: still hurt, still more to do)
            if not stay and not busy and not e.done and e.seen and #hands_for(e.id) > 0 and rank(e) >= top then
                local w = score(e) * rnd(0.6, 1.4) * (0.5 + feel)
                if cur == e and e.left > 0.5 then w = w * Mi.keep end
                opts[#opts + 1] = { e = e, w = w }
                total = total + w
            end
        end
        -- (his other choices: curl up, struggle to get up, catch his breath)
        if not stay and not busy and n_hurt > 0 and (r.air or 1.0) < 0.3 then
            local wc = B.curl_w * feel * feel * (1.0 + n_hurt / 5.0) * rnd(0.6, 1.4)
            local arms_ok = parts.upperarm_l.state < 2 or parts.upperarm_r.state < 2
            local ws = (arms_ok and not b.dazed) and B.struggle_w * b.stubborn * (b.energy / 100.0) * max(0.0, 1.0 - feel) * rnd(0.6, 1.4) or 0.0
            local wr = B.rest_w * (1.0 - b.energy / 100.0) ^ 1.5 * rnd(0.6, 1.4)
            opts[#opts + 1] = { act = "curl", w = wc }
            opts[#opts + 1] = { act = "struggle", w = ws }
            opts[#opts + 1] = { act = "rest", w = wr }
            total = total + wc + ws + wr
            -- (more to do on the ground: by how he lies, how it hurts, his strength and his nature)
            local face = facing(pawn.Mesh)
            local en = b.energy / 100.0
            local arm = free_arm(r) ~= nil
            local legs = leg_free("l") and leg_free("r") and parts.thigh_l.state < 2 and parts.thigh_r.state < 2
            local more = {
                look = 1.2 * (1.2 - feel) * (b.dazed and 0.5 or 1.0),
                reach = (arm and face ~= "down") and 0.8 * en * (0.4 + feel) or 0.0,
                pound = arm and 0.9 * feel * en * b.restless or 0.0,
                roll = (face == "down" and 2.2 or (face == "up" and 0.5 or 0.3)) * en,
                rollabout = 1.4 * (0.3 + feel) * en,
                crawl = (face == "down" and arm) and 1.6 * b.stubborn * en or 0.0,
                fours = (face == "down" and arm and legs and not b.dazed) and 1.1 * b.stubborn * en * (1.1 - feel) or 0.0,
                sit = (face == "up" and arm and not b.dazed) and 1.2 * en * (1.1 - feel) or 0.0,
            }
            for name, w in pairs(more) do
                if w > 0.0 then
                    local ww = w * rnd(0.6, 1.4)
                    opts[#opts + 1] = { act = "do_" .. name, w = ww }
                    total = total + ww
                end
            end
        end
        if #opts > 0 then
            opts[#opts + 1] = { e = nil, w = Mi.idle }
            total = total + Mi.idle
            local x, pick = rnd(0.0, total), nil
            for _, o in ipairs(opts) do x = x - o.w; if x <= 0.0 then pick = o; break end end
            pick = pick or opts[#opts]
            local cur = r.hold and r.hold.e or nil
            if pick.act == "curl" then
                log("thinks: curl up (%.0f%%) - it hurts", pick.w / total * 100.0)
                r.curl = { till = r.t + rnd(B.curl_t[1], B.curl_t[2]), side = (random() < 0.5) and -1.0 or 1.0 }
            elseif pick.act == "struggle" then
                local face = facing(pawn.Mesh)
                log("thinks: get up (%.0f%%) - %s", pick.w / total * 100.0, face == "down" and "pushes up off the ground" or "tries to sit up")
                if r.hold then hold_stop(r, "tries to get up") end
                r.struggle = { till = r.t + rnd(B.struggle_t[1], B.struggle_t[2]), face = (face == "down") and "down" or "up" }
            elseif pick.act and pick.act:find("^do_") then
                local name, A = pick.act:sub(4), M.ACTS
                if name == "look" then act_start(r, "look", rnd(A.look_t[1], A.look_t[2]))
                elseif name == "reach" then act_start(r, "reach", rnd(A.reach_t[1], A.reach_t[2]), { side = free_arm(r) or "r" })
                elseif name == "pound" then act_start(r, "pound", A.pound_cycle * math.random(A.pound_n[1], A.pound_n[2]), { side = free_arm(r) or "r" })
                elseif name == "roll" then act_start(r, "roll", rnd(A.roll_t[1], A.roll_t[2]), { dir = (random() < 0.5) and -1.0 or 1.0 })
                elseif name == "rollabout" then act_start(r, "rollabout", rnd(A.rollabout_t[1], A.rollabout_t[2]))
                elseif name == "crawl" then act_start(r, "crawl", rnd(A.crawl_t[1], A.crawl_t[2]))
                elseif name == "fours" then act_start(r, "fours", rnd(A.fours_t[1], A.fours_t[2]))
                elseif name == "sit" then act_start(r, "sit", rnd(A.sit_t[1], A.sit_t[2])) end
            elseif pick.act == "rest" then
                if not (r.rest_until and r.t < r.rest_until) then
                    r.rest_until = r.t + rnd(Mi.rest_t[1], Mi.rest_t[2]) * (1.5 - b.energy / 100.0)
                    log("thinks: catch his breath (%.0f%%) - tired", pick.w / total * 100.0)
                end
            elseif pick.e ~= cur and r.hold and pick.e and not (pick.e.id == "head" or pick.e.id == "chest")
                and r.t - r.hold.t0 < Mi.min_hold then
                -- (kept at what he holds a while: let go every half second for another, his arms jerked from place to place)
            elseif pick.e ~= cur and r.hold and r.hold.far and not head_hurt and not chest_hurt and r.t - r.hold.t0 < Mi.reach_commit and (r.hold.best or 99.0) > M.HOLD.boost_gap then
                -- (still reaching for a shin or a foot: kept at it - let go after a second, before his leg was up, he never got
                -- there, 2026-11-10)
            elseif pick.e ~= cur then
                if r.hold then hold_stop(r, pick.e and "thought of something else" or "leaves it be") end
                if pick.e then
                    log("thinks: hold his %s (%s, %.0f%% of his mind)", pick.e.id, M.STATES[pick.e.state], pick.w / total * 100.0)
                    pcall(hold_start, pawn, r, pick.e)
                else
                    log("thinks: leave it be for now (%.0f%%)", pick.w / total * 100.0)
                end
            end
        end

    end
    if r.hold then
        local e = r.hold.e
        e.left = e.left - dt
        if e.left <= 0.0 then
            e.done, e.done_t, e.rehold = true, r.t, rnd(M.MIND.rehold[1], M.MIND.rehold[2])
            hold_stop(r, (e.state == 3) and "gave up on it" or "held long enough")
            r.mind.next = min(r.mind.next, r.t + rnd(0.2, 0.6))
        end
    end
    if r.hold then pcall(look_tick, pawn, r) end
    r.breath_dt = dt
    if st.crawl_mode then
        local okcr, ecr = pcall(crawl_tick, pawn, r, dt)
        if not okcr and not r.crawl_err then r.crawl_err = true; log("crawling failed (%s)", tostring(ecr)) end
    end
    local oka, ea = pcall(act_tick, pawn, r, dt)
    if not oka and not r.act_err then r.act_err = true; log("acting failed (%s)", tostring(ea)) end
    pcall(breath_tick, pawn, r)
    pcall(twitch_tick, pawn, r)
    local okbl, ebl = pcall(ball_tick, pawn, r)
    if not okbl and not r.ball_err then r.ball_err = true; log("curling into a ball failed (%s)", tostring(ebl)) end
    local okc, ec = pcall(curl_tick, pawn, r)
    if not okc and not r.curl_err then r.curl_err = true; log("curling up failed (%s)", tostring(ec)) end
    local oks, es = pcall(struggle_tick, pawn, r)
    if not oks and not r.str_err then r.str_err = true; log("struggling failed (%s)", tostring(es)) end
    local okw, ew = pcall(writhe_tick, pawn, r, dt)
    if not okw and not r.wr_err then r.wr_err = true; log("writhing failed (%s)", tostring(ew)) end
    if r.hold and r.hold.final then
        local h = r.hold
        local mesh = pawn.Mesh
        local pp, pq = pos(mesh, h.parent), rot(mesh, h.parent)
        -- (his palms on his face: each hand turned so its palm faces his face, its fingers up his head - left free, the hands
        -- hung any way at the wrist, "palms of hands not covering face during holding face so it looks wierd", 2026-11-10)
        if h.e.id == "head" and poses and poses.face_local then
            local face = vnorm(qrot(rot(mesh, "head"), poses.face_local))
            local hup = vnorm(vsub(pos(mesh, "head"), pos(mesh, "neck_01")))
            for _, f in pairs(h.final) do
                local sd = f.side
                local hb = "hand_" .. sd
                if r.ovr[hb] == "hold" and not limp[hb] then
                    local hp = pos(mesh, hb)
                    local fing = vnorm(vsub(pos(mesh, "middle_01_" .. sd), hp))
                    local th = vnorm(vsub(pos(mesh, "thumb_01_" .. sd), hp))
                    local palm = (sd == "r") and vnorm(vcross(fing, th)) or vnorm(vcross(th, fing))   -- (was the back of his hand: "holds his face with the back of his hands", 2026-11-11)
                    local want_palm = vmul(face, -1.0)
                    local q1 = qarc(palm, want_palm)
                    local f2 = qrot(q1, fing)
                    local upp = vsub(hup, vmul(want_palm, vdot(hup, want_palm)))     -- (fingers up his head: fixed on him)
                    local f2p = vsub(f2, vmul(want_palm, vdot(f2, want_palm)))
                    local qw = qmul(q1, rot(mesh, hb))
                    if vlen(upp) > 0.1 and vlen(f2p) > 0.1 then qw = qmul(qarc(vnorm(f2p), vnorm(upp)), qw) end
                    ovr_write(r, hb, qmul(qinv(rot(mesh, "lowerarm_" .. sd)), qw), M.HOLD.palm_hz * share(hb))
                end
            end
        end
        -- (his palms flat on his chest, the fingers toward its middle: hanging any way at the wrist they stood out from it,
        -- "make hands actually sit on chest not float in air", 2026-11-11)
        if h.e.id == "chest" and poses and poses.chest_fwd_local then
            local qc = rot(mesh, "spine_05")
            local cf, cr = vnorm(qrot(qc, poses.chest_fwd_local)), vnorm(qrot(qc, poses.chest_right_local))
            for _, f in pairs(h.final) do
                local sd = f.side
                local hb = "hand_" .. sd
                if r.ovr[hb] == "hold" and not limp[hb] then
                    local hp = pos(mesh, hb)
                    local fing = vnorm(vsub(pos(mesh, "middle_01_" .. sd), hp))
                    local th = vnorm(vsub(pos(mesh, "thumb_01_" .. sd), hp))
                    local palm = (sd == "r") and vnorm(vcross(fing, th)) or vnorm(vcross(th, fing))   -- (was the back of his hand: "holds his face with the back of his hands", 2026-11-11)
                    local want_palm = vmul(cf, -1.0)
                    -- (the fingers on along the forearm, laid on his chest: turned to point a set way, the wrist was bent
                    -- back - "hands are all bent in the wrong way", 2026-11-11)
                    -- (toward his middle: a way fixed on his body - aimed by the forearm, which the turn itself moved, the
                    -- hands went round in circles: "hands spinning in circles", 2026-11-11)
                    local want_fing = (sd == "l") and cr or vmul(cr, -1.0)
                    local q1 = qarc(palm, want_palm)
                    local f2 = qrot(q1, fing)
                    local f2p = vsub(f2, vmul(want_palm, vdot(f2, want_palm)))
                    local wfp = vsub(want_fing, vmul(want_palm, vdot(want_fing, want_palm)))
                    local qw = qmul(q1, rot(mesh, hb))
                    if vlen(wfp) > 0.1 and vlen(f2p) > 0.1 then qw = qmul(qarc(vnorm(f2p), vnorm(wfp)), qw) end
                    ovr_write(r, hb, qmul(qinv(rot(mesh, "lowerarm_" .. sd)), qw), M.HOLD.palm_hz * share(hb))
                end
            end
        end
        local gap = 0.0
        for _, f in pairs(h.final) do
            local d = vlen(vsub(pos(mesh, "hand_" .. f.side), vadd(pp, qrot(pq, f.loc))))
            if not h.best or d < h.best then h.best = d end
            if d > gap then gap = d end
        end
        if not h.dist_said and r.t - h.t0 > 1.5 then
            h.dist_said = true
            local o = {}
            for _, f in pairs(h.final) do o[#o + 1] = string.format("%s %.1f cm", f.side, vlen(vsub(pos(mesh, "hand_" .. f.side), vadd(pp, qrot(pq, f.loc))))) end
            log("holding his %s 1.5 s in: hands from their places %s", h.e.id, table.concat(o, ", "))
        end
        local H = M.HOLD
        if not r.grounded and (r.air or 0.0) > 0.5 then hold_stop(r, "in the air"); return end
        local okw, lv, av = pcall(function() return mesh:GetPhysicsLinearVelocity(FN["pelvis"]), mesh:GetPhysicsAngularVelocityInDegrees(FN["pelvis"]) end)
        if okw and lv and av and r.t - h.t0 > 0.3 then
            local sp = sqrt(lv.X * lv.X + lv.Y * lv.Y + lv.Z * lv.Z)
            local sw = sqrt(av.X * av.X + av.Y * av.Y + av.Z * av.Z)
            if abs(av.Z) > H.spin_w then h.spin_for = (h.spin_for or 0.0) + (r.breath_dt or 0.016) else h.spin_for = 0.0 end
            if sp > H.wild_v or sw > H.wild_w or h.spin_for > H.spin_t then
                log("holding his %s threw him about (%.0f cm/s, %.0f deg/s) - let go", h.e.id, sp, sw)
                hold_stop(r, "too wild")
                return
            end
        end
        if h.far and r.t - h.t0 > H.boost_after and gap > H.boost_gap and r.t - (h.boost_t or 0.0) > H.boost_every
            and (h.boost or 1.0) < H.boost_max then
            h.boost_t = r.t
            h.boost = min(H.boost_max, (h.boost or 1.0) * 1.25)
            for nm, f in pairs(h.final) do
                pcall(function() r.pc:SetControlLinearData(nm, H.hz * arm_share(f.side) * H.far_k * h.boost, H.damp, H.extra, H.far_max_force, true, true, false) end)
            end
            if h.foot_ctl then pcall(function() r.pc:SetControlLinearData(h.foot_ctl, H.foot_hz * h.boost, 1.0, 1.0, H.foot_max_force, true, true, false) end) end
            log("still %.0f cm short of his %s: pulling %.1fx as hard", gap, h.e.id, h.boost)
        end
        -- (each holding arm reaching for its place: the upper arm aimed from the shoulder, the forearm from the elbow -
        -- with the arm let go and only the hand pulled, "not putting enough effort into grabbing limbs", 2026-11-10)
        for _, f in pairs(h.final) do
            local sd = f.side
            local goal = vadd(pp, qrot(pq, f.closed and f.loc or f.near))
            -- (the elbow bent to put the hand on its place: both bones aimed straight at it, a place nearer than his arm's
            -- length - his chest, his face - had the hand held out past it against the hold's pull, and it hung just off
            -- what it held, "hands still floating just above what they're trying to hold", 2026-11-11. Two bones: the
            -- elbow where the upper arm's and the forearm's lengths meet, on the side it already bends to)
            local S, Ec, Hc = pos(mesh, "upperarm_" .. sd), pos(mesh, "lowerarm_" .. sd), pos(mesh, "hand_" .. sd)
            local la, lb = vlen(vsub(Ec, S)), vlen(vsub(Hc, Ec))
            local sg = vsub(goal, S)
            local dg = vlen(sg)
            local elbow = nil
            if dg > 1.0 and la > 1.0 and lb > 1.0 then
                local u = vmul(sg, 1.0 / dg)
                local dd = max(abs(la - lb) + 1.0, min(la + lb - 0.5, dg))
                local x = (la * la - lb * lb + dd * dd) / (2.0 * dd)
                local hh = sqrt(max(0.0, la * la - x * x))
                -- (the elbow out to his side and down his body - fixed on him; taken from where the elbow was, it wandered
                -- round and the hand with it, "hands spinning in circles", 2026-11-11)
                local qs = rot(mesh, "spine_05")
                local side, dn = v3(0.0, 0.0, 0.0), v3(0.0, 0.0, -1.0)
                if poses and poses.chest_right_local then
                    local cr2 = vnorm(qrot(qs, poses.chest_right_local))
                    side = (sd == "l") and vmul(cr2, -1.0) or cr2
                    dn = vnorm(vsub(pos(mesh, "pelvis"), pos(mesh, "spine_05")))
                end
                local pd = vadd(side, vmul(dn, 0.7))
                local pole = vsub(pd, vmul(u, vdot(pd, u)))
                if vlen(pole) < 0.05 then pole = vsub(vsub(Ec, S), vmul(u, vdot(vsub(Ec, S), u))) end
                if vlen(pole) > 0.001 then elbow = vadd(S, vadd(vmul(u, x), vmul(vnorm(pole), hh))) end
            end
            for _, pr in ipairs({ { "upperarm_" .. sd, "clavicle_" .. sd }, { "lowerarm_" .. sd, "upperarm_" .. sd } }) do
                local bn, par = pr[1], pr[2]
                local e = BY_BONE[bn]
                if e and e.tip and r.ovr[bn] == "hold" and not limp[bn] then
                    local from = pos(mesh, bn)
                    local cur = vnorm(vsub(pos(mesh, e.tip), from))
                    local want
                    if elbow and bn:find("^upperarm_") then want = vnorm(vsub(elbow, from))
                    elseif elbow then want = vnorm(vsub(goal, elbow))
                    else want = vnorm(vsub(goal, from)) end
                    if vlen(want) > 0.5 then
                        local q = qmul(qinv(rot(mesh, par)), qmul(qarc(cur, want), rot(mesh, bn)))
                        ovr_write(r, bn, q, M.HOLD.reach_hz * share(bn))
                    end
                end
            end
        end
        for nm, f in pairs(h.final) do
            if not f.closed then
                local near_w = vadd(pp, qrot(pq, f.near))
                local d = vlen(vsub(pos(mesh, "hand_" .. f.side), near_w))
                if d < M.HOLD.close or r.t - h.t0 > M.HOLD.approach_t then
                    f.closed = true
                    pcall(function() r.pc:SetControlTargetPosition(nm, fv(f.loc), 0.0, true, false, true, false) end)   -- (all seven: with five it failed every time, and the hands stayed at the place 18 cm out - "hands floating")
                end
            end
        end
    end
    kick_tick(r)
end

-- ------------------------------------------------------------------ his parts kept out of each other
-- ("body parts still going through eachother", 2026-11-10.) STORROR's ragdoll has no collision between its own bodies and
-- none can be switched on from a mod (the physics asset's table is out of reach) - so, as the shelved Euphoria mod did it
-- (2026-10-29): each limb a capsule along its bones (the hand to its fingertips, the foot to its ball), his trunk three
-- broad pieces across him - chest, belly, hips - and his head a ball; every frame, each two that should never meet and
-- overlap, looked at half a frame ahead, are pushed apart along the line between their nearest points - the way they
-- were coming together taken out, and `k` cm/s more for each cm of overlap (`sep_max` at most; each body `max_dv` a frame
-- at most all told); the trunk moved a quarter as much as a limb; a limb under his trunk, with the floor in its way out,
-- holds and the trunk lifts off it. Parts torn off are left out; the pushes are no blows (their parts quiet a moment).
-- (firmer, "arms still going through body on ragdoll", 2026-11-10: was k 35, sep_max 250, max_dv 800)
-- (on the ground - `k_ground` 0 - two parts meeting only stopped from going further in, never shoved back out: his hand
-- resting on his chest, held there by his arm's weight, was kicked out every frame and fell back, and that shaking walked
-- him round in circles on the ground, 60 cm and 80 deg a second for minutes - "player is currently spinning on the
-- ground", 2026-11-11, found by turning the push off: he lay still at once. In the air, shoved apart past `tol` cm)
M.SELF = { on = true, k = 55.0, k_ground = 0.0, tol = 2.0, max_dv = 1100.0, ahead = 0.5, sep_max = 380.0, spin_k = 0.0 }
-- (limp - LIVE RAGDOLL off, or dead - a gentler push: no muscle holding his limbs off himself, they folded deep into him -
-- a thigh 17 cm into his belly - and pushed apart at full strength he was flung about, "its like ripping the player in a
-- random direction", 2026-11-10)
M.SELF_LIMP = setmetatable({ k = 18.0, max_dv = 250.0, sep_max = 110.0 }, { __index = M.SELF })
local SC = {}
local mass = nil           -- (a body's mass, kg: set by SC.tick for its mesh)
do
    local CAPS = {
        chest = { "chest_l", "chest_r", 12.0, "spine_04", 0.25, "chest" }, belly = { "belly_l", "belly_r", 11.0, "spine_02", 0.25, "chest" },
        hips = { "hips_l", "hips_r", 11.0, "pelvis", 0.25, "chest" }, head = { "head_c", "head_c", 10.5, "head", 0.5, "head" },
    }
    for _, sd in ipairs({ "l", "r" }) do
        local function b(n) return n .. "_" .. sd end
        CAPS[b("thigh")] = { b("thigh"), b("calf"), 6.5, b("thigh"), 1.0, b("thigh") }
        CAPS[b("thigh_lo")] = { b("thigh_mid"), b("calf"), 6.5, b("thigh"), 1.0, b("thigh") }
        CAPS[b("calf")] = { b("calf"), b("foot"), 5.5, b("calf"), 1.0, b("calf") }
        CAPS[b("foot")] = { b("foot"), b("ball"), 4.5, b("foot"), 1.0, b("foot") }
        CAPS[b("upperarm")] = { b("upperarm"), b("lowerarm"), 5.0, b("upperarm"), 1.0, b("upperarm") }
        CAPS[b("uarm_lo")] = { b("uarm_mid"), b("lowerarm"), 5.0, b("upperarm"), 1.0, b("upperarm") }
        CAPS[b("lowerarm")] = { b("lowerarm"), b("hand"), 4.0, b("lowerarm"), 1.0, b("lowerarm") }
        CAPS[b("hand")] = { b("hand"), b("middle_03"), 3.5, b("hand"), 1.0, b("hand") }
    end
    local PAIRS = {
        { "thigh_l", "thigh_r" }, { "thigh_l", "calf_r" }, { "calf_l", "thigh_r" }, { "calf_l", "calf_r" },
        { "foot_l", "foot_r" }, { "foot_l", "calf_r" }, { "calf_l", "foot_r" }, { "foot_l", "thigh_r" }, { "thigh_l", "foot_r" },
        { "lowerarm_l", "lowerarm_r" }, { "hand_l", "hand_r" }, { "lowerarm_l", "hand_r" }, { "hand_l", "lowerarm_r" },
        { "upperarm_l", "lowerarm_r" }, { "lowerarm_l", "upperarm_r" }, { "upperarm_l", "hand_r" }, { "hand_l", "upperarm_r" },
        { "uarm_lo_l", "uarm_lo_r" },
    }
    for _, a in ipairs({ "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "uarm_lo_l", "uarm_lo_r" }) do
        for _, b in ipairs({ "chest", "belly", "hips", "head" }) do PAIRS[#PAIRS + 1] = { a, b } end
    end
    for _, a in ipairs({ "thigh_lo_l", "thigh_lo_r" }) do
        for _, b in ipairs({ "chest", "belly" }) do PAIRS[#PAIRS + 1] = { a, b } end
    end
    for _, a in ipairs({ "uarm_lo_l", "uarm_lo_r" }) do
        for _, b in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r" }) do PAIRS[#PAIRS + 1] = { a, b } end
    end
    for _, a in ipairs({ "lowerarm_l", "lowerarm_r", "hand_l", "hand_r" }) do
        for _, b in ipairs({ "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }) do PAIRS[#PAIRS + 1] = { a, b } end
    end
    local MADE = { chest_l = true, chest_r = true, belly_l = true, belly_r = true, hips_l = true, hips_r = true, head_c = true,
                   thigh_mid_l = true, thigh_mid_r = true, uarm_mid_l = true, uarm_mid_r = true }
    local BONES = {}
    do
        local seen = {}
        for _, c in pairs(CAPS) do for i = 1, 2 do if not seen[c[i]] and not MADE[c[i]] then seen[c[i]] = true; BONES[#BONES + 1] = c[i] end end end
        for _, bn in ipairs({ "pelvis", "spine_02", "spine_04", "spine_05", "clavicle_l", "clavicle_r", "neck_01", "head", "upperarm_l", "upperarm_r" }) do
            if not seen[bn] then seen[bn] = true; BONES[#BONES + 1] = bn end
        end
    end
    local function lerp(a, b, k) return v3(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k) end
    local function madd(a, u, k, w, j) return v3(a.x + u.x * k + w.x * j, a.y + u.y * k + w.y * j, a.z + u.z * k + w.z * j) end
    local function made_points(P)
        local up = vnorm(vsub(P.spine_05, P.pelvis))
        local right = vnorm(vsub(P.clavicle_r, P.clavicle_l))
        local fwd = vcross(right, up)
        P.chest_l, P.chest_r = madd(P.spine_04, right, -6.0, fwd, 3.0), madd(P.spine_04, right, 6.0, fwd, 3.0)
        P.belly_l, P.belly_r = madd(P.spine_02, right, -6.0, fwd, 3.0), madd(P.spine_02, right, 6.0, fwd, 3.0)
        P.hips_l, P.hips_r = madd(P.pelvis, right, -7.0, fwd, 1.0), madd(P.pelvis, right, 7.0, fwd, 1.0)
        local hu = vnorm(vsub(P.head, P.neck_01))
        P.head_c = madd(P.head, hu, 9.0, fwd, 2.0)
        P.thigh_mid_l, P.thigh_mid_r = lerp(P.thigh_l, P.calf_l, 0.5), lerp(P.thigh_r, P.calf_r, 0.5)
        P.uarm_mid_l, P.uarm_mid_r = lerp(P.upperarm_l, P.lowerarm_l, 0.45), lerp(P.upperarm_r, P.lowerarm_r, 0.45)
    end
    local function closest(p1, q1, p2, q2)
        local d1x, d1y, d1z = q1.x - p1.x, q1.y - p1.y, q1.z - p1.z
        local d2x, d2y, d2z = q2.x - p2.x, q2.y - p2.y, q2.z - p2.z
        local rx, ry, rz = p1.x - p2.x, p1.y - p2.y, p1.z - p2.z
        local a = d1x * d1x + d1y * d1y + d1z * d1z
        local e = d2x * d2x + d2y * d2y + d2z * d2z
        local f = d2x * rx + d2y * ry + d2z * rz
        local sv, tv = 0.0, 0.0
        if a > 1e-6 or e > 1e-6 then
            if a <= 1e-6 then
                tv = max(0.0, min(1.0, f / e))
            else
                local c = d1x * rx + d1y * ry + d1z * rz
                if e <= 1e-6 then
                    sv = max(0.0, min(1.0, -c / a))
                else
                    local b = d1x * d2x + d1y * d2y + d1z * d2z
                    local den = a * e - b * b
                    sv = (den > 1e-6) and max(0.0, min(1.0, (b * f - c * e) / den)) or 0.0
                    tv = (b * sv + f) / e
                    if tv < 0.0 then tv = 0.0; sv = max(0.0, min(1.0, -c / a))
                    elseif tv > 1.0 then tv = 1.0; sv = max(0.0, min(1.0, (b - c) / a)) end
                end
            end
        end
        return v3(p1.x + d1x * sv, p1.y + d1y * sv, p1.z + d1z * sv), v3(p2.x + d2x * tv, p2.y + d2y * tv, p2.z + d2z * tv)
    end
    local masses = { addr = nil }
    function SC.tick(pawn, r, dt)
        local S = (r.dead or r.lifeless) and M.SELF_LIMP or M.SELF
        if not S.on then return 0 end
        local mesh = pawn.Mesh
        if masses.addr ~= mesh:GetAddress() then masses = { addr = mesh:GetAddress() } end
        mass = function(bn)
            local m = masses[bn]
            if not m then
                local ok, v = pcall(function() return mesh:GetBoneMass(FN[bn], true) end)
                m = (ok and v and v > 0.1) and v or 3.0
                masses[bn] = m
            end
            return m
        end
        local P = {}
        for _, bn in ipairs(BONES) do
            local ok, v = pcall(pos, mesh, bn)
            if ok and v then P[bn] = v end
        end
        -- (the fingertips: where the skeleton has none, the knuckles)
        for _, sd in ipairs({ "l", "r" }) do
            if not P["middle_03_" .. sd] then local ok, v = pcall(pos, mesh, "middle_01_" .. sd); if ok then P["middle_03_" .. sd] = v end end
        end
        made_points(P)
        local la = dt * S.ahead
        local V = {}
        for _, c in pairs(CAPS) do
            local bn = c[4]
            if not V[bn] then
                local ok, u = pcall(function() return mesh:GetPhysicsLinearVelocity(FN[bn]) end)
                V[bn] = ok and u and v3(u.X, u.Y, u.Z) or v3(0.0, 0.0, 0.0)
            end
        end
        local function ahead_pt(c, i) local pt = P[c[i]]; local m = V[c[4]]; return v3(pt.x + m.x * la, pt.y + m.y * la, pt.z + m.z * la) end
        local acc = {}
        local function push(cap, x, y, z)
            local e = acc[cap[4]]
            if not e then e = { bone = cap[4], region = cap[6], x = 0.0, y = 0.0, z = 0.0 }; acc[cap[4]] = e end
            e.x, e.y, e.z = e.x + x, e.y + y, e.z + z
        end
        local n_hit = 0
        local contacts = {}
        -- (a hand holding a part of him, and its forearm, let touch that part: pushed back out of it as the hold pulled it in,
        -- the two fought, his hands stopped short of his foot, and pulled harder he spun and flew - "he's finally touched his
        -- foot but its making him spin and literally fly", 2026-11-10)
        local free_of = nil
        local h = r.hold
        if h and h.sides and h.e then
            local id = h.e.id
            local held = {}
            local lg = id:match("^thigh_(%a)$") or id:match("^calf_(%a)$") or id:match("^foot_(%a)$")
            local am = id:match("^upperarm_(%a)$") or id:match("^lowerarm_(%a)$") or id:match("^hand_(%a)$")
            if lg then for _, k in ipairs({ "thigh_", "thigh_lo_", "calf_", "foot_" }) do held[k .. lg] = true end
            elseif am then for _, k in ipairs({ "upperarm_", "uarm_lo_", "lowerarm_", "hand_" }) do held[k .. am] = true end
            elseif id == "chest" then held.chest, held.belly = true, true
            elseif id == "head" then held.head = true end
            -- (the hand only: its forearm let in too, his forearms sank into his chest as he held it - "arms still going
            -- through body on ragdoll", 2026-11-10)
            local holding = {}
            for _, sd in ipairs(h.sides) do holding["hand_" .. sd] = true end
            free_of = function(a, b) return (holding[a] and held[b]) or (holding[b] and held[a]) end
        end
        for _, pr in ipairs(PAIRS) do
            local A, B = CAPS[pr[1]], CAPS[pr[2]]
            -- (parts torn off are not there to meet)
            if A and B and P[A[1]] and P[A[2]] and P[B[1]] and P[B[2]] and parts[A[6]].state < 3 and parts[B[6]].state < 3
                and not (free_of and free_of(pr[1], pr[2])) then
                local a1, a2, b1, b2 = ahead_pt(A, 1), ahead_pt(A, 2), ahead_pt(B, 1), ahead_pt(B, 2)
                local mx, my, mz = (a1.x + a2.x - b1.x - b2.x) * 0.5, (a1.y + a2.y - b1.y - b2.y) * 0.5, (a1.z + a2.z - b1.z - b2.z) * 0.5
                local reach = vlen(vsub(a2, a1)) * 0.5 + vlen(vsub(b2, b1)) * 0.5 + A[3] + B[3]
                if mx * mx + my * my + mz * mz < reach * reach then
                    local ca, cb = closest(a1, a2, b1, b2)
                    local dd = vsub(cb, ca)
                    local dist = vlen(dd)
                    local pen = A[3] + B[3] - dist
                    if pen > (r.sc_pen or 0.0) then r.sc_pen, r.sc_pair = pen, pr[1] .. " in " .. pr[2] end
                    if pen > 0.0 then
                        local nrm
                        if dist > 0.5 then nrm = vmul(dd, 1.0 / dist)
                        else
                            local el = vsub(P[B[1]], P[A[1]])
                            nrm = vlen(el) < 0.5 and v3(1.0, 0.0, 0.0) or vnorm(el)
                        end
                        local va, vb = V[A[4]], V[B[4]]
                        -- (pushed apart by one impulse, equal and opposite, shared by their masses - the lighter moves more: by
                        -- set speeds instead, an arm and his trunk pushed apart did not balance, and every frame they lay against
                        -- each other he was shoved along the ground - "players sliding for some reason", 2026-11-10)
                        local apart = vdot(vsub(vb, va), nrm)                -- (> 0: separating)
                        local kk = r.grounded and S.k_ground or S.k
                        local want = max(0.0, min(kk * max(0.0, pen - S.tol), S.sep_max) - apart)
                        if want > 0.0 then
                            local ma, mb = mass(A[4]), mass(B[4])
                            local j = want / (1.0 / ma + 1.0 / mb)
                            -- (the two pushes given where the two parts touch, not at their middles: equal and opposite but
                            -- off the line between their middles they turned him - his arms and legs pressed together as he
                            -- held a leg, he span on the spot, "still sliding and spinning when reaching for legs", 2026-11-10)
                            contacts[#contacts + 1] = { a = A, b = B, n = nrm, j = j, at = vmul(vadd(ca, cb), 0.5), ma = ma, mb = mb }
                        end
                        n_hit = n_hit + 1
                    end
                end
            end
        end
        -- (his whole body's turning about the up, lying on the ground, taken off a share `spin_k` a second - as one turn of all
        -- of him round his middle, so nothing of his limbs' own moves is touched: "still sliding and spinning when reaching
        -- for legs", 2026-11-10. Not while he rolls or crawls)
        if r.grounded and S.spin_k > 0.0 and not (r.act and (r.act.name == "roll" or r.act.name == "rollabout" or r.act.name == "crawl"))
            and not r.crawling then
            local cx, cy, mt = 0.0, 0.0, 0.0
            for bn, u in pairs(V) do local pt = P[bn]; if pt then local m = mass(bn); cx, cy, mt = cx + pt.x * m, cy + pt.y * m, mt + m end end
            if mt > 1.0 then
                cx, cy = cx / mt, cy / mt
                local L, I = 0.0, 0.0
                for bn, u in pairs(V) do
                    local pt = P[bn]
                    if pt then
                        local m, rx, ry = mass(bn), pt.x - cx, pt.y - cy
                        L = L + m * (rx * u.y - ry * u.x)
                        I = I + m * (rx * rx + ry * ry)
                    end
                end
                if I > 1.0 then
                    local w = L / I                                  -- (rad/s)
                    local dw = -w * min(1.0, S.spin_k * dt)
                    if abs(w) > 0.05 then
                        for bn, u in pairs(V) do
                            local pt = P[bn]
                            if pt then
                                local rx, ry = pt.x - cx, pt.y - cy
                                pcall(function()
                                    mesh:AddImpulse({ X = -dw * ry, Y = dw * rx, Z = 0.0 }, FN[bn], true)
                                    mesh:AddAngularImpulseInRadians({ X = 0.0, Y = 0.0, Z = dw }, FN[bn], true)
                                end)
                            end
                        end
                    end
                end
            end
        end
        for _, c in ipairs(contacts) do
            local dv = c.j / min(c.ma, c.mb)
            local k = (dv > S.max_dv) and (S.max_dv / dv) or 1.0
            local J = vmul(c.n, c.j * k)
            local at = fv(c.at)
            pcall(function()
                mesh:AddImpulseAtLocation(fv(vmul(J, -1.0)), at, FN[c.a[4]])
                mesh:AddImpulseAtLocation(fv(J), at, FN[c.b[4]])
            end)
            -- (its own push is no blow)
            if dv * k > 40.0 then
                r.quiet[c.a[6]] = max(r.quiet[c.a[6]] or 0.0, r.t + M.DAMAGE.window + 0.02)
                r.quiet[c.b[6]] = max(r.quiet[c.b[6]] or 0.0, r.t + M.DAMAGE.window + 0.02)
            end
        end
        r.self_hits = (r.self_hits or 0) + n_hit
        return n_hit
    end
end

-- ------------------------------------------------------------------ his injuries kept on his feet (RAGDOLL > KEEP INJURIES)
-- ("when the player stands up they will still be missing severed parts and broken limbs will just dangle, while fractured
-- will be bent backwards" - fractured: the dislocated, the user said - 2026-11-10.) With the switch on, getting up heals
-- nothing (the game moving him - a waypoint, a respawn - still does); on his feet:
--   SEVERED    - still gone: the gore's copy of him, its stumps, goes on being drawn in his place (gore.lua);
--   BROKEN     - each arm and leg, from its topmost broken part down, given to the physics while the rest of him is
--                animated: it hangs and swings as he goes;
--   DISLOCATED - the part under the joint given to the physics too, and held by a muscle of its own at the angle it was put
--                out to, bent backwards (`disloc_hz`), against the part above as STORROR animates it.
-- STORROR may take the physics back as it gets him up: looked at every `check` s and given again.
M.STAND = { disloc_hz = 9.0, check = 0.5 }
local function keep_on() local Mn = _G.ARMENU; return Mn ~= nil and Mn.keep_injuries ~= nil and Mn.keep_injuries() end
-- LIVE RAGDOLL, on the RAGDOLL tab: off, he lies as STORROR's own ragdoll would - no muscle, no mind, nothing of his own
-- ("also add a switch to turn live ragdolls on and off", 2026-11-10). His hurts, his blood, crawling legless go on.
local function live_on() local Mn = _G.ARMENU; return not (Mn and Mn.live_ragdoll and not Mn.live_ragdoll()) end
-- HP BAR, on the RAGDOLL tab: off, no bar and no bleeding out
local function hp_on() local Mn = _G.ARMENU; return not (Mn and Mn.hp_bar and not Mn.hp_bar()) end
local function stand_stop(pawn, why, keep_sim)
    local sd_ = st.stand
    st.stand = nil
    if not sd_ then return end
    -- (going down: his hanging limbs left as they are, simulating - the ragdoll takes them over. Put back on his animation
    -- the same instant STORROR's ragdoll began, they snapped from hanging to his pose, and the snap flung them at 4000 cm/s
    -- and 9000 deg/s - "its like a jolt the second the player holds r3", 2026-11-10)
    if pawn and not keep_sim then
        local mesh = pawn.Mesh
        for _, b in ipairs(sd_.sim) do
            pcall(function() mesh:SetAllBodiesBelowSimulatePhysics(FN[b], false, true) end)
            pcall(function() mesh:SetAllBodiesBelowPhysicsBlendWeight(FN[b], 0.0, false, true) end)
        end
    end
    if sd_.pc then pcall(function() if sd_.pc:IsValid() then sd_.pc:K2_DestroyComponent(sd_.pc) end end) end
    log("on his feet: his hurt limbs his own again (%s)", why or "?")
end
-- (the limbs to hang: in each arm and leg, its topmost hurt part not below one torn off)
local function stand_roots()
    local roots = {}
    for _, sd in ipairs({ "l", "r" }) do
        for _, chain in ipairs({ { "upperarm", "lowerarm", "hand" }, { "thigh", "calf", "foot" } }) do
            for _, k in ipairs(chain) do
                local id = k .. "_" .. sd
                local e = parts[id]
                if not e or e.state == 3 then break end
                if e.state == 1 or e.state == 2 then roots[#roots + 1] = { bone = id, state = e.state }; break end
            end
        end
    end
    return roots
end
local function stand_apply(pawn, sd_)
    local mesh = pawn.Mesh
    pcall(function() if not mesh:IsGravityEnabled() then mesh:SetEnableGravity(true) end end)
    for _, b in ipairs(sd_.sim) do
        pcall(function() mesh:SetAllBodiesBelowSimulatePhysics(FN[b], true, true) end)
        pcall(function() mesh:SetAllBodiesBelowPhysicsBlendWeight(FN[b], 1.0, false, true) end)
    end
end
local function stand_start(pawn)
    local roots = stand_roots()
    if #roots == 0 then return end
    local mesh = pawn.Mesh
    local sd_ = { sim = {}, pc = nil, t = 0.0 }
    for _, rt in ipairs(roots) do sd_.sim[#sd_.sim + 1] = rt.bone end
    -- (a dislocated joint held bent where it was put out: a muscle between the part and the one above it)
    for _, rt in ipairs(roots) do
        local d, e = dis[rt.bone], BY_BONE[rt.bone]
        if rt.state == 1 and d and d.target and e then
            if not sd_.pc then
                local cls = StaticFindObject("/Script/PhysicsControl.PhysicsControlComponent")
                if cls and cls:IsValid() then
                    sd_.pc = pawn:AddComponentByClass(cls, false, { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
                        Scale3D = { X = 1, Y = 1, Z = 1 } }, false)
                end
            end
            if sd_.pc and sd_.pc:IsValid() then
                local data = { bEnabled = true, LinearStrength = 0.0, LinearDampingRatio = 1.0, LinearExtraDamping = 0.0, MaxForce = 0.0,
                    AngularStrength = M.STAND.disloc_hz, AngularDampingRatio = 1.0, AngularExtraDamping = 0.0, MaxTorque = 0.0,
                    LinearTargetVelocityMultiplier = 0.0, AngularTargetVelocityMultiplier = 0.0, CustomControlPoint = { X = 0, Y = 0, Z = 0 },
                    bUseCustomControlPoint = false, bUseSkeletalAnimation = false, bDisableCollision = false, bOnlyControlChildObject = true }
                local target = { TargetPosition = { X = 0, Y = 0, Z = 0 }, TargetVelocity = { X = 0, Y = 0, Z = 0 },
                    TargetOrientation = q2rot(d.target), TargetAngularVelocity = { X = 0, Y = 0, Z = 0 }, bApplyControlPointToTarget = false }
                pcall(function() sd_.pc:CreateControl(mesh, FN[e.p], mesh, FN[rt.bone], data, target, FN["ActiveRagdollStand"], "ar_stand_" .. rt.bone) end)
            end
        end
    end
    st.stand = sd_
    stand_apply(pawn, sd_)
    log("on his feet, still hurt: %s hang%s", table.concat(sd_.sim, ", "), #sd_.sim == 1 and "s" or "")
end
-- What his injuries leave him able to do on his feet ("if the players missing an arm they can no longer climb up objects
-- they can still vault tho, if legs are damaged depending on severity it should slow the player", "if a whole leg is
-- missing they are stuck in place and can only jump", 2026-11-10). STORROR's own locks - EnableParkourInput(source,
-- action, on), one source of ours - and the pace of his animations (he moves by them: STORROR's movement is root motion,
-- and speed set any other way it puts back each frame):
--   an arm missing (its hand, its forearm, or all of it): no climbing - climb, climbing about, swings, arm jumps, ledge
--     grabs - his vaults left him;
--   his legs hurt: slower, each leg by its worst (`slow`), both together multiplied, never under `floor`;
--   a whole leg missing: nothing but a jump - every move off but jumping, landing and the camera, his walking too.
-- Lifted as he goes down (the ragdoll is the ragdoll) and when he is healed.
M.LIMBS = { lock = "ActiveRagdollInjury", per = { sprained = 0.03, broken = 0.05, severed = 0.10 }, floor = 0.2,
            -- (his jumps: shorter and lower by his legs - "jumps should also be shorter and slower depending on damage",
            -- 2026-11-10 - the speed he leaves the ground at x his legs' pace, never under `jump_floor`; STORROR kept from
            -- speeding him back up for `jump_hold` s)
            jump_floor = 0.45, jump_hold = 0.5,
            -- (how much lower he jumps, for each part of his legs - thigh, calf, foot - sprained, broken or gone: "jump height
            -- seems completely random. sprained leg parts should jump 2% less, broken 3.5%. severed 5%", 2026-11-10. Made by
            -- his gravity while he rises - raised so the top of the jump comes that much lower, whatever STORROR's jump was)
            jump = { sprained = 0.02, broken = 0.035, severed = 0.05 } }
local function jump_factor()
    local J = M.LIMBS.jump
    local off = 0.0
    for _, sd in ipairs({ "l", "r" }) do
        for _, k in ipairs({ "thigh", "calf", "foot" }) do
            local sv = parts[k .. "_" .. sd].state
            if sv == 1 then off = off + J.sprained elseif sv == 2 then off = off + J.broken elseif sv == 3 then off = off + J.severed end
        end
    end
    return max(M.LIMBS.jump_floor, 1.0 - off)
end
-- (his gravity his own again: after the rise, going down, healed, reloaded)
local function jump_end(pawn, why)
    local J = st.jg
    st.jg = nil
    if not J then return end
    if why and (J.rise or 0.0) > 5.0 and (M.LOG.verbose or (J.frames or 0) > 0) then
        log("jump: up %.0f cm of STORROR's %.0f (%.0f%% - his legs %.0f%%; %d frames cut%s; modes %s%s) - %s", J.top - J.z0, J.rise,
            J.rise > 0.0 and (J.top - J.z0) / J.rise * 100.0 or 0.0, J.f * 100.0, J.frames or 0, J.move and ", a climb or vault - left" or "",
            tostring(J.modes), J.list and (", " .. J.list:sub(1, 120)) or "", why)
    end
end
M.jump_end = function(pawn, why) pcall(jump_end, pawn, why) end
local ACT_IN = { Jump = 0, Vault = 1, Flip = 2, Splat = 3, Dive = 4, Climb = 5, Descent = 6, Landing = 7, Dyno180 = 8, Swing = 9,
                 ClimbLocomotion = 10, Attack = 11, ArmJump = 12, Roll = 13, AdvancedLocomotion = 14, Locomotion = 15, Camera = 16,
                 DescentReticle = 19, ClimbReticle = 20, PrimaryLedgeLaunchAssist = 22, GrabLedgeLaunchAssist = 23, SecondaryLedgeLaunchAssist = 24 }
-- (the ledge-launch assists left on: they may be what carries him over in a vault - "also cant vault", 2026-11-10)
local NO_CLIMB = { "Climb", "ClimbLocomotion", "Swing", "ArmJump", "Dyno180", "ClimbReticle", "GrabLedgeLaunchAssist" }
limbs_want = function()
    local arm_out, arms_lost = false, 0
    for _, sd in ipairs({ "l", "r" }) do
        -- (a hand alone gone, he still climbs: "if its only the hand missing should still be able to climb", 2026-11-10)
        local lost = false
        for _, k in ipairs({ "upperarm", "lowerarm" }) do if parts[k .. "_" .. sd].state == 3 then lost = true end end
        if lost then arm_out, arms_lost = true, arms_lost + 1 end
    end
    -- (both arms gone: no vaulting either - "if player loses both arms they shouldnt be able to vault", 2026-11-10)
    local arms_gone = arms_lost == 2
    -- (a leg gone below the knee is as good as gone: nothing to stand on - "missing lower leg on left side but not having
    -- to jump that needs fixed", 2026-11-10; a foot alone gone, he hobbles)
    local leg_off = false
    for _, sd in ipairs({ "l", "r" }) do
        if parts["thigh_" .. sd].state == 3 or parts["calf_" .. sd].state == 3 then leg_off = true end
    end
    -- (his pace: for each part of his arms and legs broken `per.broken` slower, sprained `per.sprained`, and for each limb
    -- torn off - counted once, where it was cut - `per.severed`; never under `floor` - "lets do it like this for each broken
    -- 5% slower speed sprained limbs 3% and severed 10%", 2026-11-10. Running, climbing and jumping alike.)
    local L = M.LIMBS
    local PARENT = { lowerarm = "upperarm", hand = "lowerarm", calf = "thigh", foot = "calf" }
    local off = 0.0
    for _, sd in ipairs({ "l", "r" }) do
        for _, k in ipairs({ "upperarm", "lowerarm", "hand", "thigh", "calf", "foot" }) do
            local sv = parts[k .. "_" .. sd].state
            if sv == 1 then off = off + L.per.sprained
            elseif sv == 2 then off = off + L.per.broken
            elseif sv == 3 then
                local par = PARENT[k]
                if not (par and parts[par .. "_" .. sd].state == 3) then off = off + L.per.severed end
            end
        end
    end
    local rate = max(L.floor, 1.0 - off)
    -- (LIMB SLOWNESS off, on the RAGDOLL tab: his hurt limbs slow him none - "add an option for limb damage slowness",
    -- 2026-11-10)
    local Mn = _G.ARMENU
    if Mn and Mn.limb_slowness and not Mn.limb_slowness() then rate = 1.0 end
    return { arm_out = arm_out, arms_gone = arms_gone, leg_off = leg_off, rate = rate, arms = rate }
end
-- (climbing now: STORROR's move by its montage's name)
local CLIMB_WORDS = { "Climb", "Ledge", "Hang", "Mantle", "Shimmy", "Pullup", "PullUp", "Brachiat", "Wall" }
local function climbing(pawn)
    local name = montage(pawn)
    for _, w in ipairs(CLIMB_WORDS) do if name:find(w) then return true end end
    return false
end
local function limbs_set(pawn, want)
    want = want or { arm_out = false, leg_off = false, rate = 1.0 }
    local sig = string.format("%s|%s|%.2f|%s", tostring(want.arm_out), tostring(want.leg_off), want.rate, tostring(want.arms_gone))
    if st.limbs_sig == sig then return end
    st.limbs_sig = sig
    local src = FN[M.LIMBS.lock]
    local pk = lib.parkour(pawn)
    local loco = lib.comp_named(pawn, "Locomotion")
    if pk then
        pcall(function() pk:EnableAllParkourInputs(src, true) end)
        if want.leg_off then
            pcall(function() pk:EnableAllParkourInputs(src, false) end)
            -- (a jump, and a vault too - "also cant vault")
            for _, a in ipairs({ "Jump", "Vault", "Landing", "Camera", "PrimaryLedgeLaunchAssist", "SecondaryLedgeLaunchAssist" }) do
                pcall(function() pk:EnableParkourInput(src, ACT_IN[a], true) end)
            end
            -- (and climbing, his arms whole enough: they pull him up, one leg or none - "still cant climb", 2026-11-10)
            if not want.arm_out then
                for _, a in ipairs(NO_CLIMB) do pcall(function() pk:EnableParkourInput(src, ACT_IN[a], true) end) end
                for _, a in ipairs({ "Descent", "DescentReticle" }) do pcall(function() pk:EnableParkourInput(src, ACT_IN[a], true) end) end
            end
        elseif want.arm_out then
            for _, a in ipairs(NO_CLIMB) do pcall(function() pk:EnableParkourInput(src, ACT_IN[a], false) end) end
        end
        if want.arms_gone then pcall(function() pk:EnableParkourInput(src, ACT_IN.Vault, false) end) end
    end
    if loco then
        pcall(function() loco:EnableLocomotionInputCallback(src, not want.leg_off) end)
        pcall(function() loco:EnableAdvancedLocomotionInput(src, not want.leg_off) end)
    end
    pcall(function() pawn.Mesh.GlobalAnimRateScale = want.rate end)
    if want.leg_off then log("on his feet: a leg gone - he can only jump%s%s", want.arms_gone and "" or ", vault", want.arm_out and "" or " and climb")
    elseif want.arm_out or want.rate < 1.0 then
        log("on his feet:%s%s", want.arms_gone and " both arms gone, no climbing or vaulting;" or want.arm_out and " an arm gone, no climbing;" or "", want.rate < 1.0 and string.format(" slowed to %.0f%%", want.rate * 100.0) or "")
    else log("on his feet: all he can do back") end
end
M.limbs_set = function(pawn, want) pcall(limbs_set, pawn, want) end
-- With a leg gone his walking is off, and with it STORROR's turning: he is turned here instead, on the spot, toward the way
-- the stick (or W A S D) points from the camera, `turn_deg` a second ("still need to be able to turn in place", 2026-11-10)
M.LIMBS.turn_deg = 240.0
local TURN_KEYS = { lx = { KeyName = FName("Gamepad_LeftX") }, ly = { KeyName = FName("Gamepad_LeftY") },
                    w = { KeyName = FName("W") }, a = { KeyName = FName("A") }, s = { KeyName = FName("S") }, d = { KeyName = FName("D") } }
local function turn_in_place(pawn, dt)
    local pc = lib.controller()
    if not pc then return end
    local x, y = 0.0, 0.0
    pcall(function() x = pc:GetInputAnalogKeyState(TURN_KEYS.lx); y = pc:GetInputAnalogKeyState(TURN_KEYS.ly) end)
    local function down(k) local ok, v = pcall(function() return pc:IsInputKeyDown(TURN_KEYS[k]) end); return ok and v end
    if down("w") then y = y + 1.0 end
    if down("s") then y = y - 1.0 end
    if down("d") then x = x + 1.0 end
    if down("a") then x = x - 1.0 end
    if x * x + y * y < 0.09 then return end
    local cam = 0.0
    pcall(function() cam = pc:GetControlRotation().Yaw end)
    local want = cam + deg(atan(x, y))
    local r = pawn:K2_GetActorRotation()
    local cur = r.Yaw
    local diff = (want - cur + 540.0) % 360.0 - 180.0
    local step = M.LIMBS.turn_deg * dt
    if abs(diff) < step then step = abs(diff) end
    local yaw = cur + ((diff > 0) and step or -step)
    pcall(function() pawn:K2_SetActorRotation({ Pitch = r.Pitch, Yaw = yaw, Roll = r.Roll }, false) end)
end

M.stand_stop = function(pawn, why) stand_stop(pawn, why) end
local function stand_tick(pawn, dt)
    local sd_ = st.stand
    sd_.t = sd_.t + dt
    if sd_.t < M.STAND.check then return end
    sd_.t = 0.0
    local mesh = pawn.Mesh
    for _, b in ipairs(sd_.sim) do
        local ok, sim = pcall(function() return mesh:IsSimulatingPhysics(FN[b]) end)
        if ok and sim == false then stand_apply(pawn, sd_); break end
    end
end

-- ------------------------------------------------------------------ the ragdoll, from start to end
-- the blows to each part, read every frame he is down
local function sever(pawn, r, id, opts)
    local G = _G.ARGORE
    if not (G and M.DAMAGE.gore) then return false end
    if M.no_sever() then return false end            -- (SEVERED LIMBS off: the blow breaks it instead)
    local ok, regs = pcall(G.sever, pawn, id, opts)
    if not (ok and regs) then
        if not ok then log("gore failed (%s)", tostring(regs)) end
        return false
    end
    for _, rid in ipairs(regs) do
        local e = parts[rid]
        if e then e.state, e.up, e.worse_t = 3, 0.0, os.clock() end
    end
    limp_update()
    if M.on_injury then pcall(M.on_injury, regs[1], 3, regs) end
    return regs
end
-- (his body blown apart: every limb and the head, the far ends first so each comes away in its own pieces)
local EXPLODE = { "hand_l", "hand_r", "foot_l", "foot_r", "lowerarm_l", "lowerarm_r", "calf_l", "calf_r",
                  "upperarm_l", "upperarm_r", "thigh_l", "thigh_r", "head" }
local explode
explode = function(pawn, r, mph)
    if r.exploded then return end
    r.exploded = true
    -- (blown apart: his HP all gone at once - "if player explodes make his hp 0", 2026-11-10 - and so dead, kept down till a
    -- waypoint)
    local G = _G.ARGORE
    if G and G.take_hp and G.hp_points then
        pcall(function() G.take_hp(G.hp_points() + 1.0) end)
        st.hp_why = string.format("blown apart at %.0f mph", mph)
    end
    local n = 0
    if M.DAMAGE.gore then
        for _, id in ipairs(EXPLODE) do
            if parts[id].state < 3 and sever(pawn, r, id, { fling = 2.5, burst = 1.6 }) then n = n + 1 end
        end
    end
    for id, e in pairs(parts) do
        if id == "chest" then e.state = max(e.state, 2) elseif M.DAMAGE.gore then e.state = 3 else e.state = max(e.state, 2) end
        e.up = 0.0
    end
    limp_update()
    crack(r, pawn.Mesh, "spine_03")
    snd("thud", 1.0, at_bone(pawn.Mesh, "pelvis"))
    log("his body exploded at %.0f mph (%d more pieces off, besides any the same hit took a moment before)", mph, n)
end
-- SCALING DAMAGE (the RAGDOLL tab, "do a better job on damage scaling", "go more in depth with it", "especially tarkov
-- mod", 2026-11-11), after Tarkov's health: each part has its health - with TARKOV DAMAGE its own HP, the figure's numbers,
-- its share of his MAX HP; without it its own wear - and every hit over `min_mph` takes from it by its speed, a fraction of
-- that part's whole: ((mph - min) / (sever - min)) ^ `pow` (20 mph about 15%, 30 about 40%, 50 all), more to his head, less
-- to his chest (`mult`). One landing's contacts, a few ms apart, count as its hardest (`window`). His part's state follows
-- its health: under `out_at` put out, under `broken_at` broken (red); red with none left, the next hit takes it off,
-- whatever its speed ("if a body part is red with 0 health the next state is dismemberment no matter the fall height");
-- his chest no further than broken. A hit alone still does what it always did besides (a 50 mph hit, off at once). With
-- TARKOV DAMAGE a part at 0 passes its hits on to the rest of him, his limbs first, his chest and head last (gore's
-- limb_lose), as Tarkov's blacked limbs do; at 0 his head or chest, he is dead.
-- And Tarkov's fall damage: landing on his feet from `fall_from` cm or more - no bail - his legs take the landing's speed
-- (`fall_k`, his feet the most), so drop after drop wears them down to a fracture and a break; a roll takes none.
M.SCALE = { min_mph = 8.0, pow = 1.5, most = 1.25, out_at = 0.75, broken_at = 0.4, window = 0.3, stack_gap = 1.0,
            mult = { head = 1.25, chest = 0.8 },
            fall_from = 245.0, fall_k = { foot_l = 1.0, foot_r = 1.0, calf_l = 0.8, calf_r = 0.8, thigh_l = 0.5, thigh_r = 0.5 } }
-- a part's health left, 0..1, and whether it is TARKOV DAMAGE's
function M.part_left(id)
    local G = _G.ARGORE
    if G and G.limb_hp then
        local ok, L = pcall(G.limb_hp)
        if ok and L and L[id] and L[id][2] > 0 then return max(0.0, L[id][1] / L[id][2]), true end
    end
    local e = parts[id]
    return e and (e.wear or 1.0) or 1.0, false
end
-- one hit to a part's health; "severed" if it came off
function M.scale_hit(pawn, r, id, mph, standing)
    local S, D = M.SCALE, M.DAMAGE
    local e = parts[id]
    if not e or e.state >= 3 then return nil end
    local now = os.clock()
    -- (at 0 already: any hit at all takes it off, whatever its state - "limbs on tarkov mode should fall off after taking
    -- damage on 0", 2026-11-11; drained there by bleeding or by hits passed on from other parts, it had to be broken by one
    -- hit before the next took it)
    local before0 = M.part_left(id)
    local fresh0 = not e.hit_t or now - e.hit_t > S.window
    if before0 <= 0.001 and fresh0 and id ~= "chest" and not M.no_sever() then
        e.hit_t = now
        if standing then
            st.sever_queue = st.sever_queue or {}
            st.sever_queue[id] = true
            log("scaling damage: his %s, no health left, gives way (%.0f mph)", id, mph)
            return "gives"
        elseif r then
            local regs = sever(pawn, r, id)
            if regs then
                r.quiet[id] = r.t + 0.2
                crack(r, pawn.Mesh, id)
                take_hp(3, id)
                log("scaling damage: his %s, no health left, came off at %.0f mph", id, mph)
                return "severed"
            end
        end
    end
    if mph <= S.min_mph then return nil end
    local frac = ((mph - S.min_mph) / max(1.0, D.sever_mph - S.min_mph)) ^ S.pow
    frac = min(S.most, frac) * (S.mult[id] or 1.0)
    local fresh = not e.hit_t or now - e.hit_t > S.window
    if fresh then
        e.hit_t, e.hit_frac = now, frac
    else
        local more = frac - (e.hit_frac or 0.0)
        if more <= 0.0 then return nil end
        e.hit_frac = frac
        frac = more
    end
    local before, tarkov = M.part_left(id)
    -- (its health: TARKOV DAMAGE's HP - its share of his MAX HP, the figure's numbers - or its own wear)
    local G, Mn = _G.ARGORE, _G.ARMENU
    if tarkov and G and G.take_hp and G.LIMB_HP and G.LIMB_HP.share[id] and Mn and Mn.hp_max then
        pcall(G.take_hp, frac * G.LIMB_HP.share[id] * Mn.hp_max(), id)
    else
        e.wear = max(0.0, (e.wear or 1.0) - frac)
    end
    local left = M.part_left(id)
    if standing then
        -- (NON-RAGDOLL DAMAGE: his legs worn down landing by landing - put out under `out_at`, broken under `broken_at`)
        local want = (left <= S.broken_at) and 2 or ((left <= S.out_at) and 1 or 0)
        if id == "chest" then want = min(want, 2) end
        if id == "head" and want == 1 then want = 0 end
        if want > e.state and set_state(id, want) then
            log("non-ragdoll damage: his %s %s - %.0f%% health left after %.0f mph", id, M.STATES[want], left * 100.0, mph)
        end
        return nil
    end
    -- (injuries stack - "you can have a broken leg and land on it again and it will still just be broken because you landed
    -- under 50mph. so to combat this make a system where the damage scales", 2026-11-11: a new hit on a part already hurt
    -- adds its own step to what it has - a hit fit to put a part out (over dislocate_mph) makes a put-out one broken and a
    -- broken one come off, a hit fit to break (over break_mph) takes a put-out one off; at most a step a second
    -- (`stack_gap`: one tumble's knocks count once). A whole part as ever by the hit alone, below. His chest no further than
    -- broken; his head only once broken (put out, it is his neck - death), and then off)
    if not fresh or now - (e.worse_t or -99.0) < S.stack_gap then return nil end
    local cur = e.state
    if cur == 0 then return nil end
    local h = (mph > D.sever_mph and 3) or ((mph > D.break_mph) and 2 or ((mph > D.dislocate_mph) and 1 or 0))
    if h == 0 then return nil end
    if id == "head" and cur < 2 then return nil end
    local new = min(3, cur + h)
    if id == "chest" then new = min(new, 2) end
    if new == 3 and M.no_sever() then new = 2 end
    if new <= cur then return nil end
    if new == 3 then
        if not r then return nil end
        local regs = sever(pawn, r, id)
        if regs then
            r.quiet[id] = r.t + 0.2
            crack(r, pawn.Mesh, id)
            take_hp(3, id)
            log("scaling damage: his %s, already %s, came off at %.0f mph - injuries stack", id, M.STATES[cur], mph)
            return "severed"
        end
        return nil
    end
    if set_state(id, new) then
        if r then crack(r, pawn.Mesh, (id == "head") and "head" or id) end
        log("scaling damage: his %s, already %s, now %s at %.0f mph - injuries stack", id, M.STATES[cur], M.STATES[new], mph)
    end
    return "worse"
end
-- TARKOV DAMAGE's 0 HP rules ("now can you also improve tarkov damage as well", "0 HP rules", 2026-11-11): a part drained to
-- none - by a hit, by its bleeding, by hits passed on from other parts - is broken (red) at once, so its next hit takes it
-- off (M.scale_hit). Looked at every `every` s, on his feet or down. (What a part at 0 can't take goes on to the rest of him
-- at 70% - gore's limb_lose.) No HP cost of its own: it has none to give
M.ZERO = { every = 0.25, t = 0.0 }
function M.zero_tick(dt)
    local Z = M.ZERO
    Z.t = Z.t - dt
    if Z.t > 0.0 then return end
    Z.t = Z.every
    local G = _G.ARGORE
    if not (G and G.limb_hp) then return end
    local ok, L = pcall(G.limb_hp)
    if not (ok and L) then return end
    for id, e in pairs(parts) do
        local l = L[id]
        if l and l[1] <= 0.001 and e.state < 2 then
            e.state, e.up, e.worse_t = 2, 0.0, os.clock()
            limp_update()
            if M.on_injury then pcall(M.on_injury, id, 2) end
            log("tarkov damage: his %s has no HP left - broken", id)
        end
    end
end
-- GRAVITY, ZERO GRAVITY and MOON GRAVITY (the RAGDOLL tab, "add a 0 gravity option", "and a moon gravity option", "can you
-- actually make a gravity slider?", 2026-11-11): the world's own gravity - the slider's share of it, 0 to 3; none, a sixth -
-- so all of it goes by it: him on his feet (STORROR's jumps and falls), his
-- ragdoll, his torn-off parts, loose things, and the blood's drops (gore.lua, by `GRAV.g`). (Done first by his movement's
-- GravityScale - which STORROR puts back every frame, so his jumps went as high as ever - and by his ragdoll's own gravity
-- switch, read wrong: "zero gravity and moon gravity not working". Zero on his feet as well - "should be zero gravity in
-- non ragdoll mode as well", 2026-11-11.) The world's settings as they were kept in `_G.AR_GRAV_WAS`, by its address -
-- over a reload of this file too - and put back once both are off. `g`: the world's gravity now (cm/s/s, down), `base` as
-- it was. `trace` on: each time in the air on his feet measured into `last`, for the dev channel.
M.GRAV = { moon = 1.0 / 6.0, g = 1500.0, base = 1500.0, k = 1.0, air = nil, last = nil, trace = false }
function M.grav_share()
    local Mn = _G.ARMENU
    if Mn and Mn.gravity_share then return Mn.gravity_share() end
    return 1.0
end
-- (for gore.lua: the share of the world's gravity now that his parts and blood get - all of it, the world's being the one
-- changed)
function M.grav_k(ragdoll) return 1.0 end
function M.GRAV.ws_of(pawn)
    local w = pawn:GetWorld()
    if not (w and w:IsValid()) then return nil end
    local lvl = w.PersistentLevel
    if not (lvl and lvl:IsValid()) then return nil end
    local ws = lvl.WorldSettings
    if ws and ws:IsValid() then return ws end
    return nil
end
function M.grav_tick(pawn)
    local G = M.GRAV
    local ws = M.GRAV.ws_of(pawn)
    if not ws then return end
    _G.AR_GRAV_WAS = _G.AR_GRAV_WAS or {}
    local key = ws:GetAddress()
    local was = _G.AR_GRAV_WAS[key]
    -- (a world not seen yet - or one at the same address with its gravity its own again: a new map)
    if was and was.applied and not ws.bGlobalGravitySet then was = nil end
    if not was then
        was = { gset = ws.bGlobalGravitySet, gz = ws.GlobalGravityZ, wset = ws.bWorldGravitySet, wz = ws.WorldGravityZ }
        local z = was.wset and was.wz or (was.gset and was.gz) or was.wz
        if not (z < -1.0) then z = -1500.0 end
        was.z = z
        _G.AR_GRAV_WAS[key] = was
    end
    -- (the first way's leftover: his movement's GravityScale at a sixth - put back)
    if not G.cleaned then
        G.cleaned = true
        pcall(function() local cm = pawn.CharacterMovement; if math.abs(cm.GravityScale - M.GRAV.moon) < 1e-3 then cm.GravityScale = 1.0 end end)
    end
    G.base = -was.z
    local k = M.grav_share()
    if math.abs(k - 1.0) > 0.001 then
        local want = was.z * k
        if math.abs(ws.WorldGravityZ - want) > 0.01 or not ws.bGlobalGravitySet or math.abs(ws.GlobalGravityZ - want) > 0.01 then
            ws.bGlobalGravitySet = true
            ws.GlobalGravityZ = want
            ws.WorldGravityZ = want
            if G.k ~= k then log("gravity: %.0f%% - %.0f cm/s/s, from %.0f", k * 100.0, -want, -was.z) end
        end
        was.applied = true
        G.g = -want
    else
        if was.applied then
            ws.bGlobalGravitySet = was.gset
            ws.GlobalGravityZ = was.gz
            ws.WorldGravityZ = was.z
            was.applied = false
            log("gravity: back to normal - %.0f cm/s/s", -was.z)
        end
        G.g = -was.z
    end
    G.k = k
end
-- (dev: one time in the air on his feet, frame by frame - how high, how fast, STORROR's animation moving him or not)
function M.grav_air(pawn, dt)
    local G = M.GRAV
    local cm = pawn.CharacterMovement
    if cm.MovementMode == 3 then
        local z = pawn:K2_GetActorLocation().Z
        local vz = cm.Velocity.Z
        local A = G.air
        if not A then A = { t = 0.0, z0 = z, top = z, vz0 = vz, n = 0, rm = 0, s = {} }; G.air = A end
        A.t = A.t + dt
        A.n = A.n + 1
        if z > A.top then A.top = z end
        A.z, A.vz = z, vz
        local okr, rm = pcall(function() return pawn:IsPlayingRootMotion() end)
        if okr and rm then A.rm = A.rm + 1 end
        if #A.s < 90 then A.s[#A.s + 1] = string.format("%.2f %.0f %.0f %s %.2f", A.t, z - A.z0, vz, (okr and rm) and "rm" or "-", cm.GravityScale) end
    elseif G.air then
        G.last, G.air = G.air, nil
    end
end
-- a landing on his feet from a height: his legs' share of it
function M.scale_fall(pawn, mph, drop)
    for id, k in pairs(M.SCALE.fall_k) do
        local okh, res = pcall(M.scale_hit, pawn, nil, id, mph * k, true)
        if not okh and not M.scale_err then M.scale_err = true; log("fall damage failed (%s)", tostring(res)) end
    end
end
-- one blow to a part, `mph` its speed: the part's state from it
local function blow(pawn, r, id, mph)
    local D = M.DAMAGE
    local e = parts[id]
    r.L0 = nil                                   -- (he met something: his spin is what it is now)
    if M.brain_blow then pcall(M.brain_blow, r, id, mph) end
    if M.stun then M.stun(r, mph, "a blow to his " .. id) end
    -- (EXPLODE, on the RAGDOLL tab: any hurt at all blows him apart - "The player just explodes on any injury", 2026-11-11)
    if mph > D.dislocate_mph and M.explode_on() then
        if (r.body_fast or 0.0) < 1.0 then r.body_fast = mph * MPH end
        explode(pawn, r, mph)
        return
    end
    -- (his whole body hitting at over explode_mph - whatever part of him met the ground first: a fall feet first at 114
    -- mph took his legs and an arm and left the rest, "just fell from very high while ragdolled and didnt explode?",
    -- 2026-11-10)
    if mph > D.explode_mph and (r.body_fast or 0.0) > D.explode_mph * MPH * 0.85 and not M.no_explode() then explode(pawn, r, mph); return end
    -- (SCALING DAMAGE: the hit wears that part's health down by its speed; its state follows its health; red with none left,
    -- the next hit takes it off - M.scale_hit)
    if M.scaling_on() then
        local okh, res = pcall(M.scale_hit, pawn, r, id, mph, false)
        if not okh and not M.scale_err then M.scale_err = true; log("scaling damage failed (%s)", tostring(res)) end
        if okh and (res == "severed" or res == "worse") then e.d = max(e.d, mph); return end
    end
    e.d = max(e.d, mph)
    if id == "chest" then
        if mph > D.explode_mph and not M.no_explode() then explode(pawn, r, mph); return end
        if mph > D.break_mph then
            if set_state(id, 2) then crack(r, pawn.Mesh, "spine_03"); log("broken: chest (%.0f mph)", mph) end
        elseif mph > D.dislocate_mph then
            if set_state(id, 1) then log("dislocated: chest (%.0f mph)", mph) end
        end
        return
    end
    if mph > D.sever_mph and D.gore and (r.body_fast or 0.0) < D.sever_mph * D.sever_body * MPH then
        log("no cut: his %s at %.0f mph, his body at %.0f mph - broken instead", id, mph, (r.body_fast or 0.0) / MPH)
        mph = min(mph, D.sever_mph)
    end
    if mph > D.sever_mph and D.gore then
        local regs = sever(pawn, r, id)
        if regs then
            r.quiet[id] = r.t + 0.2
            crack(r, pawn.Mesh, id)
            take_hp(3, id)
            log("severed: %s (%.0f mph)", table.concat(regs, ", "), mph)
            return
        end
    end
    if mph > D.break_mph then
        if set_state(id, 2) then
            crack(r, pawn.Mesh, (id == "head") and "head" or id)
            log("broken: %s (%.0f mph)", id, mph)
            -- (a long bone's break, now and then open: the bone through the skin, or the wound alone, bleeding)
            local F, G = M.FRACTURE, _G.ARGORE
            local kind = id:match("^(%a+)_")
            if G and G.fracture and M.DAMAGE.gore and M.bones_out() and F.parts[kind] and random() < F.chance then   -- (BONES STICKING OUT off: no open break at all - its wound's ball showed still, "still showing the little bleed ball", 2026-11-11)
                local e = BY_BONE[id]
                if e and e.tip then pcall(G.fracture, pawn, id, id, e.tip, random() < F.bone_p) end
            end
        end
        return
    end
    if id == "head" and mph <= D.head_dead_mph then return end
    if e.state < 1 then
        local j = REGION_JOINTS[id][1]
        if BY_BONE[j] and lim and lim.list[j] and not dis[j] then
            pcall(dislocate, pawn, r, j, 0.0, 0.0, string.format("%.0f mph", mph))
        end
        set_state(id, 1)
    end
end
-- (something solid where the part was going: a hit, not a limb whipped about by the rest of him. Looked for from its
-- joint, its middle and its far end: from the joint alone a knee or an elbow hitting the ground was missed - "sometimes
-- taking no damage", 2026-11-10)
-- (each part's own points - inside it, never at the joints it shares: from the joints a knee's hit was the thigh's too,
-- a hand's the forearm's, and a thigh 20 cm off the ground "hit" it as the foot landed - "wrong part gets hurt",
-- 2026-11-10 - and how far its surface is from them, cm)
local CONTACT_R = { head = 10.5, chest = 14.0, upperarm = 5.5, lowerarm = 4.5, hand = 3.5, thigh = 8.5, calf = 6.5, foot = 5.0 }
-- (cm past the surface a hit is still taken: 2.5, touching - at 6, his head stopped a few cm off the ground by his neck as
-- his shoulders landed was "hit": "im getting head damage even though its not hitting the ground", 2026-11-10)
M.CONTACT_MARGIN = 2.5
local function part_points(mesh, id)
    if id == "head" then
        -- (the middle of his skull: the head bone sits at its base, on the neck)
        local h, n = pos(mesh, "head"), pos(mesh, "neck_01")
        local u = vnorm(vsub(h, n))
        return { vadd(h, vmul(u, 9.0)) }
    end
    if id == "chest" then return { pos(mesh, "pelvis"), pos(mesh, "spine_03"), pos(mesh, "spine_05") } end
    local e = BY_BONE[id]
    local a = pos(mesh, id)
    local okb, b = false, nil
    if e and e.tip then okb, b = pcall(pos, mesh, e.tip) end
    if not (okb and b) then return { a } end
    local kind = id:match("^(%a+)")
    local ks = (kind == "hand" or kind == "foot") and { 0.35, 0.9 } or { 0.25, 0.5, 0.8 }
    local out = {}
    for i, k in ipairs(ks) do out[i] = vadd(a, vmul(vsub(b, a), k)) end
    return out
end
local function touching(pawn, mesh, id, pv)
    local sp = vlen(pv)
    if sp < 50.0 then return nil end
    local d = vmul(pv, 1.0 / sp)
    -- (and as far as it went in the frame: fast, a part was past the surface or bounced off it by more than its girth)
    local reach = (CONTACT_R[id:match("^(%a+)") or id] or 6.0) + M.CONTACT_MARGIN + min(200.0, sp * (M.last_dt or 0.016))
    for _, x in ipairs(part_points(mesh, id)) do
        local n = ray_hit(pawn, vsub(x, vmul(d, 3.0)), vadd(x, vmul(d, reach)))
        if n then return n end
    end
    return nil
end
local function damage_tick(pawn, r, dt)
    local D = M.DAMAGE
    local mesh = pawn.Mesh
    M.last_dt = dt
    r.prev_v = r.prev_v or {}
    r.quiet = r.quiet or {}
    -- (his body moved further than its speed takes it - STORROR putting him somewhere, his respawn: no blows then, nor
    -- for a moment after - every part's speed jumped 8000-14000 cm/s in one frame and all of him came off, 2026-11-10)
    local p = pos(mesh, "pelvis")
    local pp, pv = r.prev_pel, r.prev_v["pelvis"]
    r.prev_pel = p
    -- (further than his speed could take him: a sudden stop - a landing at 115 mph, 1.5 m short of where his speed went -
    -- is no jump; taken for one, it healed an explosion the moment it happened, "sometimes taking no damage", 2026-11-10)
    if pp and pv then
        if vlen(vsub(p, pp)) > vlen(pv) * dt * 1.5 + D.jump then
            r.quiet_all = r.t + D.jump_quiet
            r.prev_v, r.hist = {}, {}
            log("his body jumped %.0f cm in a frame - no blows for a moment", vlen(vsub(p, pp)))
            heal_all(pawn, "the game moved him")
            return
        end
    end
    if r.t < (r.quiet_all or 0.0) then
        for _, bodies in pairs(REGIONS) do for _, b in ipairs(bodies) do r.prev_v[b] = nil end end
        r.hist = {}
        pcall(function() local u = mesh:GetPhysicsLinearVelocity(FN["pelvis"]); r.prev_v["pelvis"] = v3(u.X, u.Y, u.Z) end)
        return
    end
    -- (settled: his own movements hurt him no more)
    local hv = r.prev_v["pelvis"]
    local hs = hv and vlen(hv) or 999.0
    -- (his body's speed a moment ago - its fastest, fading 5000 cm/s a second: what a hit is measured against for the
    -- explosion)
    if hv then r.body_fast = max(hs, (r.body_fast or 0.0) - 5000.0 * dt) end
    if r.settled then
        if hs > D.move_v then r.settled = false; r.still = 0.0 end
    else
        r.still = (hs < D.still_v) and ((r.still or 0.0) + dt) or 0.0
        if r.still >= D.still_t then r.settled = true end
    end
    for id, bodies in pairs(REGIONS) do
        local e = parts[id]
        for _, b in ipairs(bodies) do
            local ok, u = pcall(function() return mesh:GetPhysicsLinearVelocity(FN[b]) end)
            if ok and u then
                local v = v3(u.X, u.Y, u.Z)
                r.prev_v[b] = v
                -- (its speed over the last `window` s: the blow is the change from the oldest of them, gravity's taken off)
                r.hist = r.hist or {}
                local h = r.hist[b]
                if not h then h = {}; r.hist[b] = h end
                h[#h + 1] = { t = r.t, v = v }
                while #h > 2 and r.t - h[2].t >= D.window do table.remove(h, 1) end
                local old = h[1]
                local pv = (old ~= h[#h]) and old.v or nil
                if pv and e.state < 3 and not r.settled and r.t > D.skip and r.t > (r.quiet[id] or 0.0) and r.t > (r.quiet_all or 0.0) then
                    local dv = vsub(v, pv)
                    dv.z = dv.z + (r.g or 1500.0) * (r.t - old.t)
                    local imp = vlen(dv)
                    -- (no body is hit that hard - the physics, not a blow - unless all of him was going that fast: at NEWTONS LAW's
                    -- speeds the hardest landings were thrown away, "at very high speed damage doesnt register", 2026-11-11)
                    if imp > D.max_blow and (r.body_fast or 0.0) < imp * 0.5 then imp = 0.0 end
                    local n = (imp / MPH > D.dislocate_mph) and touching(pawn, mesh, id, pv) or nil
                    local mph = 0.0
                    if n then
                        -- (its speed into the surface before, less what it still has into it: a bounce loses it all)
                        local vin, vout = -vdot(pv, n), -vdot(v, n)
                        mph = (vin - max(0.0, vout)) / MPH
                    end
                    if n and mph > D.dislocate_mph then
                        r.hits = (r.hits or 0) + 1
                        if mph > (r.top_mph or 0.0) then r.top_mph, r.top_id = mph, id end
                        if M.CFG.thuds then hit_sound(r, mesh, id, b, mph) end
                        blow(pawn, r, id, mph)
                        r.quiet[id] = max(r.quiet[id] or 0.0, r.t + D.window + 0.02)
                        for _, bb in ipairs(bodies) do r.hist[bb] = nil end
                    end
                end
            end
        end
    end
end

-- The hit that put him down: STORROR starts its ragdoll as he lands or runs into something, and the blows of its first
-- frames are not read (`skip`) - a landing at 115 mph took only his head ("fell 6.5 s", 2026-11-10). So as he goes down
-- with the ground or a wall right where he was going, that is the hit, at the speed he was going: over `explode_mph` his
-- body explodes; otherwise the parts of him leading into it (within `lead` cm of the foremost) take it.
M.BAIL_HIT = { reach = 120.0, ahead = 0.06, lead = 6.0 }
local BAIL_BODY = { head = "head", chest = "spine_03" }
for _, sd in ipairs({ "l", "r" }) do
    for _, n in ipairs({ "upperarm", "lowerarm", "hand", "thigh", "calf", "foot" }) do BAIL_BODY[n .. "_" .. sd] = n .. "_" .. sd end
end
local function bail_hit(pawn, r)
    local v = r.impact_v
    if not v or r.knock then return end
    local sp = vlen(v)
    local mph = sp / MPH
    local D = M.DAMAGE
    if mph <= D.dislocate_mph then return end
    local mesh = pawn.Mesh
    local d = vmul(v, 1.0 / sp)
    local p = pos(mesh, "pelvis")
    local n = ray_hit(pawn, p, vadd(p, vmul(d, M.BAIL_HIT.reach + sp * M.BAIL_HIT.ahead)))
    if not n then return end
    -- (the speed into it, not along it)
    mph = max(0.0, -vdot(v, n)) / MPH
    if mph <= D.dislocate_mph then return end
    log("the bail was a hit at %.0f mph", mph)
    r.top_mph, r.top_id = mph, "the bail"
    -- (his body's own speed into it: a cut by it is no spike)
    r.body_fast = max(r.body_fast or 0.0, sp)
    if mph > D.explode_mph and not M.no_explode() then explode(pawn, r, mph); return end
    -- (each part: how far its own surface is from what he hit, along the way he was going; the nearest, and those within
    -- `lead` cm of it, take the hit)
    local reach = M.BAIL_HIT.reach + sp * M.BAIL_HIT.ahead
    local gap, best = {}, 1e9
    for id in pairs(BAIL_BODY) do
        -- (a part already cut off takes nothing: it isn't there - a 39 mph landing went to his missing foot and hurt nothing,
        -- "just landed at 30 mph nothing severed?", 2026-11-11)
        local okp, pts = false, nil
        if not (parts[id] and parts[id].state >= 3) then okp, pts = pcall(part_points, mesh, id) end
        if okp then
            local rad = CONTACT_R[id:match("^(%a+)") or id] or 6.0
            for _, x in ipairs(pts) do
                local nn, dist = ray_hit(pawn, x, vadd(x, vmul(d, reach)))
                if nn and dist then
                    local g = dist - rad
                    if not gap[id] or g < gap[id] then gap[id] = g end
                end
            end
            if gap[id] and gap[id] < best then best = gap[id] end
        end
    end
    for id, g in pairs(gap) do
        if g <= best + M.BAIL_HIT.lead then blow(pawn, r, id, mph) end
    end
end

M.MOMENTUM = { on = true, from = 150.0, keep = 1.0, frames = 2 }
local function down_start(pawn)
    local r = { t = 0.0, w = 0.0, air = 1.0, max_over = {}, max_w = 0.0, ms = 0.0, frames = 0, g = 1500.0, quiet = {}, ovr = {} }
    r.brain = brain_new()          -- (his mind from the first moment: the bail's own hit reaches it)
    -- (for the first moment's measure: what was on as he went down)
    r.j_stand = st.stand ~= nil
    r.j_dis = 0
    for _ in pairs(dis) do r.j_dis = r.j_dis + 1 end
    if st.stand then stand_stop(pawn, "down again", true) end
    limbs_set(pawn, nil)
    jump_end(pawn, nil)
    st.rag = r
    local mesh = pawn.Mesh
    -- (the world's gravity - STORROR's is 1500 cm/s/s, not the Earth's 980)
    r.g = M.GRAV.g
    local okd, ld = pcall(body_damping, mesh)
    r.lin_damp = okd and ld or 0.0
    r.ang_damp = M.COM.ang_damp or 0.0
    M.fall_end(pawn, "bailed")
    -- (his body falls: STORROR leaves gravity off in some states, and a ragdoll begun in one hung in the air)
    pcall(function() if not mesh:IsGravityEnabled() then mesh:SetEnableGravity(true); log("his body had no gravity - put back on") end end)
    if M.CFG.soft_limits or next(dis) then lim_apply(mesh) end
    local okc, e = pcall(ctl_start, pawn, r)
    if not okc then log("controls failed (%s)", tostring(e)) end
    -- (a knock's speed only for the fall it was for: one left over - the trip's StartRagdoll not taken up by STORROR - was
    -- given to his next fall, his own R3 standing still, every body of his thrown at 2000 cm/s some old way - "its like a
    -- jolt the second the player holds r3", "ripping the player in a random direction", 2026-11-10)
    if st.knock_v and os.clock() - (st.knock_t or -99.0) > M.KNOCK_FRESH then
        log("an old knock (%.0f cm/s, %.1f s ago) not given to this fall", vlen(st.knock_v), os.clock() - (st.knock_t or 0.0))
        st.knock_v, st.push = nil, nil
    end
    r.impact_v = st.knock_v or st.up_v
    -- (his momentum kept: every body of him given the speed he had on his feet, for the first frames down - as a trip's knock
    -- already was; STORROR's own bails - R3, a landing - began the ragdoll from his animation's pose, near still: "still no
    -- player ragdoll momentum", 2026-11-11)
    if M.MOMENTUM.on and not st.push and r.impact_v and vlen(r.impact_v) > M.MOMENTUM.from then
        st.push = { v = vmul(r.impact_v, M.MOMENTUM.keep), n = M.MOMENTUM.frames, t = os.clock() }
    end
    r.spin_w = st.spin
    r.carry_anim = M.CARRY.take()
    if M.GRABROLL.rolled() and not st.bled_out then st.negate = { t = os.clock(), tried = 0 }; log("rolled as he landed - the bail undone") end
    pcall(M.SLIDESND.stop, pawn, "down")
    -- (a trip too - a wall slide, a run into a wall, a fall: his motion carried, his spin with it, the knock's speed made
    -- up after if his animation carried less - a trip's even push wiped out any turn he was in, "momentum is gone",
    -- 2026-11-11)
    r.anim_W = M.ANIMSPIN.W
    M.ANIMSPIN.prev, M.ANIMSPIN.W = nil, nil
    st.spin, st.spin_q = nil, nil
    r.knock = st.knock_v ~= nil
    st.knock_v = nil
    log("down (%s), %d controls, %s", montage(pawn), r.ctl and (function() local n = 0; for _ in pairs(r.ctl) do n = n + 1 end; return n end)() or 0,
        st.up_v and string.format("going %.0f cm/s", vlen(st.up_v)) or "standing")
end
local function down_end(pawn)
    local r = st.rag
    st.rag = nil
    if r then pcall(M.LEDGER.flush, r); pcall(M.KEEPSPIN.said, r) end
    pcall(M.BLOODSPEED.tick, pawn, nil)
    for _, jn in ipairs({ "upperarm_l", "upperarm_r" }) do if reach_wide[jn] and reach_wide[jn].air then reach_wide[jn] = nil end end
    -- (the hurt written down for the log first: he is healed as he gets up)
    local hurtl = {}
    for id, e in pairs(parts) do if e.state > 0 then hurtl[#hurtl + 1] = string.format("%s %s (%.0f mph)", id, M.STATES[e.state], e.d) end end
    table.sort(hurtl)
    if keep_on() then
        log("got up with his injuries (keep injuries)")
    else
        heal_all(pawn, "he got up")
    end
    if r then ctl_end(r) end
    phys_drop("up")
    if r then
        local worst, wb = 0.0, nil
        for b, o in pairs(r.max_over) do if o > worst then worst, wb = o, b end end
        M.last = { t = r.t, max_over = r.max_over, max_w = r.max_w, ms = r.frames > 0 and r.ms / r.frames or 0.0 }
        log("up after %.1f s (most past a range: %s %.0f deg; protect at most %.2f; %.2f ms a frame; %d blows, the hardest %.0f mph to %s; hurt: %s; deepest into himself: %s %.1f cm)", r.t, tostring(wb), worst,
            r.max_w, M.last.ms, r.hits or 0, r.top_mph or 0.0, tostring(r.top_id), table.concat(hurtl, ", "), tostring(r.sc_pair), r.sc_pen or 0.0)
    end
end
-- (the first `t` s down: a body of his more than `v` cm/s faster than he went down, or spinning past `w` deg/s, held to that
-- - a flick of the physics, not his fall)
-- (`t` 0 - off, 2026-11-11: it cut a flip's limbs, swinging fast, and half his turn went with them - "THE FUCKING FALLS
-- ARE STILL WRONG". Its causes - an old knock, his hanging limbs snapping back - are mended at the root)
M.JOLT = { t = 0.0, v = 1100.0, w = 2600.0 }

-- More falling animations ("can you also make more falling animations", 2026-11-11): the body's pull toward one of
-- STORROR's own falls in the air, picked at random each time - not its one flail every time - each of them or its mirror;
-- played again if it ends while he is still in the air.
M.FALL_ANIMS = {}
for _, p in ipairs({
    "RagdollReaction/Flail/MontageRagdollReactionFlail_88_Drew_131024_Falling-004_1319-2578",
    "Falling/InAir/MontageFallingInAir_40_Drew_131024_Falling-003_frames_829-1555",
    "Falling/InAir/MontageFallingInAir_68_Drew_131024_Falling-005_frames_338-1717",
    "Falling/InAir/MontageFallingInAir_85_Drew_131024_Falling-004_1319-2578",
    "Falling/InAirFront/MontageFallingInAirFront_3098_BenjKT01c",
    "Falling/InAirFront/MontageFallingInAirFront_3103_BenjKT01c",
    "Falling/Layout/MontageFallingLayout_39_Drew_131024_Falling-007_frames_7093-7822",
    "Falling/SideTuck/MontageFallingSideTuck_31_Drew_131024_Falling-006_frames_7621-8331",
    "Falling/OneFootGrab/MontageFallingOneFootGrab_37_Drew_131024_Falling-009_frames_2131-2793",
    "Falling/Dive/MontageFallingDive_0_Dive_EDIT_01_001DiveFall_Short" }) do
    for _, m in ipairs({ "", "_Mirrored" }) do
        local full = "/SPP/SPPCharacter/Animation/" .. p .. m
        M.FALL_ANIMS[#M.FALL_ANIMS + 1] = full .. "." .. full:match("([^/]+)$")
    end
end
local fall_cache = {}
local function fall_anim_load(path)
    local o = fall_cache[path]
    if o and pcall(function() return o:IsValid() end) and o:IsValid() then return o end
    o = StaticFindObject(path)
    if not (o and o:IsValid()) then pcall(function() o = LoadAsset(path) end) end
    if o and o:IsValid() then fall_cache[path] = o; return o end
    return nil
end
-- Each fall a style of its own, at random ("make them trigger randomly flailing covering face for impact diving",
-- 2026-11-11): FLAIL - thrashing, STORROR's flails pulled at harder and played faster, his arms windmilling; COVER -
-- forearms up over his face, knees up, from the start of the fall; DIVE - arms out over his head, body long, turned
-- head-first the way he is going, covering up only as the ground comes. `w`: how often each.
-- (`styles` false: no fall styles, no falling animations of the mod's - STORROR's own flail, as before them; only his spin
-- carried on - "ALL I WANTED WAS MOMENTUM ON SPINS. remove all the different falls", 2026-11-11)
-- (`styles` back, 2026-11-11 - "lets add new falling animations like before": each fall a style of its own, shaped by his
-- muscles alone - no pull from outside, no turn of all of him - so his spin is his own. `flail_hz` his flail's swings)
-- ("nbp" out - "also remove the original pose", 2026-11-11)
M.RANDOM_POSES = { "protect", "cover", "ball", "dive", "curl", "reach", "draw", "kick", "starfish", "pencil", "superman", "seated", "fetal",
                   "brace", "runner", "scissor", "skydiver", "pinwheel", "headhold", "pike", "arch", "kneel", "hug" }
-- (`random_every`, `restyle` quicker, and `swing`: in a held pose each arm and leg now and then kicked or swung out and back
-- - "make them kick the legs and swing arms more", "make the randomizer swap them out more often", 2026-11-11)
-- (`styles` back on, 2026-11-11 - "now lets bring our poses and randomizer back and remove the original pose")
M.AIR = { styles = true, turns = false, flail_hz = 16.0, restyle = { 0.8, 1.6 }, random_every = { 0.15, 0.6 },
          swing = { gap = { 0.25, 0.8 }, hold = { 0.2, 0.45 } }, lev_g = 0.33, lev_t = 0.4, start = 0.12, flail_k = 1.8, flail_rate = 1.4, windmill = 700.0, windmill_k = 0.25,
          dive_turn = 3.0, dive_most = 220.0, dive_k = 0.12, dive_from = 400.0 }
-- (a CANNONBALL and a FACE COVER too, 2026-11-11: each of the four as often; `hz` the pull to its pose - the shapes held
-- harder than the head's protecting, to be seen in a short fall)
M.AIR_MODES = {
    -- (RANDOM: each limb its own pose at random, from all of his, changed at random - "the falling animation should be
    -- completely random tbh", 2026-11-11; the style itself picked afresh every `restyle` s of a long fall)
    { name = "random", w = 0.35, pose = nil, hz = 16.0, anims = {} },
    { name = "runner", w = 0.035, pose = "runner", hz = 16.0, anims = {} },
    { name = "scissor", w = 0.035, pose = "scissor", hz = 16.0, anims = {} },
    { name = "skydiver", w = 0.035, pose = "skydiver", hz = 16.0, anims = {} },
    { name = "pinwheel", w = 0.035, pose = "pinwheel", hz = 16.0, anims = {} },
    { name = "head hold", w = 0.035, pose = "headhold", hz = 16.0, anims = {} },
    { name = "pike", w = 0.035, pose = "pike", hz = 16.0, anims = {} },
    { name = "arch", w = 0.035, pose = "arch", hz = 16.0, anims = {} },
    { name = "kneel", w = 0.035, pose = "kneel", hz = 16.0, anims = {} },
    { name = "hug", w = 0.035, pose = "hug", hz = 16.0, anims = {} },
    { name = "starfish", w = 0.035, pose = "starfish", hz = 16.0, anims = {} },
    { name = "pencil", w = 0.035, pose = "pencil", hz = 16.0, anims = {} },
    { name = "superman", w = 0.035, pose = "superman", hz = 16.0, anims = {} },
    { name = "seated", w = 0.035, pose = "seated", hz = 16.0, anims = {} },
    { name = "fetal", w = 0.035, pose = "fetal", hz = 15.0, anims = {} },
    { name = "brace", w = 0.035, pose = "brace", hz = 16.0, anims = {} },
    { name = "flail", w = 0.035, pose = nil, hz = 16.0, anims = { "MontageRagdollReactionFlail", "MontageFallingInAir_", "MontageFallingInAirFront", "MontageFallingOneFootGrab" } },
    { name = "face cover", w = 0.035, pose = "cover", hz = 16.0, anims = { "MontageFallingInAir_85", "MontageFallingInAirFront" } },
    { name = "cannonball", w = 0.035, pose = "ball", hz = 15.0, anims = { "MontageFallingSideTuck" } },
    { name = "dive", w = 0.035, pose = "dive", hz = 16.0, anims = { "MontageFallingDive", "MontageFallingLayout" } },
}
function M.style_pose(m)
    if m.pose then return m.pose end
    local L = M.RANDOM_POSES
    return L[math.random(1, #L)]
end
local function air_pick()
    local total = 0.0
    for _, m in ipairs(M.AIR_MODES) do total = total + m.w end
    local x = random() * total
    for _, m in ipairs(M.AIR_MODES) do x = x - m.w; if x <= 0.0 then return m end end
    return M.AIR_MODES[1]
end
local function fall_anim_play(pawn, r)
    local path = r.fall_path
    if not path then
        local pool = {}
        local mode = r.air_mode_t
        for _, a in ipairs(M.FALL_ANIMS) do
            for _, key in ipairs(mode and mode.anims or { "" }) do if a:find(key, 1, true) then pool[#pool + 1] = a; break end end
        end
        if #pool == 0 then pool = M.FALL_ANIMS end
        path = pool[math.random(1, #pool)]
        r.fall_path = path
    end
    local mt = fall_anim_load(path)
    if not mt then return false end
    local ok = pcall(function() pawn.Mesh:GetAnimInstance():Montage_Play(mt, 1.0, 0, 0.0, true) end)
    if ok and not r.fall_said then
        r.fall_said = true
        log("falling: %s, as %s", r.air_mode or "?", path:match("([^/%.]+)$") or path)
    end
    return ok
end

-- Spin ("give the player spinning momentum", 2026-11-11): his body's turning as he goes down kept - a flip, a spin, a
-- roll, measured from his hips while he is on his feet - and given to all of him as one turn, with a tumble on top by how
-- fast he was going (a forward roll the way he went); `carry` of his own turn, `tumble_k` deg/s for each cm/s across the
-- ground, `max` deg/s in all.
-- (the tumble: `tumble_p` of falls, any way round - forward, back, to a side - and as hard as `tumble_k`..: always a forward
-- roll, every fall looked like a dive, "almost everytime the player ragdoll it triggers dive", 2026-11-11)
-- (no tumble now - `tumble_p` 0: a turn made up at random was spin from nowhere, "hes getting momentum while in the air
-- completely randomly", 2026-11-11 - only the turn he really had, carried on)
-- (`on` false, 2026-11-11: his hips' turn on his feet is his run's sway as much as any spin of his - given to all of him as
-- a turn it was a spin from nowhere, and tipped him over backwards. The ragdoll begins with his body's own motion in it)
M.SPIN = { on = false, carry = 1.0, tumble_k = 0.3, tumble_max = 450.0, tumble_p = 0.0, tumble_min = 0.4, max = 900.0, smooth = 12.0,
           frame_max = 75.0 }
local function spin_track(pawn, dt)
    if dt <= 1e-4 then return end
    local okq, t = pcall(function() return pawn.Mesh:GetSocketTransform(FN["pelvis"], 0) end)
    if not (okq and t) then return end
    local q = { x = t.Rotation.X, y = t.Rotation.Y, z = t.Rotation.Z, w = t.Rotation.W }
    local p = st.spin_q
    st.spin_q = q
    if not p then return end
    local d = qmul(q, qinv(p))
    if d.w < 0.0 then d = { x = -d.x, y = -d.y, z = -d.z, w = -d.w } end
    local ang = 2.0 * acos(min(1.0, d.w))
    local sn = sqrt(max(0.0, 1.0 - d.w * d.w))
    -- (a jump of his whole body - a teleport, a reset - is no turn of his)
    if deg(ang) > M.SPIN.frame_max or sn < 1e-5 then st.spin = v3(0.0, 0.0, 0.0); return end
    local w = vmul(v3(d.x / sn, d.y / sn, d.z / sn), deg(ang) / dt)
    local k = min(1.0, M.SPIN.smooth * dt)
    local o = st.spin or w
    st.spin = vadd(o, vmul(vsub(w, o), k))
end
-- the turn given to all of him, once, as his bodies first move on their own
local function spin_give(pawn, r)
    local S = M.SPIN
    if not S.on then return end
    local mesh = pawn.Mesh
    local w = vmul(r.spin_w or v3(0.0, 0.0, 0.0), S.carry)
    local v = r.impact_v or v3(0.0, 0.0, 0.0)
    local hs = sqrt(v.x * v.x + v.y * v.y)
    if hs > 50.0 and random() < S.tumble_p then
        local f = vnorm(vcross(v3(0.0, 0.0, 1.0), v3(v.x, v.y, 0.0)))
        local a = rnd(0.0, 2.0 * math.pi)
        local axis = v3(f.x * math.cos(a) - f.y * math.sin(a), f.x * math.sin(a) + f.y * math.cos(a), 0.0)
        w = vadd(w, vmul(axis, min(S.tumble_max, hs * S.tumble_k) * rnd(S.tumble_min, 1.0)))
    end
    local l = vlen(w)
    if l < 20.0 then return end
    if l > S.max then w = vmul(w, S.max / l); l = S.max end
    -- (only what his body hasn't already got: the ragdoll begins with his animation's own turn in it - topped up, not doubled)
    do
        local okc, vc, c0, P = pcall(M.COM.of, mesh)
        if okc and vc then
            local okt, Wr = pcall(M.COM.turn, vc, c0, P)
            if okt and Wr then
                local have = vlen(Wr) * 180.0 / math.pi
                if have >= l * 0.8 then log("spin: his own turn kept as it is (%.0f deg/s, %.0f measured)", have, l); return end
                w = vmul(w, (l - have) / l)
                l = l - have
            end
        end
    end
    local wr = vmul(w, math.pi / 180.0)
    local c = pos(mesh, "pelvis")
    local n = 0
    for _, bn in ipairs({ "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05", "neck_01", "head", "clavicle_l",
                          "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l",
                          "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r" }) do
        pcall(function()
            local b = pos(mesh, bn)
            local lin = vcross(wr, vsub(b, c))
            mesh:SetPhysicsAngularVelocityInDegrees({ X = w.x, Y = w.y, Z = w.z }, true, FN[bn])
            mesh:SetPhysicsLinearVelocity({ X = lin.x, Y = lin.y, Z = lin.z }, true, FN[bn])
            n = n + 1
        end)
    end
    r.spin_extra = (l * math.pi / 180.0) * 130.0
    log("spin: %.0f deg/s given (his own %.0f, a tumble at %.0f cm/s across)", l, vlen(r.spin_w or v3(0, 0, 0)), hs)
end
-- (in the air: a flail's arms windmilling round his shoulders; a dive turned head-first the way he is going)
-- Friction where he touches the ground ("still no spin momentum", "players still getting dragged around on the ground",
-- 2026-11-11): STORROR's ragdoll hardly grips the ground - he slid on it, 4 to 9 m in a second - and braked all alike, he
-- stopped dead. Now each part of him on the ground - a short trace under it - is held back along the ground, the rest of
-- him not: held at his feet, his hips, a shoulder, the rest of him goes on over it - he tumbles, his speed and his spin
-- carried on into it, as a body thrown down does. `mu` of his weight in all, shared over the parts touching (`most` times
-- gravity on a part at most: one hand brushing the ground doesn't stop all of him).
M.FRICTION = { on = true, mu = 0.6, reach = 8.0, most = 4.0, mass = {},
    bodies = { { "pelvis", 13.0 }, { "spine_03", 13.0 }, { "spine_05", 12.0 }, { "head", 10.0 }, { "upperarm_l", 5.5 },
               { "upperarm_r", 5.5 }, { "lowerarm_l", 4.5 }, { "lowerarm_r", 4.5 }, { "hand_l", 3.5 }, { "hand_r", 3.5 },
               { "thigh_l", 8.5 }, { "thigh_r", 8.5 }, { "calf_l", 6.5 }, { "calf_r", 6.5 }, { "foot_l", 5.0 }, { "foot_r", 5.0 } } }
function M.FRICTION.tick(pawn, r, mesh, dt)
    local F = M.FRICTION
    if not F.on then return end
    -- (every other frame, its time taken whole: 16 traces under him cost 1.3 ms)
    r.fr_acc = (r.fr_acc or 0.0) + dt
    r.fr_flip = not r.fr_flip
    if r.fr_flip then return end
    dt, r.fr_acc = r.fr_acc, 0.0
    local addr = mesh:GetAddress()
    if F.mass.addr ~= addr then F.mass = { addr = addr } end
    local touch, msum, mall = {}, 0.0, 0.0
    for _, e in ipairs(F.bodies) do
        local bn = e[1]
        local m = F.mass[bn]
        if m == nil then
            local ok, v = pcall(function() return mesh:GetBoneMass(FN[bn], true) end)
            m = (ok and v and v > 0.05) and v or 0.0
            F.mass[bn] = m
        end
        if m > 0.0 then
            mall = mall + m
            local okp, p = pcall(pos, mesh, bn)
            if okp and p and ray(pawn, vadd(p, v3(0.0, 0.0, 2.0)), vadd(p, v3(0.0, 0.0, -(e[2] + F.reach)))) then
                touch[#touch + 1] = bn
                msum = msum + m
            end
        end
    end
    r.touching = #touch
    if msum <= 0.0 then return end
    local a = F.mu * (r.g or 1500.0) * min(F.most / F.mu, mall / msum)
    local dvmax = a * M.pdt(dt)
    for _, bn in ipairs(touch) do
        pcall(function()
            local v = mesh:GetPhysicsLinearVelocity(FN[bn])
            local sp = sqrt(v.X * v.X + v.Y * v.Y)
            if sp > 0.5 then
                local dv = min(sp, dvmax)
                mesh:SetPhysicsLinearVelocity({ X = -v.X / sp * dv, Y = -v.Y / sp * dv, Z = 0.0 }, true, FN[bn])
            end
        end)
    end
end
local function air_style_tick(pawn, r, vel, dt)
    -- (FLAIL, by his own muscles: each arm swung between up over his head and down by his side, each leg between kicked out
    -- and drawn up, each out of step with the rest, a new swing every 0.2-0.45 s)
    -- (a long fall's style picked afresh now and then)
    if M.AIR.styles and r.air_mode and not r.grounded and r.air > 0.5 and not (r.dead or r.lifeless) then
        r.restyle_t = r.restyle_t or (r.t + rnd(M.AIR.restyle[1], M.AIR.restyle[2]))
        if r.t >= r.restyle_t then
            r.restyle_t = r.t + rnd(M.AIR.restyle[1], M.AIR.restyle[2])
            local m = air_pick()
            if m.name ~= r.air_mode then
                if r.fl then for part in pairs(r.fl) do if r.ovr and r.ovr[part] == "flail" then r.ovr[part] = nil end end; r.fl = nil end
                r.air_mode, r.air_mode_t, r.air_pose_want = m.name, m, M.style_pose(m)
                r.blend_w = -1.0
                log("falling: now %s", m.name)
            end
        end
    end
    if (r.air_mode == "flail" or r.air_mode == "random") and not r.grounded and r.air > 0.5 and not (r.dead or r.lifeless)
        and not (r.stun_until and r.t < r.stun_until) and r.pc and poses and r.t > M.AIR.start then
        r.fl = r.fl or {}
        r.ovr = r.ovr or {}
        for _, part in ipairs({ "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r" }) do
            local f, c = r.fl[part], r.ctl and r.ctl[part]
            if c and not weak[part] and (not f or r.t >= f.next) and (r.ovr[part] == nil or r.ovr[part] == "flail") then
                local pick
                if r.air_mode == "random" then
                    local opts = {}
                    for _, nm in ipairs(M.RANDOM_POSES) do if poses.targets[nm] and poses.targets[nm][part] then opts[#opts + 1] = nm end end
                    pick = opts[math.random(1, max(1, #opts))]
                elseif part:find("^upperarm") then pick = (random() < 0.5) and "dive" or "brace"
                elseif part:find("^lowerarm") then pick = (random() < 0.5) and "dive" or "cover"
                else pick = (random() < 0.5) and "kick" or "draw" end
                local q = poses.targets[pick] and poses.targets[pick][part]
                if q then
                    r.ovr[part] = "flail"
                    if M.SMOOTH.on then
                        c.q_want, c.hz_want = q, M.AIR.flail_hz
                    else
                        pcall(function()
                            r.pc:SetControlTargetOrientation(c.name, q2rot(q), 0.0, true, false, true, false)
                            r.pc:SetControlAngularData(c.name, M.AIR.flail_hz, M.CFG.tension_damp, 0.0, 0.0, true, true, false)
                        end)
                    end
                end
                r.fl[part] = { next = r.t + ((r.air_mode == "random") and rnd(M.AIR.random_every[1], M.AIR.random_every[2]) or rnd(0.2, 0.45)) }
            end
        end
    elseif r.fl then
        for part in pairs(r.fl) do if r.ovr and r.ovr[part] == "flail" then r.ovr[part] = nil end end
        r.fl = nil
        r.blend_w = -1.0
    end
    -- (a held pose's arms and legs kicked and swung now and then: out to another pose a moment, eased back)
    local SW = M.AIR.swing
    if r.air_mode and r.air_mode ~= "flail" and r.air_mode ~= "random" and not r.grounded and r.air > 0.5
        and not (r.dead or r.lifeless) and not (r.stun_until and r.t < r.stun_until) and r.pc and poses and r.t > M.AIR.start then
        r.sw = r.sw or {}
        r.ovr = r.ovr or {}
        for _, part in ipairs({ "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r" }) do
            local f, c = r.sw[part], r.ctl and r.ctl[part]
            if not f then f = { next = r.t + rnd(SW.gap[1], SW.gap[2]) }; r.sw[part] = f end
            if c and not weak[part] then
                if f.on and r.t >= f.off then
                    f.on, f.next = false, r.t + rnd(SW.gap[1], SW.gap[2])
                    if r.ovr[part] == "flail" then r.ovr[part] = nil; r.blend_w = -1.0 end
                elseif not f.on and r.t >= f.next and (r.ovr[part] == nil or r.ovr[part] == "flail") then
                    local opts
                    if part:find("^upperarm") then opts = { "dive", "brace", "starfish", "superman", "arch" }
                    elseif part:find("^lowerarm") then opts = { "dive", "cover", "skydiver", "pencil" }
                    elseif part:find("^thigh") then opts = { "kick", "draw", "scissor", "runner", "pike" }
                    else opts = { "kick", "draw", "kneel", "pencil" } end
                    local q = poses.targets[opts[math.random(1, #opts)]]
                    q = q and q[part]
                    if q then
                        r.ovr[part] = "flail"
                        c.q_want, c.hz_want = q, M.AIR.flail_hz
                        f.on, f.off = true, r.t + rnd(SW.hold[1], SW.hold[2])
                    end
                end
            end
        end
    elseif r.sw then
        for part in pairs(r.sw) do if r.ovr and r.ovr[part] == "flail" then r.ovr[part] = nil end end
        r.sw = nil
        r.blend_w = -1.0
    end
    -- (off: the flail's windmill and the dive's turn head-first both turned him from outside - a forward flip "starts going
    -- down torwards the stomach then for some reason either stops or goes back the other way", 2026-11-11. Each style is
    -- its pose and its animation's pull alone, his own turn left as it is)
    if not M.AIR.turns then return end
    if r.dead or r.lifeless or r.grounded or r.air < 0.5 or r.t < M.AIR.start then return end
    if r.stun_until and r.t < r.stun_until then return end
    local A = M.AIR
    local mesh = pawn.Mesh
    if r.air_mode == "flail" then
        local right = vnorm(vsub(pos(mesh, "clavicle_r"), pos(mesh, "clavicle_l")))
        local wv = vmul(right, A.windmill)
        for _, bn in ipairs({ "upperarm_l", "upperarm_r" }) do
            pcall(function()
                local cur = mesh:GetPhysicsAngularVelocityInDegrees(FN[bn])
                local c = v3(cur.X, cur.Y, cur.Z)
                local n = vadd(c, vmul(vsub(wv, c), A.windmill_k))
                mesh:SetPhysicsAngularVelocityInDegrees({ X = n.x, Y = n.y, Z = n.z }, false, FN[bn])
            end)
        end
    elseif r.air_mode == "dive" and vlen(vel) > A.dive_from then
        local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
        local to = vnorm(vel)
        local ax = vcross(up, to)
        local sn = vlen(ax)
        if sn < 1e-3 then return end
        local ang = deg(math.asin(min(1.0, sn)))
        if vdot(up, to) < 0.0 then ang = 180.0 - ang end
        local want = vmul(vnorm(ax), min(A.dive_most, ang * A.dive_turn))
        for _, bn in ipairs({ "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05" }) do
            pcall(function()
                local cur = mesh:GetPhysicsAngularVelocityInDegrees(FN[bn])
                local c = v3(cur.X, cur.Y, cur.Z)
                local n = vadd(c, vmul(vsub(want, c), A.dive_k))
                mesh:SetPhysicsAngularVelocityInDegrees({ X = n.x, Y = n.y, Z = n.z }, false, FN[bn])
            end)
        end
    end
end
local function down_tick(pawn, r, dt)
    local C = M.CFG
    local mesh = pawn.Mesh
    r.t = r.t + dt
    -- (SCALING DAMAGE: a part that gave way under him, off now he's down)
    if st.sever_queue and r.t > 0.05 then
        local q = st.sever_queue
        st.sever_queue = nil
        for id in pairs(q) do
            local e = parts[id]
            if e and e.state < 3 then
                local regs = sever(pawn, r, id)
                if regs then
                    crack(r, mesh, id)
                    take_hp(3, id)
                    log("scaling damage: his %s came off as it gave way", id)
                end
            end
        end
    end
    -- (his body's gravity kept on all the while he's down: STORROR's get-up tries turn it off, and put down again after one
    -- he floated - dead, his arms and legs stayed up in the air wherever they were, "hands dont fall on death they just
    -- stay floating same with legs", 2026-11-11. Only looked at as he went down before)
    pcall(M.grav_tick, pawn)
    r.g = M.GRAV.g
    if r.t - (r.grav_t or -9.0) > 0.2 then
        r.grav_t = r.t
        pcall(function()
            if not mesh:IsGravityEnabled() then
                mesh:SetEnableGravity(true)
                mesh:WakeAllRigidBodies()
                r.grav_n = (r.grav_n or 0) + 1
                if r.grav_n == 1 then log("his body's gravity was off again - put back on (and as often as it's needed this time down)") end
            end
        end)
    end
    r.lifeless = not live_on()
    M.LEDGER.begin(pawn, r, dt)
    -- (the limbs' spin from the impact that put him down: a frame in, once the bodies simulate)
    if r.carry_anim and r.t > 0.0 then M.CARRY.give(pawn, r) end
    if not r.spun and r.t > 0.0 and not st.push then
        r.spun = true
        local oks, es = pcall(spin_give, pawn, r)
        if not oks then log("spin failed (%s)", tostring(es)) end
        local oka, ea = pcall(M.ANIMSPIN.give, pawn, r)
        if not oka then log("spin from his animation failed (%s)", tostring(ea)) end
    end
    if M.AIR.styles and not r.fall_tried and r.t > 0.0 and not r.dead and not r.lifeless then
        r.fall_tried = true
        local m = air_pick()
        r.air_mode, r.air_mode_t = m.name, m
        r.air_pose_want = M.style_pose(m)
        if M.CFG.fall_anim then pcall(fall_anim_play, pawn, r) else log("falling: %s", m.name) end
    end
    if not r.kicked and r.t > 0.0 then
        r.kicked = true
        local okb, eb = pcall(bail_hit, pawn, r)
        if not okb then log("the bail's hit failed (%s)", tostring(eb)) end
        local v = r.impact_v
        if v and vlen(v) > C.impact_from_v then M.limb_impact(pawn, vnorm(v), min(1.5, vlen(v) / 900.0)) end
    end
    local vel = nil
    pcall(function() local u = mesh:GetPhysicsLinearVelocity(FN["pelvis"]); vel = v3(u.X, u.Y, u.Z) end)
    if not vel then return end
    if r.t > 0.0 then
        local oku, eu = pcall(M.UNDAMP.tick, mesh, r, dt)
        if not oku and not r.ud_err then r.ud_err = true; log("undamping failed (%s)", tostring(eu)) end
    end
    -- (tipping, measured: his trunk's lean along the way he was going, as he goes down and 0.6 s on - + forward, - back -
    -- "somethings making the player fall backwards", 2026-11-11)
    if r.impact_v and vlen(v3(r.impact_v.x, r.impact_v.y, 0.0)) > 150.0 and not r.tip_said then
        local okt = pcall(function()
            local dir = vnorm(v3(r.impact_v.x, r.impact_v.y, 0.0))
            local up = vnorm(vsub(pos(mesh, "spine_05"), pos(mesh, "pelvis")))
            local lean = vdot(up, dir)
            if not r.tip0 then r.tip0 = lean end
            if r.t >= 0.3 and not r.tip3 then r.tip3 = lean end
            if r.t >= 0.6 then
                r.tip_said = true
                log("tipping along his run (%.0f cm/s): %.2f as he went down, %.2f at 0.3 s, %.2f at 0.6 s (+ forward, - back)",
                    vlen(r.impact_v), r.tip0, r.tip3 or lean, lean)
            end
        end)
        if not okt then r.tip_said = true end
    end
    -- (the first frames down: no part of him flung far past the speed he went down at - whatever flicks it)
    if r.t <= M.JOLT.t then
        local J = M.JOLT
        local ev = r.impact_v or v3(0, 0, 0)
        for _, bodies in pairs(REGIONS) do
            for _, bn in ipairs(bodies) do
                pcall(function()
                    -- (only too fast is cut: stopped by what he hit, a part is left so)
                    local u = mesh:GetPhysicsLinearVelocity(FN[bn])
                    local l = sqrt(u.X * u.X + u.Y * u.Y + u.Z * u.Z)
                    local most = vlen(ev) + J.v + (r.spin_extra or 0.0)
                    if l > most then
                        local k = most / l
                        mesh:SetPhysicsLinearVelocity({ X = u.X * k, Y = u.Y * k, Z = u.Z * k }, false, FN[bn])
                        r.j_clamped = (r.j_clamped or 0) + 1
                    end
                    local a = mesh:GetPhysicsAngularVelocityInDegrees(FN[bn])
                    local la = sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
                    if la > J.w then
                        local k = J.w / la
                        mesh:SetPhysicsAngularVelocityInDegrees({ X = a.X * k, Y = a.Y * k, Z = a.Z * k }, false, FN[bn])
                        r.j_clamped = (r.j_clamped or 0) + 1
                    end
                end)
            end
        end
    end
    -- (the first moment down, measured - "its like a jolt the second the player holds r3", 2026-11-10)
    if r.t <= 0.4 then
        if not r.j_pel and r.t >= 0.06 then r.j_pel = vlen(vel) end
        r.j_top = r.j_top or { v = 0.0, w = 0.0 }
        for _, bn in ipairs({ "pelvis", "spine_03", "head", "hand_l", "hand_r", "foot_l", "foot_r", "lowerarm_l", "lowerarm_r", "calf_l", "calf_r" }) do
            pcall(function()
                local u = mesh:GetPhysicsLinearVelocity(FN[bn])
                local sv = sqrt(u.X * u.X + u.Y * u.Y + u.Z * u.Z)
                if sv > r.j_top.v then r.j_top.v, r.j_top.vb, r.j_top.vt = sv, bn, r.t end
                local a = mesh:GetPhysicsAngularVelocityInDegrees(FN[bn])
                local sa = sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
                if sa > r.j_top.w then r.j_top.w, r.j_top.wb, r.j_top.wt = sa, bn, r.t end
            end)
        end
    elseif r.j_top and not r.j_said then
        r.j_said = true
        local J = r.j_top
        log("first 0.4 s down: hips %.0f cm/s at 0.06 s; fastest %s %.0f cm/s at %.2f s; spinning %s %.0f deg/s at %.2f s (went down at %.0f cm/s; joints out %d; hanging limbs %s; live %s; clamped %d)",
            r.j_pel or -1.0, tostring(J.vb), J.v, J.vt or 0.0, tostring(J.wb), J.w, J.wt or 0.0, r.impact_v and vlen(r.impact_v) or 0.0, r.j_dis or 0,
            tostring(r.j_stand), tostring(not r.lifeless), r.j_clamped or 0)
    end
    local p = pos(mesh, "pelvis")
    -- (on the ground: the floor within `ground_reach` cm under his hips. 70 cm, and standing his hips were higher than that:
    -- taken for falling, he was held to the flail's animation and stood there - "its like hes in the middle of trying to
    -- stand on his own", "he ragdolls after about 30 seconds", 2026-11-10)
    local grounded = ray(pawn, vadd(p, v3(0, 0, 5)), vadd(p, v3(0, 0, -C.ground_reach)))
    -- (a hard landing: all of him let go that instant - the bail's own hit counted, STORROR starting its ragdoll as he lands)
    if r.fall_vz == nil then r.fall_vz = (r.impact_v and r.impact_v.z) or 0.0 end
    if grounded and not r.was_grounded and (r.fall_vz or 0.0) < -M.GRIP.limp_vz then
        r.air, r.w = 0.0, 0.0
        r.limp_until = r.t + 0.6
        phys_set(pawn, 0.0)
        if M.stun then M.stun(r, -(r.fall_vz or 0.0) / MPH, "landing hard") end
        log("landed hard (%.0f cm/s down): let go at once", -(r.fall_vz or 0.0))
    end
    r.was_grounded = grounded
    if grounded ~= r.grounded then
        r.grounded = grounded
        r.blend_w = -1.0
        pcall(M.air_shoulders, mesh, not grounded)
    end
    if not grounded then r.fall_vz = min(r.fall_vz or 0.0, vel.z) else r.fall_vz = 0.0; r.L0 = nil end
    r.air = grounded and max(0.0, r.air - dt / C.ground_fade) or min(1.0, r.air + dt * 4.0)
    -- (his grip on the ground: lying there, creeping slower than `below` cm/s, his body as a whole braked to a stop -
    -- `k` a second - his limbs still free to move: his kicks and writhing scooted him along the floor, "also sliding on
    -- ground", 2026-11-10. A real slide, faster, goes on.)
    if grounded and M.GRIP.on and not (r.act and (r.act.name == "crawl" or r.act.name == "roll" or r.act.name == "rollabout")) and not r.crawling then
        local hv = v3(vel.x, vel.y, 0.0)
        local hs = vlen(hv)
        if hs > 1.0 and hs < M.GRIP.below then
            local k = min(1.0, M.GRIP.k * M.pdt(dt))
            pcall(function() mesh:AddImpulseToAllBodiesBelow(fv(vmul(hv, -k)), FN["pelvis"], true, true) end)
        end
        -- (his trunk's turning about the up braked the same way)
        pcall(function()
            local k = min(1.0, M.GRIP.turn_k * M.pdt(dt))
            for _, b in ipairs({ "pelvis", "spine_03", "spine_05", "thigh_l", "thigh_r" }) do
                local w = mesh:GetPhysicsAngularVelocityInDegrees(FN[b])
                if abs(w.Z) > 1.0 and abs(w.Z) < M.GRIP.turn_below then
                    mesh:AddAngularImpulseInDegrees({ X = 0.0, Y = 0.0, Z = -w.Z * k }, FN[b], true)
                end
            end
        end)
    end
    if (grounded or (r.air or 0.0) < 1.0) and not (r.act and (r.act.name == "crawl" or r.act.name == "roll" or r.act.name == "rollabout"))
        and not r.crawling then
        local okf, ef = pcall(M.FRICTION.tick, pawn, r, mesh, dt)
        if not okf and not r.fr_err then r.fr_err = true; log("friction failed (%s)", tostring(ef)) end
    end
    -- (for tuning: on the ground, how far he went and how far he turned each second, and what he was doing)
    if grounded then
        local okf, fwd = pcall(function() local a, b = pos(mesh, "pelvis"), pos(mesh, "spine_05"); return vnorm(v3(b.x - a.x, b.y - a.y, 0.0)) end)
        local M2 = r.moved
        if not M2 then M2 = { t = r.t, p = p, yaw = 0.0, f = okf and fwd or nil }; r.moved = M2 end
        if okf and M2.f then
            local c = M2.f.x * fwd.y - M2.f.y * fwd.x
            local d = M2.f.x * fwd.x + M2.f.y * fwd.y
            M2.yaw = M2.yaw + deg(atan(c, d))
            M2.f = fwd
        end
        if r.t - M2.t >= 1.0 then
            local went = vlen(v3(p.x - M2.p.x, p.y - M2.p.y, 0.0))
            if (went > 25.0 or abs(M2.yaw) > 30.0) and r.t > 1.5 then
                log("on the ground: went %.0f cm and turned %.0f deg in %.1f s (%s%s%s%s)", went, M2.yaw, r.t - M2.t,
                    r.act and ("act " .. tostring(r.act.name)) or "no act", r.hold and ", holding" or "",
                    r.curl and ", curled" or "", r.struggle and ", struggling" or "")
            end
            r.moved = nil
        end
    else
        r.moved = nil
    end
    if not grounded then
        -- (STORROR's damping given back only clearly in the air - a quarter second off the ground: given back while he slid
        -- over an edge, nothing slowed the slide)
        if (r.air or 0.0) >= 1.0 then fall_ragdoll(mesh, vel, r, dt) end
        -- (how fast he falls as a ragdoll, measured: the speed down at the start and end of each time in the air)
        if not r.air_from then
            r.air_from, r.air_vz0, r.air_t = r.t, vel.z, 0.0
        end
        r.air_t, r.air_vz1 = r.air_t + dt, vel.z
        if vel.z < (r.vz_min or 0.0) then r.vz_min = vel.z end
    elseif r.air_from then
        if r.air_t > 0.3 then
            local acc = (r.air_vz0 - r.air_vz1) / r.air_t
            r.air_log = string.format("in the air %.1f s, falling %.0f -> %.0f cm/s: %.0f cm/s/s against gravity %.0f", r.air_t,
                -r.air_vz0, -r.air_vz1, acc, r.g or 0.0)
            log("ragdoll %s", r.air_log)
        end
        r.air_from = nil
    end
    -- falling animation: the flail's pull, fading on the ground; its pace by his speed up or down
    if r.dead or r.lifeless then
        phys_set(pawn, 0.0)
        -- (dead or limp: every muscle of his at nothing, written again every half second - written once, his dead body
        -- after STORROR's get-ups held a pose, knees up and feet in the air: "while dead bodys not going limp", 2026-11-11)
        if r.t - (r.zero_t or -9.0) > 0.5 then
            r.zero_t = r.t
            -- (all of him physics, nothing of an animation drawn in - STORROR's get-up tries leave his body part-blended
            -- with its pose, knees up and arms raised as he lay dead - and no motor in his joints)
            pcall(function() mesh:SetAllBodiesPhysicsBlendWeight(1.0, false) end)
            pcall(function() mesh:SetAllMotorsAngularDriveParams(0.0, 0.0, 0.0, false) end)
            pcall(function() mesh:SetAllMotorsAngularPositionDrive(false, false) end)
            pcall(function() mesh:SetAllMotorsAngularVelocityDrive(false, false) end)
        end
        if r.pc and r.ctl and r.t - (r.zero_t2 or -9.0) > 0.5 then
            r.zero_t2 = r.t
            -- (every pull on him that isn't one of his limbs' - a hold's, a foot's - taken off: "all animations should
            -- let go after death", 2026-11-11)
            if r.hold then hold_stop(r, "dead") end
            pcall(function()
                local mine = {}
                for _, c in pairs(r.ctl) do
                    local sn = c.name
                    sn = (type(sn) == "userdata" and sn.ToString) and sn:ToString() or tostring(sn)
                    mine[sn] = true
                end
                local names = r.pc:GetAllControlNames()
                local gone = {}
                for i = 1, #names do
                    local sn = names[i]:get():ToString()
                    if not mine[sn] then gone[#gone + 1] = sn end
                end
                for _, sn in ipairs(gone) do r.pc:DestroyControl(FName(sn), true, false) end
                if #gone > 0 then log("dead: %d pulls left on him taken off (%s)", #gone, table.concat(gone, ", ")) end
            end)
            for _, c in pairs(r.ctl) do
                pcall(function()
                    r.pc:SetControlAngularData(c.name, 0.0, 0.0, 0.0, 0.0, true, true, false)
                    r.pc:SetControlLinearData(c.name, 0.0, 0.0, 0.0, 0.0, true, true, false)
                end)
            end
        end
    elseif C.stagger and r.t < C.stagger_legs and not (r.limp_until and r.t < r.limp_until) and not (r.stun_until and r.t < r.stun_until) then
        -- (the upper body and the legs each pulled to the animation, hard at first and less and less)
        local function fade(t0, t1) return 1.0 - min(1.0, max(0.0, (r.t - t0) / (t1 - t0))) end
        local ku = C.stagger_k * fade(0.0, C.stagger_up) ^ 2
        local kl = C.stagger_k * fade(C.stagger_legs_from, C.stagger_legs) ^ 2
        local base = C.fall_anim and C.fall_k or 0.0
        local c = phys_comp(pawn)
        if c then pcall(function()
            c:ApplyPhysicalAnimationSettingsBelow(FN["spine_02"], pa_data(max(base, ku)), true)
            c:ApplyPhysicalAnimationSettingsBelow(FN["thigh_l"], pa_data(max(base, kl)), true)
            c:ApplyPhysicalAnimationSettingsBelow(FN["thigh_r"], pa_data(max(base, kl)), true)
            c:ApplyPhysicalAnimationSettings(FN["pelvis"], pa_data(0.0))
            for j, f in pairs(weak) do
                local leg = j:match("^thigh") or j:match("^calf") or j:match("^foot")
                c:ApplyPhysicalAnimationSettings(FN[j], pa_data(max(base, leg and kl or ku) * f))
            end
        end) end
        phys.k = -1.0                                   -- (the fall animation's pull written afresh after)
    elseif C.fall_anim then
        local k = C.fall_k * r.air * (1.0 - r.w) * ((r.air_mode == "flail") and M.AIR.flail_k or 1.0)
        if r.stun_until and r.t < r.stun_until then k = 0.0 end
        phys_set(pawn, k)
        local name, mt = montage(pawn)
        if (not mt or name == "") and r.fall_path and r.air > 0.5 and r.t < 20.0 then
            r.fall_again = (r.fall_again or 0.0) - dt
            if r.fall_again <= 0.0 then r.fall_again = 0.5; pcall(fall_anim_play, pawn, r) end
        end
        if mt and (name:find("Ragdoll") or name:find("Falling")) then
            local rate = 1.0
            if vel.z > 0.0 then rate = 1.0 + (C.rate_up - 1.0) * min(1.0, vel.z / 600.0)
            else rate = 1.0 + (C.rate_down - 1.0) * min(1.0, -vel.z / 800.0) end
            if r.air_mode == "flail" then rate = rate * M.AIR.flail_rate end
            if abs(rate - (r.rate or 0.0)) > 0.05 then
                r.rate = rate
                pcall(function() mesh:GetAnimInstance():Montage_SetPlayRate(mt, rate) end)
            end
        end
    else
        phys_set(pawn, 0.0)
    end
    -- protecting the head: falling fast with the ground (or a wall) close along the way he is going
    local want = 0.0
    if C.protect and not r.dead and not r.lifeless and r.t > 0.1 and vel.z < C.protect_vz then
        local sp = vlen(vel)
        local ahead = vadd(p, vmul(vel, C.protect_t))
        if ray(pawn, p, ahead) or ray(pawn, p, vadd(p, v3(0, 0, -sp * C.protect_t * 0.6))) then want = 1.0 end
    end
    -- (held up in the air - his whole body falling at under `lev_g` of gravity for `lev_t` s, whatever the cause - the
    -- style is dropped and he falls loose)
    if r.air_pose_want and not r.grounded and r.air > 0.5 and M.COM and M.COM.of then
        local okv, vc = pcall(M.COM.of, mesh)
        if okv and vc then
            if r.lev_vz then
                local acc = (vc.z - r.lev_vz) / max(dt, 1e-3)
                if acc > -(r.g or 1500.0) * M.AIR.lev_g then r.lev_t = (r.lev_t or 0.0) + dt else r.lev_t = 0.0 end
                if r.lev_t > M.AIR.lev_t then
                    log("falling: %s held him up in the air - dropped, he falls loose", tostring(r.air_mode))
                    r.air_pose_want, r.lev_t = nil, 0.0
                end
            end
            r.lev_vz = vc.z
        end
    end
    local pose_now = r.air_pose_want
    if r.air_pose_want and not r.dead and not r.lifeless and r.t > M.AIR.start and not r.grounded and r.air > 0.5 then
        if want >= 1.0 and r.air_pose_want == "dive" then pose_now = "protect" end
        want = 1.0
    elseif want >= 1.0 then
        pose_now = nil
    end
    if pose_now ~= r.air_pose then r.air_pose = pose_now; r.blend_w = -1.0 end
    if (r.limp_until and r.t < r.limp_until) or (r.stun_until and r.t < r.stun_until) then want = 0.0; r.w = 0.0 end
    if want > r.w then r.w = min(want, r.w + dt * C.protect_in) else r.w = max(want, r.w - dt * C.protect_out) end
    pcall(air_style_tick, pawn, r, vel, dt)
    if r.w > r.max_w then r.max_w = r.w end
    if r.wake_t and r.t - r.wake_t < M.STUN.wake + 0.05 then r.blend_w = -1.0 end
    ctl_blend(r, r.w)
    pcall(M.ctl_smooth, r, dt)
    dislocation_tick(pawn, r)
    local oks, es = pcall(SC.tick, pawn, r, dt)
    if not oks and not r.sc_err then r.sc_err = true; log("keeping his parts apart failed (%s)", tostring(es)) end
    damage_tick(pawn, r, dt)
    local okb, eb = pcall(behaviors_tick, pawn, r, dt)
    if not okb and not r.beh_err then r.beh_err = true; log("behaviours failed (%s)", tostring(eb)) end
end

-- ------------------------------------------------------------------ tripping: a flip not finished, a run into a wall
-- ("next I want to work on flips not finishing therefore the player falling", "or running into objects should cause player
-- to fall", 2026-11-10.) On his feet, each frame:
--   A FLIP - his body's tilt (pelvis to upper chest, off the upright) and STORROR's moves kept while he is in the air; touching
--     down in a flip (a move named like one, `flip_words`) more than `flip_tilt` deg off upright - not round yet - he goes
--     down, carrying the speed he came down at (the landing's own blow then hurts him like any other).
--   A WALL - running at `wall_speed` cm/s or more and stopped to under `wall_drop` of it inside `wall_win` s, with a wall
--     (a surface facing him, not a floor) within `wall_reach` cm the way he was going: down he goes into it at that speed.
--     Not in a vault, a climb or a move on a wall (`skip_words`).
-- Neither for `after` s after he gets up. Every flip landing and every sudden stop logged, to tune by.
-- (a flip counts only coming down out of a fall - mode 3, or faster than `flip_fall` cm/s: STORROR's ground tricks - a
-- roundoff on the flat - are its animation played to its end, and one ended bent over; tripped, wrongly, 2026-11-10)
-- (a fall: landing `fall_cm` or more below the highest he was since leaving the ground, he goes down whatever he was doing
-- - "next should make the player ragdoll from 20 feet fall no matter what", 2026-11-10; 20 ft = 610 cm)
-- (`wall_speed` 120, was 300: running slowly into something did nothing - "if the players slow and runs into something it
-- doesnt trigger this", 2026-11-11; the stick still has to be pushing him at it)
M.TRIP = { on = true, fall_cm = 610.0, flip_tilt = 70.0, flip_fall = 400.0, wall_speed = 120.0, wall_drop = 0.35, wall_held = 0.5, wall_win = 0.15, wall_reach = 140.0, wall_push = 0.5, wall_face = 0.35, sweep_r = 28.0, sweep_back = 40.0, after = 0.6,
           flip_words = { "flip", "twist", "cork", "gainer", "aerial", "butterfly", "webster", "spin", "somersault" },
           skip_words = { "Vault", "Climb", "Ledge", "Hang", "Mantle", "Wall", "Kong", "Monkey", "Swing", "Pullup", "PullUp",
                          "Shimmy", "Tic", "Grab", "Brachiat" } }
local function tilt_of(mesh)
    local okp, a, b = pcall(function() return mesh:GetSocketLocation(FN["pelvis"]), mesh:GetSocketLocation(FN["spine_05"]) end)
    if not (okp and a and b) then return 0.0 end
    local u = vnorm(v3(b.X - a.X, b.Y - a.Y, b.Z - a.Z))
    return deg(acos(max(-1.0, min(1.0, u.z))))
end
-- (a menu up, or the game paused: nothing of his measured or done - the game crashed at 20:55, 2026-11-10, half a second
-- after the FIRST PERSON page opened, as a "31 ft fall" put him down with the menu still up)
local function menu_open()
    local paused = false
    pcall(function() paused = StaticFindObject("/Script/Engine.Default__GameplayStatics"):IsGamePaused(lib.world()) end)
    if paused then return true end
    local Mn = _G.ARMENU
    return (Mn and Mn.menu_up) and true or false
end
M.menu_open = menu_open
M.KNOCK_FRESH = 0.35       -- (s a knock's speed waits for the fall it was for)
local function trip(pawn, why, vel)
    if menu_open() then return false end
    local pk = lib.parkour(pawn)
    if not pk then return false end
    if not pcall(function() pk:StartRagdoll(1.0, false) end) then return false end
    -- (his speed given to every body for the first frames down, as a test knock's is)
    if vel then st.knock_v, st.knock_t = vel, os.clock(); st.push = { v = vel, n = 2, t = os.clock() } end
    log("down: %s", why)
    return true
end
local function realistic() local Mn = _G.ARMENU; return not (Mn and Mn.realistic_falls) or Mn.realistic_falls() end
local function trip_tick(pawn, dt)
    local T = M.TRIP
    if not T.on or st.crawl_mode then return end
    -- (no fall measured across a menu: his height before it and after it are no fall)
    if menu_open() then st.trip = nil; return end
    local real = realistic()                -- (RAGDOLL > REALISTIC FALLS: the 20 ft fall and running into things)
    local cm = pawn.CharacterMovement
    local mode, v = cm.MovementMode, cm.Velocity
    local now = os.clock()
    local name = montage(pawn)
    local tr = st.trip
    if not tr then tr = { hist = {} }; st.trip = tr end
    local fresh = now - (st.up_t or -9.0) < T.after
    -- (a flip)
    if mode == 3 or mode == 5 then
        local A = tr.air
        local z = pawn:K2_GetActorLocation().Z
        if not A then A = { t0 = now, names = {}, flip = false, top = z, zp = z }; tr.air = A end
        if abs(z - A.zp) > 400.0 then A.top = z end          -- (put somewhere in a frame - a waypoint: no fall)
        if z > A.top then A.top = z end
        A.zp = z
        -- (holding a ledge, climbing: his fall over - measured again from here)
        if M.GRABROLL.caught(name) then
            if not A.caught then log("caught a ledge (%s, mode %s) - no fall from before it", name, tostring(mode)) end
            A.caught, A.top = true, z
        end
        if name ~= "" and not A.names[name] then
            A.names[name] = true
            A.list = A.list and (A.list .. ", " .. name) or name
            local low = name:lower()
            for _, w in ipairs(T.flip_words) do if low:find(w, 1, true) then A.flip = true end end
        end
        A.tilt = tilt_of(pawn.Mesh)
        A.vel = v3(v.X, v.Y, v.Z)
        A.mode = mode
    elseif tr.air and mode ~= 1 and mode ~= 2 and mode ~= 0 then
        -- (not on the ground - a hold of a ledge in a mode of its own: no landing, the fall measured again from here)
        local A = tr.air
        tr.air = nil
        log("caught (mode %s%s) after %.0f cm down - no landing", tostring(mode), name ~= "" and (", " .. name) or "", (A.top or 0.0) - pawn:K2_GetActorLocation().Z)
    elseif tr.air and M.GRABROLL.caught(name) then
        tr.air = nil
        log("caught a ledge (%s) as he came out of the air - no landing", name)
    elseif tr.air then
        local A = tr.air
        tr.air = nil
        local drop = (A.top or 0.0) - pawn:K2_GetActorLocation().Z
        if drop > 300.0 then
            log("landed %.0f cm (%.1f ft) below his highest, at %.0f cm/s down, mode %s%s", drop, drop / 30.48, -(A.vel and A.vel.z or 0.0),
                tostring(mode), A.list and (" (" .. A.list .. ")") or "")
        end
        -- (the height from the RAGDOLL tab's FALL HEIGHT; OFF, no fall puts him down)
        local Mn = _G.ARMENU
        local fall_cm = T.fall_cm
        if Mn and Mn.fall_ft then local ft = Mn.fall_ft(); fall_cm = ft and ft * 30.48 or nil
        elseif not real then fall_cm = nil end
        -- (by the world's gravity now - GRAVITY on the tab: `hard`, the height that lands as hard at STORROR's own. On the
        -- moon a 20 ft drop lands as softly as a 3 ft one, and its jumps go six times as high)
        local gnow = M.GRAV.g
        local hard = drop * ((M.GRAV.base > 1.0) and (gnow / M.GRAV.base) or 1.0)
        -- (SCALING DAMAGE: landed on his feet from a height - no bail - his legs take it)
        if M.feet_damage_on() and hard >= M.SCALE.fall_from and not fresh and not M.GRABROLL.rolled() and not (fall_cm and hard >= fall_cm)
            and (mode == 1 or mode == 2) then
            local vz = -(A.vel and A.vel.z or 0.0)
            local need = sqrt(2.0 * gnow * drop)
            if vz < need * 0.6 then vz = need end
            pcall(M.scale_fall, pawn, vz / MPH, drop)
            if st.sever_queue and next(st.sever_queue) then
                local vel = A.vel or v3(0.0, 0.0, -vz)
                trip(pawn, string.format("a leg with no health left gave way (%.0f ft)", drop / 30.48), vel)
                tr.hist = {}
                return
            end
        end
        if fall_cm and hard >= fall_cm and not fresh and not M.GRABROLL.rolled() then
            local vel = A.vel or v3(0.0, 0.0, 0.0)
            -- (his speed down as he landed, at the least what that fall gives)
            local need = -sqrt(2.0 * gnow * drop)
            if vel.z > need * 0.6 then vel = v3(vel.x, vel.y, need) end
            trip(pawn, string.format("a %.0f ft fall (%.0f cm)", drop / 30.48, drop), vel)
            tr.hist = {}
            return
        end
        if (A.flip or (A.tilt or 0.0) > 45.0) and (mode == 1 or mode == 2) then
            local falling = A.mode == 3 or -(A.vel and A.vel.z or 0.0) > T.flip_fall
            log("landed from %.2f s in the air %.0f deg off upright, at %.0f cm/s down, mode %s%s", now - A.t0, A.tilt or 0.0, -(A.vel and A.vel.z or 0.0),
                tostring(A.mode), A.list and (" (" .. A.list .. ")") or "")
            if A.flip and falling and (A.tilt or 0.0) > T.flip_tilt and not fresh and not M.GRABROLL.rolled() then
                trip(pawn, string.format("a flip not finished - %.0f deg off upright as he landed (%s)", A.tilt, A.list or "?"), A.vel)
                tr.hist = {}
                return
            end
        end
    end
    -- (a wall. His speed as he really went - how far he moved this frame: STORROR moves him by his animation, and with root
    -- motion the movement's own velocity stays at the animation's speed even as a wall stops him dead - "running into things
    -- not ragdolling player", 2026-11-10. Stopped: going `wall_speed` or more and now under `wall_drop` of it, or the
    -- animation driving him on at that speed while he hardly moves, two frames running.)
    local at = pawn:K2_GetActorLocation()
    local ah = 0.0
    local ax, ay = 0.0, 0.0
    if tr.lp and dt > 0.0005 then
        ax, ay = (at.X - tr.lp.x) / dt, (at.Y - tr.lp.y) / dt
        ah = sqrt(ax * ax + ay * ay)
        if ah > 6000.0 then ah, ax, ay = 0.0, 0.0, 0.0; tr.hist = {} end      -- (put somewhere: no speed)
    end
    tr.lp = v3(at.X, at.Y, at.Z)
    local want = sqrt(v.X * v.X + v.Y * v.Y)
    local H = tr.hist
    H[#H + 1] = { now, ax, ay, ah }
    while #H > 0 and now - H[1][1] > T.wall_win do table.remove(H, 1) end
    local peak = nil
    for i2 = 1, #H - 1 do local e = H[i2]; if not peak or e[4] > peak[4] then peak = e end end
    local dropped = peak and peak[4] >= T.wall_speed and ah < peak[4] * T.wall_drop
    if want >= T.wall_speed and ah < want * T.wall_held then tr.held = (tr.held or 0) + 1 else tr.held = 0 end
    local held = tr.held >= 2
    -- (for tuning: running with a wall just ahead, what STORROR does with him - twice a second at most)
    if want >= 300.0 and (mode == 1 or mode == 3) and now - (tr.diag_t or -9.0) > 0.5 then
        local dd = vnorm(v3(v.X, v.Y, 0.0))
        local a0 = v3(at.X, at.Y, at.Z + 20.0)
        local nn, d0 = ray_hit(pawn, a0, vadd(a0, vmul(dd, 120.0)))
        if nn and (nn.x * dd.x + nn.y * dd.y) < -0.5 then
            tr.diag_t = now
            log("near a wall %.0f cm ahead: really going %.0f cm/s, his animation %.0f, mode %d, held %d%s", d0 or -1.0, ah, want, mode,
                tr.held, name ~= "" and (" (" .. name .. ")") or "")
        end
    end
    if (dropped or held) and now - (tr.wall_t or -9.0) > 1.0 and (mode == 1 or mode == 3) then
        tr.wall_t = now
        local skip = nil
        for _, w in ipairs(T.skip_words) do if name:find(w, 1, true) then skip = w end end
        local sp, dx, dy
        if dropped then sp, dx, dy = peak[4], peak[2], peak[3] else sp, dx, dy = want, v.X, v.Y end
        local dir = vnorm(v3(dx, dy, 0.0))
        -- (what is ahead, chest high down to a shin's height: a wall, a bench, a box; STORROR slows him short of a wall
        -- itself, so out to `wall_reach` cm. Only while the stick still drives him at it: let go to stop near one, he
        -- doesn't fall)
        -- (swept as wide as he is, from a little behind him - `sweep_r`, `sweep_back` - at his chest, hips and shins: "it
        -- has trouble with recognizing smaller objects like trash cans", 2026-11-10 - a line from his middle passed a bin
        -- that stopped him by a shoulder or a hip)
        -- (looked for the way he was going and the way his animation drove him - a bin or a fence turns him aside as it
        -- stops him; then, met by nothing, again for anything solid at all: a small fence, a bin, may not stop a trace -
        -- "small fences", 2026-11-10)
        local n, d = nil, nil
        local dirs = { dir }
        if want > 50.0 then dirs[2] = vnorm(v3(v.X, v.Y, 0.0)) end
        for _, solid in ipairs({ false, true }) do
            for _, dd in ipairs(dirs) do
                for _, dz in ipairs({ 20.0, -30.0, -50.0, 55.0 }) do
                    local a = vadd(v3(at.X, at.Y, at.Z + dz), vmul(dd, -T.sweep_back))
                    local hn, hd = sweep_hit(pawn, a, vadd(a, vmul(dd, T.wall_reach + T.sweep_back)), T.sweep_r, solid)
                    if hn and (hn.x * dd.x + hn.y * dd.y) < -T.wall_face and abs(hn.z) < 0.6 then
                        n, d, dir = hn, (hd or 0.0) - T.sweep_back, dd
                        break
                    end
                    if hn and not n then n, d = hn, (hd or 0.0) - T.sweep_back end
                end
                if n and (n.x * dir.x + n.y * dir.y) < -T.wall_face then break end
            end
            if n and (n.x * dir.x + n.y * dir.y) < -T.wall_face then break end
        end
        local sdir = stick_dir()
        local push = sdir and (sdir.x * dir.x + sdir.y * dir.y) or 0.0
        local wall = n and (n.x * dir.x + n.y * dir.y) < -T.wall_face and abs(n.z) < 0.6 and push > T.wall_push
        if M.LOG.verbose then log("stopped from %.0f to %.0f cm/s (%s; his animation at %.0f; the stick %s) %s%s%s", sp, ah, dropped and "slowed" or "held", want,
            sdir and string.format("%.0f%% on at it", push * 100.0) or "let go",
            n and string.format("- a surface %.0f cm ahead%s", d or -1.0, wall and ", a wall facing him" or ", not a wall in his way") or "- nothing ahead",
            name ~= "" and (" (" .. name .. ")") or "", fresh and " - just up" or "") end
        -- (RUN INTO WALLS, on the RAGDOLL tab - "add another switch for ragdolling when running into objects", 2026-11-11)
        local Mn = _G.ARMENU
        local walls_on = not (Mn and Mn.run_into_walls and not Mn.run_into_walls())
        if wall and not skip and not fresh and real and walls_on then
            trip(pawn, string.format("ran into a wall at %.0f cm/s", sp), v3(dir.x * sp, dir.y * sp, 0.0))
            tr.hist, tr.held = {}, 0
        end
    end
end

-- Back at a waypoint - STORROR's own reset of him (its parkour component's OnCharacterReset / SimpleReset) - he is healed,
-- all of him, however near the waypoint ("make it so when you teleport back to waypoint you fully heal", 2026-11-10: a jump
-- of more than his speed takes him in a frame missed a waypoint close by). Hooked once a game; healed on the next frame,
-- not inside the game's call.
-- (before STORROR's reset runs: the fall animation's component off him - see phys_drop)
if not _G.AR_RESET_HOOK2 then
    _G.AR_RESET_HOOK2 = {}
    for _, fn in ipairs({ "/Script/HumanEmotion.ParkourComponent:OnCharacterReset", "/Script/HumanEmotion.ParkourComponent:SimpleReset" }) do
        local nm = fn:match(":(.+)$")
        local ok = pcall(RegisterHook, fn, function()
            local A = _G.AR
            if A and A.on_reset_pre then pcall(A.on_reset_pre, nm) end
        end, function()
            local A = _G.AR
            if A and A.on_reset and not _G.AR_RESET_HOOK then pcall(A.on_reset, nm) end
        end)
        _G.AR_RESET_HOOK2[fn] = ok
        log("hooked %s (before and after): %s", nm, tostring(ok))
    end
end
-- (STORROR's own try at getting him up, watched: it got him up in the air, flying at 3800 and 4600 cm/s - "for about 3
-- seconds it sends him flying then all speed stops for no reason", 2026-11-11)
if _G.AR_TGU_HOOK == nil then
    _G.AR_TGU = _G.AR_TGU or { n = 0, last = -9.0 }
    local ok = pcall(RegisterHook, "/Script/HumanEmotion.ParkourComponent:TryGetupFromRagdoll", function()
        local A = _G.AR
        if A and A.on_try_getup then pcall(A.on_try_getup) end
    end)
    _G.AR_TGU_HOOK = ok
    log("hooked TryGetupFromRagdoll: %s", tostring(ok))
end
function M.on_try_getup()
    local T = _G.AR_TGU
    if not T then return end
    T.n = T.n + 1
    local now = os.clock()
    if now - T.last < 0.5 then return end
    T.last = now
    local r = st.rag
    local pawn = lib.pawn()
    local sp, vz = -1.0, 0.0
    if pawn then pcall(function() local u = pawn.Mesh:GetPhysicsLinearVelocity(FN["pelvis"]); sp, vz = sqrt(u.X * u.X + u.Y * u.Y + u.Z * u.Z), u.Z end) end
    log("STORROR tries to get him up (%d tries so far): %.1f s down, his body %.0f cm/s (%.0f down), %s", T.n, r and r.t or -1.0, sp, -vz,
        (r and r.grounded) and "on the ground" or "in the air")
end
function M.on_reset_pre(name)
    phys_drop(name)
    -- (how still his body was as STORROR got him up - it gets him up once he lies still: to learn how still is still)
    local r = st.rag
    r = r and not r.getup_said and r or nil
    if r then r.getup_said = true end
    if name == "SimpleReset" and r and r.spd then
        local now = os.clock()
        local function peak(win) local m = 0.0; for _, e in ipairs(r.spd) do if now - e[1] <= win and e[2] > m then m = e[2] end end; return m end
        log("STORROR's get-up after %.1f s down: his pelvis at most %.0f cm/s over the last 0.25 s, %.0f over 0.5 s, %.0f over 1 s",
            r.t, peak(0.25), peak(0.5), peak(1.0))
    end
end
-- (SimpleReset comes on a plain get-up too - "players healing when standing up?", 2026-11-10 - so it heals only if his
-- body was moved: further than `far` from where it lay the frame before, looked at for `wait` s. OnCharacterReset - the
-- waypoint - heals always.)
M.RESET = { far = 200.0, wait = 0.6 }
-- (STORROR gets him up as soon as he lies still - limp from a 50 mph blow, both legs and his chest broken, he lay still at
-- once and was up 0.35 s after: "player stood up on his own?", 2026-11-11. So down at least a while by the hardest blow -
-- from `from` mph, `per` s a mph more, at most `most` s; a broken or cut leg `legs` s more - put down again if he's got
-- up sooner)
M.REGRAB_STILL = 0.25
function M.on_reset(name)
    st.reset_pending = { name = name or "reset", from = st.body_at, t = os.clock() }
    if name == "SimpleReset" and (st.crawl_mode or st.bled_out) then st.crawl_regrab = true end
    if name == "SimpleReset" and not st.bled_out then
        local r = st.rag
        -- (never on his own: STORROR's get-up let through only on the player's press, or a roll's undoing of a bail -
        -- "should never stand on his own", 2026-11-11)
        local pressed = os.clock() - (st.getup_press_t or -99.0) < 2.0
        -- (the press itself, looked at as STORROR gets him up: it does so in the frame of the press, before the mod's own
        -- look at the keys, and the press was taken for none - "takes multiple presses to stand up", 2026-11-11)
        if not pressed then
            pcall(function()
                local pc = lib.controller()
                for _, k in ipairs(M.GETUP_KEYS or {}) do
                    if pc and pc:IsInputKeyDown(k) then pressed = true; st.getup_press_t = os.clock(); break end
                end
            end)
        end
        if st.down and r and not pressed and not st.negate then
            st.crawl_regrab, st.keep_down = true, true
        end
    end
end
-- REGENERATION (the RAGDOLL tab): his HP back at `rate` a second, 1 to 100, and his hurts mended one at a time - the
-- slightest first - each as its own HP comes back (a fracture 3 HP, a break 5: at 1 HP a second 3 s and 5 s); a part cut
-- off never ("add a regeneration slider", "1 hp healed a second up to 100hp a second", "cant regenerate severed limbs",
-- 2026-11-10). Nothing once he has bled out.
local function regen_rate() local Mn = _G.ARMENU; return (Mn and Mn.regeneration and Mn.regeneration()) or 0 end
-- (the parts in a fixed order - head, chest, then arms and legs - for the next to mend)
local PART_IDS = { "head", "chest", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r",
                   "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r" }
local function mend(pawn, id)
    local e = parts[id]
    e.state, e.d, e.up, e.wear = 0, 0.0, 0.0, nil
    for b, reg in pairs(JOINT_REGION) do if reg == id and dis[b] then dis[b] = nil end end
    limp_update()
    if pawn then pcall(lim_apply, pawn.Mesh) end
    local G = _G.ARGORE
    if G and G.fractures_clear then pcall(G.fractures_clear, { id }) end
    local r = st.rag
    if r then
        if r.hold and r.hold.e and r.hold.e.id == id then hold_stop(r, "mended") end
        if r.inj then r.inj[id] = nil end
        r.blend_w = -1.0
    end
end
local function regen_tick(pawn, dt)
    local rate = regen_rate()
    local G = _G.ARGORE
    if rate <= 0 or st.bled_out or not G then st.mend_acc = 0.0; return end
    -- (broken first, then fractured - "healing goes to broken limbs first then fractured limbs", 2026-11-10; with LIMB HP its
    -- HP goes to that limb alone - "it should only heal one limb at a time")
    local pick, cost = nil, nil
    for _, want in ipairs({ 2, 1 }) do
        for _, id in ipairs(PART_IDS) do
            local e = parts[id]
            if e and e.state == want then pick, cost = id, M.HP_COST[want] or 5; break end
        end
        if pick then break end
    end
    if G.heal_hp then pcall(G.heal_hp, rate * dt, pick and G.GROUP_OF and G.GROUP_OF[pick] or nil) end
    if not pick then st.mend_acc = 0.0; return end
    -- (LIMB HP: a hurt mended once its limb's HP is all back - mended at once after a few HP, his limbs showed no damage
    -- while their HP was still low, "some limbs not showing damage", 2026-11-11; otherwise once its own HP has come back)
    local LH = nil
    if G.limb_hp then local okl, v = pcall(G.limb_hp); if okl then LH = v end end
    local grp = LH and G.GROUP_OF and G.GROUP_OF[pick]
    if grp and LH[grp] then
        if LH[grp][1] < LH[grp][2] - 0.01 then return end
    else
        st.mend_acc = (st.mend_acc or 0.0) + rate * dt
        if st.mend_acc < cost then return end
    end
    st.mend_acc = 0.0
    local was = parts[pick].state
    mend(pawn, pick)
    log("regenerated: his %s mended (was %s)", pick, (was == 1) and "fractured" or "broken")
end
M.GETUP_AFTER = 1.0
-- ROLLS NEGATE RAGDOLLS, on the RAGDOLL tab ("rolls always negate ragdolls", 2026-11-11): a roll as he lands - STORROR's
-- roll key pressed within `roll_t` s, or its roll under way - and the mod's fall and unfinished-flip trips are let go, and a
-- bail STORROR begins in the moment of it is undone: he is got up again at once. (The mod's fall trip comes the frame he
-- lands, before STORROR's roll has begun, so the key is what tells.) And STORROR's catches of a ledge, told from a landing.
-- (GRABS AT ANY SPEED - his fall slowed by walls for STORROR's grab to catch - taken out: STORROR let go of a fast catch
-- however it was slowed, and "hell no remove whatever you added that slows the player in air", 2026-11-11)
M.GRABROLL = { roll_t = 0.6,
               roll_keys = { { KeyName = FName("LeftControl") }, { KeyName = FName("Gamepad_FaceButton_Right") } } }
function M.GRABROLL.rolled()
    local Mn = _G.ARMENU
    if not (Mn and Mn.rolls_negate and Mn.rolls_negate()) then return false end
    return os.clock() - (st.roll_t or -99.0) < M.GRABROLL.roll_t
end
function M.GRABROLL.tick(pawn, dt)
    local name = montage(pawn)
    if name:find("Roll") then st.roll_t = os.clock() end
    local pc = lib.controller()
    if not pc then return end
    for _, k in ipairs(M.GRABROLL.roll_keys) do
        local ok, d = pcall(function() return pc:IsInputKeyDown(k) end)
        if ok and d then st.roll_t = os.clock(); break end
    end
end
-- (a hold of a ledge, a climb: not a landing - after a long drop, it was taken as one and he was put down)
function M.GRABROLL.caught(name)
    if name == "" or name:find("^MontageFalling") then return false end
    for _, w in ipairs({ "Hang", "Grab", "Ledge", "Climb", "Brace", "Catch", "Shimmy", "Mantle" }) do if name:find(w) then return true end end
    return false
end
local GETUP_KEYS = { { KeyName = FName("Gamepad_FaceButton_Bottom") }, { KeyName = FName("SpaceBar") } }
M.GETUP_KEYS = GETUP_KEYS
function M.tick(dt)
    local t0 = os.clock()
    local pawn = lib.pawn()
    if st.reset_pending and pawn then
        local rp = st.reset_pending
        local at = nil
        pcall(function() local q = pawn.Mesh:GetSocketLocation(FN["pelvis"]); at = v3(q.X, q.Y, q.Z) end)
        local moved = (rp.from and at) and vlen(vsub(at, rp.from)) or -1.0
        if rp.name ~= "SimpleReset" or moved > M.RESET.far then
            st.reset_pending = nil
            log("%s: his body moved %.0f cm", rp.name, moved)
            heal_all(pawn, "back at a waypoint (" .. rp.name .. ")")
        elseif os.clock() - rp.t > M.RESET.wait then
            st.reset_pending = nil
            if M.LOG.verbose then log("%s where he was (moved %.0f cm): getting up, not a waypoint - not healed", rp.name, moved) end
        end
    end
    if pawn and not st.reset_pending then
        pcall(function() local q = pawn.Mesh:GetSocketLocation(FN["pelvis"]); st.body_at = v3(q.X, q.Y, q.Z) end)
    end
    -- (no legs to stand on, and STORROR getting him up: put down again the same frame, before he is seen to stand -
    -- "players getting bugged out by something", 2026-11-10: up and down every second)
    if st.negate and pawn then
        local N = st.negate
        local age = os.clock() - N.t
        local pk = lib.parkour(pawn)
        if not st.down or age > 1.0 then st.negate = nil
        elseif pk and N.tried == 0 and age > 0.05 then N.tried = 1; pcall(function() pk:TryGetupFromRagdoll() end)
        elseif pk and N.tried == 1 and age > 0.3 then N.tried = 2; pcall(function() pk:SimpleReset() end) end
    end
    if st.crawl_regrab and pawn then
        st.crawl_regrab = nil
        if st.keep_down and not ((keep_on() and legs_gone()) or st.bled_out) then
            st.keep_down = nil
            local pk = lib.parkour(pawn)
            if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
            st.still_until = os.clock() + M.REGRAB_STILL
            st.kept_n = (st.kept_n or 0) + 1
            if st.kept_n <= 3 or st.kept_n % 20 == 0 then log("STORROR got him up with no press: kept down (%d)", st.kept_n) end
        elseif (keep_on() and legs_gone()) or st.bled_out then
            st.keep_down = nil
            local pk = lib.parkour(pawn)
            if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
            st.still_until = os.clock() + M.REGRAB_STILL
            st.crawl_kept = (st.crawl_kept or 0) + 1
            if st.crawl_kept <= 3 or st.crawl_kept % 20 == 0 then log("no legs to stand on: kept down (%d)", st.crawl_kept) end
        end
    end
    -- (put down again after STORROR's get-up: no motion of that get-up kept - each one, every 0.6 s while he lay still, set
    -- his body spinning, and a dead body twitched: "player spins on ground", "not going limp when dead", 2026-11-11)
    -- (only his trunk's turn taken out, once: all of him held still for a quarter second after each, with STORROR trying
    -- every 0.3-0.5 s while he lay dead, froze him - arms and legs left up in the air: "hands dont fall on death they
    -- just stay floating same with legs", 2026-11-11)
    if st.still_until and pawn then
        st.still_until = nil
        pcall(function()
            for _, b in ipairs({ "pelvis", "spine_03", "spine_05" }) do
                pawn.Mesh:SetPhysicsAngularVelocityInDegrees({ X = 0.0, Y = 0.0, Z = 0.0 }, false, FN[b])
            end
        end)
    end
    if pawn then pcall(M.zero_tick, dt) end
    if not pawn then
        if st.down then down_end(nil) end
        st.down, st.up_v, st.up_p = false, nil, nil
        return
    end
    fr = { q = {}, p = {} }
    local down = is_down(pawn)
    if down ~= st.down then
        st.down = down
        if down then down_start(pawn) else down_end(pawn); st.up_p = nil; st.stand_tried = nil; st.up_t = os.clock(); st.trip = nil end
    end
    -- (the player's get-up, honoured at once: STORROR gets him up only once his body lies still, and his writhing, kicking
    -- and rocking never let it - he lay there for minutes. A fresh press of A or Space, a second or more down: STORROR's
    -- own get-up asked for straight away, as the old Euphoria mod did)
    -- (his HP gone - "1000 blood drops fall the player dies", 2026-11-10: dead, put down, kept down till a waypoint)
    if pawn and not st.bled_out and hp_on() then
        local G = _G.ARGORE
        local okh, hp = pcall(function() return G and G.hp and G.hp() end)
        -- (LIMB HP: his head's or his chest's gone is death too)
        local okd, dg = pcall(function() return G and G.limb_dead and G.limb_dead() end)
        if not okd then dg = nil end
        if okh and hp and (hp <= 0.0 or dg) then
            st.bled_out = true
            if dg and hp > 0.0 then log("his %s HP gone - dead till a waypoint", dg)
            elseif st.hp_why then log("HP gone (%s) - dead till a waypoint", st.hp_why)
            else log("bled out (%d drops of his blood) - dead till a waypoint", math.floor((G.blood_lost and G.blood_lost()) or -1)) end
            st.hp_why = nil
        end
    end
    if pawn and not menu_open() then
        local okr, er = pcall(regen_tick, pawn, dt)
        if not okr and not st.regen_err then st.regen_err = true; log("regenerating failed (%s)", tostring(er)) end
    end
    -- (the player's get-up press, seen whenever he's down: only a press gets him up - NEVER GETS UP ON HIS OWN)
    if down then
        local pc = lib.controller()
        if pc then
            for _, k in ipairs(GETUP_KEYS) do
                local okk, kv = pcall(function() return pc:IsInputKeyDown(k) end)
                if okk and kv then st.getup_press_t = os.clock(); break end
            end
        end
    end
    -- (only on the ground: a press of Space falling past a building got him up in the air, all his speed and tumble gone -
    -- "for about 3 seconds it sends him flying then all speed stops for no reason", 2026-11-11)
    if down and st.rag and st.rag.t > M.GETUP_AFTER and (st.rag.grounded or M.grav_share() <= 0.0) and not st.crawl_mode and not st.bled_out then
        local pc = lib.controller()
        local held = false
        if pc then
            for _, k in ipairs(GETUP_KEYS) do
                local okk, kv = pcall(function() return pc:IsInputKeyDown(k) end)
                if okk and kv then held = true; break end
            end
        end
        if held and not st.getup_held then
            local pk = lib.parkour(pawn)
            if pk and pcall(function() pk:TryGetupFromRagdoll() end) then log("getting up on the player's press") end
        end
        st.getup_held = held
    elseif not down then
        st.getup_held = nil
    end
    if down and st.rag then
        local rr = st.rag
        rr.spd = rr.spd or {}
        pcall(function()
            local u = pawn.Mesh:GetPhysicsLinearVelocity(FN["pelvis"])
            local now = os.clock()
            rr.spd[#rr.spd + 1] = { now, sqrt(u.X * u.X + u.Y * u.Y + u.Z * u.Z) }
            while #rr.spd > 0 and now - rr.spd[1][1] > 1.5 do table.remove(rr.spd, 1) end
        end)
        local ok, e = pcall(down_tick, pawn, st.rag, dt)
        if not ok and not st.rag.err then st.rag.err = true; log("down tick failed (%s)", tostring(e)) end
        if st.rag then M.LEDGER.finish(pawn, st.rag, dt) end
        if st.rag then M.KEEPSPIN.tick(pawn, st.rag, dt) end
        if st.rag then pcall(M.POSELOG.tick, pawn, st.rag, dt) end
        pcall(M.BLOODSPEED.tick, pawn, st.rag)
        st.rag.ms = st.rag.ms + (os.clock() - t0) * 1000.0
        st.rag.frames = st.rag.frames + 1
    elseif not down then
        -- (put somewhere by the game - a waypoint, a respawn: further than his speed takes him in a frame - healed)
        local okl, l = pcall(function() return pawn:K2_GetActorLocation() end)
        if okl and l then
            local p = v3(l.X, l.Y, l.Z)
            if st.up_p and st.up_v and vlen(vsub(p, st.up_p)) > vlen(st.up_v) * dt * 1.5 + M.DAMAGE.teleport then
                heal_all(pawn, "a teleport")
            end
            st.up_p = p
        end
        -- (an unfinished flip, a run into a wall: down he goes)
        local okt, et = pcall(trip_tick, pawn, dt)
        pcall(spin_track, pawn, dt)
        pcall(M.ANIMSPIN.track, pawn, dt)
        pcall(M.CARRY.track, pawn, dt)
        pcall(M.SLIDESND.tick, pawn, dt)
        pcall(M.GRABROLL.tick, pawn, dt)
        pcall(M.grav_tick, pawn)
        if M.GRAV.trace then pcall(M.grav_air, pawn, dt) end
        -- (WALL SLIDE off, on the RAGDOLL tab: no sliding down a wall - the moment STORROR starts its wall slide he goes
        -- down instead, at the speed he had: "add an option to turn off wall sliding and replace it will getting
        -- ragdolled", 2026-11-11. Its wall run is left as it is)
        local Mn = _G.ARMENU
        if Mn and Mn.wall_slide and not Mn.wall_slide() then
            local name = montage(pawn)
            if name:find("FallingSlide_Wall_", 1, true) then
                local v = st.up_v or v3(0.0, 0.0, 0.0)
                if trip(pawn, "a wall slide (WALL SLIDE off)", v) then log("no wall slide: down instead (%s)", name) end
            end
        end
        if not okt and not st.trip_err then st.trip_err = true; log("tripping check failed (%s)", tostring(et)) end
        -- (his injuries on his feet: hanging and bent limbs kept up; healed if KEEP INJURIES is turned off)
        local hurt_up = false
        for _, e in pairs(parts) do if e.state > 0 then hurt_up = true; break end end
        -- (bled out on his feet: down he goes, dead)
        if st.bled_out and not menu_open() and os.clock() - (st.crawl_down_t or -9.0) > 0.5 then
            st.crawl_down_t = os.clock()
            local pk = lib.parkour(pawn)
            if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
        end
        -- (no legs to stand on: down he goes, to crawl)
        if keep_on() and legs_gone() then
            if not st.crawl_mode then log("both legs gone - he crawls") end
            st.crawl_mode = true
            if os.clock() - (st.crawl_down_t or -9.0) > 0.5 then
                st.crawl_down_t = os.clock()
                local pk = lib.parkour(pawn)
                if pk then pcall(function() pk:StartRagdoll(1.0, false) end) end
            end
        end
        if keep_on() and hurt_up then
            st.limbs_t = (st.limbs_t or 0.0) - dt
            if st.limbs_t <= 0.0 then
                st.limbs_t = 0.1
                local w = limbs_want()
                -- (climbing, his arms set the pace; otherwise his legs)
                local okc, cl = pcall(climbing, pawn)
                st.jump_f = jump_factor()
                if okc and cl then w.rate = w.arms end
                pcall(limbs_set, pawn, w)
            end
            -- (a leg gone: turned on the spot by the stick)
            if st.limbs_sig and st.limbs_sig:find("|true|") then pcall(turn_in_place, pawn, dt) end
        end
        -- (his jumps, hurt or not: each frame he rises, the rise cut to f of itself - he is put back down by the rest. STORROR's
        -- jump itself left alone - its speed, built up over several frames - so its top comes exactly f as high: "jump height
        -- seems completely random. sprained leg parts should jump 2% less, broken 3.5%. severed 5%", 2026-11-10. Not a climb
        -- or a vault: those rise too, and must reach the top. Every jump logged.)
        local jf = (keep_on() and hurt_up) and (st.jump_f or 1.0) or 1.0
        local okj, ej = pcall(function()
            local cm = pawn.CharacterMovement
            local v, mode = cm.Velocity, cm.MovementMode
            local J = st.jg
            if (mode == 3 or mode == 5) and v.Z > 0.0 then
                local l = pawn:K2_GetActorLocation()
                local name = montage(pawn)
                if not J then
                    J = { f = jf, z0 = l.Z, top = l.Z, zp = l.Z, rise = 0.0, modes = tostring(mode), last = mode, frames = 0, names = {} }
                    st.jg = J
                end
                if mode ~= J.last then J.last = mode; if #J.modes < 24 then J.modes = J.modes .. "/" .. tostring(mode) end end
                if name ~= "" and not J.names[name] then J.names[name] = true; J.list = J.list and (J.list .. ", " .. name) or name end
                -- (a climb, a hang, a move on a wall: left alone, it must reach the top. A vault or a launch off an edge is a
                -- jump, cut as one - left alone, jumping beside an edge he went up as high as ever, "sometimes the cap works
                -- but other times when jumping right next to a edge the jump with injuries gets completely ignored", 2026-11-10)
                local move = name:find("Climb") or name:find("Mantle") or name:find("Wall")
                    or name:find("Hang") or name:find("Swing") or name:find("Pull")
                if move then J.move = true end
                local dz = l.Z - J.zp
                local z = l.Z
                if dz > 0.0 then
                    J.rise = J.rise + dz
                    local low = name:lower()
                    if J.f < 0.995 and not J.move and (mode == 3 or name == "" or low:find("jump", 1, true) or low:find("vault", 1, true)
                        or low:find("ledge", 1, true) or low:find("kong", 1, true)) then
                        z = l.Z - (1.0 - J.f) * dz
                        pawn:K2_SetActorLocation({ X = l.X, Y = l.Y, Z = z }, true, {}, false)
                        z = pawn:K2_GetActorLocation().Z
                        J.frames = J.frames + 1
                    end
                end
                J.zp = z
                if z > J.top then J.top = z end
            elseif J then
                jump_end(pawn, (mode == 3 or mode == 5) and "the top" or "landed")
            end
        end)
        if not okj and not st.jump_err then st.jump_err = true; log("jump cut failed (%s)", tostring(ej)) end
        if keep_on() then
            if st.stand then pcall(stand_tick, pawn, dt)
            elseif hurt_up and not st.stand_tried then
                st.stand_tried = true
                local oks, es = pcall(stand_start, pawn)
                if not oks then log("keeping his injuries on his feet failed (%s)", tostring(es)) end
            end
        elseif hurt_up or st.stand then
            heal_all(pawn, "keep injuries off")
        end
        local okf, ef = pcall(fall_tick, pawn, dt)
        if not okf and not st.fall_err then st.fall_err = true; log("falling failed (%s)", tostring(ef)) end
        -- (his speed on his feet, kept for the impact as he goes down)
        pcall(function() local v = pawn.CharacterMovement.Velocity; st.up_v = v3(v.X, v.Y, v.Z) end)
    end
    fr = nil
end

-- ------------------------------------------------------------------ for testing (the dev channel)
-- knock him down going `v` (cm/s), or blown away from a point `at` with `speed`: STORROR's own ragdoll, then the push and
-- the limbs' spin
function M.knock(v)
    local pawn = lib.pawn()
    if not pawn then return "no athlete" end
    local pk = lib.parkour(pawn)
    if not pk then return "no parkour component" end
    local kv = v and v3(v.x or v.X or 0.0, v.y or v.Y or 0.0, v.z or v.Z or 0.0) or nil
    st.knock_v, st.knock_t = kv, os.clock()
    local ok = pcall(function() pk:StartRagdoll(1.0, false) end)
    if ok and kv then st.push = { v = kv, n = 2, t = os.clock() } end
    return ok and "knocked" or "StartRagdoll failed"
end
function M.explode(dist, speed)
    local pawn = lib.pawn()
    if not pawn then return "no athlete" end
    local fwd = pawn:GetActorForwardVector()
    local v = vmul(vnorm(v3(-fwd.X, -fwd.Y, 0.35)), speed or 1500.0)
    return M.knock(v)
end
function M.heal()
    local pawn = lib.pawn()
    heal_all(pawn, "dev")
    if pawn then pcall(lim_apply, pawn.Mesh) end
    return "healed"
end
function M.state() return st, poses, lim, dis end
-- (his parts' states, for the x-ray skeleton - xray.lua)
function M.parts() return parts end
-- (dev: how far past each joint's range a pose puts it - the neutral pose and protect should be inside every range)
function M.pose_over(name)
    local pawn = lib.pawn()
    if not pawn then return "no athlete" end
    local mesh = pawn.Mesh
    local P = poses or build_poses(mesh)
    poses = P
    local L = lim_load(mesh)
    local Q = P.Qs[name or "nbp"]
    if name == "ref" then
        local get = ref_pose(mesh)
        Q = setmetatable({}, { __index = function(t, k) local r = get(k); return r and r.q end })
    end
    local out = {}
    for _, bone in ipairs(DISLOC) do
        local j = L.list[bone]
        if j then
            local a, b, tw = joint_over(mesh, j, Q)
            out[#out + 1] = string.format("%s %.0f/%.0f (tw %.0f)", bone, a, b, tw)
        end
    end
    return table.concat(out, ", ")
end
-- (dev: the poses worked out now, and what they look like: the torso frame, and each pose's limb angles)
function M.test_poses()
    local pawn = lib.pawn()
    if not pawn then return "no athlete" end
    local P, why = build_poses(pawn.Mesh)
    if not P then return tostring(why) end
    poses = P
    local F = P.F
    local out = { string.format("r %.2f %.2f %.2f | f %.2f %.2f %.2f | u %.2f %.2f %.2f", F.r.x, F.r.y, F.r.z, F.f.x, F.f.y, F.f.z, F.u.x, F.u.y, F.u.z) }
    local miss = {}
    for b in pairs(P.missing) do miss[#miss + 1] = b end
    out[#out + 1] = "missing: " .. table.concat(miss, ",")
    for name, T in pairs(P.targets) do
        local parts = {}
        for _, b in ipairs({ "lowerarm_l", "calf_l", "upperarm_l", "thigh_l", "head", "hand_l", "foot_l" }) do
            local q = T[b]
            if q then parts[#parts + 1] = string.format("%s %.0f", b, deg(2.0 * acos(min(1.0, abs(q.w))))) end
        end
        out[#out + 1] = name .. ": " .. table.concat(parts, ", ")
    end
    return table.concat(out, " || ")
end
-- (a reload of this file, the map the same: what it did to him on his feet undone first - his limbs hanging, his locks,
-- his pace - or they stayed on him with nothing left to take them off)
function M.unload()
    -- (his injuries carried over to the new copy: a reload is no healing - wiping them while the gore still showed a leg
    -- gone, he was missing it and running about as if not)
    local keep = { parts = {}, dis = {} }
    for id, e in pairs(parts) do keep.parts[id] = { state = e.state, d = e.d } end
    for k, v in pairs(dis) do keep.dis[k] = v end
    _G.AR_STASH = keep
    local pawn = lib.pawn()
    if pawn then
        pcall(stand_stop, pawn, "reload")
        pcall(limbs_set, pawn, nil)
        pcall(jump_end, pawn, nil)
    end
    pcall(M.forget)
end
function M.forget()
    if st.rag then ctl_end(st.rag) end
    st = { down = false }
    poses, lim = nil, nil
    phys = { comp = nil, addr = nil, k = -1.0 }
    dis = {}
    for _, e in pairs(parts) do e.d, e.state, e.up = 0.0, 0, 0.0 end
    limp_update()
end
M._explode = explode
-- (the push of a test knock, given to every body a frame or two into the ragdoll)
-- EASY INJURIES (the RAGDOLL tab): a fracture from 5 mph, a break from 15, a cut from 30 ("add a easy injurys option,
-- fractures at 5 mph, broken bones at 15 mph and severed limbs at 30mph", 2026-11-11), blown apart from 50 ("for easy
-- injurys 50mph explodes player"); off, M.DAMAGE_NORMAL's
M.DAMAGE_NORMAL = { dislocate_mph = M.DAMAGE.dislocate_mph, break_mph = M.DAMAGE.break_mph, sever_mph = M.DAMAGE.sever_mph,
                    explode_mph = M.DAMAGE.explode_mph }
M.DAMAGE_EASY = { dislocate_mph = 5.0, break_mph = 15.0, sever_mph = 30.0, explode_mph = 50.0 }
local function easy_set()
    local Mn = _G.ARMENU
    local easy = Mn and Mn.easy_injuries and Mn.easy_injuries()
    local T = easy and M.DAMAGE_EASY or M.DAMAGE_NORMAL
    local D = M.DAMAGE
    if D.dislocate_mph ~= T.dislocate_mph or D.break_mph ~= T.break_mph or D.sever_mph ~= T.sever_mph or D.explode_mph ~= T.explode_mph then
        D.dislocate_mph, D.break_mph, D.sever_mph, D.explode_mph = T.dislocate_mph, T.break_mph, T.sever_mph, T.explode_mph
        log("injuries from %.0f / %.0f / %.0f mph, blown apart from %.0f (%s)", T.dislocate_mph, T.break_mph, T.sever_mph, T.explode_mph, easy and "easy" or "normal")
    end
end
local tick0 = M.tick
function M.tick(dt)
    pcall(easy_set)
    tick0(dt)
    if not _G.AR_MAIN_HUD and _G.ARHUD then pcall(_G.ARHUD.tick, dt) end     -- (a main from before the HUD)
    if not _G.AR_MAIN_GORE and _G.ARGORE then
        local ok, e = pcall(_G.ARGORE.tick, dt, M.DAMAGE.gore)
        if not ok and not M.gore_err then M.gore_err = true; log("gore tick failed (%s)", tostring(e)) end
    end
    local p = st.push
    -- (a push not taken up while fresh: dropped, never given to a later fall)
    if p and os.clock() - (p.t or -99.0) > M.KNOCK_FRESH + 0.2 then st.push, p = nil, nil end
    if p and st.down then
        local pawn = lib.pawn()
        -- (all of him moved to that speed as a whole - the turn he already had kept: set on every body alike, his flip's turn,
        -- carried into the ragdoll, was wiped out, "the body stops all momentum", 2026-11-11 - the spin watch saw it go)
        if pawn then pcall(function()
            local mesh = pawn.Mesh
            local vc = M.COM and M.COM.of and M.COM.of(mesh)
            -- (only the speed it lacks: a body already going his speed - the animation's own - is left as it is)
            if vc then
                if vlen(vc) < vlen(p.v) * 0.8 then mesh:AddImpulseToAllBodiesBelow(fv(vsub(p.v, vc)), FN["pelvis"], true, true) end
            else mesh:SetAllPhysicsLinearVelocity(fv(p.v), false) end
        end) end
        p.n = p.n - 1
        if p.n <= 0 then st.push = nil end
    end
end
-- (as this copy takes over - its first frame, not as it loads: main.lua loads the new copy before the old one's unload
-- puts his injuries by, so read at load they were never there, and a reload as he got up healed him - "health getting
-- healed when standing back up", 2026-11-10 - his injuries from the one before it, and the parts torn off as the gore has
-- them)
local function restore_injuries()
    local S = _G.AR_STASH
    _G.AR_STASH = nil
    if S then
        for id, e in pairs(S.parts or {}) do if parts[id] then parts[id].state, parts[id].d = e.state, e.d end end
        for k, v in pairs(S.dis or {}) do dis[k] = v end
    end
    local G = _G.ARGORE
    if G and G.active and G.active() and G.debug and G.regions_of then
        local ok, gs = pcall(G.debug)
        if ok and gs and gs.pieces then
            for pid in pairs(gs.pieces) do
                for _, rid in ipairs(G.regions_of(pid)) do if parts[rid] then parts[rid].state = 3 end end
            end
        end
    end
    limp_update()
    local hurt = {}
    for id, e in pairs(parts) do if e.state > 0 then hurt[#hurt + 1] = id .. "=" .. M.STATES[e.state] end end
    table.sort(hurt)
    log("took over his injuries: %s", #hurt > 0 and table.concat(hurt, ", ") or "none")
end
do
    local tick1 = M.tick
    local restored = false
    function M.tick(dt)
        if not restored then
            restored = true
            local ok, e = pcall(restore_injuries)
            if not ok then log("taking over his injuries failed (%s)", tostring(e)) end
        end
        return tick1(dt)
    end
end
return M
