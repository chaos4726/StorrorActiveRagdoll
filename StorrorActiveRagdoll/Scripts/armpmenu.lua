-- STORROR Active Ragdoll: the multiplayer screen in STORROR's ONLINE tab, in place of STORROR's own multiplayer (its
-- servers can't be reached): SM64Map's screen made the ragdoll mod's ("remove the multiplayer and switch it for steam
-- peer to peer", "same as SM64", 2026-11-11). Host a public, passworded or friends-only lobby, invite Steam friends, see
-- the public lobbies and join one, go to a friend, PvP, leave. (armp.lua and bin\arnet.dll do the networking.)
--
-- STORROR's menu keeps every key from the mod while it is up, so the pad reaches this the way it reaches Mario 64's
-- screen in SPOTS (msettings.lua m64_spots): ONLINE's own page swapped for a page of three unseen rows of STORROR's
-- (its audio page's MUSIC slider), the middle one picked - the pick stepping to the one over it is Up, to the one
-- under it Down, its slider pushed right is A; each put back at once. The screen itself is drawn under STORROR's menu.
local lib = _G.ARLIB
local log = lib.log

local M = {}

local ONLINE = "ONLINE"
local CONTENT = "MultiPageMultiplayerMenuWidget_C"
local PAGE_CLASS = "/SPP/UI/PauseMenu/Audio/CommonAudioMenuWidget.CommonAudioMenuWidget_C"
local SUB = "ARMultiplayer"
local Z = -5                                   -- (under STORROR's menu, as Mario 64's screen in SPOTS)
local REFRESH = 10.0                           -- s between lobby list refreshes while the screen is up

local function alive(o) return o ~= nil and pcall(function() return o:IsValid() end) and o:IsValid() end

-- (a map's name as said: STORROR's map, its SPP_ taken off and its words spaced - SPP_MegaMap: Mega Map)
local function scene_name(s)
    if not s or s == "" then return "" end
    s = s:gsub("^SPP_", ""):gsub("(%l)(%u)", "%1 %2")
    return s
end
M.scene_name = scene_name

-- ------------------------------------------------------------------------------- the input page in ONLINE

local CTL = _G.AR_MP_CTL or {}                 -- (by page address: { page, rows, name })
_G.AR_MP_CTL = CTL
local ev = { up = 0, down = 0, ok = 0 }

-- a widget of the page by name: its variable, or else from its tree (as msettings.lua's part)
local function part(page, name)
    local w = nil
    pcall(function() w = page[name] end)
    if alive(w) then return w end
    w = nil
    pcall(function() w = page.WidgetTree:FindWidget(FName(name)) end)
    if alive(w) then return w end
    return nil
end

-- ONLINE's page set up for our screen (one bar's menu): a page of three unseen rows added as a tab of its own, its own
-- tabs hidden and shut off, ours picked, that row out of sight
local function online_page(bar)
    if not bar:IsValid() or bar:GetFName():ToString():find("^Default__") then return end
    local sw = bar:GetLinkedSwitcher()
    if not alive(sw) then return end
    local mw = nil
    for i = 0, sw:GetChildrenCount() - 1 do
        local c = sw:GetChildAt(i)
        if alive(c) and c:GetClass():GetFName():ToString() == CONTENT then mw = c end
    end
    if not alive(mw) then return end
    if mw:GetVisibility() == 1 then mw:SetVisibility(4) end
    local sub, asw = mw.MenuTabBar, mw.AnimatedSwitcher
    if not (alive(sub) and alive(asw)) then return end
    if not alive(sub:GetTabButtonBaseByID(FName(SUB))) then
        local ref = nil
        pcall(function()
            for i = 0, sub:GetTabCount() - 1 do
                local b = sub:GetTabButtonBaseByID(sub:GetTabIdAtIndex(i))
                if alive(b) then ref = b; break end
            end
        end)
        if not alive(ref) then return end
        local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(PAGE_CLASS)
        if not alive(cls) then pcall(function() cls = LoadAsset(PAGE_CLASS) end) end
        if not (WBL and alive(cls)) then return end
        local page = WBL:Create(lib.world(), cls, ref:GetOwningPlayer())
        if not alive(page) then return end
        if asw:GetChildIndex(page) < 0 then asw:AddChild(page) end
        sub:RegisterTab(FName(SUB), ref:GetClass(), page, -1)
        CTL[page:GetAddress()] = { page = page, rows = nil, name = page:GetFName():ToString() }
        if not M.page_said then M.page_said = true; log("multiplayer: our page on ONLINE") end
    end
    pcall(function()
        for i = 0, sub:GetTabCount() - 1 do
            local id = sub:GetTabIdAtIndex(i)
            if id:ToString() ~= SUB then
                local b = sub:GetTabButtonBaseByID(id)
                if alive(b) and (b:GetIsEnabled() or b:GetVisibility() ~= 1) then
                    sub:SetTabVisibility(id, 1)
                    sub:SetTabEnabled(id, false)
                end
            end
        end
    end)
    if sub:GetSelectedTabId():ToString() ~= SUB then sub:SelectTabByID(FName(SUB), true) end
    if sub:GetVisibility() ~= 1 then sub:SetVisibility(1) end
    for addr, e in pairs(CTL) do
        pcall(function()
            local page = e.page
            if not page:IsValid() or page:GetFName():ToString() ~= e.name then CTL[addr] = nil; return end
            if e.rows then return end
            local box = part(page, "VerticalBox")
            local mus = part(page, "MusicVolumeSlider")
            if not (alive(box) and alive(mus)) then return end
            local WBL = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            local g = box.ButtonGroup
            for i = 0, box:GetChildrenCount() - 1 do
                local c = box:GetChildAt(i)
                if alive(c) then
                    c:SetVisibility(1)
                    pcall(function() if alive(g) and g:FindButtonIndex(c) >= 0 then g:RemoveWidget(c) end end)
                end
            end
            local rows = {}
            for i = 1, 3 do
                local r = WBL:Create(lib.world(), mus:GetClass(), mus:GetOwningPlayer())
                r.SettingsName = FText("AR MP " .. i)
                box:AddChildToVerticalBox(r)
                pcall(function() local b = r.Slider; b:SetMinValue(0.0); b:SetMaxValue(1.0); b:SetStepSize(0.1); b:SetValue(0.5) end)
                r:SetRenderOpacity(0.0)
                if alive(g) then g:AddWidget(r) end
                rows[i] = r
            end
            if alive(g) then g:SelectButtonAtIndex(1, false) end
            e.rows = rows
            if not M.rows_said then M.rows_said = true; log("multiplayer: our rows on ONLINE") end
        end)
    end
end

-- each frame the menu is up: the picks and pushes on our unseen rows, as Up, Down and A, each put back at once
local function read_input()
    for addr, e in pairs(CTL) do
        pcall(function()
            local page = e.page
            if not (e.rows and page:IsValid() and page:IsVisible()) then return end
            local box = part(page, "VerticalBox")
            local g = box and box.ButtonGroup
            if not alive(g) then return end
            local mid = e.rows[2]
            if not page:HasFocusedDescendants() then pcall(function() mid:SetFocus() end) end
            if page:GetRenderOpacity() > 0.0 then page:SetRenderOpacity(0.0) end
            -- (a step is the pick or the keys' focus going to the row over or under the middle one: here the focus went
            -- and the pick didn't, and stayed there - every press after it reached nothing, "Still can't", 2026-11-01)
            local function has(r)
                local f = false
                pcall(function() f = r:HasAnyUserFocus() or r:HasFocusedDescendants() end)
                return f
            end
            local sel = g:GetSelectedButtonIndex()
            local i0, i1, i2 = g:FindButtonIndex(e.rows[1]), g:FindButtonIndex(mid), g:FindButtonIndex(e.rows[3])
            local up, down = sel == i0 or has(e.rows[1]), sel == i2 or has(e.rows[3])
            if up then ev.up = ev.up + 1 elseif down then ev.down = ev.down + 1 end
            if M.DEBUG and (up or down) then log("mp input: %s (sel %d)", up and "up" or "down", sel) end
            if sel ~= i1 and i1 >= 0 then g:SelectButtonAtIndex(i1, false) end
            if up or down then pcall(function() mid:SetFocus() end) end
            -- (select: any of the three rows' sliders pushed right - the one with the focus takes it; back: pushed left.
            -- STORROR's menu keeps the pad's A to itself - nothing of the mod's ever saw it - so Right is select here)
            for _, r in ipairs(e.rows) do
                local v = r.Slider:GetValue()
                if v > 0.55 then ev.ok = ev.ok + 1 elseif v < 0.45 then ev.back = (ev.back or 0) + 1 end
                if M.DEBUG and math.abs(v - 0.5) > 0.01 then log("mp input: slider %.2f", v) end
                if math.abs(v - 0.5) > 0.01 then r.Slider:SetValue(0.5) end
            end
        end)
    end
end

-- ------------------------------------------------------------------------------------------- the screen

local ui = nil
local sel = 1
local items = {}
local list_t = -100.0
local shown_key = nil

local function remove()
    if ui then pcall(function() if ui.widget:IsValid() then ui.widget:RemoveFromParent() end end) end
    ui = nil
    shown_key = nil
end

local WHITE = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
local GREY = { R = 0.65, G = 0.65, B = 0.65, A = 1.0 }
local YELLOW = { R = 1.0, G = 0.85, B = 0.1, A = 1.0 }
local RED = { R = 1.0, G = 0.35, B = 0.3, A = 1.0 }

-- Passworded lobbies ("I also want passworded lobbies", "needs to be more than 4 digits", "7 is good", 2026-11-01): a
-- 7-digit password, put in with the pad - Up and Down change the digit the cursor is on, Right goes to the next; after the
-- last, CONFIRM, RETYPE or CANCEL.
local DIGITS = 7
local pw = nil                -- { purpose = "host" | "join", lobby, digits, pos, done }
local my_code = nil           -- the password of the lobby this player made (shown to them, to give to friends)
local msg, msg_t = nil, 0.0   -- a line said for a moment ("Wrong password")
local friends_page = false    -- the invite page: friends online, to invite one
local invited = {}            -- friends invited, by Steam id
local function code_of(p) local s = ""; for i = 1, DIGITS do s = s .. tostring(p.digits[i]) end return s end
local function pw_start(purpose, lobby)
    pw = { purpose = purpose, lobby = lobby, digits = {}, pos = 1 }
    for i = 1, DIGITS do pw.digits[i] = 0 end
end

-- what the screen lists: { text, col, act } (act nil: a line to read, not to pick)
local function build_items(MP)
    local s = MP.status
    local out = {}
    local function add(text, col, act) out[#out + 1] = { text = text, col = col, act = act } end
    if pw then
        add(pw.purpose == "host" and "Set a 7-digit password for your lobby" or "This lobby has a password", WHITE)
        local parts = {}
        for i = 1, DIGITS do
            local d = tostring(pw.digits[i])
            parts[i] = (not pw.done and i == pw.pos) and ("[" .. d .. "]") or (i < pw.pos or pw.done) and d or "_"
        end
        add(table.concat(parts, "  "), YELLOW)
        if not pw.done then
            add("Up / Down: change the digit     A or Right: next     Left: back", GREY)
        else
            add(pw.purpose == "host" and "HOST WITH THIS PASSWORD" or "JOIN", YELLOW, { "pw_ok" })
            add("RETYPE", YELLOW, { "pw_retype" })
            add("CANCEL", YELLOW, { "pw_cancel" })
        end
        return out
    end
    if friends_page and s.state == "in_lobby" then
        -- (inviting: Steam's overlay window, or a friend picked here - Steam's own invite, no overlay needed)
        add("Invite a friend", WHITE)
        add("OPEN STEAM'S INVITE WINDOW (opens in the Steam app)", YELLOW, { "invite" })
        local fl = s.friends or {}
        if #fl == 0 then add("No friends online right now", GREY) end
        for _, f in ipairs(fl) do
            add(f.name .. (f.here and "   (playing STORROR)" or "") .. (invited[f.id] and "   - invited" or ""), YELLOW, { "invite_friend", f.id })
        end
        add("BACK", YELLOW, { "friends_back" })
        return out
    end
    friends_page = false
    if msg and os.clock() - msg_t < 4.0 then add(msg, RED) end
    if s.state == "off" then
        add("Waiting for Steam...", GREY)
        if s.error and s.error ~= "" then add(s.error, RED) end
        return out
    end
    if s.state == "creating" then add("Making a lobby...", GREY) return out end
    if s.state == "joining" then add("Joining...", GREY) return out end
    if s.state == "in_lobby" then
        local pub = s.public == "1"
        local mine = s.owner == s.me
        local locked = s.lock and s.lock ~= ""
        add((mine and "Your " or "In a ") .. (locked and "passworded" or pub and "public" or "friends-only") .. " lobby  -  " .. #s.members .. " / " ..
            (tonumber(s.max) or 100) .. " players", WHITE)
        if mine and locked and my_code and MP.lock_of(my_code) == s.lock then add("Password: " .. my_code, YELLOW) end
        add("INVITE STEAM FRIENDS", YELLOW, { "friends" })
        add("PVP: " .. (MP.pvp() and "ON" or "OFF"), YELLOW, { "pvp" })
        local here = MP.scene_now and MP.scene_now()
        for _, m in ipairs(s.members) do
            if m.id ~= s.me then
                local where = MP.scene_of and MP.scene_of(m.id) or nil
                local tag = ((MP.peer_pvp and MP.peer_pvp[m.id]) and "  [PVP]" or "") .. ((MP.peer_down and MP.peer_down[m.id]) and "  [DOWN]" or "")
                if where and where == here then
                    add("GO TO " .. m.name .. tag, YELLOW, { "goto", m.id })
                else
                    add(m.name .. (where and ("  (" .. scene_name(where) .. ")") or "") .. tag, GREY)
                end
            end
        end
        add("LEAVE LOBBY", YELLOW, { "leave" })
        return out
    end
    if s.error and s.error ~= "" then add(s.error, RED) end
    add("HOST A PUBLIC LOBBY", YELLOW, { "host", true })
    add("HOST A PASSWORDED LOBBY", YELLOW, { "host_pw" })
    add("HOST A FRIENDS-ONLY LOBBY", YELLOW, { "host", false })
    add("REFRESH THE LOBBY LIST", YELLOW, { "list" })
    add("PVP: " .. (MP.pvp() and "ON" or "OFF"), YELLOW, { "pvp" })
    if #s.list == 0 then
        add((s.listdone or 0) > 0 and "No public lobbies right now" or "Looking for lobbies...", GREY)
    else
        add("Public lobbies:", WHITE)
        for _, l in ipairs(s.list) do
            local full = l.max and l.max > 0 and l.n >= l.max
            local locked = l.lock and l.lock ~= ""
            add(string.format("%s's lobby   %d / %d   %s%s", l.name ~= "" and l.name or "Someone", l.n or 0, l.max or 100, scene_name(l.scene),
                locked and "   [PASSWORD]" or ""),
                full and GREY or YELLOW, (not full) and (locked and { "join_pw", l.id } or { "join", l.id }) or nil)
        end
    end
    return out
end

local function pickable(i) return items[i] and items[i].act ~= nil end
local function fix_sel()
    if pickable(sel) then return end
    for i = 1, #items do if pickable(i) then sel = i; return end end
    sel = 1
end

local function draw()
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    local function cls(p) return StaticFindObject(p) end
    remove()
    local w = StaticConstructObject(cls("/Script/UMG.UserWidget"), pc, FName("ARMPScreen"))
    local tree = StaticConstructObject(cls("/Script/UMG.WidgetTree"), w, FName("ARMPTree"))
    w.WidgetTree = tree
    local canvas = StaticConstructObject(cls("/Script/UMG.CanvasPanel"), tree, FName("ARMPCanvas"))
    tree.RootWidget = canvas
    local box = StaticConstructObject(cls("/Script/UMG.VerticalBox"), canvas, FName("ARMPBox"))
    local slot = canvas:AddChildToCanvas(box)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.22 }, Maximum = { X = 0.5, Y = 0.22 } })
    slot:SetAlignment({ X = 0.5, Y = 0.0 })
    slot:SetAutoSize(true)
    local n = 0
    local function line(s, col, scale, gap)
        n = n + 1
        local t = StaticConstructObject(cls("/Script/UMG.TextBlock"), box, FName("ARMPText" .. n))
        pcall(function() t:SetText(FText(s)) end)
        pcall(function() t:SetColorAndOpacity({ SpecifiedColor = col, ColorUseRule = 0 }) end)
        pcall(function() t:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
        pcall(function() t:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.85 }) end)
        pcall(function() t:SetJustification(1) end)
        local s2 = box:AddChildToVerticalBox(t)
        pcall(function() s2:SetHorizontalAlignment(2) end)              -- (centred)
        pcall(function() s2:SetPadding({ Left = 0.0, Top = gap or 6.0, Right = 0.0, Bottom = 0.0 }) end)
        if scale then pcall(function() t:SetRenderScale({ X = scale, Y = scale }) end) end
        return t
    end
    line("MULTIPLAYER", WHITE, 1.8, 0.0)
    line("Peer to peer through Steam", GREY, 1.0, 22.0)
    -- (a long list - the friends online, the lobbies - scrolls with the cursor: SHOWN lines at once)
    local SHOWN = 14
    local first, last = 1, #items
    if #items > SHOWN then
        first = math.max(1, math.min(sel - SHOWN // 2, #items - SHOWN + 1))
        last = first + SHOWN - 1
    end
    if first > 1 then line("...", GREY, 1.0, 8.0) end
    for i = first, last do
        local it = items[i]
        local here = (i == sel) and it.act
        line((here and "> " or "") .. it.text .. (here and " <" or ""), here and WHITE or it.col, here and 1.15 or 1.0, (i == first) and 26.0 or 8.0)
    end
    if last < #items then line("...", GREY, 1.0, 8.0) end
    w:AddToViewport(Z)
    ui = { widget = w }
end

local function act(MP, a)
    if not a then return end
    if a[1] == "host" then my_code = nil; MP.host(a[2])
    elseif a[1] == "host_pw" then pw_start("host")
    elseif a[1] == "join_pw" then pw_start("join", a[2])
    elseif a[1] == "pw_retype" then pw_start(pw.purpose, pw.lobby)
    elseif a[1] == "pw_cancel" then pw = nil
    elseif a[1] == "pw_ok" then
        local code, p = code_of(pw), pw
        pw = nil
        if p.purpose == "host" then
            my_code = code
            MP.host(true, code)
        elseif not MP.join(p.lobby, code) then
            msg, msg_t = "Wrong password", os.clock()
        end
    elseif a[1] == "pvp" then MP.set_pvp(MP.pvp() and 0 or 1)
    elseif a[1] == "list" then MP.list(); list_t = os.clock()
    elseif a[1] == "join" then MP.join(a[2])
    elseif a[1] == "leave" then MP.leave()
    elseif a[1] == "invite" then MP.invite()
    elseif a[1] == "friends" then friends_page = true; sel = 1
    elseif a[1] == "friends_back" then friends_page = false; sel = 1
    elseif a[1] == "invite_friend" then MP.invite_friend(a[2]); invited[a[2]] = true
    elseif a[1] == "goto" then if MP.go_to then MP.go_to(a[2]) end
    end
end

-- every frame (msettings.lua's tick): the page in ONLINE kept set up; the screen up while ONLINE is the tab on
local look_t = -10.0
local pad_on, pad_t = false, 0.0
function M.tick()
    local now = os.clock()
    if now - look_t > 0.3 then
        look_t = now
        for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do pcall(online_page, bar) end
    end
    local on = false
    for _, bar in ipairs(FindAllOf("PauseMenuTabBarBP_C") or {}) do
        pcall(function()
            if bar:IsValid() and not bar:GetFName():ToString():find("^Default__") and bar:GetSelectedTabId():ToString() == ONLINE then on = true end
        end)
    end
    if on then read_input() end                           -- (only on ONLINE: see msettings.lua spots_read)
    -- (the pad's A and the keyboard's Enter, read by sm64net.dll straight from the controller while this is up: STORROR's
    -- menu keeps A to itself - "theres no way to select ... with A?", 2026-11-01)
    local NETD = lib.MOD_DIR .. "net\\"
    -- (the DLL started first: it clears its files as it starts, and took the first pad_on.txt with them - A did nothing,
    -- "A press still not working", 2026-11-01. And the file put back twice a second while the screen is up.)
    if on then
        local MP0 = _G.ARMP
        if MP0 then MP0.start() end
    end
    if on ~= pad_on or (on and now - pad_t > 0.5) then
        if on ~= pad_on then os.remove(NETD .. "pad.txt") end
        pad_on, pad_t = on, now
        if on then
            local f = io.open(NETD .. "pad_on.txt", "r")
            if f then f:close() else f = io.open(NETD .. "pad_on.txt", "w"); if f then f:close() end end
        else
            os.remove(NETD .. "pad_on.txt")
        end
    end
    if on and os.rename(NETD .. "pad.txt", NETD .. "pad.take") then
        local f = io.open(NETD .. "pad.take", "r")
        local text = f and f:read("*a") or ""
        if f then f:close() end
        os.remove(NETD .. "pad.take")
        local _, n = text:gsub("A", "")
        ev.ok = ev.ok + n
    end
    if not on then
        ev.up, ev.down, ev.ok, ev.back = 0, 0, 0, 0
        pw = nil                                          -- (off the tab: a password half put in is dropped)
        if ui then remove() end
        return
    end
    local MP = _G.ARMP
    if not MP then return end
    MP.start()
    if now - list_t > REFRESH and MP.status.state == "idle" then MP.list(); list_t = now end
    items = build_items(MP)
    fix_sel()
    local moved = false
    local function step(d)
        for _ = 1, #items do
            sel = sel + d
            if sel < 1 then sel = #items elseif sel > #items then sel = 1 end
            if pickable(sel) then break end
        end
        moved = true
    end
    local press = ev.ok > 0
    local back = (ev.back or 0) > 0
    if pw and not pw.done then
        -- (putting in the password: Up and Down change the digit on, Right goes to the next, Left to the one before -
        -- from the first, out)
        local d = pw.digits[pw.pos]
        if ev.up > 0 then d = (d + 1) % 10; moved = true end
        if ev.down > 0 then d = (d + 9) % 10; moved = true end
        pw.digits[pw.pos] = d
        if press then
            pw.pos = pw.pos + 1
            if pw.pos > DIGITS then pw.done = true; pw.pos = DIGITS end
            moved = true
            press = false
        elseif back then
            if pw.pos > 1 then pw.pos = pw.pos - 1 else pw = nil end
            moved = true
        end
        items = build_items(MP)
        fix_sel()
    else
        if ev.up > 0 then step(-1) end
        if ev.down > 0 then step(1) end
        if back and pw and pw.done then pw.done = false; moved = true; items = build_items(MP); fix_sel() end
    end
    ev.up, ev.down, ev.ok, ev.back = 0, 0, 0, 0
    if press and pickable(sel) then act(MP, items[sel].act); items = build_items(MP); fix_sel() end
    local key = tostring(sel)
    for _, it in ipairs(items) do key = key .. "|" .. it.text end
    if ui and not (pcall(function() return ui.widget:IsValid() end) and ui.widget:IsValid() and ui.widget:IsInViewport()) then ui = nil end
    if ui and key == shown_key then return end
    local ok, err = pcall(draw)
    if ok then shown_key = key else log("multiplayer screen: %s", tostring(err)) end
end

return M
