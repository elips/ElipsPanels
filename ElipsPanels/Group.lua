-- Group.lua
-- Two panels for a party or raid.
--
--   Group mana       each healer's and each Mage's mana as a percent, colored
--                    from full (blue) to empty (red), with a small icon
--                    beside anyone getting mana back: drinking, Innervate,
--                    Evocation, Mana Tide. Healers are those with the
--                    Healer role; in a group where nobody has a role, the
--                    healing classes stand in.
--   Raid cooldowns   Rebirth, Reincarnation, Lay on Hands, Divine
--                    Intervention, Soulstone, Innervate (and more, switched
--                    on in the settings): who has each ready, and how long
--                    until the others' are back.
--
-- What an addon can see of other players, on this client:
--   * Mana is a hidden number. The game will turn the hidden fraction into
--     a percent or a color through a curve, so each row has a true percent
--     in a color that runs from blue to red as mana runs low, with no
--     number ever read. (Rows can't be sorted by mana, or warned about, for
--     the same reason.)
--   * There is no combat log here. A group member's cooldown is known from
--     the game saying they cast the spell (UNIT_SPELLCAST_SUCCEEDED). Where
--     the game hides which spell it was, that use isn't seen; /ep status
--     counts how many casts were readable and how many hidden.
--   * A cooldown nobody has been seen using is taken to be ready.
--   * Buffs on other players can be read out of combat. In combat the game
--     hides them, so there the mana icons come from casts: your own
--     Innervate (you know who you cast it on), a Mage's Evocation (it is
--     their own channel), a Shaman's Mana Tide (their party gets it).
--     Another Druid's Innervate in combat can't be placed: the game says
--     they cast it, not on whom.
-- Cooldowns seen are kept by wall clock in the settings, so a /rl in the
-- middle of a raid doesn't forget an hour-long one.

