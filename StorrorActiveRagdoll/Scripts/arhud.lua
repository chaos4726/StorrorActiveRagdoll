-- STORROR Active Ragdoll: on the screen - a little figure of him, on the right, cut into the parts that take damage
-- (head, chest, upper and lower arms, hands, upper and lower legs, feet: "a human hud of diffrent areas that took
-- damage", 2026-11-10 - in place of the video's "Dislocated:" list), and his HP under it. Each part's colour by its
-- damage: see M.COLORS. The figure seen while any part is hurt, or he is down; the HP while the RAGDOLL tab's HP BAR is
-- on. Neither over a menu.
-- (since 2026-11-10 late, "make the hp and human damage huds better": each part a rounded, shaded shape with a rim, on a
-- dark card; a part flashes as it gets worse; the HP a panel of its own - its number, a bar that changes colour as it
-- falls, a pale trail of what was just lost, a pulse when it is low. Pictures: tools/hud_art.py)
local lib = _G.ARLIB
local M = {}
local log = lib.log

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end
local function cls(path) return StaticFindObject(path) end
local max, min = math.max, math.min

-- the parts: x, y, width, height in the figure (px), seen from behind as the camera sees him (his left on the left)
-- (tools/hud_art.py draws each part's picture to this size: change both together)
local W, H = 112, 254
M.PARTS = {
    { id = "head", x = 41, y = 0, w = 30, h = 32 },
    { id = "chest", x = 31, y = 36, w = 50, h = 86 },
    { id = "upperarm_l", x = 14, y = 38, w = 14, h = 46 },
    { id = "lowerarm_l", x = 12, y = 87, w = 14, h = 44 },
    { id = "hand_l", x = 10, y = 134, w = 17, h = 18 },
    { id = "upperarm_r", x = 84, y = 38, w = 14, h = 46 },
    { id = "lowerarm_r", x = 86, y = 87, w = 14, h = 44 },
    { id = "hand_r", x = 85, y = 134, w = 17, h = 18 },
    { id = "thigh_l", x = 32, y = 126, w = 22, h = 56 },
    { id = "calf_l", x = 33, y = 185, w = 20, h = 52 },
    { id = "foot_l", x = 28, y = 240, w = 25, h = 14 },
    { id = "thigh_r", x = 58, y = 126, w = 22, h = 56 },
    { id = "calf_r", x = 59, y = 185, w = 20, h = 52 },
    { id = "foot_r", x = 59, y = 240, w = 25, h = 14 },
}
-- (the figure's place: on the right edge, a third of the way down - clear of STORROR's trick score low on the left,
-- its next-challenge panel high on the left and the controller low on the right)
M.ANCHOR = { X = 1.0, Y = 0.36 }
M.MARGIN = 30                                 -- (px in from the screen's edge)
M.RIM = 3                                     -- (px round each part's picture for its rim)
M.PAD = 12                                    -- (the card round the figure)

-- each state's colour: healthy white, dislocated orange, broken red, severed black ("healthy white, dislocated orange,
-- broken red ... severed black", 2026-11-10); and its rim (a severed part's red, to be seen on the dark card)
M.COLORS = { [0] = { R = 0.95, G = 0.95, B = 0.95, A = 0.88 }, { R = 1.0, G = 0.55, B = 0.08, A = 0.95 },
             { R = 0.92, G = 0.08, B = 0.06, A = 0.97 }, { R = 0.03, G = 0.03, B = 0.03, A = 0.97 } }
M.RIMS = { [0] = { R = 0.0, G = 0.0, B = 0.0, A = 0.6 }, { R = 0.25, G = 0.1, B = 0.0, A = 0.7 },
           { R = 0.3, G = 0.0, B = 0.0, A = 0.75 }, { R = 0.85, G = 0.12, B = 0.1, A = 0.95 } }
M.FLASH = 0.45                                -- (s a part flashes white as it gets worse)
local function color_of(state) return M.COLORS[state or 0] or M.COLORS[0] end
local function rim_of(state) return M.RIMS[state or 0] or M.RIMS[0] end
local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local function mix(a, b, k) return { R = a.R + (b.R - a.R) * k, G = a.G + (b.G - a.G) * k, B = a.B + (b.B - a.B) * k, A = a.A + (b.A - a.A) * k } end

-- the HP panel, under the figure ("make a hp bar depending on blood drops", 2026-11-10: his HP is what is left of his
-- blood - gore.lua's hp, 1000 drops out of his wounds and he has bled out)
M.BAR = { gap = 6, h = 42, bar_h = 10, digit = 7.5,
          full = { R = 0.40, G = 0.86, B = 0.32, A = 0.96 }, half = { R = 0.98, G = 0.78, B = 0.16, A = 0.96 },
          none = { R = 0.92, G = 0.10, B = 0.07, A = 0.96 }, trail = { R = 1.0, G = 0.92, B = 0.78, A = 0.55 },
          trail_wait = 0.45, trail_speed = 0.35, low = 0.25, dead = { R = 0.95, G = 0.12, B = 0.08, A = 1.0 } }
local function hp_color(hp)
    local B = M.BAR
    if hp >= 0.5 then return mix(B.half, B.full, (hp - 0.5) / 0.5) end
    return mix(B.none, B.half, hp / 0.5)
end

-- ------------------------------------------------------------------ building
local function tex(world, name)
    local ok, t = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(world, lib.MOD_DIR .. "textures/" .. name .. ".png")
    end)
    if ok and t and t:IsValid() then return t end
    return nil
end
local function new_root(pc)
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("None"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("None"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("None"))
    tree.RootWidget = canvas
    return w, canvas
end
-- a picture on `canvas` at x, y in the figure's px (its top left the figure's), sx by sy; `t` its texture or a plain block
local OX, OY = -(30 + W), -H / 2
local function pic(canvas, t, x, y, sx, sy, col, anchored)
    local img = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("None"))
    if t then pcall(function() img:SetBrushFromTexture(t, false) end) end
    pcall(function() img:SetColorAndOpacity(col) end)
    local s = canvas:AddChildToCanvas(img)
    if anchored ~= false then
        s:SetAnchors({ Minimum = M.ANCHOR, Maximum = M.ANCHOR })
        s:SetAlignment({ X = 0.0, Y = 0.0 })
        s:SetPosition({ X = OX + x, Y = OY + y })
    else
        s:SetPosition({ X = x, Y = y })
    end
    s:SetSize({ X = sx, Y = sy })
    return img, s
end

-- (LIMB HP: each limb's HP inside it on the figure - "numbers should go inside the limbs on the human hud", 2026-11-11 -
-- its middle x, y; the part it sits in, for its colour - dark on a pale part, white on a red or black one; the digits'
-- size, smaller in his narrow arms)
-- (every part its own since 2026-11-11, "some limbs still have no hp on them": its middle, from M.PARTS; the digits' size by
-- how narrow it is; places for its number - 3 for his chest, up to 360 at a MAX HP of 1000, 2 for the rest)
M.NUM_SIZE = { head = 1.0, chest = 1.0, upperarm = 0.75, lowerarm = 0.75, hand = 0.6, thigh = 0.88, calf = 0.85, foot = 0.65 }
M.NUM_AT = {}
for _, p in ipairs(M.PARTS) do
    local kind = p.id:match("^(%a+)_") or p.id
    M.NUM_AT[p.id] = { p.x + p.w * 0.5, p.y + p.h * 0.5, p.id, M.NUM_SIZE[kind] or 0.75, (p.id == "chest") and 3 or 2 }
end
local DARK = { R = 0.06, G = 0.06, B = 0.06, A = 0.95 }
local hud = nil           -- { w, parts = { [id] = { img, rim, key, flash } }, nums = { [group] = { slots, on, n, dark } }, shown }
local function build()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return nil end
    OX = -(M.MARGIN + W)
    local w, canvas = new_root(pc)
    local P = M.PAD
    -- (each picture brought in once: many images show the same digit)
    local cache = {}
    local function tx(name)
        if cache[name] == nil then cache[name] = tex(world, name) or false end
        return cache[name] or nil
    end
    pic(canvas, tx("hud_card_fig"), -P, -P, W + 2 * P, H + 2 * P, WHITE)
    local parts = {}
    local R = M.RIM
    for _, p in ipairs(M.PARTS) do
        local t = tex(world, "hud_rim_" .. p.id)
        parts[p.id] = { rim = pic(canvas, t, p.x - R, p.y - R, p.w + 2 * R, p.h + 2 * R, rim_of(0)) }
    end
    for _, p in ipairs(M.PARTS) do
        local t = tex(world, "hud_part_" .. p.id)
        if t then parts[p.id].img = pic(canvas, t, p.x - R, p.y - R, p.w + 2 * R, p.h + 2 * R, color_of(0))
        else parts[p.id].img = pic(canvas, nil, p.x, p.y, p.w, p.h, color_of(0)) end
        parts[p.id].key = 0
    end
    local nums = {}
    for g, a in pairs(M.NUM_AT) do
        local k = a[4] or 1.0
        local slots = {}
        for slot = 1, (a[5] or 3) do
            slots[slot] = {}
            for d = 0, 9 do
                local img, sl = pic(canvas, tx("hud_digit_" .. d), a[1], a[2], 9 * k, 14 * k, WHITE)
                pcall(function() img:SetVisibility(1) end)
                slots[slot][d] = { img = img, s = sl }
            end
        end
        nums[g] = { slots = slots, at = a, on = a[3], n = -1, dark = nil, len = nil }
    end
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(42)
    log("hud: the damage figure on the screen")
    return { w = w, parts = parts, nums = nums, shown = false }
end

local bar = nil           -- { w, fill_img, fill_s, trail_s, digits = { [slot] = { [0..9] = img } }, shown, hp, trail, ... }
local function clip_box(canvas, x, y, sx, sy)
    local c = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), canvas, FName("None"))
    pcall(function() c:SetClipping(1) end)       -- (clip to its bounds: the bar shortened, not squashed)
    local s = canvas:AddChildToCanvas(c)
    s:SetAnchors({ Minimum = M.ANCHOR, Maximum = M.ANCHOR })
    s:SetAlignment({ X = 0.0, Y = 0.0 })
    s:SetPosition({ X = OX + x, Y = OY + y })
    s:SetSize({ X = sx, Y = sy })
    return c, s
end
local function build_bar()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return nil end
    OX = -(M.MARGIN + W)
    local B, P = M.BAR, M.PAD
    local w, canvas = new_root(pc)
    local y0 = H + P + B.gap
    pic(canvas, tex(world, "hud_card_hp"), -P, y0, W + 2 * P, B.h, WHITE)
    pic(canvas, tex(world, "hud_hp"), 0, y0 + 6, 24, 14, WHITE)
    -- (four places for its number, right-aligned; each a picture of every digit, one seen - the pictures held by the
    -- images, so none is let go)
    local digits = {}
    for slot = 1, 4 do
        digits[slot] = {}
        local x = W - (5 - slot) * B.digit - 1.5
        for n = 0, 9 do
            local img = pic(canvas, tex(world, "hud_digit_" .. n), x, y0 + 6, 9, 14, WHITE)
            pcall(function() img:SetVisibility(1) end)
            digits[slot][n] = img
        end
    end
    local by = y0 + 24
    pic(canvas, tex(world, "hud_track"), 0, by, W, B.bar_h, WHITE)
    local ft = tex(world, "hud_fill")
    local tc, ts = clip_box(canvas, 0, by, W, B.bar_h)
    pic(tc, ft, 0, 0, W, B.bar_h, B.trail, false)
    local fc, fs = clip_box(canvas, 0, by, W, B.bar_h)
    local fill_img = pic(fc, ft, 0, 0, W, B.bar_h, B.full, false)
    -- (DEAD, in place of his number while he is - "reflect that on the hp bar if the players dead", 2026-11-11)
    local dead_img = pic(canvas, tex(world, "hud_dead"), W - 36, y0 + 6, 36, 14, M.BAR.dead)
    pcall(function() dead_img:SetVisibility(1) end)
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(42)
    log("hud: the HP panel on the screen")
    return { w = w, fill_img = fill_img, fill_s = fs, trail_s = ts, digits = digits, dead_img = dead_img, shown = false,
             hp = -1.0, trail = 1.0, trail_hold = 0.0, num = -1, col_t = 0.0, dead = false, dead_t = 0.0 }
end

-- ------------------------------------------------------------------ each frame
local function menu_up()
    local R = _G.AR
    if R and R.menu_open then
        local ok, up = pcall(R.menu_open)
        return ok and up
    end
    return false
end
-- `n` in the places `slots` (each a picture of every digit, one seen), right-aligned
local function show_digits(slots, n)
    local s = tostring(n)
    local N = #slots
    for slot = 1, N do
        local i = #s - (N - slot)
        local want = (i >= 1) and tonumber(s:sub(i, i)) or nil
        for d, img in pairs(slots[slot]) do
            pcall(function() img:SetVisibility(d == want and 3 or 1) end)
        end
    end
end
-- a limb's HP inside it: centred on its middle, the digits moved as the number's length changes
local function num_show(nb, n)
    local a = nb.at
    local places = #nb.slots
    local txt = tostring(math.min(10 ^ places - 1, n))
    local len = #txt
    local k = a[4] or 1.0
    local w, h, sp = 9 * k, 14 * k, M.BAR.digit * k
    if nb.len ~= len then
        nb.len = len
        local x0 = a[1] - ((len - 1) * sp + w) * 0.5
        for slot = 1, places do
            for _, e in pairs(nb.slots[slot]) do
                pcall(function() e.s:SetPosition({ X = OX + x0 + (slot - 1) * sp, Y = OY + a[2] - h * 0.5 }) end)
            end
        end
    end
    for slot = 1, places do
        local want = (slot <= len) and tonumber(txt:sub(slot, slot)) or nil
        for d, e in pairs(nb.slots[slot]) do pcall(function() e.img:SetVisibility(d == want and 3 or 1) end) end
    end
end
local function set_number(b, n)
    if n == b.num then return end
    b.num = n
    show_digits(b.digits, n)
end
local function bar_tick(dt, menu)
    local Mn, G = _G.ARMENU, _G.ARGORE
    local on = not (Mn and Mn.hp_bar and not Mn.hp_bar()) and not menu
    if on and not (bar and alive(bar.w)) then
        local ok, b = pcall(build_bar)
        bar = ok and b or nil
        if not ok then log("hud: HP panel failed (%s)", tostring(b)) end
    end
    if not (bar and alive(bar.w)) then return end
    if bar.shown ~= on then
        pcall(function() bar.w:SetVisibility(on and 3 or 1) end)
        bar.shown = on
    end
    if not on then return end
    local B = M.BAR
    local hp = 1.0
    if G and G.hp then local okh, v = pcall(G.hp); if okh and v then hp = max(0.0, min(1.0, v)) end end
    -- (his HP in points: MAX HP less what he has lost)
    local pts = hp * 100.0
    if G and G.hp_points then local okp, v = pcall(G.hp_points); if okp and v then pts = v end end
    -- (dead - his head's or chest's HP gone, bled out, blown apart, his head off: DEAD for his number, the bar empty)
    local dead = false
    local R = _G.AR
    if R and R.state then
        local oks, s = pcall(R.state)
        if oks and s then dead = (s.bled_out and true) or (s.rag and s.rag.dead and true) or false end
    end
    if dead then hp = 0.0 end
    if dead ~= bar.dead then
        bar.dead = dead
        if dead then
            bar.num = -2
            for _, sl in ipairs(bar.digits) do for _, img in pairs(sl) do pcall(function() img:SetVisibility(1) end) end end
        end
        pcall(function() bar.dead_img:SetVisibility(dead and 3 or 1) end)
    end
    if dead then
        bar.dead_t = bar.dead_t + dt
        local c = M.BAR.dead
        pcall(function() bar.dead_img:SetColorAndOpacity({ R = c.R, G = c.G, B = c.B, A = 0.55 + 0.45 * (0.5 + 0.5 * math.cos(bar.dead_t * 2.0 * math.pi * 1.2)) }) end)
    else
        set_number(bar, math.max(0, math.ceil(pts - 0.001)))
    end
    -- (the trail: held a moment where it was, then down to the HP)
    if hp > bar.trail then bar.trail, bar.trail_hold = hp, 0.0 end
    if hp < bar.hp then bar.trail_hold = B.trail_wait end
    if bar.trail_hold > 0.0 then bar.trail_hold = bar.trail_hold - dt
    else bar.trail = max(hp, bar.trail - B.trail_speed * dt) end
    if math.abs(hp - bar.hp) > 0.001 then
        pcall(function() bar.fill_s:SetSize({ X = W * hp, Y = B.bar_h }) end)
    end
    pcall(function() bar.trail_s:SetSize({ X = W * bar.trail, Y = B.bar_h }) end)
    local col = hp_color(hp)
    if hp < B.low then
        bar.col_t = bar.col_t + dt
        col.A = col.A * (0.6 + 0.4 * (0.5 + 0.5 * math.cos(bar.col_t * 2.0 * math.pi * 1.6)))
    end
    pcall(function() bar.fill_img:SetColorAndOpacity(col) end)
    bar.hp = hp
end
-- ------------------------------------------------------------------ the speedometer
-- (his speed, in mph and km/h, under the HP panel - "add a speedomitor to the gore mod as well where it tracks your speed",
-- "kmh and mph", 2026-11-10: on his feet his own, down his body's. The RAGDOLL tab's SPEEDOMETER; not over a menu)
M.SPEED = { h = 30, gap = 6 }
local speedo = nil        -- { w, mph = slots, kmh = slots, shown, n1, n2 }
local function digit_slots(world, canvas, x0, y, n)
    local slots = {}
    for slot = 1, n do
        slots[slot] = {}
        for d = 0, 9 do
            local img = pic(canvas, tex(world, "hud_digit_" .. d), x0 + (slot - 1) * M.BAR.digit, y, 9, 14, WHITE)
            pcall(function() img:SetVisibility(1) end)
            slots[slot][d] = img
        end
    end
    return slots
end
local function build_speed()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return nil end
    OX = -(M.MARGIN + W)
    local P, B = M.PAD, M.BAR
    local w, canvas = new_root(pc)
    local y0 = H + P + B.gap + B.h + M.SPEED.gap
    pic(canvas, tex(world, "hud_card_speed"), -P, y0, W + 2 * P, M.SPEED.h, WHITE)
    local mph = digit_slots(world, canvas, 0, y0 + 8, 3)
    pic(canvas, tex(world, "hud_mph"), 3 * B.digit + 3, y0 + 8, 26, 14, WHITE)
    local kmh = digit_slots(world, canvas, 56, y0 + 8, 3)
    pic(canvas, tex(world, "hud_kmh"), 56 + 3 * B.digit + 3, y0 + 8, 31, 14, WHITE)
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(42)
    log("hud: the speedometer on the screen")
    return { w = w, mph = mph, kmh = kmh, shown = false, n1 = -1, n2 = -1 }
end
local function speed_tick(menu)
    local Mn = _G.ARMENU
    local on = not (Mn and Mn.speedometer and not Mn.speedometer()) and not menu
    if on and not (speedo and alive(speedo.w)) then
        local ok, b = pcall(build_speed)
        speedo = ok and b or nil
        if not ok then log("hud: speedometer failed (%s)", tostring(b)) end
    end
    if not (speedo and alive(speedo.w)) then return end
    if speedo.shown ~= on then
        pcall(function() speedo.w:SetVisibility(on and 3 or 1) end)
        speedo.shown = on
    end
    if not on then return end
    local pawn = lib.pawn()
    if not pawn then return end
    local R = _G.AR
    local down = false
    if R and R.state then local oks, s = pcall(R.state); down = oks and s and s.down or false end
    local v = nil
    pcall(function()
        if down then v = pawn.Mesh:GetPhysicsLinearVelocity(FName("pelvis")) else v = pawn:GetVelocity() end
    end)
    if not v then return end
    local cms = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    local n1 = math.min(999, math.floor(cms / 44.704 + 0.5))
    local n2 = math.min(999, math.floor(cms * 0.036 + 0.5))
    if n1 ~= speedo.n1 then speedo.n1 = n1; show_digits(speedo.mph, n1) end
    if n2 ~= speedo.n2 then speedo.n2 = n2; show_digits(speedo.kmh, n2) end
end

-- ------------------------------------------------------------------ STORROR's injury counter
-- (its bail counter - a number, the injury now and three before it - by STORROR's own sums from the impacts: its
-- "Sprain", "Fracture", "Dislocation" none of the mod's - "fix storrors injury counter, its not matching with what actual
-- injurys the player has", 2026-11-10. Its words written over while it is up: his injuries as the mod has them, newest
-- first; its number the HP he has lost. INJURY COUNTER off: moved off the screen. STORROR's own sums left running.)
M.COUNTER = { words = { [1] = "Fracture", [2] = "Broken", [3] = "Severed" }, none = "Unhurt" }
local PART_SAY = { head = "Head", chest = "Chest", upperarm_l = "L Upper Arm", lowerarm_l = "L Forearm", hand_l = "L Hand",
                   upperarm_r = "R Upper Arm", lowerarm_r = "R Forearm", hand_r = "R Hand", thigh_l = "L Thigh", calf_l = "L Shin",
                   foot_l = "L Foot", thigh_r = "R Thigh", calf_r = "R Shin", foot_r = "R Foot" }
local hurts = { list = {}, last = {} }      -- (each part's state as last seen; his hurts as they came, newest last)
local function track_hurts(dmg)
    local new = {}
    for _, p in ipairs(M.PARTS) do
        local s = (dmg[p.id] and dmg[p.id].state) or 0
        local was = hurts.last[p.id] or 0
        if s ~= was then
            hurts.last[p.id] = s
            if s > was then new[#new + 1] = { id = p.id, state = s } end
        end
    end
    if #new == 0 and next(hurts.list) == nil then return end
    -- (a cut taking several parts at once: the part it was cut at - the first of them, in the figure's order - alone)
    local cut = false
    for _, h in ipairs(new) do
        if h.state < 3 or not cut then hurts.list[#hurts.list + 1] = h end
        if h.state == 3 then cut = true end
    end
    -- (a hurt made worse, or healed: its old line goes)
    local keep = {}
    for _, h in ipairs(hurts.list) do if hurts.last[h.id] == h.state then keep[#keep + 1] = h end end
    hurts.list = keep
end
local function hurt_say(h)
    if not h then return "" end
    return (M.COUNTER.words[h.state] or "Hurt") .. " " .. (PART_SAY[h.id] or h.id)
end
local BAIL_CLASS = nil
local counter = { off = nil, wrote = nil }
local function counter_frame()
    local pawn = lib.pawn()
    if not pawn then return end
    if not (BAIL_CLASS and BAIL_CLASS:IsValid()) then BAIL_CLASS = StaticFindObject("/Script/SPP.BailComponent") end
    if not BAIL_CLASS then return end
    local bc = nil
    pcall(function() bc = pawn:GetComponentByClass(BAIL_CLASS) end)
    if not (bc and bc:IsValid()) then return end
    local w = nil
    pcall(function() w = bc.BailModeWidget end)
    if not (w and w:IsValid()) then return end
    local Mn = _G.ARMENU
    local off = Mn and Mn.injury_counter and not Mn.injury_counter()
    if off ~= counter.off then
        counter.off = off
        pcall(function() w:SetRenderTranslation({ X = 0.0, Y = off and -6000.0 or 0.0 }) end)
    end
    if off then return end
    local vis = false
    pcall(function() vis = w:IsVisible() end)
    if not vis then counter.wrote = nil; return end
    local G = _G.ARGORE
    local lost = 0.0
    if G and G.hp_lost then local okl, v = pcall(G.hp_lost); if okl and v then lost = v end end
    local n = #hurts.list
    local total = string.format("%d", math.floor(lost + 0.5))
    -- (written again only when STORROR has written its own over it, or his hurts have changed)
    local now_total = nil
    pcall(function() now_total = w.TotalDamageTaken:GetText():ToString() end)
    local sig = total .. "|" .. n .. "|" .. hurt_say(hurts.list[n])
    if counter.wrote == sig and now_total == total then return end
    counter.wrote = sig
    local texts = { TotalDamageTaken = total, CurrentInjuryType = (n > 0) and hurt_say(hurts.list[n]) or M.COUNTER.none,
                    PastInjuryType1 = hurt_say(hurts.list[n - 1]), PastInjuryType2 = hurt_say(hurts.list[n - 2]),
                    PastInjuryType3 = hurt_say(hurts.list[n - 3]) }
    for k, v in pairs(texts) do pcall(function() w[k]:SetText(FText(v)) end) end
end

local write_t = 0.0
function M.tick(dt)
    dt = dt or 0.016
    do
        local R = _G.AR
        if R and R.damage then
            local ok, d = pcall(R.damage)
            if ok and d then pcall(track_hurts, d) end
        end
        local okc, ec = pcall(counter_frame)
        if not okc and not M.counter_err then M.counter_err = true; log("hud: injury counter failed (%s)", tostring(ec)) end
    end
    write_t = write_t - dt
    if write_t > 0.0 then return end
    local step = 0.05 - write_t
    write_t = 0.05
    local menu = menu_up()
    local okb, eb = pcall(bar_tick, step, menu)
    if not okb and not M.bar_err then M.bar_err = true; log("hud: HP panel tick failed (%s)", tostring(eb)) end
    local oks, es = pcall(speed_tick, menu)
    if not oks and not M.speed_err then M.speed_err = true; log("hud: speedometer tick failed (%s)", tostring(es)) end
    local R = _G.AR
    local dmg, down = {}, false
    if R and R.damage then
        local ok, d, dn = pcall(R.damage)
        if ok and d then dmg, down = d, dn end
    end
    local show = down
    for _, v in pairs(dmg) do if (v.state or 0) > 0 then show = true; break end end
    -- (LIMB HP: each limb's HP; the figure up while any is down)
    local G = _G.ARGORE
    local LH = nil
    if G and G.limb_hp then local okl, v = pcall(G.limb_hp); if okl then LH = v end end
    if LH then for _, v in pairs(LH) do if v[1] < v[2] - 0.05 then show = true; break end end end
    if menu then show = false end
    local Mn = _G.ARMENU
    if Mn and Mn.damage_hud and not Mn.damage_hud() then show = false end
    if show and not (hud and alive(hud.w)) then
        local ok, h = pcall(build)
        hud = ok and h or nil
        if not ok then log("hud failed (%s)", tostring(h)) end
    end
    if not (hud and alive(hud.w)) then return end
    if hud.shown ~= show then
        pcall(function() hud.w:SetVisibility(show and 3 or 1) end)       -- (seen, never hit; or collapsed)
        hud.shown = show
    end
    if not show then return end
    for id, part in pairs(hud.parts) do
        local state = (dmg[id] and dmg[id].state) or 0
        if state ~= part.key then
            if state > part.key then part.flash = M.FLASH end
            part.key = state
            pcall(function() part.rim:SetColorAndOpacity(rim_of(state)) end)
            if not part.flash then pcall(function() part.img:SetColorAndOpacity(color_of(state)) end) end
        end
        if part.flash then
            part.flash = part.flash - step
            local k = 1.0 - max(0.0, part.flash) / M.FLASH
            pcall(function() part.img:SetColorAndOpacity(mix(WHITE, color_of(state), k)) end)
            if part.flash <= 0.0 then part.flash = nil end
        end
    end
    for g, nb in pairs(hud.nums or {}) do
        local n = -1
        if LH and LH[g] then n = math.max(0, math.ceil(LH[g][1] - 0.001)) end
        if n ~= nb.n then
            nb.n = n
            if n < 0 then
                for _, sl in ipairs(nb.slots) do for _, e in pairs(sl) do pcall(function() e.img:SetVisibility(1) end) end end
            else num_show(nb, n) end
        end
        local sv = (nb.on and dmg[nb.on] and dmg[nb.on].state) or 0
        local dark = nb.on ~= nil and sv <= 1
        if dark ~= nb.dark then
            nb.dark = dark
            for _, sl in ipairs(nb.slots) do for _, e in pairs(sl) do pcall(function() e.img:SetColorAndOpacity(dark and DARK or WHITE) end) end end
        end
    end
end

function M.dislocated() end     -- (the old list's call: the figure reads the damage itself)
function M.forget() hud = nil; bar = nil; speedo = nil end
-- (a reload of this file: its figure taken off the screen first - the map is the same, so the widget still lives)
function M.unload()
    if hud and alive(hud.w) then pcall(function() hud.w:RemoveFromParent() end) end
    if bar and alive(bar.w) then pcall(function() bar.w:RemoveFromParent() end) end
    if speedo and alive(speedo.w) then pcall(function() speedo.w:RemoveFromParent() end) end
    hud, bar, speedo = nil, nil, nil
end
return M
