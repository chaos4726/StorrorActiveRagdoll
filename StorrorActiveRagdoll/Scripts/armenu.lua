-- STORROR Active Ragdoll: its tab on STORROR's menu, RAGDOLL, next to the first person mod's FIRST PERSON ("add a new tab
-- to the menu next to first person and in it put keep injuries", 2026-11-10), and its settings (settings.txt).
--
-- Made the way the first person mod (StorrorFirstPerson's fpmenu.lua and fpsettings.lua) makes its tab, after what that
-- cost to learn:
--   * the tab goes on the list every menu bar is copied from (MenuPresenterBP's MenuTabBar's Tabs), so STORROR makes it
--     itself on every bar, as its own - its icon, its name, its place for LT/RT. (Put on each bar from outside -
--     RegisterTab - every icon went off the row, LT/RT turned about, and the game crashed as the menu shut.)
--   * its page is one of STORROR's Camera pages, the page's own rows put away; ours a row of the page's slider kind made
--     into a switch (a two-step slider, unseen, with a switch drawn over it from copies of CAMERA INVERT Y's pieces, and
--     an unseen button over that for clicks) - what the player does to a switch of the game's own never reaches a mod.
--   * no widget of a menu kept from one look to the next, nor once the menu is shut: STORROR makes a new page each time a
--     tab is shown and frees the old, and touching one freed crashed the game.
--   * ours goes before FIRST PERSON (or before SETTINGS, without it): the first person mod takes the LAST Camera page on
--     a bar for its own, this the first, so neither puts its rows on the other's.
local lib = _G.ARLIB
local log = lib.log
local M = {}

local TAB_ID, TAB_TITLE = "ActiveRagdoll", "RAGDOLL"
local BEFORE = { "FirstPerson", "Settings" }
local TEMPLATE = "/SPP/UI/PauseMenu/MenuPresenterBP.MenuPresenterBP_C:WidgetTree.MenuTabBar"
local PAGE_CLASS = "/SPP/UI/PauseMenu/CameraMenu/SPPCameraSettingsWidgetBP.SPPCameraSettingsWidgetBP_C"
local PAGE_NAME = "SPPCameraSettingsWidgetBP_C"
M.icon_file = lib.MOD_DIR .. "ui\\ragdoll_icon.png"

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- ------------------------------------------------------------------ the settings (settings.txt: "key = value" lines)
local SETTINGS = lib.MOD_DIR .. "settings.txt"
-- (the player's own settings as they had them, the mod's start - "I also want the mod to launch with the options I currently
-- have on", 2026-11-11)
local DEFAULTS = { keep_injuries = 1, realistic_falls = 0, fall_ft = 20, blood_max = 3000,
                   bleed_forever = 0, live_ragdoll = 1, hp_bar = 1, hp_max = 100, damage_hud = 1, injury_counter = 1,
                   regeneration = 0.25, speedometer = 1, limb_slowness = 1, limb_hp = 1, easy_injuries = 0, explode = 0,
                   wall_slide = 0, run_into_walls = 1, newtons_law = 1, no_explosions = 0, rolls_negate = 0, setting_info = 1,
                   xray_breaks = 0, xray_body = 0, severed_limbs = 1, bones_out = 1, bleeding = 1, xray_always = 0,
                   remove_player = 0, scaling_damage = 1, damage_on_feet = 1, gravity = 100 }
local values = {}
local function load_settings()
    for k, v in pairs(DEFAULTS) do values[k] = v end
    local f = io.open(SETTINGS, "r")
    if not f then return end
    local seen = {}
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([%-%d%.]+)")
        if k and tonumber(v) then values[k] = tonumber(v); seen[k] = true end
    end
    f:close()
    -- (ZERO GRAVITY and MOON GRAVITY saved as switches before the GRAVITY slider: its place from them)
    if not seen.gravity then
        if (values.zero_gravity or 0) >= 0.5 then values.gravity = 0
        elseif (values.moon_gravity or 0) >= 0.5 then values.gravity = 100.0 / 6.0 end
    end
    values.zero_gravity, values.moon_gravity = nil, nil
    -- (20 FT FALLS, 40 FT FALLS, 60 FT FALLS saved as switches before the FALL HEIGHT slider: its place from them - none
    -- on, OFF)
    if not seen.fall_ft and (seen.falls_20 or seen.falls_40 or seen.falls_60) then
        if (values.falls_60 or 0) >= 0.5 then values.fall_ft = 60
        elseif (values.falls_40 or 0) >= 0.5 then values.fall_ft = 40
        elseif (values.falls_20 or 0) >= 0.5 then values.fall_ft = 20
        else values.fall_ft = 0 end
    end
    values.falls_20, values.falls_40, values.falls_60 = nil, nil, nil
end
local function save_settings()
    local f = io.open(SETTINGS, "w")
    if not f then return end
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(string.format("%s = %s\n", k, tostring(values[k]))) end
    f:close()
end
load_settings()
function M.num(k) return values[k] or DEFAULTS[k] or 0 end
function M.set(k, v) values[k] = v; save_settings(); log("setting: %s = %s", k, tostring(v)) end
function M.keep_injuries() return M.num("keep_injuries") >= 0.5 end
-- (REALISTIC FALLS - down from a 20 ft drop, and on running into things, "add a setting in the gore mod for realistic falls,
-- 20ft drop and ragdolling when running into surfaces" - its switch taken off the tab: "remove the realistic falls in
-- settings", 2026-11-10. Running into things always on; the falls by the height switches alone.)
function M.realistic_falls() return true end
-- (FALL HEIGHT, a slider: how high a fall puts him down as he lands, 5 to 500 ft - "ykw also make a fall slider instead of
-- the 20 40 60 ft", 2026-11-11; it was three switches, 20 / 40 / 60 FT FALLS, "I want to add a 40 foot and 60 foot ragdoll
-- option in gore mod", "and 20ft", 2026-11-10. 20 ft to start with; OFF, no fall puts him down.) The height in ft, or nil.
function M.fall_ft()
    local ft = M.num("fall_ft")
    if ft <= 0 then return nil end
    return ft
end
-- (BLOOD STAIN LIMIT: how many splats of blood lie about before the oldest go - "in setting make a slider for particle
-- limit, so how many bloodstains there can be before despawning", 2026-11-10)
function M.blood_max() return M.num("blood_max") end
-- (BLEED FOREVER: his cuts and open breaks bleed on for as long as they are there, not five minutes - "in settings add a
-- bleed forever option", 2026-11-10; a stump bleeds two minutes otherwise, a broken bone's wound 30 s)
function M.bleed_forever() return M.num("bleed_forever") >= 0.5 end
-- (LIVE RAGDOLL: on, he moves of his own while down - holds his hurts, kicks, curls up, tries to get up; off, he lies as
-- STORROR's own ragdoll would, limp - "also add a switch to turn live ragdolls on and off", 2026-11-10)
function M.live_ragdoll() return M.num("live_ragdoll") >= 0.5 end
-- (HP BAR: his HP by the blood he has lost, a bar under the damage figure; at none he has bled out, dead - "make a hp bar
-- depending on blood drops", "then add hp bar to settings", 2026-11-10. Off: no bar, no bleeding out)
function M.hp_bar() return M.num("hp_bar") >= 0.5 end
-- (MAX HP: how much HP he has, 10 to 1000 - "add a hp slide up to 1000 hp", 2026-11-10. A drop of his blood is 0.1 HP, a
-- fracture 3, a break 5, a cut 10)
function M.hp_max() return M.num("hp_max") end
-- (DAMAGE HUD: the figure of him by his injuries; INJURY COUNTER: STORROR's own bail counter, showing his injuries as the
-- mod has them - "add hud options to turn all of this stuff", 2026-11-10)
function M.damage_hud() return M.num("damage_hud") >= 0.5 end
-- (REGENERATION: HP healed a second, 0.25, 0.5, 1 to 100, off at 0; his fractures and breaks mended as it goes, a part cut off never -
-- "1 hp healed a second up to 100hp a second", "cant regenerate severed limbs", 2026-11-10)
function M.regeneration() return M.num("regeneration") end
function M.injury_counter() return M.num("injury_counter") >= 0.5 end
-- (SPEEDOMETER: his speed in mph and km/h under the HP panel - "add a speedomitor", "kmh and mph", 2026-11-10)
function M.speedometer() return M.num("speedometer") >= 0.5 end
-- (LIMB SLOWNESS: his hurt limbs slow him on his feet - off, they don't: "add an option for limb damage slowness",
-- 2026-11-10)
function M.limb_slowness() return M.num("limb_slowness") >= 0.5 end
-- (LIMB HP: his MAX HP split over his head, chest, arms and legs as Tarkov does - each its own, his head's or chest's gone
-- dead; healed one limb at a time, broken before fractured - "each limb should have its own seperate hp", "or a switch
-- actually", 2026-11-10)
function M.limb_hp() return M.num("limb_hp") >= 0.5 end
-- (EASY INJURIES: a fracture from 5 mph, a break from 15, a cut from 30 - "add a easy injurys option", 2026-11-11)
function M.easy_injuries() return M.num("easy_injuries") >= 0.5 end
-- (EXPLODE: any injury blows him apart - "add another option to the menu called explode. The player just explodes on any
-- injury", 2026-11-11)
function M.explode_mode() return M.num("explode") >= 0.5 end
-- (NO EXPLOSIONS: never blown apart - "add an option called no expolsions", 2026-11-11)
function M.no_explosions() return M.num("no_explosions") >= 0.5 end
-- (GRABS AT ANY SPEED, ROLLS NEGATE RAGDOLLS - "add two more options, grabs at any speed so you'll always grab ledges and
-- rolls always negate ragdolls", 2026-11-11)
function M.rolls_negate() return M.num("rolls_negate") >= 0.5 end
-- (WALL SLIDE: STORROR's sliding down a wall; off, he ragdolls the moment it starts - "add an option to turn off wall
-- sliding and replace it will getting ragdolled", 2026-11-11)
function M.wall_slide() return M.num("wall_slide") >= 0.5 end
-- (RUN INTO WALLS: running into a wall or an object puts him down; off, it doesn't - "add another switch for ragdolling
-- when running into objects", 2026-11-11)
function M.run_into_walls() return M.num("run_into_walls") >= 0.5 end
-- (NEWTONS LAW: his spin carried into the ragdoll and held through the air, and falls with no air's drag - faster and
-- faster till 400 mph; off, the engine's own spin and the drag toward 120 mph - "make the fall speed cap out at 400mph.
-- combine the 400mph and normal spinning in the settings and call it newtons law", 2026-11-11)
function M.newtons_law() return M.num("newtons_law") >= 0.5 end
-- (SETTING INFO: the box explaining the row picked, on or off - "add a switch at the bottom of the menu", 2026-11-11)
function M.setting_info() return M.num("setting_info") >= 0.5 end
-- (X-RAY ON BREAKS, X-RAY BODY: his skeleton seen through him - xray.lua; "skate 3 skeleton", 2026-11-11)
function M.xray_breaks() return M.num("xray_breaks") >= 0.5 end
-- (SEVERED LIMBS, BONES STICKING OUT, BLEEDING: off, no limb is ever cut off (nor is he blown apart); a break never shows
-- its bone; he never bleeds - "add a severed limb option to turn off severed limbs, and a broken bone option to turn off
-- bones sticking out and, blood player doesnt bleed option", 2026-11-11)
function M.severed_limbs() return M.num("severed_limbs") >= 0.5 end
function M.bones_out() return M.num("bones_out") >= 0.5 end
function M.bleeding() return M.num("bleeding") >= 0.5 end
function M.xray_body() return M.num("xray_body") >= 0.5 end
-- (X-RAY ALWAYS ON: his skeleton seen all the time, on his feet too; REMOVE PLAYER: his body hidden whenever his skeleton
-- shows - "add an xray always on option and add a remove player option", 2026-11-11)
function M.xray_always() return M.num("xray_always") >= 0.5 end
-- (SCALING DAMAGE: a part already hurt gets worse with every real hit, whatever its speed - "if a body part is red with 0
-- health the next state is dismemberment no matter the fall height. do this for the rest of the body parts as well and
-- add a setting", 2026-11-11)
function M.scaling_damage() return M.num("scaling_damage") >= 0.5 end
-- (GRAVITY, a slider: the world's gravity - on his feet and ragdolled, his parts, blood, loose things - in % of STORROR's
-- own, 0 to 300 - "can you actually make a gravity slider?", 2026-11-11. MOON GRAVITY - "and a moon gravity option" - kept
-- as a mark on it: on puts it at the moon's 17%, off back at 100%. (ZERO GRAVITY's switch taken off - "actually you can
-- remove zero gravity", 2026-11-11 - the slider's 0% is the same)
M.MOON_PCT = 100.0 / 6.0
function M.gravity_share() return math.max(0.0, M.num("gravity")) / 100.0 end
function M.moon_gravity() return math.abs(M.num("gravity") - M.MOON_PCT) < 0.05 end
function M.pick_moon(on) M.set("gravity", on and M.MOON_PCT or 100) end
-- (NON-RAGDOLL DAMAGE (was DAMAGE ON FEET: "call it something else", 2026-11-11): hurt while not a ragdoll - his legs by a landing on his feet from a height - "add another option for
-- damage when not ragdolled", 2026-11-11)
function M.damage_on_feet() return M.num("damage_on_feet") >= 0.5 end
function M.remove_player() return M.num("remove_player") >= 0.5 end

-- the rows on the tab's page
local ROWS = {
    { label = "LIVE RAGDOLL", switch = true,
      get = function() return M.live_ragdoll() end,
      set = function(on) M.set("live_ragdoll", on and 1 or 0) end },
    { label = "NEWTONS LAW", switch = true,
      get = function() return M.newtons_law() end,
      set = function(on) M.set("newtons_law", on and 1 or 0) end },
    { label = "KEEP INJURIES", switch = true,
      get = function() return M.keep_injuries() end,
      set = function(on) M.set("keep_injuries", on and 1 or 0) end },
    { label = "EASY INJURIES", switch = true,
      get = function() return M.easy_injuries() end,
      set = function(on) M.set("easy_injuries", on and 1 or 0) end },
    { label = "EXPLODE", switch = true,
      get = function() return M.explode_mode() end,
      set = function(on) M.set("explode", on and 1 or 0) end },
    { label = "NO EXPLOSIONS", switch = true,
      get = function() return M.no_explosions() end,
      set = function(on) M.set("no_explosions", on and 1 or 0) end },
    { label = "ROLLS NEGATE RAGDOLLS", switch = true,
      get = function() return M.rolls_negate() end,
      set = function(on) M.set("rolls_negate", on and 1 or 0) end },
    { label = "WALL SLIDE", switch = true,
      get = function() return M.wall_slide() end,
      set = function(on) M.set("wall_slide", on and 1 or 0) end },
    { label = "RUN INTO WALLS", switch = true,
      get = function() return M.run_into_walls() end,
      set = function(on) M.set("run_into_walls", on and 1 or 0) end },
    { label = "FALL HEIGHT", slider = true, min = 0, max = 500, step = 5,
      -- (OFF, every 5 ft to 200, then 250, 300, 400, 500)
      values = (function()
          local t = { 0 }
          for i = 1, 40 do t[#t + 1] = i * 5 end
          for _, x in ipairs({ 250, 300, 400, 500 }) do t[#t + 1] = x end
          return t
      end)(),
      get = function() return M.num("fall_ft") end,
      set = function(v) M.set("fall_ft", v) end,
      fmt = function(v)
          if v <= 0 then return "OFF" end
          return string.format("%d FT", math.floor(v + 0.5))
      end },
    { label = "BLEED FOREVER", switch = true,
      get = function() return M.bleed_forever() end,
      set = function(on) M.set("bleed_forever", on and 1 or 0) end },
    { label = "HP BAR", switch = true,
      get = function() return M.hp_bar() end,
      set = function(on) M.set("hp_bar", on and 1 or 0) end },
    { label = "MAX HP", slider = true, min = 10, max = 1000, step = 10,
      get = function() return M.hp_max() end,
      set = function(v) M.set("hp_max", v) end,
      fmt = function(v) return string.format("%d", v) end },
    { label = "TARKOV DAMAGE", switch = true,      -- (was LIMB HP: "rename limb damage tarkov damage", 2026-11-11)
      get = function() return M.limb_hp() end,
      set = function(on) M.set("limb_hp", on and 1 or 0) end },
    { label = "REGENERATION", slider = true, min = 0, max = 100, step = 1,
      values = (function() local t = { 0, 0.25, 0.5 }; for i = 1, 100 do t[#t + 1] = i end; return t end)(),
      get = function() return M.regeneration() end,
      set = function(v) M.set("regeneration", v) end,
      fmt = function(v)
          if v <= 0.0 then return "OFF" end
          if v < 1.0 then return string.format("%.2f HP/S", v) end
          return string.format("%d HP/S", math.floor(v + 0.5))
      end },
    { label = "DAMAGE HUD", switch = true,
      get = function() return M.damage_hud() end,
      set = function(on) M.set("damage_hud", on and 1 or 0) end },
    { label = "INJURY COUNTER", switch = true,
      get = function() return M.injury_counter() end,
      set = function(on) M.set("injury_counter", on and 1 or 0) end },
    { label = "SPEEDOMETER", switch = true,
      get = function() return M.speedometer() end,
      set = function(on) M.set("speedometer", on and 1 or 0) end },
    { label = "LIMB SLOWNESS", switch = true,
      get = function() return M.limb_slowness() end,
      set = function(on) M.set("limb_slowness", on and 1 or 0) end },
    { label = "BLOOD STAIN LIMIT", slider = true, min = 1000, max = 1000000, step = 1000,
      -- (0, 100, 250, 500, 750 below its 1000s - "make blood stain limit have a 100 250 500 750", "oh and 0", 2026-11-11)
      values = (function() local t = { 0, 100, 250, 500, 750 }; for i = 1, 1000 do t[#t + 1] = i * 1000 end; return t end)(),
      get = function() return M.blood_max() end,
      set = function(v) M.set("blood_max", v) end,
      fmt = function(v) return string.format("%d", v) end },
}
ROWS[#ROWS + 1] = { label = "GRAVITY", slider = true, min = 0, max = 300, step = 5,
    -- (every 5%, and the moon's 17%, Mars' 38% and Jupiter's 253% among them)
    values = (function()
        local t = {}
        for i = 0, 60 do t[#t + 1] = i * 5 end
        for _, x in ipairs({ 100.0 / 6.0, 38, 253 }) do t[#t + 1] = x end
        table.sort(t)
        return t
    end)(),
    get = function() return M.num("gravity") end,
    set = function(v) M.set("gravity", v) end,
    fmt = function(v) return string.format("%d%%", math.floor(v + 0.5)) end }
ROWS[#ROWS + 1] = { label = "MOON GRAVITY", switch = true,
    get = function() return M.moon_gravity() end,
    set = function(on) M.pick_moon(on) end }
ROWS[#ROWS + 1] = { label = "SCALING DAMAGE", switch = true,
    get = function() return M.scaling_damage() end,
    set = function(on) M.set("scaling_damage", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "NON-RAGDOLL DAMAGE", switch = true,
    get = function() return M.damage_on_feet() end,
    set = function(on) M.set("damage_on_feet", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "SEVERED LIMBS", switch = true,
    get = function() return M.severed_limbs() end,
    set = function(on) M.set("severed_limbs", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "BONES STICKING OUT", switch = true,
    get = function() return M.bones_out() end,
    set = function(on) M.set("bones_out", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "BLEEDING", switch = true,
    get = function() return M.bleeding() end,
    set = function(on) M.set("bleeding", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "X-RAY ON BREAKS", switch = true,
    get = function() return M.xray_breaks() end,
    set = function(on) M.set("xray_breaks", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "X-RAY BODY", switch = true,
    get = function() return M.xray_body() end,
    set = function(on) M.set("xray_body", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "X-RAY ALWAYS ON", switch = true,
    get = function() return M.xray_always() end,
    set = function(on) M.set("xray_always", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "REMOVE PLAYER", switch = true,
    get = function() return M.remove_player() end,
    set = function(on) M.set("remove_player", on and 1 or 0) end }
ROWS[#ROWS + 1] = { label = "SETTING INFO", switch = true,
    get = function() return M.setting_info() end,
    set = function(on) M.set("setting_info", on and 1 or 0) end }
-- (the rows grouped by topic - "organize the menu", 2026-11-11: his ragdoll and moves, injuries and gore, falls, HP, the
-- HUD; SETTING INFO last)
-- (GRABS AT ANY SPEED taken off the tab, and headings put over each group - "remove grabs at any speed in settings also
-- organize ragdoll menu", 2026-11-11)
for _, h in ipairs({ "[RAGDOLL]", "[GRAVITY]", "[FALLS]", "[INJURIES]", "[GORE]", "[X-RAY]", "[HEALTH]", "[HUD]", "[HELP]" }) do
    ROWS[#ROWS + 1] = { label = h, header = true }
end
M.ORDER = {
    "[RAGDOLL]", "LIVE RAGDOLL", "NEWTONS LAW", "ROLLS NEGATE RAGDOLLS", "WALL SLIDE", "RUN INTO WALLS",
    "[GRAVITY]", "GRAVITY", "MOON GRAVITY",
    "[FALLS]", "FALL HEIGHT",
    "[INJURIES]", "KEEP INJURIES", "EASY INJURIES", "SCALING DAMAGE", "NON-RAGDOLL DAMAGE", "TARKOV DAMAGE", "LIMB SLOWNESS", "BLEED FOREVER",
    "[GORE]", "SEVERED LIMBS", "BONES STICKING OUT", "BLEEDING", "EXPLODE", "NO EXPLOSIONS", "BLOOD STAIN LIMIT",
    "[X-RAY]", "X-RAY ON BREAKS", "X-RAY BODY", "X-RAY ALWAYS ON", "REMOVE PLAYER",
    "[HEALTH]", "HP BAR", "MAX HP", "REGENERATION",
    "[HUD]", "DAMAGE HUD", "INJURY COUNTER", "SPEEDOMETER",
    "[HELP]", "SETTING INFO",
}
do
    local at = {}
    for i, l in ipairs(M.ORDER) do at[l] = i end
    for i, r in ipairs(ROWS) do r.was = i end
    table.sort(ROWS, function(a, b)
        local x, y = at[a.label] or (900 + a.was), at[b.label] or (900 + b.was)
        return x < y
    end)
end

-- ------------------------------------------------------------------ the tab on the template's list
local check_t, look_t = 0.0, 0.0
local patched, failed = false, false

local function ids_on(bar)
    local t = {}
    pcall(function()
        local tabs = bar.Tabs
        local n = #tabs
        for i = 1, n do t[i] = tabs[i].Name:ToString() end
    end)
    return t
end

local function patch(tmpl)
    local ids = ids_on(tmpl)
    for _, id in ipairs(ids) do if id == TAB_ID then return "there" end end
    local at = nil
    for _, b in ipairs(BEFORE) do
        for i, id in ipairs(ids) do if id == b then at = i end end
        if at then break end
    end
    if not at then return "no place on the list (" .. table.concat(ids, ",") .. ")" end
    local cls = StaticFindObject(PAGE_CLASS)
    if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
    if not alive(cls) then return "no page class" end
    local tex = nil
    pcall(function()
        tex = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary"):ImportFileAsTexture2D(lib.world(), M.icon_file)
    end)
    if not alive(tex) then return "no icon" end
    local n = #ids
    local tabs = tmpl.Tabs
    -- (one place more, alone: nothing of the array held while it may move)
    tabs[n + 1] = nil
    tabs = tmpl.Tabs
    if #tabs ~= n + 1 then return "the list did not grow" end
    for i = n, at, -1 do
        local list = tmpl.Tabs
        list[i + 1] = list[i]
    end
    local list = tmpl.Tabs
    local e = list[at]
    e.Name = FName(TAB_ID)
    e.Title = FText(TAB_TITLE)
    e.ContentClass = cls
    e.Icon = tex
    return "added: " .. table.concat(ids_on(tmpl), ",")
end

-- our page on a bar: the FIRST Camera page among its pages (the first person mod's is the last)
local function our_page(bar)
    local found = nil
    pcall(function()
        local sw = bar:GetLinkedSwitcher()
        for i = 0, sw:GetChildrenCount() - 1 do
            local c = sw:GetChildAt(i)
            if not found and alive(c) and c:GetClass():GetFName():ToString() == PAGE_NAME then found = c end
        end
    end)
    return found
end

-- ------------------------------------------------------------------ our rows
local THUMB_ON = 40.5
local HOLD = 0.6
local rows = {}                         -- by address: { spec, g = the switch drawn (true till drawn), name }
local live = {}                         -- watched: { row, page, page_addr, was_pressed, last, flip_t }
local tried = {}
local PANEL = StaticFindObject("/Script/UMG.PanelWidget")

local function part(page, name)
    local w = nil
    pcall(function() w = page[name] end)
    if alive(w) then return w end
    return nil
end
local function holder(row, child)
    local want = child:GetAddress()
    local found = nil
    local function walk(w, depth)
        if found or depth > 10 or not alive(w) or not w:IsA(PANEL) then return end
        local n = 0
        pcall(function() n = w:GetChildrenCount() end)
        for i = 0, n - 1 do
            local c = nil
            pcall(function() c = w:GetChildAt(i) end)
            if alive(c) then
                if c:GetAddress() == want then found = w; return end
                walk(c, depth + 1)
            end
        end
    end
    local root = nil
    pcall(function() root = row.WidgetTree.RootWidget end)
    walk(root, 0)
    return found
end
local function build_graphic(row, real)
    if not (alive(real.ToggleTrack) and alive(real.ToggleThumb)) then return nil end
    local ov = holder(row, row.Slider)
    if not (ov and ov:GetClass():GetFName():ToString() == "Overlay") then return "failed" end
    local tree = row.WidgetTree
    local function copy(src) return StaticConstructObject(src:GetClass(), tree, FName("None"), 0, 0, false, false, src) end
    local function fresh(path) return StaticConstructObject(StaticFindObject(path), tree, FName("None"), 0, 0, false, false, nil) end
    local function slot_like(dst, src)
        pcall(function() dst:SetPadding(src.Padding) end)
        pcall(function() dst:SetHorizontalAlignment(src.HorizontalAlignment) end)
        pcall(function() dst:SetVerticalAlignment(src.VerticalAlignment) end)
    end
    local g = {}
    local w, h = real.Toggle_TrackWidth or 67.0, real.Toggle_TrackHeight or 32.0
    g.outer = fresh("/Script/UMG.SizeBox")
    g.outer:SetWidthOverride(w)
    g.outer:SetHeightOverride(h)
    local inner = fresh("/Script/UMG.Overlay")
    g.track = copy(real.ToggleTrack)
    g.on_l = copy(real.ToggleLabelOn)
    g.off_l = copy(real.ToggleLabelOff)
    g.tbox = fresh("/Script/UMG.SizeBox")
    g.tbox:SetWidthOverride(real.Toggle_ThumbSize or 21.0)
    g.tbox:SetHeightOverride(real.Toggle_ThumbSize or 21.0)
    g.thumb = copy(real.ToggleThumb)
    g.button = fresh("/Script/UMG.Button")
    local s
    s = inner:AddChildToOverlay(g.track); slot_like(s, real.ToggleTrack.Slot)
    s = inner:AddChildToOverlay(g.on_l); slot_like(s, real.ToggleLabelOn.Slot)
    s = inner:AddChildToOverlay(g.off_l); slot_like(s, real.ToggleLabelOff.Slot)
    s = inner:AddChildToOverlay(g.tbox); slot_like(s, real.ThumbSizeBox.Slot)
    g.tbox:AddChild(g.thumb)
    s = inner:AddChildToOverlay(g.button)
    pcall(function() s:SetHorizontalAlignment(0); s:SetVerticalAlignment(0) end)
    pcall(function() g.button:SetRenderOpacity(0.0) end)
    g.outer:AddChild(inner)
    -- (beside the slider's ScaleBox, not in it: in it, it was drawn a third of its size)
    local place = ov
    pcall(function()
        local sb = ov:GetParent()
        if not (alive(sb) and sb:GetClass():GetFName():ToString() == "ScaleBox") then return end
        local sz = sb:GetParent()
        if not (alive(sz) and sz:GetClass():GetFName():ToString() == "SizeBox") then return end
        local pad, ha, va = nil, 0, 0
        local sl = sb.Slot
        if alive(sl) then
            local P = sl.Padding
            pad = { Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom }
            ha, va = sl.HorizontalAlignment, sl.VerticalAlignment
        end
        local wrap = fresh("/Script/UMG.Overlay")
        if not alive(wrap) then return end
        sz:SetContent(wrap)
        local ss = wrap:AddChildToOverlay(sb)
        if alive(ss) then
            if pad then pcall(function() ss:SetPadding(pad) end) end
            pcall(function() ss:SetHorizontalAlignment(ha) end)
            pcall(function() ss:SetVerticalAlignment(va) end)
        end
        place = wrap
    end)
    s = place:AddChildToOverlay(g.outer)
    pcall(function() s:SetHorizontalAlignment(1); s:SetVerticalAlignment(2) end)
    g.lit, g.plain = real.Toggle_SelectedColor, real.Toggle_NormalColor
    return g
end
local function show_switch(row, on)
    local r = rows[row:GetAddress()]
    if not r then return end
    local g = r.g
    if r.sw_g ~= g then r.sw_g, r.sw_hid, r.sw_on, r.sw_picked = g, nil, nil, nil end
    if not r.sw_hid then
        pcall(function() row.ProgressBar:SetRenderOpacity(0.0) end)
        pcall(function() row.SliderValue:SetRenderOpacity(0.0) end)
        pcall(function() row.Slider:SetRenderOpacity(0.0) end)
        r.sw_hid = true
    end
    if type(g) ~= "table" then return end
    if r.sw_on ~= on then
        pcall(function() g.tbox:SetRenderTranslation({ X = on and THUMB_ON or 0.0, Y = 0.0 }) end)
        r.sw_on = on
    end
    local picked = false
    pcall(function() picked = row:GetSelected() or row:IsHovered() end)
    if r.sw_picked == picked then return end
    r.sw_picked = picked
    local c = picked and g.lit or g.plain
    if c then
        local col = { R = c.R, G = c.G, B = c.B, A = c.A }
        for _, x in ipairs({ g.track, g.thumb }) do pcall(function() x:SetColorAndOpacity(col) end) end
        for _, x in ipairs({ g.on_l, g.off_l }) do pcall(function() x:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end) end
    end
end
local function enlist(box, row, anchor)
    local g = box.ButtonGroup
    if not alive(g) or g:FindButtonIndex(row) >= 0 then return end
    local mi = anchor and g:FindButtonIndex(anchor) or -1
    local after = {}
    if mi >= 0 then
        for i = mi + 1, g:GetButtonCount() - 1 do after[#after + 1] = g:GetButtonBaseAtIndex(i) end
    end
    for _, b in ipairs(after) do g:RemoveWidget(b) end
    g:AddWidget(row)
    for _, b in ipairs(after) do g:AddWidget(b) end
end
-- a slider row's number: a text of our own in the place of the row's (a copy of it, same look, in the number's box) -
-- STORROR writes its rows' numbers itself, as percentages, over ours ("change the blood stain limit to amount not
-- percentage", 2026-11-10); as the first person mod's fpsettings.lua does it
local function own_text(row)
    local r = rows[row:GetAddress()]
    if r and alive(r.tv) then return r.tv end
    local sv = row.SliderValue
    if not alive(sv) then return nil end
    local box = sv:GetParent()
    if not (alive(box) and box:GetClass():GetFName():ToString() == "SizeBox") then return sv end
    local sl = sv.Slot
    local pad, ha, va = nil, nil, nil
    if alive(sl) then
        local P = sl.Padding
        pad = { Left = P.Left, Top = P.Top, Right = P.Right, Bottom = P.Bottom }
        ha, va = sl.HorizontalAlignment, sl.VerticalAlignment
    end
    local tb = StaticConstructObject(sv:GetClass(), row.WidgetTree, FName("None"), 0, 0, false, false, sv)
    if not alive(tb) then return sv end
    local ns = box:SetContent(tb)
    if alive(ns) and pad then
        pcall(function() ns:SetPadding(pad) end)
        pcall(function() ns:SetHorizontalAlignment(ha) end)
        pcall(function() ns:SetVerticalAlignment(va) end)
    end
    pcall(function() tb:SetVisibility(4) end)
    if r then r.tv = tb end
    return tb
end
-- (a slider by a list of `values` - not even steps: REGENERATION's 0.25 and 0.5 below its 1 to 100, "add a 0.25 and 0.50
-- heal options", 2026-11-11 - runs over their places 0 .. n-1)
local function value_place(spec, v)
    local best, bd = 0, math.huge
    for i, x in ipairs(spec.values) do local d = math.abs(x - v); if d < bd then best, bd = i - 1, d end end
    return best
end
local function show_amount(row, spec, v)
    if spec.values then
        pcall(function() row.ProgressBar.ProgressValue = value_place(spec, v) / math.max(1, #spec.values - 1) end)
    else
        pcall(function() row.ProgressBar.ProgressValue = (v - spec.min) / (spec.max - spec.min) end)
    end
    pcall(function()
        local tv = own_text(row)
        local want = spec.fmt(v)
        if tv:GetText():ToString() ~= want then tv:SetText(FText(want)) end
    end)
end
-- a heading: a copy of the page's own heading line (the first text line in its column), our words in it - as the first
-- person mod's fpsettings.lua does its headings; seen, never picked
local function add_heading(page, spec, anchor)
    local box = part(page, "VerticalBox")
    if not (box and alive(anchor)) then return nil end
    local src = nil
    pcall(function()
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if not src and alive(c) and c:GetClass():GetFName():ToString():find("TextBlock") and not rows[c:GetAddress()] then src = c end
        end
    end)
    if not src then return nil end
    local t = StaticConstructObject(src:GetClass(), page.WidgetTree, FName("None"), 0, 0, false, false, src)
    if not alive(t) then return nil end
    rows[t:GetAddress()] = { spec = spec, header = true, name = t:GetFName():ToString() }
    pcall(function() t:SetText(FText(spec.label)) end)
    local at = box:GetChildIndex(anchor)
    local after = {}
    for i = at + 1, box:GetChildrenCount() - 1 do after[#after + 1] = box:GetChildAt(i) end
    for _, c in ipairs(after) do box:RemoveChild(c) end
    local slot = box:AddChildToVerticalBox(t)
    for _, c in ipairs(after) do box:AddChildToVerticalBox(c) end
    pcall(function()
        local ss = src.Slot
        slot:SetPadding(ss.Padding)
        slot:SetHorizontalAlignment(ss.HorizontalAlignment)
        slot:SetVerticalAlignment(ss.VerticalAlignment)
    end)
    pcall(function() t:SetVisibility(4) end)
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = { R = 0.8, G = 0.8, B = 0.8, A = 1.0 }, ColorUseRule = 0 }) end)
    return t
end
local function add(page, spec, anchor)
    if spec.header then return add_heading(page, spec, anchor) end
    local box = part(page, "VerticalBox")
    local tmpl = part(page, "CameraShakeFactor")
    if not (box and tmpl and alive(anchor)) then return nil end
    local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local row = WBL:Create(lib.world(), tmpl:GetClass(), tmpl:GetOwningPlayer())
    if not alive(row) then return nil end
    rows[row:GetAddress()] = { spec = spec, g = true, name = row:GetFName():ToString() }
    row.SettingsName = FText(spec.label)
    local at = box:GetChildIndex(anchor)
    local after = {}
    for i = at + 1, box:GetChildrenCount() - 1 do after[#after + 1] = box:GetChildAt(i) end
    for _, c in ipairs(after) do box:RemoveChild(c) end
    local slot = box:AddChildToVerticalBox(row)
    for _, c in ipairs(after) do box:AddChildToVerticalBox(c) end
    pcall(function()
        local ts = anchor.Slot
        slot:SetPadding(ts.Padding)
        slot:SetHorizontalAlignment(ts.HorizontalAlignment)
        slot:SetVerticalAlignment(ts.VerticalAlignment)
        slot:SetSize(ts.Size)
    end)
    pcall(function() row.Title:SetText(FText(spec.label)) end)
    if spec.slider then
        rows[row:GetAddress()].g = "slider"
        if spec.values then
            pcall(function() row.Slider:SetMinValue(0.0); row.Slider:SetMaxValue(#spec.values - 1); row.Slider:SetStepSize(1.0) end)
            pcall(function() row.Slider:SetValue(value_place(spec, spec.get())) end)
        else
            pcall(function() row.Slider:SetMinValue(spec.min); row.Slider:SetMaxValue(spec.max); row.Slider:SetStepSize(spec.step) end)
            pcall(function() row.Slider:SetValue(spec.get()) end)
        end
        show_amount(row, spec, spec.get())

        return row
    end
    pcall(function() row.Slider:SetMinValue(0.0); row.Slider:SetMaxValue(1.0); row.Slider:SetStepSize(1.0) end)
    pcall(function() row.Slider:SetValue(spec.get() and 1.0 or 0.0) end)
    show_switch(row, spec.get())

    return row
end
-- the page's own rows (STORROR's camera settings) put away on our page: not seen, not among the column's buttons
local function hide_theirs(page)
    pcall(function()
        local root = page.WidgetTree.RootWidget
        for i = 0, root:GetChildrenCount() - 1 do
            local c = root:GetChildAt(i)
            if alive(c) and c:GetClass():GetFName():ToString() == "MenuVerticalSeparatorBP_C" and c:GetVisibility() ~= 1 then c:SetVisibility(1) end
        end
    end)
    local box = part(page, "VerticalBox")
    if not box then return end
    local g = box.ButtonGroup
    for i = 0, box:GetChildrenCount() - 1 do
        local c = box:GetChildAt(i)
        if alive(c) and not rows[c:GetAddress()] then
            if c:GetVisibility() ~= 1 then c:SetVisibility(1) end
            pcall(function() if alive(g) and g:FindButtonIndex(c) >= 0 then g:RemoveWidget(c) end end)
        end
    end
end
local function watch_switch(r, addr)
    local spec, rr = rows[addr].spec, rows[addr]
    local on = spec.get() and true or false
    local g = rr.g
    local now = os.clock()
    local held = r.flip_t and now - r.flip_t < HOLD
    if type(g) == "table" and g.button then
        local down = g.button:IsPressed()
        if down and not r.was_pressed and not held then
            on = not on
            spec.set(on)
            r.row.Slider:SetValue(on and 1.0 or 0.0)
            r.flip_t, held = now, true
        end
        r.was_pressed = down
    end
    local v = r.row.Slider:GetValue() >= 0.5
    if v ~= on then
        if not held and r.last ~= nil and v ~= r.last then
            on = v
            spec.set(on)
            r.flip_t = now
        else
            r.row.Slider:SetValue(on and 1.0 or 0.0)
        end
    end
    r.last = on
    show_switch(r.row, on)
end
-- a slider row: the player's moves kept (to its steps), its number and bar shown
local function watch_slider(r, addr)
    local spec = rows[addr].spec
    local v
    if spec.values then
        local i = math.floor(r.row.Slider:GetValue() + 0.5)
        v = spec.values[math.max(1, math.min(#spec.values, i + 1))]
    else
        local step = spec.step or 1
        v = math.floor(r.row.Slider:GetValue() / step + 0.5) * step
    end
    local cur = spec.get()
    if r.last == nil then r.last = cur end
    if v ~= cur then
        if v ~= r.last then spec.set(v); cur = v
        else r.row.Slider:SetValue(spec.values and value_place(spec, cur) or cur) end
    end
    r.last = cur
    show_amount(r.row, spec, cur)
end
local watch_skip = false
local function watch()
    watch_skip = not watch_skip
    if watch_skip then return end
    for addr, r in pairs(live) do
        local ok = pcall(function()
            if not (r.row:IsValid() and r.page:IsValid()) then live[addr], rows[addr] = nil, nil; return end
            if not rows[addr] then live[addr] = nil; return end
            if rows[addr].spec.slider then watch_slider(r, addr) else watch_switch(r, addr) end
        end)
        if not ok then live[addr], rows[addr] = nil, nil end
    end
end
local FOCUS_FOR = 1.0
local focus_until, was_open = 0.0, false
local function give_focus(page)
    if not (alive(page) and page:IsVisible()) or page:HasFocusedDescendants() then return end
    local box = page.VerticalBox
    if not alive(box) then return end
    local g = box.ButtonGroup
    if not alive(g) or g:GetButtonCount() == 0 then return end
    local i = g:GetSelectedButtonIndex()
    if i < 0 or i >= g:GetButtonCount() then i = 0 end
    local row = g:GetButtonBaseAtIndex(i)
    if alive(row) and row:IsVisible() then row:SetFocus() end
end

-- each row's explanation, shown in a box at the bottom of the screen while the RAGDOLL tab is open, for the row the
-- mouse is over or that is picked ("make a dialog at the bottom explaining every setting", 2026-11-11)
M.DESC = {
    ["LIVE RAGDOLL"] = "While he's down he moves on his own: holds his injuries, kicks, curls up and tries to get up. Off: he lies limp like STORROR's own ragdoll.",
    ["NEWTONS LAW"] = "Real momentum: his spin carries into the ragdoll and never slows in the air, and falls have no air drag, speeding up to 400 mph. Off: normal spin, and drag holds falls near 120 mph.",
    ["KEEP INJURIES"] = "Injuries stay after he gets up: broken or dislocated limbs keep hanging until they heal. Off: he's healed every time he gets up.",
    ["EASY INJURIES"] = "Injuries at much lower speeds: a fracture from 5 mph, a break from 15 mph, a limb cut off from 30 mph.",
    ["EXPLODE"] = "Any injury at all blows him apart.",
    ["NO EXPLOSIONS"] = "He is never blown apart, however fast the hit. Overrides EXPLODE. Hits still break and cut off limbs.",
    ["ROLLS NEGATE RAGDOLLS"] = "A roll saves him: falls and trips during a roll don't ragdoll him, and if one starts he's put straight back on his feet.",
    ["WALL SLIDE"] = "STORROR's slide down walls. Off: he ragdolls the moment a wall slide starts.",
    ["RUN INTO WALLS"] = "Running into a wall or an object knocks him down. Off: it doesn't.",
    ["FALL HEIGHT"] = "How far he can fall before the landing knocks him down, 5 to 500 ft. OFF: falls never knock him down. Heights are at normal gravity: with GRAVITY lower it takes a longer fall, with it higher a shorter one.",
    ["BLEED FOREVER"] = "Cuts and open breaks keep bleeding for as long as he has them. Off: a stump bleeds for 2 minutes, a broken bone's wound for 30 seconds.",
    ["HP BAR"] = "Shows his HP, lost as he bleeds and gets hurt; at zero he's dead. Off: no bar and no bleeding out.",
    ["MAX HP"] = "How much HP he has, 10 to 1000. A drop of blood costs 0.1 HP, a fracture 3, a break 5, a limb cut off 10.",
    ["TARKOV DAMAGE"] = "His HP is split over head, chest, arms and legs, each with its own HP like Tarkov. Head or chest at zero kills him; limbs heal one at a time.",
    ["REGENERATION"] = "HP healed every second, from 0.25 up to 100 (OFF at 0). Fractures and breaks mend as he heals; cut-off limbs never grow back.",
    ["DAMAGE HUD"] = "Shows the body figure, each part colored by its injuries.",
    ["INJURY COUNTER"] = "STORROR's bail counter, counting his injuries as this mod has them.",
    ["SPEEDOMETER"] = "Shows his speed in mph and km/h under the HP panel.",
    ["LIMB SLOWNESS"] = "Hurt legs and arms slow him down on his feet. Off: injuries don't slow him.",
    ["BLOOD STAIN LIMIT"] = "How many blood stains can be on the ground before the oldest disappear. Lower it if the game slows down.",
}
M.DESC["SETTING INFO"] = "Shows this box explaining the setting you are on. Off: no box."
M.DESC["GRAVITY"] = "How strong gravity is, for everything: him on his feet and ragdolled, cut-off limbs, blood and loose objects. 100% is normal and 0% is none at all; 17% is the moon, 38% Mars, 253% Jupiter. Under 100%: higher jumps, slower falls. Over it: lower jumps, harder landings."
M.DESC["MOON GRAVITY"] = "Puts GRAVITY at 17%, the moon's: higher, floatier jumps and slow falls on his feet, and a ragdoll, cut-off limbs, blood and loose objects that fall slowly. Turn it off to go back to 100%."
M.DESC["SCALING DAMAGE"] = "Injuries stack: each new landing on a hurt part makes it worse by that hit - a dislocated part breaks, a broken part comes off, even under 50 mph. With TARKOV DAMAGE a limb at 0 HP comes off on its next hit."
M.DESC["NON-RAGDOLL DAMAGE"] = "He's hurt while not ragdolled: landing on his feet from about 8 ft or more hurts his legs by the landing's speed - fractures, breaks, a leg giving way. A roll takes none."
M.DESC["SEVERED LIMBS"] = "Limbs and his head can be cut off by hard enough hits. Off: nothing is ever cut off - those hits break the limb instead, and he never explodes."
M.DESC["BONES STICKING OUT"] = "Some breaks are open: the broken bone pokes out through a bleeding wound. Off: every break is closed - no bone, no wound."
M.DESC["BLEEDING"] = "He bleeds from cuts, stumps and open breaks, losing HP as he does. Off: no blood at all and no HP lost to bleeding."
M.DESC["X-RAY ON BREAKS"] = "When one of his bones breaks, you see his real skeleton through his body until he gets up: broken bones red, dislocated orange."
M.DESC["X-RAY BODY"] = "See his skeleton through his body the whole time he's ragdolled: broken bones red, dislocated orange, cut-off bones gone."
M.DESC["X-RAY ALWAYS ON"] = "His skeleton shows through his body all the time - running, climbing and ragdolled."
M.DESC["REMOVE PLAYER"] = "Hides his body whenever his skeleton shows, so you see only the bones. With X-RAY ALWAYS ON he's a walking skeleton."
M.DESC_NONE = "Pick a setting to see what it does."
-- (a box of the mod's own, on the screen over the menu - not on STORROR's page, which is freed each time it's shut; its
-- name's text a copy of a row's title, for STORROR's look; it lets the mouse through)
M.DESC_BOX = { w = nil, title = nil, body = nil, shown = false, cur = nil, at = { x = -40.0, y = 0.0, w = 480.0, h = 300.0 } }
function M.desc_build(row)
    local B = M.DESC_BOX
    local pc = lib.controller()
    if not pc then return end
    local function cls(path) return StaticFindObject(path) end
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("None"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("None"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("None"))
    tree.RootWidget = canvas
    local A = B.at
    local BOTTOM = { X = 1.0, Y = 0.5 }
    local function place(x, y, sx, sy, ax, ay)
        return function(s)
            s:SetAnchors({ Minimum = BOTTOM, Maximum = BOTTOM })
            s:SetAlignment({ X = ax, Y = ay })
            s:SetPosition({ X = x, Y = y })
            s:SetSize({ X = sx, Y = sy })
        end
    end
    local bg = StaticConstructObject(cls("/Script/UMG.Image"), canvas, FName("None"))
    pcall(function() bg:SetColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.78 }) end)
    place(A.x, A.y, A.w, A.h, 1.0, 0.5)(canvas:AddChildToCanvas(bg))
    local title = nil
    pcall(function() title = StaticConstructObject(row.Title:GetClass(), tree, FName("None"), 0, 0, false, false, row.Title) end)
    if not alive(title) then title = StaticConstructObject(cls("/Script/UMG.TextBlock"), canvas, FName("None")) end
    local x0, top = A.x - A.w + 22.0, A.y - A.h / 2 + 16.0
    place(x0, top, A.w - 44.0, 44.0, 0.0, 0.0)(canvas:AddChildToCanvas(title))
    local body = StaticConstructObject(cls("/Script/UMG.TextBlock"), canvas, FName("None"))
    pcall(function() body:SetAutoWrapText(true) end)
    pcall(function() body:SetColorAndOpacity({ SpecifiedColor = { R = 0.92, G = 0.92, B = 0.92, A = 1.0 }, ColorUseRule = 0 }) end)
    place(x0, top + 52.0, A.w - 44.0, A.h - 76.0, 0.0, 0.0)(canvas:AddChildToCanvas(body))
    pcall(function() w:SetVisibility(1) end)
    w:AddToViewport(1000)
    B.w, B.title, B.body, B.shown, B.cur = w, title, body, false, nil
    log("menu: the settings' explanation box made")
end
function M.desc_tick(open)
    local B = M.DESC_BOX
    if not open or not M.setting_info() then
        if B.shown and alive(B.w) then pcall(function() B.w:SetVisibility(1) end) end
        B.shown = false
        return
    end
    -- (the row the mouse is over, else the picked one)
    local hov, sel, any = nil, nil, nil
    for addr, r in pairs(live) do
        local rr = rows[addr]
        if rr and alive(r.row) then
            any = any or r.row
            local h, s_ = false, false
            pcall(function() h = r.row:IsHovered() end)
            pcall(function() s_ = r.row:GetSelected() or r.row:HasKeyboardFocus() end)
            if h then hov = rr.spec.label end
            if s_ then sel = rr.spec.label end
        end
    end
    if not any then return end
    if not alive(B.w) then B.w = nil; local ok, e = pcall(M.desc_build, any); if not ok then log("menu: no explanation box (%s)", tostring(e)) end end
    if not alive(B.w) then return end
    local label = hov or sel
    if label ~= B.cur then
        B.cur = label
        pcall(function() B.title:SetText(FText(label or "RAGDOLL")) end)
        pcall(function() B.body:SetText(FText(label and M.DESC[label] or M.DESC_NONE)) end)
    end
    if not B.shown then pcall(function() B.w:SetVisibility(3) end); B.shown = true end
end

-- ------------------------------------------------------------------ every frame
M.menu_up = false
function M.tick(dt)
    -- the template's list seen to: now and then
    check_t = check_t - dt
    if check_t <= 0 and not failed then
        check_t = patched and 5.0 or 0.5
        local tmpl = StaticFindObject(TEMPLATE)
        if alive(tmpl) then
            local ok, res = pcall(patch, tmpl)
            if not ok then failed = true; log("menu: the RAGDOLL tab not put on STORROR's list (%s)", tostring(res))
            elseif res ~= "there" then
                log("menu: %s", res)
                patched = res:find("^added") ~= nil
                if not patched then failed = true end
            else patched = true end
        end
    end
    if M.menu_up then watch() end
    look_t = look_t - dt
    if look_t > 0 then return end
    look_t = M.menu_up and 0.1 or 0.3
    local up, open, page_open = false, false, nil
    local shown = {}
    for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
        pcall(function()
            if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
            local sw = bar:GetLinkedSwitcher()
            if not alive(sw) then return end
            local sel = bar:GetSelectedTabId():ToString()
            if sel ~= "None" then up = true end
            if sel ~= TAB_ID then return end
            local page = our_page(bar)
            if not page then return end
            open, page_open = true, page
            shown[page:GetAddress()] = true
            hide_theirs(page)
            -- (our rows, under the page's first row of its own as their anchor; one try each per page)
            local box = part(page, "VerticalBox")
            local real = part(page, "CameraInvertYNewSelector")
            if not (box and real) then return end
            local key = page:GetFName():ToString()
            local by_label = {}
            for i = 0, box:GetChildrenCount() - 1 do
                local c = box:GetChildAt(i)
                local r = c and rows[c:GetAddress()]
                if r and r.name and c:GetFName():ToString() ~= r.name then rows[c:GetAddress()], r = nil, nil end
                if r then by_label[r.spec.label] = c end
            end
            local anchor = real
            for _, spec in ipairs(ROWS) do
                local row = by_label[spec.label]
                if not row and not tried[key .. "|" .. spec.label] then
                    tried[key .. "|" .. spec.label] = true
                    local okr, res = pcall(add, page, spec, anchor)
                    if not okr then log("menu: %s not added (%s)", spec.label, tostring(res)) end
                    row = okr and res or nil
                end
                local rh = row and rows[row:GetAddress()]
                if row and rh and rh.header then
                    anchor = row
                elseif row then
                    pcall(enlist, box, row, nil)
                    local rr = rows[row:GetAddress()]
                    if rr and rr.g == true then
                        local okb, g = pcall(build_graphic, row, real)
                        if okb and g then rr.g = g elseif not okb then rr.g = "failed"; log("menu: switch not drawn (%s)", tostring(g)) end
                    end
                    local addr = row:GetAddress()
                    if not live[addr] then live[addr] = { row = row, page = page, page_addr = page:GetAddress(), was_pressed = false } end
                    anchor = row
                end
            end
        end)
    end
    M.menu_up = up
    -- (only rows of a page on screen now watched; shut, nothing of the menu kept)
    for addr, r in pairs(live) do if not shown[r.page_addr] then live[addr] = nil end end
    if not up then live = {} end
    if open and not was_open then focus_until = os.clock() + FOCUS_FOR end
    was_open = open
    if open and page_open and os.clock() < focus_until then pcall(give_focus, page_open) end
    local okd, ed = pcall(M.desc_tick, open)
    if not okd then log("menu: explanation box failed (%s)", tostring(ed)) end
end

function M.forget() tried = {}; live = {}; rows = {}; M.DESC_BOX.w, M.DESC_BOX.shown, M.DESC_BOX.cur = nil, false, nil end
M.TAB_ID = TAB_ID
return M