local _, ns = ...
local W = ns.W

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local HEADER = 26
local ROW_HEIGHT = 18
-- The mana panel is the small one: a short header, close rows, and in each
-- row a name (with a small icon beside it for each thing giving them mana
-- back) and their mana as a percent, colored from full to empty.
local MANA_WIDTH = 150
local MANA_HEADER = 22
local MANA_ROW = 16
local MANA_FONT = 11
local ICON_SIZE = 12
local MAX_ICONS = 3
local DRINK_ICON = "Interface\\Icons\\INV_Drink_07"
local DRINKS = { "Drink", "Refreshment", "Food & Drink" }   -- the buffs drinking gives
-- What gives mana back, in the order the icons sit after the name. `names`:
-- what the buff goes by (the spell's name in your game's language is added).
-- `calm`: only ever out of combat. `lasts`: seconds, for one seen by its cast.
local REGEN = {
    { key = "drinking", icon = DRINK_ICON, names = DRINKS, calm = true },
    { key = "innervate", id = 29166, icon = "Interface\\Icons\\Spell_Nature_Lightning", names = { "Innervate" }, lasts = 20 },
    { key = "evocation", id = 12051, icon = "Interface\\Icons\\Spell_Nature_Purge", names = { "Evocation" }, lasts = 8 },
    { key = "manaTide", id = 16190, icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
        names = { "Mana Tide", "Mana Tide Totem" }, lasts = 12 },
}
local COOLDOWN_WIDTH = 300
local NAME_WIDTH = 68        -- a player's name before their mana
local SPELL_WIDTH = 98       -- a cooldown's name; who has it gets the rest
local NAMES_FIT = 27         -- letters of "who has it" that fit beside it
local MANA_SPOT = { "TOPLEFT", "LEFT", 40, 330 }
local COOLDOWN_SPOT = { "TOPLEFT", "LEFT", 270, 330 }
local GREY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }
-- Mana as a percent: blue when full, through yellow at half, to red from a
-- fifth down.
local BLUE = { 0.42, 0.72, 1.00 }
local HALF = { 1.00, 0.85, 0.25 }
local LOW = { 1.00, 0.30, 0.25 }
local HEAL_CLASSES = { PRIEST = true, PALADIN = true, SHAMAN = true, DRUID = true }
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- The cooldowns that can be watched. `id`: a rank of the spell (its icon,
-- and its name in your game's language). `cd`: seconds, used when the game
-- won't give the cast rank's own. `on`: watched unless switched off.
-- `talent`: not every one of the class has it, so only those seen using it
-- are listed. `names`: other names the cast goes by.
local TRACKED = {
    { key = "rebirth", label = "Rebirth", id = 20484, class = "DRUID", cd = 1800, on = true },
    { key = "reincarnation", label = "Reincarnation", id = 20608, class = "SHAMAN", cd = 3600, on = true },
    { key = "layOnHands", label = "Lay on Hands", id = 633, class = "PALADIN", cd = 3600, on = true },
    { key = "divineIntervention", label = "Divine Intervention", short = "Div. Intervention", id = 19752, class = "PALADIN",
        cd = 3600, on = true },
    { key = "soulstone", label = "Soulstone", id = 20707, class = "WARLOCK", cd = 1800, on = true,
        names = { "Soulstone Resurrection" } },
    { key = "innervate", label = "Innervate", id = 29166, class = "DRUID", cd = 360, on = true },
    { key = "tranquility", label = "Tranquility", id = 740, class = "DRUID", cd = 300 },
    { key = "manaTide", label = "Mana Tide Totem", short = "Mana Tide", id = 16190, class = "SHAMAN", cd = 300, talent = true },
    { key = "shieldWall", label = "Shield Wall", id = 871, class = "WARRIOR", cd = 1800 },
    { key = "bop", label = "Blessing of Protection", short = "Bl. of Protection", id = 1022, class = "PALADIN", cd = 300 },
    { key = "powerInfusion", label = "Power Infusion", id = 10060, class = "PRIEST", cd = 180, talent = true },
    { key = "bloodlust", label = "Bloodlust", id = 2825, class = "SHAMAN", cd = 600, names = { "Heroism" } },
}
ns.GROUP_COOLDOWNS = TRACKED

local status = { scans = 0, casts = 0, readable = 0, readableCombat = 0, hidden = 0, hiddenCombat = 0, fromGUID = 0,
    used = 0, manaPlain = 0, manaHidden = 0, percentShown = 0, percentFailed = 0,
    colorText = 0, colorVertex = 0, colorSwatch = 0, colorNone = 0, drinking = 0,
    auraCombat = 0, auraHidden = 0, regenCasts = 0, regenShown = 0 }
ns.groupStatus = status

local function Settings()
    local db = ns.db
    db.group = db.group or {}
    local group = db.group
    group.mana = group.mana or {}
    group.cooldowns = group.cooldowns or {}
    group.cooldowns.spells = group.cooldowns.spells or {}
    group.used = group.used or {}
    group.seen = group.seen or {}
    return group
end
ns.GroupSettings = Settings

local function Enabled()
    return ns.ModuleLoaded("group")
end

local function PlainString(value)
    if ns.IsSecret(value) or type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

local function ClassColor(class)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local color = class and colors and colors[class]
    if color then
        return color.r, color.g, color.b
    end
    return 0.85, 0.85, 0.85
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Is this spell in this game at all? (Bloodlust may not be.) Taken to be,
-- unless the game says otherwise.
local function Exists(entry)
    if entry.exists == nil then
        entry.exists = true
        local asks = C_Spell and C_Spell.DoesSpellExist
        if asks then
            local ok, there = pcall(asks, entry.id)
            if ok and not ns.IsSecret(there) and there == false then
                entry.exists = false
            end
        end
    end
    return entry.exists
end

-- The cooldowns this game has, for the settings page.
function ns.GroupCooldownList()
    local list = {}
    for _, entry in ipairs(TRACKED) do
        if Exists(entry) then
            list[#list + 1] = entry
        end
    end
    return list
end

local function EntryOn(entry)
    if not Exists(entry) then
        return false
    end
    local chosen = Settings().cooldowns.spells[entry.key]
    if chosen == nil then
        return entry.on == true
    end
    return chosen == true
end

------------------------------------------------------------------------------
-- Who is in your group
------------------------------------------------------------------------------

local members = {}   -- { unit, name, known, class, role, healer, me, fake }, in the game's order
local byUnit = {}
local classOf = {}   -- name -> class, remembered for when the game stops saying
local sample         -- /ep group test: a made-up group
local Dirty          -- below

local function Grouped()
    if sample then
        return "raid"
    end
    if IsInRaid and ns.Bool(IsInRaid(), false) then
        return "raid"
    elseif IsInGroup and ns.Bool(IsInGroup(), false) then
        return "party"
    end
    return nil
end

local function ScanUnit(unit, raidIndex, myName)
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or not ns.Bool(exists, false) then
        return nil
    end
    local okName, name = pcall(UnitName, unit)
    -- A hidden name can't be read, but a line of text can still show it.
    local hiddenName = okName and ns.IsSecret(name) and name or nil
    name = okName and PlainString(name) or nil
    local okClass, _, class = pcall(UnitClass, unit)
    class = okClass and PlainString(class) or nil
    local combatRole, subgroup
    local roster = rawget(_G, "GetRaidRosterInfo")
    if raidIndex and roster then
        local ok, rosterName, _, rosterGroup, _, _, rosterClass, _, _, _, _, _, rosterRole = pcall(roster, raidIndex)
        if ok then
            subgroup = ns.Num(rosterGroup)
            name = name or PlainString(rosterName)
            class = class or PlainString(rosterClass)
            combatRole = PlainString(rosterRole)
        end
    end
    local unknown = rawget(_G, "UNKNOWNOBJECT") or "Unknown"
    if name == unknown then
        name = nil
    end
    class = class or (name and classOf[name]) or nil
    if name and class then
        classOf[name] = class
    end
    local okRole, role = pcall(UnitGroupRolesAssigned, unit)
    role = okRole and PlainString(role) or nil
    if not (role and ROLES[role]) then
        role = combatRole and ROLES[combatRole] and combatRole or nil
    end
    return { unit = unit, name = name or unit, known = name ~= nil, hiddenName = hiddenName, class = class, role = role,
        subgroup = subgroup, me = unit == "player" or (name ~= nil and name == myName) }
end

local function Scan()
    members, byUnit = {}, {}
    status.scans = status.scans + 1
    if sample then
        for _, member in ipairs(sample) do
            members[#members + 1] = member
        end
    else
        local kind = Grouped()
        local okMe, myName = pcall(UnitName, "player")
        myName = okMe and PlainString(myName) or nil
        if kind == "raid" then
            local count = ns.Num(GetNumGroupMembers and GetNumGroupMembers()) or 0
            for index = 1, math.min(40, count) do
                members[#members + 1] = ScanUnit("raid" .. index, index, myName)
            end
        elseif kind == "party" then
            members[#members + 1] = ScanUnit("player", nil, myName)
            for index = 1, 4 do
                members[#members + 1] = ScanUnit("party" .. index, nil, myName)
            end
        end
    end
    -- Healers: by role; in a group where nobody has one, the healing classes.
    local anyRole = false
    for _, member in ipairs(members) do
        byUnit[member.unit] = member
        anyRole = anyRole or member.role ~= nil
    end
    for _, member in ipairs(members) do
        if anyRole then
            member.healer = member.role == "HEALER"
        else
            member.healer = member.class ~= nil and HEAL_CLASSES[member.class] == true
        end
    end
    status.members = #members
    status.byRole = anyRole
end

local function Alive(member)
    if member.fake then
        return not member.fake.dead, not member.fake.offline
    end
    local okDead, dead = pcall(UnitIsDeadOrGhost, member.unit)
    local okOnline, online = pcall(UnitIsConnected, member.unit)
    return not (okDead and ns.Bool(dead, false)), not okOnline or ns.Bool(online, true)
end

------------------------------------------------------------------------------
-- A small themed panel (both are one of these)
------------------------------------------------------------------------------

local function Text(parent, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function HideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip then
        tip:Hide()
    end
end

-- `spec`: name (the frame's), title, width, key and label (its mover), spot
-- (where it starts), settings (a function: its table), hint (its header's
-- tooltip); header and rowHeight for a panel smaller than the usual. Returns the frame; frame.rows holds its lines, frame.offset how
-- far the mouse wheel has moved through them.
local function NewPanel(spec)
    local ok, made = pcall(CreateFrame, "Frame", spec.name, UIParent, "BackdropTemplate")
    local panel = (ok and made) or CreateFrame("Frame", spec.name, UIParent)
    panel:SetWidth(spec.width)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    W.PanelBackdrop(panel, 0.88)
    W.ThemePanel(panel, nil, W.NATURE)
    if spec.quiet ~= false then
        W.QuietInCombat(panel)   -- out of the way in a fight; the mouse brings it back
    end
    local small = spec.header ~= nil and spec.header < HEADER
    panel.headerHeight = spec.header or HEADER
    panel.rowHeight = spec.rowHeight or ROW_HEIGHT
    panel.side = small and 6 or 8
    local headerHeight = panel.headerHeight
    local crest = panel:CreateTexture(nil, "ARTWORK")
    crest:SetTexture("Interface\\AddOns\\ElipsPanels\\Media\\ElipsPanels")
    crest:SetSize(small and 12 or 16, small and 12 or 16)
    crest:SetPoint("TOPLEFT", panel.side, small and -4 or -6)
    panel.title = Text(panel, small and "GameFontNormalSmall" or "GameFontNormal")
    panel.title:SetPoint("LEFT", crest, "RIGHT", small and 4 or 6, 0)
    panel.title:SetText(spec.title)
    panel.count = Text(panel)
    panel.count:SetPoint("RIGHT", panel, "TOPRIGHT", small and -7 or -10, small and -10 or -14)
    panel.count:SetJustifyH("RIGHT")
    panel.count:SetTextColor(GREY[1], GREY[2], GREY[3])
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel.side, -headerHeight)
    line:SetPoint("TOPRIGHT", -panel.side, -headerHeight)
    W.AccentLine(line, W.NATURE, 0.6)
    panel.rows = {}
    panel.more = Text(panel, "GameFontDisableSmall")
    panel.offset = 0

    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        panel.offset = (panel.offset or 0) - delta
        HideTip()
        Dirty()
    end)
    -- The header: click to fold the panel to this line, drag to move.
    local header = CreateFrame("Button", nil, panel)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(headerHeight)
    header:RegisterForClicks("LeftButtonUp")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        header.dragged = true
        if not Settings().locked then
            panel:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local x, top = panel:GetLeft(), panel:GetTop()
        if x and top then
            spec.settings().pos = { math.floor(x + 0.5), math.floor(top + 0.5) }
        end
        C_Timer.After(0.05, function()
            header.dragged = false
        end)
    end)
    header:SetScript("OnClick", function()
        if header.dragged then
            header.dragged = false
            return
        end
        spec.settings().collapsed = not spec.settings().collapsed
        Dirty()
    end)
    header:SetScript("OnEnter", function(self)
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText(spec.title, 1, 1, 1)
            tip:AddLine(spec.hint, 0.8, 0.8, 0.8, true)
            tip:AddLine("Click: fold or open. Drag: move. Mouse wheel: scroll.", 0.6, 0.8, 1)
            tip:Show()
        end
    end)
    header:SetScript("OnLeave", HideTip)
    panel.header = header

    W.PlacePanel(panel, spec.settings().pos, spec.spot)
    panel:Hide()
    ns.RegisterMover({
        key = spec.key, label = spec.label, width = spec.width, height = 110, default = spec.spot,
        get = function() return spec.settings().pos end,
        set = function(pos)
            spec.settings().pos = pos
            W.PlacePanel(panel, pos, spec.spot)
        end,
    })
    return panel
end

-- Sizes a panel to `shown` of `total` lines, with "+N more" under them.
local function FitPanel(panel, shown, total, collapsed)
    for index = shown + 1, #panel.rows do
        panel.rows[index]:Hide()
    end
    local hiddenLines = total - shown
    local header, rowHeight = panel.headerHeight, panel.rowHeight
    if collapsed or hiddenLines <= 0 then
        panel.more:Hide()
        panel:SetHeight(collapsed and header or (header + 8 + shown * rowHeight))
        return
    end
    local above = panel.offset or 0
    local below = total - shown - above
    panel.more:ClearAllPoints()
    panel.more:SetPoint("TOPLEFT", panel.side + 2, -(header + 5 + shown * rowHeight))
    panel.more:SetText(above > 0 and string.format("%d above · %d below", above, below) or string.format("+%d more", below))
    panel.more:Show()
    panel:SetHeight(header + 8 + shown * rowHeight + 14)
end

-- Is this panel wanted where you are? `where`: "group" (a party or a raid)
-- or "raid" (raids only).
local function Wanted(settings)
    if settings.show == false then
        return false
    end
    local kind = Grouped()
    if not kind then
        return false
    end
    return settings.where ~= "raid" or kind == "raid"
end

------------------------------------------------------------------------------
-- Group mana
------------------------------------------------------------------------------

local manaPanel
local manaRows = {}   -- the members listed, in order

-- A hidden fraction of mana, turned by the game into a percent (0..100).
local percentCurve
local function PercentCurve()
    if percentCurve == nil then
        percentCurve = false
        local curves = rawget(_G, "C_CurveUtil")
        if curves and curves.CreateCurve then
            local ok, made = pcall(function()
                local curve = curves.CreateCurve()
                curve:AddPoint(0, 0)
                curve:AddPoint(1, 100)
                return curve
            end)
            if ok and made then
                percentCurve = made
            end
        end
    end
    return percentCurve or nil
end

-- ... and into a color: blue when full, yellow at half, red from 20% down.
local colorCurve
local function ColorCurve()
    if colorCurve == nil then
        colorCurve = false
        local curves = rawget(_G, "C_CurveUtil")
        if curves and curves.CreateColorCurve and CreateColor then
            local ok, made = pcall(function()
                local curve = curves.CreateColorCurve()
                curve:AddPoint(0, CreateColor(LOW[1], LOW[2], LOW[3], 1))
                curve:AddPoint(0.2, CreateColor(LOW[1], LOW[2], LOW[3], 1))
                curve:AddPoint(0.5, CreateColor(HALF[1], HALF[2], HALF[3], 1))
                curve:AddPoint(1, CreateColor(BLUE[1], BLUE[2], BLUE[3], 1))
                return curve
            end)
            if ok and made then
                colorCurve = made
            end
        end
    end
    return colorCurve or nil
end

local function PlainColor(left)
    if left <= 0.2 then
        return LOW[1], LOW[2], LOW[3]
    end
    local from, to, t = LOW, HALF, (left - 0.2) / 0.3
    if left >= 0.5 then
        from, to, t = HALF, BLUE, math.min(1, (left - 0.5) / 0.5)
    end
    return from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t
end

local function ManaRow(index)
    local row = manaPanel.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, manaPanel)
    local side, top = manaPanel.side, manaPanel.headerHeight + 4 + (index - 1) * manaPanel.rowHeight
    row:SetHeight(manaPanel.rowHeight)
    row:SetPoint("TOPLEFT", side, -top)
    row:SetPoint("TOPRIGHT", -side, -top)
    row.name = Text(row)
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetWidth(NAME_WIDTH)
    -- Small icons after the name: what's giving them mana back.
    row.icons = {}
    for slot = 1, MAX_ICONS do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetPoint("LEFT", row, "LEFT", NAME_WIDTH + 4 + (slot - 1) * (ICON_SIZE + 1), 0)
        icon:Hide()
        row.icons[slot] = icon
    end
    row.drink = row.icons[1]   -- (the first of them, as it was when a drink was the only one)
    -- Their mana, as a percent, at the row's end.
    row.text = Text(row)
    row.text:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    row.text:SetJustifyH("RIGHT")
    for _, text in ipairs({ row.name, row.text }) do
        local font, _, flags = text:GetFont()
        if font then
            text:SetFont(font, MANA_FONT, flags)
        end
    end
    manaPanel.rows[index] = row
    return row
end

-- (Made once: a closure made on every look is garbage four times a second
-- for every row.)
local function ShowPercent(text, percent, unit)
    text:SetFormattedText("%d%%", percent(unit, MANA, false, PercentCurve()))
end

-- The percent's color, from a color whose parts are hidden numbers. Three
-- ways, the first the game allows: the text's own color, the text's tint,
-- or (text left white) a small swatch before it, which is a bar: bars are
-- known to take a hidden color. /ep status says which is in use.
local function TextColor(text, color)
    text:SetTextColor(color:GetRGB())
end

local function TextTint(text, color)
    text:SetVertexColor(color:GetRGB())
end

local function SwatchColor(swatch, color)
    local r, g, b = color:GetRGB()
    -- (As the health bars are colored by health, which works in the game.)
    if not pcall(swatch.SetStatusBarColor, swatch, r, g, b) then
        swatch:GetStatusBarTexture():SetVertexColor(r, g, b)
    end
end

local colorWay   -- nil until one has worked

local function Swatch(row)
    if not row.swatch then
        local swatch = CreateFrame("StatusBar", nil, row)
        swatch:SetSize(5, 5)
        swatch:SetPoint("RIGHT", row.text, "LEFT", -3, 0)
        swatch:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        swatch:SetMinMaxValues(0, 1)
        swatch:SetValue(1)
        row.swatch = swatch
    end
    return row.swatch
end

local function ColorHidden(row, percent, unit)
    local ok, color = pcall(percent, unit, MANA, false, ColorCurve())
    if not (ok and color) then
        return false
    end
    if (colorWay == nil or colorWay == "text") and pcall(TextColor, row.text, color) then
        colorWay = "text"
        status.colorText = status.colorText + 1
        return true
    end
    if (colorWay == nil or colorWay == "tint") and pcall(TextTint, row.text, color) then
        colorWay = "tint"
        status.colorVertex = status.colorVertex + 1
        return true
    end
    if pcall(SwatchColor, Swatch(row), color) then
        colorWay = "swatch"
        row.text:SetTextColor(1, 1, 1)
        row.swatch:Show()
        status.colorSwatch = status.colorSwatch + 1
        return true
    end
    return false
end

-- What's giving them mana back.
local regenUntil = {}     -- a member's name -> { what -> when it ends (GetTime) }: those seen by their cast

local function Names(effect)
    if not effect.looked then
        effect.looked = true
        local spells = rawget(_G, "C_Spell")
        if effect.id and spells then
            local okName, name = pcall(spells.GetSpellName or tostring, effect.id)
            name = okName and PlainString(name) or nil
            local have = false
            for index = 1, #effect.names do
                have = have or effect.names[index] == name
            end
            if name and not have then
                table.insert(effect.names, 1, name)
            end
            if spells.GetSpellTexture then
                local okIcon, icon = pcall(spells.GetSpellTexture, effect.id)
                effect.icon = (okIcon and (ns.Num(icon) or ns.Str(icon))) or effect.icon
            end
        end
    end
    return effect.names
end

-- The icon for `effect` if `member` has it. Their buffs say so wherever the
-- game lets them be read (always out of combat); where it doesn't, a cast
-- seen within the time the effect lasts does.
local function Regen(member, effect)
    if member.fake then
        return member.fake[effect.key] and effect.icon or nil
    end
    local fighting = ns.inCombat == true
    if effect.calm and fighting then
        return nil
    end
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if byName then
        local names = Names(effect)
        for index = 1, #names do
            local ok, aura = pcall(byName, member.unit, names[index], "HELPFUL")
            if ok then
                if ns.IsSecret(aura) then
                    status.auraHidden = status.auraHidden + 1
                elseif type(aura) == "table" then
                    if fighting then
                        status.auraCombat = status.auraCombat + 1
                    end
                    return (effect.calm and (ns.Num(aura.icon) or ns.Str(aura.icon))) or effect.icon
                end
            end
        end
    end
    local marks = regenUntil[member.name]
    local till = marks and marks[effect.key]
    if not till then
        return nil
    end
    local now = GetTime()
    -- Where buffs can be read and theirs isn't there, they've lost it (past
    -- the moment between the cast and the buff landing).
    local readable = byName ~= nil and (not fighting or status.auraCombat > 0)
    if till <= now or (readable and now - (till - effect.lasts) > 1.5) then
        marks[effect.key] = nil
        return nil
    end
    return effect.icon
end

local function ShowIcons(row, member)
    local shown, drinking = 0, false
    if member then
        for index = 1, #REGEN do
            local effect = REGEN[index]
            local icon = shown < MAX_ICONS and Regen(member, effect) or nil
            if icon then
                shown = shown + 1
                local texture = row.icons[shown]
                if texture.icon ~= icon then
                    texture.icon = icon
                    texture:SetTexture(icon)
                end
                drinking = drinking or effect.calm == true
            end
        end
    end
    if drinking and not row.drinking then
        status.drinking = status.drinking + 1
    end
    row.drinking = drinking
    if shown > 0 and row.iconCount ~= shown then
        status.regenShown = status.regenShown + 1
    end
    row.iconCount = shown
    -- Right after the name as it is written.
    local start = shown > 0 and (2 + math.min(ns.Num(row.name:GetStringWidth()) or NAME_WIDTH, NAME_WIDTH) + 3) or nil
    for slot = 1, MAX_ICONS do
        local texture = row.icons[slot]
        if slot <= shown then
            if texture.at ~= start then
                texture.at = start
                texture:ClearAllPoints()
                texture:SetPoint("LEFT", row, "LEFT", start + (slot - 1) * (ICON_SIZE + 1), 0)
            end
            if not texture:IsShown() then
                texture:Show()
            end
        elseif texture:IsShown() then
            texture:Hide()
        end
    end
end

-- One row's percent, from the member's mana as it is now; its color and the
-- icons too when `withColor` (those change slowly, and are looked at once a
-- second).
local function ManaValue(row, withColor)
    local member = row.member
    local alive, online = Alive(member)
    if not online or not alive then
        row.text:SetText(online and "dead" or "offline")
        row.text:SetTextColor(GREY[1], GREY[2], GREY[3])
        row.name:SetTextColor(GREY[1], GREY[2], GREY[3])
        if row.swatch then
            row.swatch:Hide()
        end
        ShowIcons(row, nil)
        row.out = true
        return
    end
    if row.out ~= false then
        row.out = false
        withColor = true
        row.text:SetTextColor(BLUE[1], BLUE[2], BLUE[3])
        row.name:SetTextColor(ClassColor(member.class))
    end
    if withColor then
        ShowIcons(row, member)
    end
    if member.fake then
        local left = member.fake.mana or 1
        row.text:SetFormattedText("%d%%", left * 100)
        row.text:SetTextColor(PlainColor(left))
        return
    end
    local unit = member.unit
    local okMost, most = pcall(UnitPowerMax, unit, MANA)
    local okMana, mana = pcall(UnitPower, unit, MANA)
    local plainMost, plainMana = okMost and ns.Num(most) or nil, okMana and ns.Num(mana) or nil
    if plainMost and plainMana then
        status.manaPlain = status.manaPlain + 1
        local left = plainMost > 0 and math.max(0, math.min(1, plainMana / plainMost)) or 0
        row.text:SetFormattedText("%d%%", left * 100)
        if withColor then
            row.text:SetTextColor(PlainColor(left))
            if row.swatch then
                row.swatch:Hide()
            end
        end
        return
    end
    status.manaHidden = status.manaHidden + 1
    -- Hidden: the game does the sums.
    local percent = rawget(_G, "UnitPowerPercent")
    if percent and PercentCurve() and pcall(ShowPercent, row.text, percent, unit) then
        status.percentShown = status.percentShown + 1
    else
        status.percentFailed = status.percentFailed + 1
        row.text:SetText("")
    end
    if withColor and not (percent and ColorCurve() and ColorHidden(row, percent, unit)) then
        status.colorNone = status.colorNone + 1
        row.text:SetTextColor(BLUE[1], BLUE[2], BLUE[3])
    end
end

local function DrawMana()
    local settings = Settings().mana
    manaRows = {}
    if Wanted(settings) then
        for _, member in ipairs(members) do
            if (member.healer or member.class == "MAGE") and (not member.me or settings.self == true) then
                manaRows[#manaRows + 1] = member
            end
        end
    end
    if #manaRows == 0 then
        if manaPanel then
            manaPanel:Hide()
        end
        return
    end
    -- Healers first, then the Mages; each by name.
    table.sort(manaRows, function(a, b)
        if a.healer ~= b.healer then
            return a.healer
        end
        return a.name < b.name
    end)
    local limit = settings.rows or 8
    manaPanel.offset = math.max(0, math.min(manaPanel.offset or 0, math.max(0, #manaRows - limit)))
    local shown = 0
    if not settings.collapsed then
        for index = 1, math.min(limit, #manaRows) do
            local member = manaRows[index + manaPanel.offset]
            local row = ManaRow(index)
            row.member = member
            if member.known or not (member.hiddenName and pcall(row.name.SetText, row.name, member.hiddenName)) then
                row.name:SetText(member.name)
            end
            row.out = nil
            ManaValue(row, true)
            row:Show()
            shown = index
        end
    end
    manaPanel.count:SetText(tostring(#manaRows))
    FitPanel(manaPanel, shown, #manaRows, settings.collapsed)
    manaPanel:Show()
end

local manaTicks = 0
local function ManaTick()
    if not (manaPanel and manaPanel:IsShown()) then
        return
    end
    manaTicks = manaTicks + 1
    local withColor = manaTicks % 4 == 0
    for _, row in ipairs(manaPanel.rows) do
        if row:IsShown() and row.member then
            ManaValue(row, withColor)
        end
    end
end

------------------------------------------------------------------------------
-- Raid cooldowns
------------------------------------------------------------------------------

local cooldownPanel
local cooldownRows = {}   -- { entry, owners = { { member, left, alive, online } } }
local byName              -- spell name -> tracked entry
local byID = {}           -- spell ID -> tracked entry, or false
local sampleUsed          -- /ep group test: its made-up cooldowns

local function SpellNameOf(id)
    return C_Spell and C_Spell.GetSpellName and PlainString(C_Spell.GetSpellName(id)) or nil
end

local function EntryFor(id)
    local entry = byID[id]
    if entry == nil then
        if not byName then
            byName = {}
            for _, tracked in ipairs(TRACKED) do
                byName[tracked.label] = tracked
                local name = SpellNameOf(tracked.id)
                if name then
                    byName[name] = tracked
                end
                for _, other in ipairs(tracked.names or {}) do
                    byName[other] = tracked
                end
            end
        end
        local name = SpellNameOf(id)
        entry = name and byName[name] or false
        byID[id] = entry
    end
    return entry or nil
end

-- Seconds until this member's cooldown is back (nil: ready, as far as is known).
local function Left(member, entry)
    local used = (sampleUsed or Settings().used)[member.name]
    local record = used and used[entry.key]
    if not record then
        return nil
    end
    local left = record.at + record.lasts - time()
    if left <= 0 then
        used[entry.key] = nil
        return nil
    end
    return left
end

local function MarkUsed(member, entry, spellID)
    local lasts = entry.cd
    local base = rawget(_G, "GetSpellBaseCooldown")
    if base and spellID then
        local ok, milliseconds = pcall(base, spellID)
        milliseconds = ok and ns.Num(milliseconds) or nil
        if milliseconds and milliseconds >= 10000 then
            lasts = milliseconds / 1000
        end
    end
    local settings = Settings()
    settings.used[member.name] = settings.used[member.name] or {}
    settings.used[member.name][entry.key] = { at = time(), lasts = lasts }
    settings.seen[member.name] = settings.seen[member.name] or {}
    settings.seen[member.name][entry.key] = true
    status.used = status.used + 1
    status.lastUse = string.format("%s by %s (%s)", entry.label, member.name, Clock(lasts))
    Dirty()
end

-- Mana coming back, seen by its cast (for where buffs can't be read).
local regenByID = {}      -- spell ID -> its REGEN entry, or false
local innervateTarget     -- who your Innervate was sent at
local channelEnded = {}   -- a member's name -> when their channel last ended

local function RegenEffect(id)
    local effect = regenByID[id]
    if effect == nil then
        effect = false
        local name = SpellNameOf(id)
        for _, candidate in ipairs(REGEN) do
            if not candidate.calm then
                local match = candidate.id == id
                for _, known in ipairs(Names(candidate)) do
                    match = match or known == name
                end
                if match then
                    effect = candidate
                end
            end
        end
        regenByID[id] = effect
    end
    return effect or nil
end

local function Mark(member, effect)
    regenUntil[member.name] = regenUntil[member.name] or {}
    regenUntil[member.name][effect.key] = GetTime() + effect.lasts
end

local function RegenCast(member, id)
    local effect = RegenEffect(id)
    if not effect then
        return
    end
    if effect.key == "innervate" then
        -- Yours: you know who you cast it on. Another Druid's: the game
        -- says they cast it, not on whom.
        if not member.me then
            return
        end
        local target = innervateTarget
        innervateTarget = nil
        local got = (target == nil) and member or nil
        for _, other in ipairs(members) do
            if target and other.name == target then
                got = other
            end
        end
        status.innervateOn = got and got.name or "nobody in the group"
        if not got then
            return
        end
        Mark(got, effect)
    elseif effect.key == "manaTide" then
        -- The totem is for the Shaman's own party.
        for _, other in ipairs(members) do
            if other.subgroup == member.subgroup then
                Mark(other, effect)
            end
        end
    else
        -- Evocation: their own channel. (Not the game's word that the cast
        -- "succeeded" where it comes just after the channel ended.)
        local ended = channelEnded[member.name]
        if ended and GetTime() - ended < 0.5 then
            return
        end
        Mark(member, effect)
    end
    status.regenCasts = status.regenCasts + 1
    Dirty()
end

-- The spell a cast event is about: its ID where the game gives it, else
-- from the cast's own ID (Cast-3-4170-0-13-<spell>-000A9BBA2A).
local function SpellOf(castGUID, spellID)
    local id = ns.Num(spellID)
    if not id and not ns.IsSecret(castGUID) and type(castGUID) == "string" then
        id = tonumber(castGUID:match("^Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
        return id, id ~= nil
    end
    return id, false
end

ns.On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if ns.IsSecret(unit) or unit ~= "player" or not Enabled() then
        return
    end
    local id = SpellOf(castGUID, spellID)
    local effect = id and RegenEffect(id)
    if effect and effect.key == "innervate" then
        -- Forever's characters have two names ("Styleen Silvercart"): a
        -- cast names its target by both, a unit goes by the first alone.
        -- So the first is kept (and no realm).
        local name = PlainString(target)
        innervateTarget = name and name:match("^([^%s%-]+)") or nil
        status.innervateSent = tostring(name)
    end
end)

ns.On("UNIT_SPELLCAST_CHANNEL_START", function(unit, castGUID, spellID)
    local member = not ns.IsSecret(unit) and type(unit) == "string" and byUnit[unit] or nil
    if not member or member.fake or not Enabled() then
        return
    end
    local id = SpellOf(castGUID, spellID)
    if id then
        channelEnded[member.name] = nil
        RegenCast(member, id)
    end
end)

ns.On("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
    local member = not ns.IsSecret(unit) and type(unit) == "string" and byUnit[unit] or nil
    if not member or member.fake then
        return
    end
    channelEnded[member.name] = GetTime()
    local marks = regenUntil[member.name]
    if marks and marks.evocation then
        marks.evocation = nil
        Dirty()
    end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if ns.IsSecret(unit) or type(unit) ~= "string" then
        return
    end
    -- (Only "player", "partyN" and "raidN" are in here, so a cast the game
    -- tells of twice, as "raid5" and as "target", is counted once.)
    local member = byUnit[unit]
    if not member or member.fake or not Enabled() then
        return
    end
    local fighting = ns.inCombat == true
    status.casts = status.casts + 1
    local id, fromGUID = SpellOf(castGUID, spellID)
    if fromGUID then
        status.fromGUID = status.fromGUID + 1
    end
    if not id then
        status.hidden = status.hidden + 1
        if fighting then
            status.hiddenCombat = status.hiddenCombat + 1
        end
        return
    end
    status.readable = status.readable + 1
    if fighting then
        status.readableCombat = status.readableCombat + 1
    end
    RegenCast(member, id)
    local entry = EntryFor(id)
    if entry and member.known then
        MarkUsed(member, entry, id)
    end
end)

-- Who has `entry`: everyone of its class (for a talent, those seen using it).
local function Owners(entry)
    local owners = {}
    local seen = Settings().seen
    for _, member in ipairs(members) do
        if member.class == entry.class and member.known
            and (not entry.talent or member.fake or (seen[member.name] and seen[member.name][entry.key])) then
            local alive, online = Alive(member)
            owners[#owners + 1] = { member = member, left = Left(member, entry), alive = alive, online = online }
        end
    end
    -- Ready first, then the soonest back; the dead and offline last.
    table.sort(owners, function(a, b)
        local aOut, bOut = not (a.alive and a.online), not (b.alive and b.online)
        if aOut ~= bOut then
            return bOut
        end
        if (a.left or 0) ~= (b.left or 0) then
            return (a.left or 0) < (b.left or 0)
        end
        return a.member.name < b.member.name
    end)
    return owners
end

local function OwnerText(owner, colored)
    local name = owner.member.name
    if not owner.online then
        return colored and string.format("|cff808080%s (offline)|r", name) or (name .. " (offline)")
    elseif not owner.alive then
        return colored and string.format("|cff808080%s (dead)|r", name) or (name .. " (dead)")
    elseif owner.left then
        return colored and string.format("|cff999999%s %s|r", name, Clock(owner.left)) or string.format("%s %s", name, Clock(owner.left))
    end
    return colored and name or (name .. " ready")
end

-- "Deps · Alice 12:30"; with more than three, or more letters than `fit`:
-- "3 ready · Alice 12:30". Also how many are ready.
local function Summary(row, colored, fit)
    local owners = row.owners
    local ready = 0
    for _, owner in ipairs(owners) do
        if owner.alive and owner.online and not owner.left then
            ready = ready + 1
        end
    end
    local separator = colored and " · " or ", "
    if #owners <= 3 then
        local parts, letters = {}, 0
        for _, owner in ipairs(owners) do
            parts[#parts + 1] = OwnerText(owner, colored)
            letters = letters + #OwnerText(owner, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") + 3
        end
        if not fit or #owners == 1 or letters - 3 <= fit then
            return table.concat(parts, separator), ready
        end
    end
    local parts = {}
    if ready > 0 then
        parts[#parts + 1] = colored and string.format("|cff40d060%d ready|r", ready) or (ready .. " ready")
    else
        parts[#parts + 1] = colored and "|cffff5040none ready|r" or "none ready"
    end
    local listed = 0
    for _, owner in ipairs(owners) do
        if owner.left and owner.alive and owner.online and listed < (fit and 1 or 2) then
            parts[#parts + 1] = OwnerText(owner, colored)
            listed = listed + 1
        end
    end
    return table.concat(parts, separator), ready
end

local function CooldownTip(row)
    local tip = rawget(_G, "GameTooltip")
    local data = row.data
    if not (tip and data) then
        return
    end
    tip:SetOwner(row, "ANCHOR_RIGHT")
    tip:SetText(data.entry.label, 1, 1, 1)
    for _, owner in ipairs(data.owners) do
        local r, g, b = ClassColor(owner.member.class)
        local state, sr, sg, sb = "ready", 0.25, 0.85, 0.4
        if not owner.online then
            state, sr, sg, sb = "offline", 0.5, 0.5, 0.5
        elseif not owner.alive then
            state, sr, sg, sb = "dead", 0.5, 0.5, 0.5
        elseif owner.left then
            state, sr, sg, sb = Clock(owner.left), 1, 0.82, 0
        end
        tip:AddDoubleLine(owner.member.name, state, r, g, b, sr, sg, sb)
    end
    if data.entry.talent then
        tip:AddLine("A talent: only those seen using it are listed.", 0.6, 0.6, 0.6, true)
    end
    tip:AddLine("A cooldown nobody was seen using counts as ready.", 0.6, 0.6, 0.6, true)
    tip:AddLine("Shift-click: tell your group", 0.6, 0.8, 1)
    tip:Show()
end

local function CooldownRow(index)
    local row = cooldownPanel.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, cooldownPanel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 8, -(HEADER + 4 + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -8, -(HEADER + 4 + (index - 1) * ROW_HEIGHT))
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = Text(row)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetWidth(SPELL_WIDTH)
    row.value = Text(row)
    row.value:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    row:SetScript("OnEnter", CooldownTip)
    row:SetScript("OnLeave", HideTip)
    row:SetScript("OnClick", function(self)
        if self.data and IsShiftKeyDown() and ns.SendGroupLine and not sample then
            ns.SendGroupLine(string.format("%s: %s", self.data.entry.label, (Summary(self.data, false))))
        end
    end)
    cooldownPanel.rows[index] = row
    return row
end

local function IconOf(entry)
    if entry.icon == nil then
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
        entry.icon = (not ns.IsSecret(texture) and texture) or false
    end
    return entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function CooldownLine(row, data)
    row.data = data
    local text, ready = Summary(data, true, NAMES_FIT)
    row.value:SetText(text)
    local color = ready > 0 and WHITE or GREY
    row.name:SetTextColor(color[1], color[2], color[3])
    row.icon:SetDesaturated(ready == 0)
    return ready
end

local function DrawCooldowns()
    local settings = Settings().cooldowns
    cooldownRows = {}
    if Wanted(settings) then
        for _, entry in ipairs(TRACKED) do
            if EntryOn(entry) then
                local owners = Owners(entry)
                if #owners > 0 then
                    cooldownRows[#cooldownRows + 1] = { entry = entry, owners = owners }
                end
            end
        end
    end
    if #cooldownRows == 0 then
        if cooldownPanel then
            cooldownPanel:Hide()
        end
        return
    end
    local limit = settings.rows or 8
    cooldownPanel.offset = math.max(0, math.min(cooldownPanel.offset or 0, math.max(0, #cooldownRows - limit)))
    local shown, cooling = 0, 0
    for _, data in ipairs(cooldownRows) do
        for _, owner in ipairs(data.owners) do
            if owner.left then
                cooling = cooling + 1
            end
        end
    end
    if not settings.collapsed then
        for index = 1, math.min(limit, #cooldownRows) do
            local data = cooldownRows[index + cooldownPanel.offset]
            local row = CooldownRow(index)
            row.icon:SetTexture(IconOf(data.entry))
            row.name:SetText(data.entry.short or data.entry.label)
            CooldownLine(row, data)
            row:Show()
            shown = index
        end
    end
    cooldownPanel.count:SetText(cooling > 0 and string.format("%d on cooldown", cooling) or "all ready")
    FitPanel(cooldownPanel, shown, #cooldownRows, settings.collapsed)
    cooldownPanel:Show()
end

------------------------------------------------------------------------------
-- Keeping both up to date
------------------------------------------------------------------------------

local pending, pendingAt = false, 0
local lastScan = 0

-- Both panels are made when the addon starts (hidden), so they can be
-- placed with /ep move before you're ever in a group.
local function EnsurePanels()
    if manaPanel then
        return
    end
    manaPanel = NewPanel({
        name = "ElipsPanelsGroupMana", title = "Group mana", width = MANA_WIDTH, key = "groupMana", label = "Group mana",
        header = MANA_HEADER, rowHeight = MANA_ROW, quiet = false,   -- (it's for the fight: it stays)
        spot = MANA_SPOT, settings = function() return Settings().mana end,
        hint = "Your group's healers and Mages: mana as a percent, blue when full, through yellow, to red when low. Small icons beside a name: drinking, Innervate, Evocation, Mana Tide.",
    })
    cooldownPanel = NewPanel({
        name = "ElipsPanelsGroupCooldowns", title = "Raid cooldowns", width = COOLDOWN_WIDTH, key = "groupCooldowns",
        label = "Raid cooldowns", spot = COOLDOWN_SPOT, settings = function() return Settings().cooldowns end,
        hint = "Who has each cooldown ready, and how long until the others' are back. Point at a line for everyone.",
    })
end

local function Update()
    pending = false
    if not Enabled() then
        if manaPanel then
            manaPanel:Hide()
        end
        if cooldownPanel then
            cooldownPanel:Hide()
        end
        return
    end
    EnsurePanels()
    Scan()
    lastScan = GetTime()
    DrawMana()
    DrawCooldowns()
end

Dirty = function()
    -- (Asked again if the last ask never ran.)
    if pending and GetTime() - pendingAt < 1 then
        return
    end
    pending, pendingAt = true, GetTime()
    C_Timer.After(0.1, Update)
end
ns.RefreshGroupPanels = Dirty

-- Mana every quarter second; the cooldowns' clocks every second; and the
-- group looked at afresh every 10 seconds (names and classes the game
-- wasn't saying yet, someone dying or going offline).
local ticker = CreateFrame("Frame")
local sinceMana, sinceClock = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    sinceMana, sinceClock = sinceMana + elapsed, sinceClock + elapsed
    if sinceMana >= 0.25 then
        sinceMana = 0
        ManaTick()
    end
    if sinceClock >= 1 then
        sinceClock = 0
        if not Enabled() then
            return
        end
        if Grouped() and GetTime() - lastScan >= 10 then
            Dirty()
        elseif cooldownPanel and cooldownPanel:IsShown() and not pending then
            DrawCooldowns()   -- the clocks
        end
    end
end)

ns.On("GROUP_ROSTER_UPDATE", function() Dirty() end)
ns.On("PLAYER_ROLES_ASSIGNED", function() Dirty() end)
ns.On("PLAYER_ENTERING_WORLD", function() Dirty() end)
ns.Hook("INIT", function()
    if not Enabled() then
        return
    end
    EnsurePanels()
    -- Cooldowns that came back while you were away.
    local now = time()
    for name, used in pairs(Settings().used) do
        for key, record in pairs(used) do
            if type(record) ~= "table" or (record.at or 0) + (record.lasts or 0) <= now then
                used[key] = nil
            end
        end
        if next(used) == nil then
            Settings().used[name] = nil
        end
    end
    Dirty()
end)

------------------------------------------------------------------------------
-- /ep group
------------------------------------------------------------------------------

-- A made-up raid, to see and place the panels without being in one.
local function Sample(on)
    if not on then
        sample, sampleUsed = nil, nil
        Dirty()
        return
    end
    local function Fake(name, class, role, mana, flags)
        local fake = flags or {}
        fake.mana = mana
        return { unit = "sample" .. name, name = name, known = true, class = class, role = role, fake = fake }
    end
    sample = {
        Fake("Aldric", "PRIEST", "HEALER", 0.82, { innervate = true }), Fake("Brenna", "SHAMAN", "HEALER", 0.34, { drinking = true }),
        Fake("Corwin", "PALADIN", "HEALER", 0.12, { innervate = true, manaTide = true }), Fake("Delphi", "DRUID", "HEALER", 0.67),
        Fake("Elowen", "MAGE", "DAMAGER", 0.55, { evocation = true }), Fake("Faolan", "MAGE", "DAMAGER", 0.91, { dead = true }),
        Fake("Gareth", "WARRIOR", "TANK", 0), Fake("Hesper", "WARLOCK", "DAMAGER", 0.4),
        Fake("Isolde", "DRUID", "DAMAGER", 0.5), Fake("Jorund", "SHAMAN", "DAMAGER", 0.6),
    }
    local now = time()
    sampleUsed = {
        Delphi = { rebirth = { at = now - 600, lasts = 1800 } },
        Brenna = { reincarnation = { at = now - 1200, lasts = 3600 } },
        Isolde = { innervate = { at = now - 60, lasts = 360 } },
    }
    Dirty()
    local mine = sample
    C_Timer.After(60, function()
        if sample == mine then
            Sample(false)
        end
    end)
end

function ns.GroupCommand(argument)
    if not Enabled() then
        ns.Print("The Group panels module is off (Modules page).")
        return
    end
    if argument == "test" then
        Sample(not sample)
        ns.Print(sample and "Group panels: showing a made-up raid for a minute (/ep group test again to stop)."
            or "Group panels: the made-up raid is gone.")
    elseif argument == "reset" then
        Settings().used, Settings().seen = {}, {}
        Dirty()
        ns.Print("Group panels: every cooldown seen is forgotten (all count as ready).")
    else
        ns.Print("/ep group test: a made-up raid, to see and place the panels. /ep group reset: forget the cooldowns seen.")
    end
end

-- "/ep status" lines.
function ns.GroupDiagLines()
    local lines = {}
    local settings = Settings()
    lines[#lines + 1] = string.format("  Group panels: %s | group %s, %s member(s) seen, healers %s | scans %d",
        Enabled() and "on" or "off", tostring(Grouped() or "none"), tostring(status.members or 0),
        status.byRole and "by role" or "by class (nobody has a role)", status.scans)
    lines[#lines + 1] = string.format("    mana panel: %s, %d row(s) | mana read as a number %d time(s), hidden %d (percent shown %d, not shown %d) | a hidden percent colored: as text %d, by tint %d, by swatch %d, couldn't %d (way in use: %s) | drinking seen %d | mana icons shown %d: from casts %d, buffs read in combat %d, buff answers hidden %d | your last Innervate: sent at %s, placed on %s",
        (manaPanel and manaPanel:IsShown()) and "showing" or "not showing", #manaRows, status.manaPlain, status.manaHidden,
        status.percentShown, status.percentFailed, status.colorText, status.colorVertex, status.colorSwatch, status.colorNone,
        tostring(colorWay or "none yet"), status.drinking, status.regenShown, status.regenCasts, status.auraCombat, status.auraHidden,
        tostring(status.innervateSent or "none yet"), tostring(status.innervateOn or "-"))
    lines[#lines + 1] = string.format(
        "    cooldowns panel: %s, %d line(s) | group casts seen %d: spell readable %d (%d in combat, %d from the cast's ID), hidden %d (%d in combat)",
        (cooldownPanel and cooldownPanel:IsShown()) and "showing" or "not showing", #cooldownRows, status.casts, status.readable,
        status.readableCombat, status.fromGUID, status.hidden, status.hiddenCombat)
    local running = 0
    for _, used in pairs(settings.used) do
        for _ in pairs(used) do
            running = running + 1
        end
    end
    lines[#lines + 1] = string.format("    cooldown uses seen %d (last: %s) | running now %d", status.used, tostring(status.lastUse or "none"),
        running)
    -- What the game says it would hide, for the first other member.
    local secrets = rawget(_G, "C_Secrets")
    for _, member in ipairs(members) do
        if not member.me and not member.fake and secrets then
            local parts = {}
            for _, probe in ipairs({ { "power", "ShouldUnitPowerBeSecret", MANA }, { "cast", "ShouldUnitSpellCastBeSecret", 20484 },
                { "identity", "ShouldUnitIdentityBeSecret" } }) do
                local fn = secrets[probe[2]]
                if fn then
                    local ok, answer = pcall(fn, member.unit, probe[3])
                    parts[#parts + 1] = string.format("%s %s", probe[1], ok and (ns.IsSecret(answer) and "(hidden)" or tostring(answer))
                        or "error")
                end
            end
            lines[#lines + 1] = string.format("    the game on %s (%s): would hide %s", member.unit, tostring(member.class),
                table.concat(parts, ", "))
            break
        end
    end
    return lines
end

-- For the tests.
ns.GroupInternals = {
    Members = function() return members end, ManaRows = function() return manaRows end,
    CooldownRows = function() return cooldownRows end, Update = Update, Summary = Summary,
    ManaPanel = function() return manaPanel end, CooldownPanel = function() return cooldownPanel end,
}

ns.commands.group = ns.GroupCommand
ns.statusParts[#ns.statusParts + 1] = function()
    if not ns.ModuleLoaded("group") then
        return "Group panels: switched off."
    end
    return ns.GroupDiagLines()
end
