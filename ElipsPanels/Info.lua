-- Info.lua
-- The information bar: one thin panel, centered at the top of the screen
-- to start with, with the things worth a glance:
--
--   Time            your clock (the game's 12 or 24 hour setting)
--   Latency         to the world server, in milliseconds
--   FPS             frames per second
--   XP per hour     this session (not shown at the level cap)
--   Gold per hour   this session: what you have now against what you had;
--                   with Auctionator, plus what the things you looted are
--                   worth at its latest prices (Worth.lua)
--   Addon CPU       the share of each frame the addons take
--   Memory          what the addons (and the game's own interface code)
--                   hold together
--   Durability      your most worn piece
--   Bag space       free slots
--   Currencies      any from your currency tab that you tick; Tarnished
--                   Undermine Reals unless you untick them
--
-- Right-click the bar and a list opens under it: tick what it shows.
-- Shift-click it to start the per-hour counts again. Point at it for the
-- details (realm time, both latencies, the addons using the most memory,
-- what the session has earned). /ep move moves it; /ep info shows or hides it.

local _, ns = ...
local W = ns.W

local HEIGHT = 20
local PAD, GAP = 10, 14
local LEFT = PAD             -- where the first piece starts
local SNAP = 12              -- this near the screen's top edge (or its middle) and it sits exactly there
-- Against the top edge the bar hangs from it: this much of it is above the
-- screen. (The panel's edge art has a see-through margin outside its gold
-- line, which left a sliver of the world showing along the top. Two pixels
-- puts that margin off the screen and keeps the gold line on it.)
local OVER = 2
local SPOT = { "TOP", "TOP", 0, 0 }      -- against the top edge of the screen, in the middle
local LABEL = "|cffdbb575"     -- the labels: the suite's antique gold
local GOOD, FAIR, POOR = "|cff5fe65f", "|cffffd633", "|cffff5040"
-- Each piece's icon. Where the game has a picture for the thing, the
-- game's: its coins, a bag, an anvil, each currency's own icon. For the
-- rest (a clock, signal bars, a screen, a star for experience, a chip, a
-- memory stick) the addon's own small glyphs in the headings' gold
-- (Media\Info, drawn by tools/art/info/make_icons.py). Written into the
-- text, at its size. An icon stands in for the word (cpu, mem, bags...);
-- units stay (ms, fps, mb, /h).
local GLYPHS = "Interface\\AddOns\\ElipsPanels\\Media\\Info\\"
local ART = {
    time = GLYPHS .. "Clock", latency = GLYPHS .. "Latency", fps = GLYPHS .. "Frames", xp = GLYPHS .. "Experience",
    cpu = GLYPHS .. "CPU", memory = GLYPHS .. "Memory",
    durability = "Interface\\Icons\\Trade_BlackSmithing", bags = "Interface\\Icons\\INV_Misc_Bag_08",
    gold = "Interface\\MoneyFrame\\UI-GoldIcon", silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}
local icon = {}              -- the same, as text escapes at the bar's text size (ApplyFont)
local iconSize = 12          -- the bar's text size
local REALS = "Tarnished Undermine Real"   -- the currency shown unless you untick it
local CURRENCY_ROWS = 12     -- currencies the list under the bar shows at once (the mouse wheel moves through more)
local MEMORY_EVERY = 15      -- seconds between memory readings
local RATE_AFTER = 30        -- seconds of session before a per-hour figure means anything
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }   -- what wears out

local panel, menu
local hung = false           -- against the top edge of the screen
local segments = {}          -- key -> font string
local session = { at = 0, money = 0, xp = 0, lastXP = nil, lastMax = nil }
local lastMinute, timeText
local memoryAt, memoryMB = -100, 0
local durability, freeSlots, allSlots
local status = { ticks = 0 }
ns.infoStatus = status

local function Settings()
    local db = ns.db
    if type(db.info) ~= "table" then
        db.info = {}
    end
    if type(db.info.items) ~= "table" then
        db.info.items = {}
    end
    if type(db.info.currencies) ~= "table" then
        db.info.currencies = {}
    end
    return db.info
end

local function Call(name, ...)
    local fn = rawget(_G, name)
    if not fn then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
    return nil
end

------------------------------------------------------------------------------
-- What each piece says
------------------------------------------------------------------------------
-- Each returns false when it has nothing to show (the piece is left out).

local function Military()
    local cvars = rawget(_G, "C_CVar")
    local get = (cvars and cvars.GetCVarBool) or rawget(_G, "GetCVarBool")
    if get then
        local ok, on = pcall(get, "timeMgrUseMilitaryTime")
        if ok then
            return ns.Bool(on, true)
        end
    end
    return true
end

local function ShowTime(text)
    local now = time()
    local minute = math.floor(now / 60)
    if minute ~= lastMinute or not timeText then
        lastMinute = minute
        local stamp = rawget(_G, "date")
        timeText = stamp and (Military() and stamp("%H:%M", now) or stamp("%I:%M %p", now):gsub("^0", "")) or "?"
    end
    text:SetFormattedText("%s %s", icon.time, timeText)
    return true
end

local function Latency()
    local _, _, home, world = Call("GetNetStats")
    return ns.Num(home), ns.Num(world)
end

local function ShowLatency(text)
    local home, world = Latency()
    local ms = world or home
    if not ms then
        return false
    end
    text:SetFormattedText("%s %s%d|r%sms|r", icon.latency, ms < 120 and GOOD or (ms < 300 and FAIR or POOR), ms, LABEL)
    return true
end

local function ShowFPS(text)
    local fps = ns.Num(Call("GetFramerate"))
    if not fps then
        return false
    end
    text:SetFormattedText("%s %s%d|r%sfps|r", icon.fps, fps >= 50 and GOOD or (fps >= 25 and FAIR or POOR), fps + 0.5, LABEL)
    return true
end

local function AtLevelCap()
    local level = ns.Num(Call("UnitLevel", "player"))
    local cap = ns.Num(Call("GetMaxPlayerLevel")) or ns.Num(Call("GetMaxLevelForPlayerExpansion"))
    local most = ns.Num(Call("UnitXPMax", "player"))
    return (level and cap and level >= cap) or most == nil or most <= 0
end

local function Elapsed()
    return GetTime() - session.at
end

local function PerHour(amount)
    local elapsed = Elapsed()
    if elapsed < RATE_AFTER then
        return nil
    end
    return amount * 3600 / elapsed
end

local function ShowXP(text)
    if AtLevelCap() then
        return false
    end
    local rate = PerHour(session.xp)
    if not rate then
        text:SetFormattedText("%s -%s/h|r", icon.xp, LABEL)
    elseif rate >= 10000 then
        text:SetFormattedText("%s %.1fk%s/h|r", icon.xp, rate / 1000, LABEL)
    else
        text:SetFormattedText("%s %d%s/h|r", icon.xp, rate, LABEL)
    end
    return true
end

local function MoneyNow()
    return ns.Num(Call("GetMoney"))
end

local function ShowGold(text)
    local money = MoneyNow()
    if not money then
        return false
    end
    -- Coin gained, and (with Auctionator) what the loot is worth.
    local rate = PerHour(money - session.money + ns.LootEarnings())
    if not rate then
        text:SetFormattedText("-%s/h|r", LABEL)
        return true
    end
    local sign = rate < 0 and (POOR .. "-|r") or ""
    local copper = math.floor(math.abs(rate) + 0.5)
    local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
    if gold > 0 then
        text:SetFormattedText("%s%d%s %02d%s%s/h|r", sign, gold, icon.gold, silver, icon.silver, LABEL)
    else
        text:SetFormattedText("%s%d%s %02d%s%s/h|r", sign, silver, icon.silver, copper % 100, icon.copper, LABEL)
    end
    return true
end

-- The addons' share of each frame, from the game's own profiler: the time
-- all addons took on average over the last 60 frames, against the frame's.
local function AddonCPU()
    local profiler = rawget(_G, "C_AddOnProfiler")
    local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
    if not (profiler and metric and profiler.GetOverallMetric and profiler.GetApplicationMetric) then
        return nil
    end
    if profiler.IsEnabled then
        local okOn, on = pcall(profiler.IsEnabled)
        if okOn and ns.Bool(on, true) == false then
            return nil
        end
    end
    local okA, addons = pcall(profiler.GetOverallMetric, metric)
    local okF, frame = pcall(profiler.GetApplicationMetric, metric)
    addons, frame = okA and ns.Num(addons) or nil, okF and ns.Num(frame) or nil
    if not (addons and frame and frame > 0) then
        return nil
    end
    return math.max(0, math.min(100, addons / frame * 100)), addons, frame
end

local function ShowCPU(text)
    local share = AddonCPU()
    if not share then
        return false
    end
    text:SetFormattedText("%s %s%d%%|r", icon.cpu, share < 15 and GOOD or (share < 35 and FAIR or POOR), share + 0.5)
    return true
end

local function ShowMemory(text)
    local now = GetTime()
    if now - memoryAt >= MEMORY_EVERY then
        memoryAt = now
        -- (Everything the addons and the game's own interface hold, in one
        -- figure the game keeps anyway: no walk through every addon.)
        memoryMB = collectgarbage("count") / 1024
    end
    text:SetFormattedText("%s %d%smb|r", icon.memory, memoryMB + 0.5, LABEL)
    return true
end

local function ReadDurability()
    local get = rawget(_G, "GetInventoryItemDurability")
    durability = nil
    if not get then
        return
    end
    for index = 1, #SLOTS do
        local ok, now, most = pcall(get, SLOTS[index])
        now, most = ok and ns.Num(now) or nil, ok and ns.Num(most) or nil
        if now and most and most > 0 then
            local left = now / most * 100
            if not durability or left < durability then
                durability = left
            end
        end
    end
end

local function ShowDurability(text)
    if not durability then
        return false
    end
    text:SetFormattedText("%s %s%d%%|r", icon.durability, durability > 50 and GOOD or (durability > 20 and FAIR or POOR), durability)
    return true
end

local function ReadBags()
    freeSlots, allSlots = nil, nil
    local bags = rawget(_G, "C_Container")
    if not (bags and bags.GetContainerNumFreeSlots and bags.GetContainerNumSlots) then
        return
    end
    local free, all = 0, 0
    for bag = 0, 4 do
        local okFree, slots = pcall(bags.GetContainerNumFreeSlots, bag)
        local okAll, size = pcall(bags.GetContainerNumSlots, bag)
        free = free + (okFree and ns.Num(slots) or 0)
        all = all + (okAll and ns.Num(size) or 0)
    end
    freeSlots, allSlots = free, all
end

local function ShowBags(text)
    if not freeSlots then
        return false
    end
    text:SetFormattedText("%s %s%d|r", icon.bags, freeSlots > 8 and GOOD or (freeSlots > 2 and FAIR or POOR), freeSlots)
    return true
end

------------------------------------------------------------------------------
-- Currencies
------------------------------------------------------------------------------
-- Whatever is on your currency tab can go on the bar: its own icon and how
-- many you have (red once you're at its cap). Read when the game says a
-- currency changed, not every second.

local currencies = {}        -- in your currency tab's order: { id, name, art, have, cap }
local currencyTexts = {}     -- a currency's ID -> its text on the bar

-- One of the game's square icons as text, its edges trimmed.
local function SquareIcon(texture)
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(texture), iconSize + 1, iconSize + 1)
end

local function ReadCurrencies()
    for index = #currencies, 1, -1 do
        currencies[index] = nil
    end
    local api = rawget(_G, "C_CurrencyInfo")
    if not (api and api.GetCurrencyListSize and api.GetCurrencyListInfo) then
        return
    end
    local okSize, size = pcall(api.GetCurrencyListSize)
    for index = 1, (okSize and ns.Num(size)) or 0 do
        local ok, info = pcall(api.GetCurrencyListInfo, index)
        if ok and type(info) == "table" and not ns.IsSecret(info) and ns.Bool(info.isHeader, false) ~= true then
            local name, id = ns.Str(info.name), ns.Num(info.currencyID)
            if not id and api.GetCurrencyListLink then
                local okLink, link = pcall(api.GetCurrencyListLink, index)
                id = okLink and type(link) == "string" and not ns.IsSecret(link) and tonumber(link:match("currency:(%d+)")) or nil
            end
            if name and id then
                local have, cap, texture = ns.Num(info.quantity), ns.Num(info.maxQuantity), ns.Num(info.iconFileID)
                if not (have and texture) and api.GetCurrencyInfo then
                    -- (Where the list holds only the name: the currency's own record.)
                    local okOwn, own = pcall(api.GetCurrencyInfo, id)
                    if okOwn and type(own) == "table" and not ns.IsSecret(own) then
                        have, cap = have or ns.Num(own.quantity), cap or ns.Num(own.maxQuantity)
                        texture = texture or ns.Num(own.iconFileID)
                    end
                end
                currencies[#currencies + 1] = { id = id, name = name, have = have, cap = (cap and cap > 0) and cap or nil,
                    art = texture and SquareIcon(texture) or "" }
            end
        end
    end
    status.currencies = #currencies
end

local function CurrencyWanted(entry)
    local chosen = Settings().currencies[entry.id]
    if chosen == nil then
        return entry.name == REALS
    end
    return chosen == true
end

-- In the order they sit on the bar. `on`: shown unless switched off.
local ITEMS = {
    { key = "time", label = "Time", show = ShowTime, on = true },
    { key = "latency", label = "Latency", show = ShowLatency, on = true },
    { key = "fps", label = "Frames per second", show = ShowFPS, on = true },
    { key = "xp", label = "Experience per hour", show = ShowXP, on = true, note = "not at the level cap" },
    { key = "gold", label = "Gold per hour", show = ShowGold, on = true },
    { key = "cpu", label = "Addon CPU", show = ShowCPU, on = true },
    { key = "memory", label = "Memory (addons and interface)", show = ShowMemory, on = true },
    { key = "durability", label = "Durability", show = ShowDurability, on = true },
    { key = "bags", label = "Bag space", show = ShowBags, on = true },
}

local function Wanted(item)
    local chosen = Settings().items[item.key]
    if chosen == nil then
        return item.on == true
    end
    return chosen == true
end

------------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------------

local Tick, ShowTip, ToggleMenu   -- below

local function ApplyFont()
    local size = tonumber(Settings().size) or 12
    iconSize = size
    -- The glyphs a touch taller than the text; the game's square icons with
    -- their edges trimmed; the coins as the game writes them.
    for key, path in pairs(ART) do
        if path:find("MoneyFrame", 1, true) then
            icon[key] = string.format("|T%s:%d:%d:1:0|t", path, size, size)
        elseif path:find("Interface\\Icons", 1, true) then
            icon[key] = SquareIcon(path)
        else
            icon[key] = string.format("|T%s:%d:%d:0:0|t", path, size + 2, size + 2)
        end
    end
    ReadCurrencies()
    for _, texts in ipairs({ segments, currencyTexts }) do
        for _, text in pairs(texts) do
            local font = text:GetFont()
            text:SetFont(font or "Fonts\\FRIZQT__.TTF", size, "")
            text.slot = 0
        end
    end
    if panel then
        local over = hung and OVER or 0
        panel:SetHeight(size + 14 + over)
        if panel.elipsTheme then
            -- The theme's glow fills the bar (a panel's is as tall as its heading).
            panel.elipsTheme.glow:SetHeight(size + 8 + over)
        end
    end
end

-- Where it sits: where you left it, and within a few pixels of the screen's
-- top edge, hung from it; within a few of the middle, dead center.
local function Place()
    local pos = Settings().pos
    local wide, tall = ns.Num(UIParent:GetWidth()), ns.Num(UIParent:GetHeight())
    local x, y
    if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" and wide and tall then
        x, y = pos[1], pos[2]
        if math.abs(x - wide / 2) <= SNAP then
            x = wide / 2
        end
        hung = tall - (y + (iconSize + 14) / 2) <= SNAP
    else
        x, hung = (wide or 0) / 2, true      -- nowhere saved: the top, in the middle
    end
    -- (Hung from the top it reaches past the screen's edge, which the game
    -- would otherwise push back.)
    panel:SetClampedToScreen(not hung)
    panel:SetHeight(iconSize + 14 + (hung and OVER or 0))
    if panel.elipsTheme then
        panel.elipsTheme.glow:SetHeight(iconSize + 8 + (hung and OVER or 0))
    end
    panel:ClearAllPoints()
    if hung then
        panel:SetPoint("TOP", UIParent, "TOP", x - (wide or 0) / 2, OVER)
    else
        panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
end

local function NewText()
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    text.slot = 0
    return text
end

local function Build()
    local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsInfo", UIParent, "BackdropTemplate")
    panel = (ok and made) or CreateFrame("Frame", "ElipsPanelsInfo", UIParent)
    panel:SetSize(200, HEIGHT)
    panel:SetFrameStrata("MEDIUM")
    -- A panel's heading, and nothing under it: the dark gold-edged panel,
    -- the theme's glow from the top, and the line that runs from gold into
    -- the theme's color along the bottom. (No emblem: at this size it is a
    -- speck.)
    W.PanelBackdrop(panel, 0.88)
    W.ThemePanel(panel, nil, W.NATURE)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 3, 3)      -- from the panel's edge to its edge
    line:SetPoint("BOTTOMRIGHT", -3, 3)
    W.AccentLine(line, W.NATURE, 0.6)
    panel.line = line
    for _, item in ipairs(ITEMS) do
        segments[item.key] = NewText()
    end
    ApplyFont()
    Place()
    W.QuietInCombat(panel, function() return menu end)   -- out of the way in a fight; the mouse brings it back
    panel:EnableMouse(true)
    panel:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ToggleMenu()
        elseif button == "LeftButton" and IsShiftKeyDown() then
            ns.InfoRestart()
            ns.Print("the information bar's per-hour counts start again from now.")
        end
    end)
    panel:SetScript("OnEnter", function() ShowTip() end)
    panel:SetScript("OnLeave", function()
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:Hide()
        end
    end)
    panel:Hide()
