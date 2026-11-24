-- Leveling.lua
-- A small panel of leveling numbers, the kind the "XP per hour" WeakAuras
-- show; at the level cap it turns into the same for gold.
--
-- Leveling (below the level cap):
--   Level 23, and how far through it you are
--   XP per hour      this session (the information bar's session)
--   Time to level    at that rate
--   This level       time played at this level
--   XP per kill      the average of your last 10 kills
--   Kills to level   at that average
--   XP to go
--   Rested           your rested XP, as a share of a level
--
-- Gold (at the level cap, or always, as set):
--   Gold per hour    coin gained and, with Auctionator, what the loot is
--                    worth (the information bar's figure)
--   Earned           the same, in all
--   Coin             what your purse has gained
--   Loot             what you've looted is worth (with Auctionator)
--   Session          how long it has been running
--   Purse            what you have
--
-- /ep move moves it; /ep leveling shows or hides it. Settings on the Leveling
-- tab.
--
-- Time at this level is counted here from then on. The first time (for each
-- character, and after leveling with the addon off) the game is asked for it
-- once, which also prints the /played lines in chat.

local _, ns = ...
local W = ns.W

local WIDTH = 176
local PAD = 9
local TITLE = 22            -- the title and the rule under it
local ROW = 14
local DEFAULT_SPOT = { "TOPLEFT", "TOPLEFT", 24, -240 }
local RECENT_KILLS = 10     -- XP per kill: over this many of the last kills
local KILL_WINDOW = 1.5     -- seconds between a kill's line in chat and its XP arriving
local SAVE_EVERY = 60       -- seconds between savings of the time at this level
local LABEL, VALUE, DIM = { 0.78, 0.74, 0.66 }, { 1, 1, 1 }, { 0.55, 0.52, 0.47 }

local LEVEL_ROWS = {
    { key = "rate", label = "XP per hour" },
    { key = "eta", label = "Time to level" },
    { key = "played", label = "This level" },
    { key = "perKill", label = "XP per kill" },
    { key = "kills", label = "Kills to level" },
    { key = "togo", label = "XP to go" },
    { key = "rested", label = "Rested" },
}
local GOLD_ROWS = {
    { key = "goldRate", label = "Gold per hour" },
    { key = "earned", label = "Earned" },
    { key = "coin", label = "Coin" },
    { key = "loot", label = "Loot" },
    { key = "session", label = "Session" },
    { key = "purse", label = "Purse" },
}
ns.LEVELING_ROWS, ns.LEVELING_GOLD_ROWS = LEVEL_ROWS, GOLD_ROWS

local panel
local status = { mode = "not shown yet", sync = "not asked", kills = 0, secretLines = 0 }
local kills = { count = 0, xp = 0, recent = {} }       -- this session
local lastXP, lastMax                                  -- your XP when last read
local pendingKills, pendingAt = 0, 0                   -- kills seen in chat whose XP hasn't arrived
local loose                                            -- XP that arrived before any kill line: { amount, at }

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

local function Settings()
    local db = ns.db
    if type(db.leveling) ~= "table" then
        db.leveling = {}
    end
    local settings = db.leveling
    if type(settings.rows) ~= "table" then
        settings.rows = {}
    end
    if type(settings.chars) ~= "table" then
        settings.chars = {}
    end
    return settings
end
ns.LevelingSettings = Settings

-- What's kept for each character: the level it was last seen at and the
-- time played at it.
local function Character()
    local settings = Settings()
    local realm = rawget(_G, "GetRealmName")
    local key = tostring(UnitName("player") or "?") .. "-" .. tostring(realm and realm() or "")
    if type(settings.chars[key]) ~= "table" then
        settings.chars[key] = {}
    end
    return settings.chars[key]
end

------------------------------------------------------------------------------
-- Time played at this level
------------------------------------------------------------------------------

local countingFrom          -- GetTime() when the saved seconds were last brought up to date
local asked = false         -- the game has been asked this session (once is enough: it prints in chat)

local function Level()
    return ns.Num(Call("UnitLevel", "player"))
end

local function PlayedThisLevel()
    local record = Character()
    if type(record.seconds) ~= "number" or record.level ~= Level() or not countingFrom then
        return nil
    end
    return record.seconds + (GetTime() - countingFrom)
end

-- The seconds so far go into the saved record (so a crash loses a minute at
-- most), and the count goes on from now.
local function SavePlayed()
    local record = Character()
    if type(record.seconds) == "number" and countingFrom then
        record.seconds = record.seconds + (GetTime() - countingFrom)
        countingFrom = GetTime()
    end
end

-- The game's own figure (from asking it, or from you typing /played).
local function PlayedAnswer(_, atLevel)
    atLevel = ns.Num(atLevel)
    local level = Level()
    if not (atLevel and level) then
        return
    end
    local record = Character()
    record.level, record.seconds = level, atLevel
    countingFrom = GetTime()
    status.sync = "the game's figure"
end

-- At login: carry on counting, or (nothing kept for this level) ask once.
local function StartPlayed(ask)
    local record, level = Character(), Level()
    if not level then
        return
    end
    if record.level == level and type(record.seconds) == "number" then
        countingFrom = countingFrom or GetTime()
        if status.sync == "not asked" then
            status.sync = "counted here"
        end
        return
    end
    record.level, record.seconds = level, nil
    countingFrom = nil
    if ask and not asked and rawget(_G, "RequestTimePlayed") then
        asked = true
        status.sync = "asked"
        pcall(RequestTimePlayed)
    end
end

local function LeveledUp(level)
    level = ns.Num(level) or Level()
    local record = Character()
    record.level, record.seconds = level, 0
    countingFrom = GetTime()
    status.sync = "counted here"
end

------------------------------------------------------------------------------
-- Kills
------------------------------------------------------------------------------

-- The start of the line the game prints for a kill ("%s dies, you gain %d
-- experience." and its longer forms), as a pattern: up to its number.
local killHead
local function KillHead()
    if killHead ~= nil then
        return killHead
    end
    local format = rawget(_G, "COMBATLOG_XPGAIN_FIRSTPERSON")
    killHead = "^.+ dies, you gain "
    if type(format) == "string" then
        local head = format:match("^(.-)%%%d?%$?d")
        if head and head:find("%%%d?%$?s") then
            head = head:gsub("%%%d?%$?s", "\1")
            head = head:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            killHead = "^" .. head:gsub("\1", ".+")
        end
    end
    return killHead
end

local function CountKill(amount)
    kills.count = kills.count + 1
    kills.xp = kills.xp + amount
    local recent = kills.recent
    recent[#recent + 1] = amount
    if #recent > RECENT_KILLS then
        table.remove(recent, 1)
    end
    status.kills = kills.count
end

local function XPPerKill()
    local recent = kills.recent
    if #recent == 0 then
        return nil
    end
    local sum = 0
    for _, amount in ipairs(recent) do
        sum = sum + amount
    end
    return sum / #recent
end

-- A line about XP in chat. A kill's names the mob first; a quest's doesn't.
local function XPLine(text)
    local kill
    if ns.IsSecret(text) then
        -- (Hidden in a fight: XP gained in a fight is a kill's.)
        status.secretLines = status.secretLines + 1
        kill = ns.inCombat == true
    else
        kill = type(text) == "string" and text:find(KillHead()) ~= nil
    end
    if not kill then
        return
    end
    local now = GetTime()
    if loose and now - loose.at <= KILL_WINDOW then
        -- Its XP got here first.
        CountKill(loose.amount)
        loose = nil
    else
        pendingKills, pendingAt = pendingKills + 1, now
    end
end

-- Your XP changed: how much came, and whether a kill brought it.
local function XPChanged()
    local now, most = ns.Num(Call("UnitXP", "player")), ns.Num(Call("UnitXPMax", "player"))
    if not (now and most) then
        return
    end
    local gained = 0
    if lastXP then
        if most ~= lastMax and now < lastXP then
            gained = (lastMax - lastXP) + now          -- a level gained
        elseif now > lastXP then
            gained = now - lastXP
        end
    end
    lastXP, lastMax = now, most
    if gained <= 0 then
        return
    end
    local at = GetTime()
    if pendingKills > 0 and at - pendingAt <= KILL_WINDOW then
        -- (Several kills at once: the XP is shared out between them.)
        for _ = 1, pendingKills do
            CountKill(gained / pendingKills)
        end
        pendingKills = 0
    else
        pendingKills = 0
        loose = { amount = gained, at = at }
    end
end

function ns.LevelingRestart()
    kills.count, kills.xp, kills.recent = 0, 0, {}
    pendingKills, loose = 0, nil
    status.kills = 0
    if panel and ns.UpdateLeveling then
        ns.UpdateLeveling()
    end
end

------------------------------------------------------------------------------
-- Words for the numbers
------------------------------------------------------------------------------

local function Commas(number)
    local text = tostring(math.floor(number + 0.5))
    local done
    repeat
        text, done = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
    until done == 0
    return text
end

local function Short(number)
    if number >= 1000000 then
        return string.format("%.2fm", number / 1000000)
    elseif number >= 10000 then
        return string.format("%.1fk", number / 1000)
    end
    return Commas(number)
end

local function Duration(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge or seconds < 0 then
        return "-"
    end
    seconds = math.floor(seconds + 0.5)
    local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %02ds", minutes, seconds % 60)
    end
    return string.format("%ds", seconds)
end

local GOLD, SILVER, COPPER = "|cffffd24a", "|cffc7c7cf", "|cffd98c56"
local function Coins(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.floor(math.abs(copper) + 0.5)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if gold >= 100 then
        return string.format("%s%s%sg|r", sign, Commas(gold), GOLD)
    elseif gold > 0 then
        return string.format("%s%d%sg|r %02d%ss|r", sign, gold, GOLD, silver, SILVER)
    elseif silver > 0 then
        return string.format("%s%d%ss|r %02d%sc|r", sign, silver, SILVER, rest, COPPER)
    end
    return string.format("%s%d%sc|r", sign, rest, COPPER)
end

------------------------------------------------------------------------------
-- What the panel shows
------------------------------------------------------------------------------

-- "level": the leveling numbers. "gold": the gold ones. nil: nothing.
local function Mode()
    local settings = Settings()
    local what = settings.what or "auto"
    if what == "gold" then
        return "gold"
    end
    if not ns.Session.AtLevelCap() then
        return "level"
    end
    return what == "auto" and "gold" or nil
end

-- title, title's right side, and each row's text (nil: the row is left out).
local function LevelFigures()
    local session = ns.Session
    local now, most = ns.Num(Call("UnitXP", "player")), ns.Num(Call("UnitXPMax", "player"))
    local level = Level()
    local values = {}
    local rate = session.PerHour(session.XP())
    values.rate = rate and Short(rate) or "-"
    local togo = now and most and most > 0 and (most - now) or nil
    values.eta = (rate and rate > 0 and togo) and Duration(togo * 3600 / rate) or "-"
    local played = PlayedThisLevel()
    values.played = played and Duration(played) or "-"
    local perKill = XPPerKill()
    values.perKill = perKill and Commas(perKill) or "-"
    values.kills = (perKill and perKill > 0 and togo) and Commas(math.ceil(togo / perKill)) or "-"
    values.togo = togo and Commas(togo) or "-"
    local rested = ns.Num(Call("GetXPExhaustion"))
    values.rested = (rested and rested > 0 and most and most > 0) and string.format("%d%%", rested * 100 / most + 0.5) or "none"
    local share = (now and most and most > 0) and string.format("%.1f%%", now * 100 / most) or ""
    return level and ("Level " .. level) or "Level", share, values
end

local function GoldFigures()
    local session = ns.Session
    local values = {}
    local gained = session.MoneyGained()
    local earned = gained and (gained + ns.LootEarnings()) or nil
    local rate = earned and session.PerHour(earned) or nil
    values.goldRate = rate and Coins(rate) or "-"
    values.earned = earned and Coins(earned) or "-"
    values.coin = gained and Coins(gained) or "-"
    if ns.PricesKnown() then
        local tally = ns.LootTally()
        values.loot = string.format("%s |cff8c857a(%d)|r", Coins(tally.value), tally.items)
    end
    local elapsed = session.Elapsed()
    values.session = string.format("%d:%02d", math.floor(elapsed / 3600), math.floor(elapsed / 60) % 60)
    local purse = session.Money()
    values.purse = purse and Coins(purse) or "-"
    return "Gold", "", values
end

------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------

local function Create()
    local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsLeveling", UIParent, "BackdropTemplate")
    panel = (ok and made) or CreateFrame("Frame", "ElipsPanelsLeveling", UIParent)
    panel:SetWidth(WIDTH)
    panel:SetFrameStrata("LOW")
    panel:SetClampedToScreen(true)
    W.PanelBackdrop(panel, 0.88)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", PAD, -6)
    panel.share = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.share:SetPoint("TOPRIGHT", -PAD, -8)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", PAD - 1, -TITLE + 1)
    line:SetPoint("TOPRIGHT", -PAD + 1, -TITLE + 1)
    W.ThemePanel(panel, nil, W.NATURE)
    W.AccentLine(line, W.NATURE)
    panel.rows = {}
    for index = 1, math.max(#LEVEL_ROWS, #GOLD_ROWS) do
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
        local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        panel.rows[index] = { label = label, value = value }
    end
    panel.since = 100
    panel:SetScript("OnUpdate", function(self, elapsed)
        self.since = self.since + elapsed
        if self.since >= 1 then
            self.since = 0
            ns.UpdateLeveling()
        end
    end)
    W.PlacePanel(panel, Settings().pos, DEFAULT_SPOT)
    panel:Hide()
end

local function Fill(rows, title, share, values)
    local settings = Settings()
    panel.title:SetText(title)
    panel.share:SetText(share)
    local used = 0
    for _, row in ipairs(rows) do
        local text = values[row.key]
        if text and settings.rows[row.key] ~= false then
            used = used + 1
            local line = panel.rows[used]
            line.label:ClearAllPoints()
            line.label:SetPoint("TOPLEFT", PAD, -TITLE - 3 - (used - 1) * ROW)
            line.value:ClearAllPoints()
            line.value:SetPoint("TOPRIGHT", -PAD, -TITLE - 3 - (used - 1) * ROW)
            line.label:SetText(row.label)
            line.value:SetText(text)
            local quiet = text == "-" or text == "none"
            line.value:SetTextColor((quiet and DIM or VALUE)[1], (quiet and DIM or VALUE)[2], (quiet and DIM or VALUE)[3])
            line.label:Show()
            line.value:Show()
        end
    end
    for index = used + 1, #panel.rows do
        panel.rows[index].label:Hide()
        panel.rows[index].value:Hide()
    end
    panel:SetHeight(TITLE + 3 + used * ROW + 6)
    panel.used = used
end

function ns.UpdateLeveling()
    if not panel then
        return
    end
    local settings = Settings()
    local mode = settings.show ~= false and not ns.PanelsHidden() and Mode() or nil
    if not mode then
        status.mode = settings.show == false and "off" or (ns.PanelsHidden() and "hidden in a battleground" or "nothing to show at the level cap")
        panel:Hide()
        return
    end
    status.mode = mode == "level" and "leveling" or "gold"
    if mode == "level" then
        Fill(LEVEL_ROWS, LevelFigures())
    else
        Fill(GOLD_ROWS, GoldFigures())
    end
    panel:Show()
end

ns.Hook("INIT", function()
    Settings()
    Create()
    ns.RegisterMover({
        key = "leveling", label = "Leveling", width = WIDTH, height = TITLE + 3 + #LEVEL_ROWS * ROW + 6, default = DEFAULT_SPOT,
        get = function() return Settings().pos end,
        set = function(pos)
            Settings().pos = pos
            W.PlacePanel(panel, pos, DEFAULT_SPOT)
        end,
    })
    ns.On("PLAYER_ENTERING_WORLD", function()
        if not lastXP then
            lastXP, lastMax = ns.Num(Call("UnitXP", "player")), ns.Num(Call("UnitXPMax", "player"))
        end
        -- (Only a character still leveling is asked about: at the cap the
        -- time at this level isn't shown.)
        StartPlayed(not ns.Session.AtLevelCap())
        ns.UpdateLeveling()
    end)
    ns.On("PLAYER_XP_UPDATE", function()
        XPChanged()
        ns.UpdateLeveling()
    end)
    ns.On("CHAT_MSG_COMBAT_XP_GAIN", XPLine)
    ns.On("PLAYER_LEVEL_UP", function(level)
        LeveledUp(level)
        C_Timer.After(0.6, ns.UpdateLeveling)
    end)
    ns.On("TIME_PLAYED_MSG", PlayedAnswer)
    ns.On("PLAYER_LOGOUT", SavePlayed)
    ns.On("UPDATE_EXHAUSTION", ns.UpdateLeveling)
    ns.On("PLAYER_MONEY", ns.UpdateLeveling)
    ns.Hook("BATTLEGROUND", ns.UpdateLeveling)
    local timers = rawget(_G, "C_Timer")
    if timers and timers.NewTicker then
        timers.NewTicker(SAVE_EVERY, SavePlayed)
    end
end)

------------------------------------------------------------------------------
-- /ep leveling, /ep status
------------------------------------------------------------------------------

-- /ep leveling: on or off (show, hide, on, off say which). reset: a new
-- session. played: ask the game again for the time at this level.
ns.commands.leveling = function(rest)
    local settings = Settings()
    local word = (rest or ""):lower()
    if word == "reset" or word == "restart" then
        ns.InfoRestart()
        ns.Print("a new session: XP per hour, gold per hour and the kills start again.")
        return
    elseif word == "played" then
        if rawget(_G, "RequestTimePlayed") then
            status.sync = "asked"
            pcall(RequestTimePlayed)
        end
        return
    end
    local on = settings.show == false
    if word == "show" or word == "on" then
        on = true
    elseif word == "hide" or word == "off" then
        on = false
    end
    settings.show = on
    ns.UpdateLeveling()
    ns.Print(on and "leveling panel on (/ep move to place it)." or "leveling panel off.")
end
ns.commands.level = ns.commands.leveling
ns.commands.xp = ns.commands.leveling

ns.statusParts[#ns.statusParts + 1] = function()
    local settings = Settings()
    local played = PlayedThisLevel()
    return {
        string.format("Leveling panel: %s | showing %s (%s) | now: %s", settings.show == false and "off" or "on",
            settings.what == "gold" and "gold always" or settings.what == "level" and "leveling only" or "leveling, then gold at the cap",
            ns.Session.AtLevelCap() and "at the level cap" or "leveling", tostring(status.mode)),
        string.format("    Kills this session %d (XP per kill over the last %d: %s; lines hidden in a fight %d) | time at this level: %s (%s)",
            kills.count, #kills.recent, XPPerKill() and string.format("%.0f", XPPerKill()) or "none yet", status.secretLines,
            played and Duration(played) or "not known", status.sync),
    }
end

-- For the tests.
ns.LevelingInternals = {
    Panel = function() return panel end,
    Mode = Mode,
    Kills = kills,
    XPLine = XPLine,
    XPChanged = XPChanged,
    KillHead = KillHead,
    Played = PlayedThisLevel,
    SavePlayed = SavePlayed,
    Character = Character,
    Coins = Coins,
    Duration = Duration,
    Status = status,
}