end

-- Each piece keeps the widest it has been, so the bar doesn't twitch as
-- digits change; the bar is as wide as its pieces and stays centered.
local order = {}             -- the texts on the bar, left to right (made new each look)

local function Layout()
    local x = LEFT
    local shown = 0
    for index = 1, #order do
        local text = order[index]
        if text.on then
            local width = math.ceil(ns.Num(text:GetStringWidth()) or 30)
            if width > text.slot or text.slot - width > 24 then
                text.slot = width
            end
            text:ClearAllPoints()
            -- (A touch above the middle of what shows, clear of the line below.)
            text:SetPoint("CENTER", panel, "LEFT", x + text.slot / 2, hung and (1 - OVER / 2) or 1)
            text:Show()
            x = x + text.slot + GAP
            shown = shown + 1
        else
            text:Hide()
        end
    end
    local width = math.max(60, x - GAP + PAD)
    if panel.wide ~= width then
        panel.wide = width
        panel:SetWidth(width)
    end
    status.shown = shown
end

Tick = function()
    if not (panel and panel:IsShown()) then
        return
    end
    status.ticks = status.ticks + 1
    for index = #order, 1, -1 do
        order[index] = nil
    end
    for _, item in ipairs(ITEMS) do
        local text = segments[item.key]
        text.on = Wanted(item) and item.show(text) ~= false
        order[#order + 1] = text
    end
    -- The currencies after them, in your currency tab's order.
    for _, text in pairs(currencyTexts) do
        text.on = false
    end
    for _, entry in ipairs(currencies) do
        if CurrencyWanted(entry) and entry.have then
            local text = currencyTexts[entry.id]
            if not text then
                text = NewText()
                local font = text:GetFont()
                text:SetFont(font or "Fonts\\FRIZQT__.TTF", iconSize, "")
                currencyTexts[entry.id] = text
            end
            text.on = true
            text:SetFormattedText("%s %s%d|r", entry.art, (entry.cap and entry.have >= entry.cap) and POOR or "|cffffffff", entry.have)
            order[#order + 1] = text
        end
    end
    for _, text in pairs(currencyTexts) do
        if not text.on and text:IsShown() then
            text:Hide()
        end
    end
    Layout()
end

local looping = false
local function Loop()
    looping = false
    if panel and panel:IsShown() then
        Tick()
        looping = true
        C_Timer.After(1, Loop)
    end
end

local function Apply()
    local settings = Settings()
    if settings.show == false then
        if panel then
            panel:Hide()
        end
        if menu then
            menu:Hide()
        end
        return
    end
    if not panel then
        Build()
    end
    ApplyFont()
    ReadDurability()
    ReadBags()
    panel:Show()
    Tick()
    if not looping then
        looping = true
        C_Timer.After(1, Loop)
    end
end
ns.ApplyInfoBar = Apply

function ns.InfoSettings()
    return Settings()
end

function ns.InfoRestart()
    session.at = GetTime()
    session.money = MoneyNow() or 0
    session.xp = 0
    ns.LootTallyRestart()
    if panel and panel:IsShown() then
        Tick()
    end
end

------------------------------------------------------------------------------
-- The tooltip: the details
------------------------------------------------------------------------------

local function Coins(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper) + 0.5)
    return string.format("%s%dg %02ds %02dc", sign, math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- The addons holding the most memory. Asking the game for every addon's
-- share takes a moment, so it is done here (when you point), not on the bar.
local function TopMemory(count)
    local update, usage = rawget(_G, "UpdateAddOnMemoryUsage"), rawget(_G, "GetAddOnMemoryUsage")
    local addons = rawget(_G, "C_AddOns")
    if not (update and usage and addons and addons.GetNumAddOns and addons.GetAddOnInfo) then
        return nil
    end
    pcall(update)
    local list = {}
    local okCount, total = pcall(addons.GetNumAddOns)
    for index = 1, (okCount and ns.Num(total)) or 0 do
        local okUse, kb = pcall(usage, index)
        kb = okUse and ns.Num(kb) or 0
        if kb > 0 then
            local okName, name = pcall(addons.GetAddOnInfo, index)
            list[#list + 1] = { name = okName and ns.Str(name) or ("addon " .. index), kb = kb }
        end
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    for index = #list, count + 1, -1 do
        list[index] = nil
    end
    return list
end

ShowTip = function()
    local tip = rawget(_G, "GameTooltip")
    if not (tip and panel) or (menu and menu:IsShown()) then
        return
    end
    tip:SetOwner(panel, "ANCHOR_BOTTOM", 0, -4)
    tip:SetText("Information", 1, 1, 1)
    local hour, minute = Call("GetGameTime")
    hour, minute = ns.Num(hour), ns.Num(minute)
    if hour and minute then
        tip:AddDoubleLine("Realm time", string.format("%d:%02d", hour, minute), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local home, world = Latency()
    if home or world then
        tip:AddDoubleLine("Latency", string.format("home %s ms, world %s ms", tostring(home or "?"), tostring(world or "?")),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    local share, addons, frame = AddonCPU()
    if share then
        tip:AddDoubleLine("Addon CPU", string.format("%.2f of each frame's %.1f ms", addons, frame), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local elapsed = Elapsed()
    tip:AddDoubleLine("This session", string.format("%d:%02d", math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60),
        0.8, 0.8, 0.8, 1, 1, 1)
    local money = MoneyNow()
    if money then
        tip:AddDoubleLine("Gold", string.format("%s (%s since)", Coins(money), Coins(money - session.money)), 0.8, 0.8, 0.8, 1, 1, 1)
        if ns.PricesKnown() then
            -- What gold per hour adds to the coin: the loot at Auctionator's prices.
            local tally = ns.LootTally()
            tip:AddDoubleLine("Loot", string.format("%s, %d %s at Auctionator's prices", Coins(tally.value), tally.items,
                tally.items == 1 and "item" or "items"), 0.8, 0.8, 0.8, 1, 1, 1)
            if tally.aside > 0 then
                tip:AddDoubleLine("Not counted", string.format("%s from vendors and the mail", Coins(tally.aside)), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            tip:AddDoubleLine("Earned", Coins(money - session.money + ns.LootEarnings()), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    if not AtLevelCap() then
        local now, most = ns.Num(Call("UnitXP", "player")), ns.Num(Call("UnitXPMax", "player"))
        local rate = PerHour(session.xp)
        local left = (now and most and rate and rate > 0) and (most - now) / rate * 60 or nil
        tip:AddDoubleLine("Experience", string.format("%d this session%s", session.xp,
            left and string.format(", level in %d min", left + 0.5) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if freeSlots then
        tip:AddDoubleLine("Bags", string.format("%d of %d free", freeSlots, allSlots or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    for _, entry in ipairs(currencies) do
        if CurrencyWanted(entry) and entry.have then
            tip:AddDoubleLine(entry.name, entry.cap and string.format("%d of %d", entry.have, entry.cap) or tostring(entry.have),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    tip:AddDoubleLine("Memory", string.format("%d mb, addons and the game's interface", collectgarbage("count") / 1024 + 0.5),
        0.8, 0.8, 0.8, 1, 1, 1)
    local top = TopMemory(5)
    if top and #top > 0 then
        tip:AddLine(" ")
        tip:AddLine("Addons holding the most", 0.8, 0.8, 0.8)
        for _, entry in ipairs(top) do
            tip:AddDoubleLine(entry.name, string.format("%.1f mb", entry.kb / 1024), 1, 1, 1, 1, 1, 1)
        end
    end
    tip:AddLine(" ")
    tip:AddLine("Right-click: choose what it shows", 0.6, 0.8, 1)
    tip:AddLine("Shift-click: start the per-hour counts again", 0.6, 0.8, 1)
    tip:Show()
end

------------------------------------------------------------------------------
-- The list under the bar: what it shows
------------------------------------------------------------------------------

local ROW = 20
local MENU_HEADER = 24
local FillMenu   -- below

-- A line of the list: a box that's ticked or not, and what it is.
local function MenuRow(onClick)
    local row = CreateFrame("Button", nil, menu)
    row:SetSize(194, ROW)
    local box = row:CreateTexture(nil, "BACKGROUND")
    box:SetSize(13, 13)
    box:SetPoint("LEFT", 2, 0)
    box:SetColorTexture(W.PANEL_EDGE[1], W.PANEL_EDGE[2], W.PANEL_EDGE[3], 1)
    local inner = row:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.10, 0.09, 0.08, 1)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    row.tick:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    row.tick:SetColorTexture(W.NATURE[1], W.NATURE[2], W.NATURE[3], 1)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    row.label:SetWidth(170)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(W.NATURE[1], W.NATURE[2], W.NATURE[3], 0.15)
    row:SetScript("OnClick", onClick)
    return row
end

local function ClickItem(self)
    Settings().items[self.item.key] = not Wanted(self.item)
    self.tick:SetShown(Wanted(self.item))
    Tick()
end

local function ClickCurrency(self)
    Settings().currencies[self.entry.id] = not CurrencyWanted(self.entry)
    self.tick:SetShown(CurrencyWanted(self.entry))
    Tick()
end

local function BuildMenu()
    local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsInfoMenu", UIParent, "BackdropTemplate")
    menu = (ok and made) or CreateFrame("Frame", "ElipsPanelsInfoMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetWidth(210)
    menu:SetPoint("TOP", panel, "BOTTOM", 0, -2)
    menu:EnableMouse(true)
    W.PanelBackdrop(menu, 0.95)
    W.ThemePanel(menu, nil, W.NATURE)
    local crest = menu:CreateTexture(nil, "ARTWORK")
    crest:SetTexture("Interface\\AddOns\\ElipsPanels\\Media\\ElipsPanels")
    crest:SetSize(14, 14)
    crest:SetPoint("TOPLEFT", 8, -5)
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("LEFT", crest, "RIGHT", 5, 0)
    menu.title:SetText("Information bar")
    local line = menu:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -MENU_HEADER)
    line:SetPoint("TOPRIGHT", -8, -MENU_HEADER)
    W.AccentLine(line, W.NATURE, 0.6)
    menu.rows = {}
    for index, item in ipairs(ITEMS) do
        local row = MenuRow(ClickItem)
        row:SetPoint("TOPLEFT", 8, -MENU_HEADER - 5 - (index - 1) * ROW)
        row.label:SetText(string.format("%s %s%s", icon[item.key] or "", item.label,
            item.note and string.format(" |cff909090(%s)|r", item.note) or ""))
        row.item = item
        menu.rows[index] = row
    end
    -- Under them: your currencies.
    local top = MENU_HEADER + 5 + #ITEMS * ROW + 8
    menu.currencyTop = top + 18
    menu.currencyTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.currencyTitle:SetPoint("TOPLEFT", 10, -top)
    menu.currencyTitle:SetText("Currencies")
    local under = menu:CreateTexture(nil, "ARTWORK")
    under:SetHeight(1)
    under:SetPoint("TOPLEFT", 8, -(top + 14))
    under:SetPoint("TOPRIGHT", -8, -(top + 14))
    W.AccentLine(under, W.NATURE, 0.4)
    menu.currencyRows = {}
    menu.note = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.note:SetJustifyH("LEFT")
    menu.offset = 0
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, delta)
        menu.offset = (menu.offset or 0) - delta
        FillMenu()
    end)
    menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    menu.hint:SetPoint("BOTTOM", 0, 8)
    menu.hint:SetText("Right-click the bar again to close")
    local special = rawget(_G, "UISpecialFrames")
    if special then
        special[#special + 1] = "ElipsPanelsInfoMenu"
    end
    menu:Hide()
end

-- The ticks as they stand, and the currencies you have now.
FillMenu = function()
    for _, row in ipairs(menu.rows) do
        row.tick:SetShown(Wanted(row.item))
    end
    local total = #currencies
    local shown = math.min(CURRENCY_ROWS, total)
    menu.offset = math.max(0, math.min(menu.offset or 0, total - shown))
    for index = 1, shown do
        local entry = currencies[index + menu.offset]
        local row = menu.currencyRows[index]
        if not row then
            row = MenuRow(ClickCurrency)
            row:SetPoint("TOPLEFT", 8, -menu.currencyTop - (index - 1) * ROW)
            menu.currencyRows[index] = row
        end
        row.entry = entry
        row.label:SetText(string.format("%s %s", entry.art, entry.name))
        row.tick:SetShown(CurrencyWanted(entry))
        row:Show()
    end
    for index = shown + 1, #menu.currencyRows do
        menu.currencyRows[index]:Hide()
    end
    local bottom = menu.currencyTop + shown * ROW
    local note = (total == 0 and "None on your currency tab yet.")
        or (total > shown and string.format("%d more: mouse wheel", total - shown)) or nil
    if note then
        menu.note:ClearAllPoints()
        menu.note:SetPoint("TOPLEFT", 12, -(bottom + 3))
        menu.note:SetText(note)
        menu.note:Show()
        bottom = bottom + 16
    else
        menu.note:Hide()
    end
    menu:SetHeight(bottom + 26)
end

ToggleMenu = function()
    if not menu then
        BuildMenu()
    end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    ReadCurrencies()
    FillMenu()
    Tick()
    local tip = rawget(_G, "GameTooltip")
    if tip then
        tip:Hide()
    end
    menu:Show()
end

------------------------------------------------------------------------------
-- Events, /ep info, /ep status
------------------------------------------------------------------------------

local function ReadXP()
    local now, most = ns.Num(Call("UnitXP", "player")), ns.Num(Call("UnitXPMax", "player"))
    if not (now and most) then
        return
    end
    if session.lastXP then
        if most ~= session.lastMax and now < session.lastXP then
            -- A level gained: the rest of the old one, and what's in the new.
            session.xp = session.xp + (session.lastMax - session.lastXP) + now
        elseif now > session.lastXP then
            session.xp = session.xp + (now - session.lastXP)
        end
    end
    session.lastXP, session.lastMax = now, most
end

ns.Hook("INIT", function()
    Settings()
    ns.On("PLAYER_ENTERING_WORLD", function()
        if session.at == 0 then
            session.at = GetTime()
            session.money = MoneyNow() or 0
            ReadXP()
        end
        Apply()
    end)
    ns.On("PLAYER_XP_UPDATE", ReadXP)
    ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, ReadXP) end)
    ns.On("UPDATE_INVENTORY_DURABILITY", ReadDurability)
    ns.On("PLAYER_EQUIPMENT_CHANGED", ReadDurability)
    ns.On("BAG_UPDATE_DELAYED", ReadBags)
    ns.On("CURRENCY_DISPLAY_UPDATE", function()
        ReadCurrencies()
        if menu and menu:IsShown() then
            FillMenu()
        end
        if panel and panel:IsShown() then
            Tick()
        end
    end)
    ns.RegisterMover({
        key = "info", label = "Information bar", width = 420, height = 26, center = true,
        default = SPOT,
        get = function() return Settings().pos end,
        set = function(pos)
            Settings().pos = pos
            if panel then
                Place()
                Tick()
            end
        end,
    })
end)

function ns.InfoCommand()
    local settings = Settings()
    settings.show = settings.show == false
    Apply()
    ns.Print(settings.show and "information bar shown. Right-click it to choose what it shows." or "information bar hidden. /ep info brings it back.")
end

function ns.InfoDiagLines()
    local settings = Settings()
    local on = {}
    for _, item in ipairs(ITEMS) do
        local text = segments[item.key]
        on[#on + 1] = string.format("%s %s", item.key, not Wanted(item) and "off" or ((text and text.on) and "shown" or "nothing to show"))
    end
    local share = AddonCPU()
    local coins = {}
    for _, entry in ipairs(currencies) do
        if CurrencyWanted(entry) then
            coins[#coins + 1] = string.format("%s (%d) %s", entry.name, entry.id, tostring(entry.have))
        end
    end
    return {
        string.format("Information bar: %s, %d looks | %s", settings.show == false and "off" or "on", status.ticks, table.concat(on, ", ")),
        string.format("  currencies on your tab %d, on the bar: %s", #currencies, #coins > 0 and table.concat(coins, ", ") or "none"),
        string.format("  session %d sec, xp %d, money then %s now %s | addon profiler %s | durability %s, bags %s",
            Elapsed(), session.xp, tostring(session.money), tostring(MoneyNow()), share and string.format("%.0f%%", share) or "not there",
            durability and string.format("%.0f%%", durability) or "not read", tostring(freeSlots)),
    }
end

ns.InfoInternals = {
    Panel = function() return panel end,
    Menu = function() return menu end,
    Segments = segments,
    Currencies = currencies,
    CurrencyTexts = currencyTexts,
    Session = session,
    Tick = function() Tick() end,
    Place = function() Place() end,
    Hung = function() return hung end,
    Items = ITEMS,
    ReadXP = ReadXP,
}

ns.commands.info = ns.InfoCommand
ns.statusParts[#ns.statusParts + 1] = function()
    return ns.InfoDiagLines()
end
