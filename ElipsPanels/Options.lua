-- Options.lua
-- The settings window (/ep): a tab for the whole addon, and one for each
-- panel with settings of its own.

local _, ns = ...
local K = ns.K

local window
local tabs = {}
local current

-- A choice from a list, as a stepper: list = { { key, name }, ... }.
local function Choice(page, text, x, y, list, get, set, tip)
    local function Index()
        local now = get()
        for index, entry in ipairs(list) do
            if entry[1] == now then
                return index
            end
        end
        return 1
    end
    return K.Stepper(page, text, x, y, Index,
        function(index) set(list[index][1]) end, 1, 1, #list,
        function(index) return list[index] and list[index][2] or "?" end, tip)
end
ns.OptionsChoice = Choice

-- Panels add their tab: build(page, x, y) lays out the controls with the
-- kit (K.Check(page, ...) and so on).
function ns.AddTab(key, title, build)
    tabs[#tabs + 1] = { key = key, title = title, build = build }
end

local function Show(key)
    current = key
    for _, tab in ipairs(tabs) do
        local on = tab.key == key
        tab.page:SetShown(on)
        tab.button:SetSelected(on)
    end
end

local function Build()
    window = K.Window("ElipsPanelsOptions", "ElipsPanels", 600, 440)
    local x = 14
    for _, tab in ipairs(tabs) do
        local width = 26 + #tab.title * 7
        tab.button = K.Button(window, tab.title, width, x, -40, function() Show(tab.key) end)
        x = x + width + 6
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 0, -68)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        page.body, page.controls = page, window.controls
        tab.page = page
        tab.build(page, 16, -6)
    end
    Show(current or tabs[1].key)
end

function ns.ToggleOptions(key)
    if not window then
        Build()
    end
    if key then
        Show(key)
        window:Show()
    elseif window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
    return window
end

------------------------------------------------------------------------------
-- General
------------------------------------------------------------------------------

-- The panels list themselves here: { text, get(), set(shown), tip }.
ns.panelSwitches = {}

ns.AddTab("general", "General", function(page, x, y)
    local db = ns.db
    y = K.Para(page, "The suite's small panels. Show the ones you want; each has a tab of its own for the rest of its settings.", x, y, 430)
    y = y - 6
    K.Header(page, "Panels", x, y)
    y = y - 24
    for _, switch in ipairs(ns.panelSwitches) do
        K.Check(page, switch[1], x, y, switch[2], switch[3], switch[4])
        y = y - 24
    end
    y = y - 10
    K.Header(page, "All panels", x, y)
    y = y - 24
    K.Check(page, "Fade away in a fight", x, y,
        function() return db.quietPanels ~= false end,
        function(checked)
            db.quietPanels = checked
            ns.W.ApplyQuiet()
        end,
        "In combat the panels fade out, and come back while the mouse is over where they sit. Out of combat they're as they were.")
    y = y - 24
    K.Check(page, "Hide in battlegrounds", x, y,
        function() return db.hideInBattlegrounds ~= false end,
        function(checked)
            db.hideInBattlegrounds = checked
            ns.ApplyBattlegrounds()
        end,
        "Inside a battleground none of the panels show: the information bar, the chase list, group mana and raid cooldowns. They come back when you leave.")
    y = y - 30
    K.Button(page, "Move the panels", 130, x, y, function()
        local on = ns.Move()
        if on then
            K.Print("drag a blue box to move its panel (right-click one to put it back); click Move the panels again, or type /ep move, when done.")
        end
    end, "A blue box appears where each panel sits. Drag one and its panel goes there; it lines up with the middle of the screen and with the suite's other frames (hold Shift not to). Right-click a box to put its panel back where it started.")
end)

------------------------------------------------------------------------------
-- Information bar
------------------------------------------------------------------------------

ns.panelSwitches[#ns.panelSwitches + 1] = { "Information bar",
    function() return ns.InfoSettings().show ~= false end,
    function(checked)
        ns.InfoSettings().show = checked
        ns.ApplyInfoBar()
    end,
    "A thin bar at the top of the screen with the things worth a glance. Same as /ep info." }

ns.AddTab("info", "Info bar", function(page, x, y)
    local info = ns.InfoSettings()
    y = K.Para(page, "A thin bar, centered at the top of the screen to start with: the time, latency, frames per second, experience and gold per hour, what the addons take of each frame and of memory, your most worn piece of gear, free bag slots and the currencies you tick.", x, y, 430)
    y = y - 4
    y = K.Para(page, "Right-click the bar to choose what it shows, your currencies included. Shift-click it to start the per-hour counts again. Point at it for the details.", x, y, 430)
    y = y - 4
    y = K.Para(page, "With Auctionator installed, gold per hour is the coin you've gained plus what the things you looted are worth at the prices from its latest scan (the vendor's price for what can't be auctioned). Coin from a vendor or the mailbox isn't added on top.", x, y, 430)
    y = y - 8
    K.Stepper(page, "Text size", x, y,
        function() return tonumber(info.size) or 12 end,
        function(value)
            info.size = value
            ns.ApplyInfoBar()
        end, 1, 9, 18,
        function(value) return string.format("%d", value) end)
end)

------------------------------------------------------------------------------
-- Chase list
------------------------------------------------------------------------------

ns.panelSwitches[#ns.panelSwitches + 1] = { "Chase panel",
    function() return ns.ChaseSettings().show ~= false end,
    function(checked)
        ns.ChaseSettings().show = checked
        ns.RefreshChase()
    end,
    "A small panel with the first few things still to get from your chase list, and how far along each is. It hides itself when there's nothing left. Same as /ep chase show and /ep chase hide." }

ns.AddTab("chase", "Chase", function(page, x, y)
    local chase = ns.ChaseSettings()
    local function Apply()
        ns.RefreshChase()
    end
    y = K.Para(page, "Things to go after, each with a note on how to get it: items (by link or ID), reputations (to Exalted), quests, and goals of your own. Items, reputations and quests tick themselves off; a goal you tick off yourself. Each character has its own list.", x, y, 430)
    y = y - 4
    K.Button(page, "Open the chase list", 150, x, y, function()
        ns.ToggleChaseWindow(true)
    end, "The list window: add things, write how to get them, move them up and down, tick them off. Same as /ep chase.")
    y = y - 36
    K.Header(page, "Panel on screen", x, y)
    y = y - 24
    K.Check(page, "Hide it in combat", x, y,
        function() return chase.hideInCombat ~= false end,
        function(checked) chase.hideInCombat = checked Apply() end,
        "With \"Fade away in a fight\" on (General) it fades like the other panels instead, so the mouse can still find it.")
    y = y - 24
    K.Check(page, "Lock it in place", x, y,
        function() return chase.locked == true end,
        function(checked) chase.locked = checked end,
        "On: dragging doesn't move it.")
    y = y - 28
    K.Stepper(page, "Rows shown", x, y,
        function() return chase.rows or 6 end,
        function(value) chase.rows = value Apply() end, 1, 3, 12,
        function(value) return string.format("%d", value) end,
        "How many of the things still to get the panel lists; the rest are counted under them.")
    y = y - 34
    K.Header(page, "Speaking up", x, y)
    y = y - 24
    K.Check(page, "Tell me when something on the list drops or is done", x, y,
        function() return chase.alerts ~= false end,
        function(checked) chase.alerts = checked end,
        "A line in chat and a notice on screen when an item on your list comes up for a roll or lies in a loot window, and \"Chase complete\" when you get an item, reach the standing or finish the quest.")
    y = y - 24
    K.Check(page, "With a sound", x, y,
        function() return chase.sound ~= false end,
        function(checked) chase.sound = checked end)
    y = y - 24
    K.Check(page, "Mark items on the list in their tooltips", x, y,
        function() return chase.tooltip ~= false end,
        function(checked) chase.tooltip = checked end,
        "An item's tooltip says \"On your chase list\", with your note on how to get it.")
end)

------------------------------------------------------------------------------
-- Group mana, raid cooldowns
------------------------------------------------------------------------------

ns.panelSwitches[#ns.panelSwitches + 1] = { "Group mana",
    function() return ns.GroupSettings().mana.show ~= false end,
    function(checked)
        ns.GroupSettings().mana.show = checked
        ns.RefreshGroupPanels()
    end,
    "In a party or raid: each healer's and each Mage's mana as a percent, with an icon beside anyone getting mana back." }
ns.panelSwitches[#ns.panelSwitches + 1] = { "Raid cooldowns",
    function() return ns.GroupSettings().cooldowns.show ~= false end,
    function(checked)
        ns.GroupSettings().cooldowns.show = checked
        ns.RefreshGroupPanels()
    end,
    "In a party or raid: who has Rebirth, Reincarnation, Lay on Hands and the like ready, and how long until the others' are back." }

local WHERE = { { "group", "Parties and raids" }, { "raid", "Raids only" } }

ns.AddTab("mana", "Mana", function(page, x, y)
    local group = ns.GroupSettings()
    local mana = group.mana
    local function Apply()
        ns.RefreshGroupPanels()
    end
    y = K.Para(page, "Each healer's and each Mage's mana as a percent, colored from full (blue) through half (yellow) to nearly empty (red), with a small icon beside the name of anyone getting mana back: drinking, Innervate, Evocation, Mana Tide. Healers are those with the Healer role; where nobody has a role, the healing classes stand in.", x, y, 430)
    y = y - 4
    y = K.Para(page, "Click the panel's header to fold it, drag the header to move it; the mouse wheel scrolls a list longer than the rows shown.", x, y, 430)
    y = y - 6
    K.Check(page, "Include yourself", x, y,
        function() return mana.self == true end,
        function(checked) mana.self = checked Apply() end,
        "On: you get a row too, when you're a healer.")
    y = y - 28
    Choice(page, "Show it in", x, y, WHERE,
        function() return mana.where or "group" end,
        function(value) mana.where = value Apply() end)
    y = y - 28
    K.Stepper(page, "Rows shown", x, y,
        function() return mana.rows or 8 end,
        function(value) mana.rows = value Apply() end, 1, 3, 15,
        function(value) return string.format("%d", value) end)
    y = y - 34
    K.Check(page, "Lock the group panels in place", x, y,
        function() return group.locked == true end,
        function(checked) group.locked = checked end,
        "On: dragging doesn't move the group mana or the raid cooldowns panel.")
    y = y - 32
    K.Button(page, "Show a made-up raid", 150, x, y, function()
        ns.GroupCommand("test")
    end, "Both group panels with a made-up raid for a minute, to see them and place them (same as /ep group test). Click again to stop.")
end)

ns.AddTab("cooldowns", "Cooldowns", function(page, x, y)
    local group = ns.GroupSettings()
    local cooldowns = group.cooldowns
    local function Apply()
        ns.RefreshGroupPanels()
    end
    y = K.Para(page, "Who has each of these ready, and how long until the others' are back. A use is seen when the game says who cast what; a cooldown nobody was seen using counts as ready. Shift-click a line on the panel to tell your group.", x, y, 430)
    y = y - 6
    Choice(page, "Show it in", x, y, WHERE,
        function() return cooldowns.where or "group" end,
        function(value) cooldowns.where = value Apply() end)
    y = y - 30
    -- The cooldowns watched, in two columns.
    local list = ns.GroupCooldownList()
    local half = math.ceil(#list / 2)
    for index, entry in ipairs(list) do
        local column, line = (index > half) and 1 or 0, (index - 1) % half
        K.Check(page, entry.label, x + column * 220, y - line * 22,
            function()
                local chosen = cooldowns.spells[entry.key]
                if chosen == nil then
                    return entry.on == true
                end
                return chosen == true
            end,
            function(checked) cooldowns.spells[entry.key] = checked Apply() end,
            entry.talent and "A talent: only those seen using it are listed." or nil)
    end
    y = y - half * 22 - 10
    K.Button(page, "Forget cooldowns seen", 160, x, y, function()
        ns.GroupCommand("reset")
    end, "Every cooldown counts as ready again (same as /ep group reset).")
end)

------------------------------------------------------------------------------
-- Rebuff List
------------------------------------------------------------------------------

if ns.rebuffClass then
    ns.panelSwitches[#ns.panelSwitches + 1] = { "Rebuff List",
        function() return ns.db.rebuff.show ~= false end,
        function(checked)
            ns.db.rebuff.show = checked
            ns.UpdateRebuffList()
        end,
        "Out of combat in a group: who needs the buffs you can cast, one row per player, a click to cast. Same as /ep rebuff. The buff key works with the list hidden." }
end

ns.AddTab("rebuff", "Rebuff", function(page, x, y)
    if not ns.rebuffClass then
        K.Para(page, "The Rebuff List shows who in your group needs the buffs you can cast, with a click (or one key) to cast them. So far it knows a Druid's: Mark of the Wild and Thorns. There's nothing for this class yet.", x, y, 480)
        return
    end
    ns.db.rebuff = type(ns.db.rebuff) == "table" and ns.db.rebuff or {}
    local list = ns.db.rebuff
    local function Refresh()
        ns.UpdateRebuffList()
    end
    y = K.Para(page, "Out of combat in a group: who needs Mark of the Wild or Thorns, one row per player. Left-click casts Mark, then Thorns; right-click casts Thorns first. Hidden in combat; drag it to move it. Switch it on or off on the General tab.", x, y, 480)
    y = y - 2
    K.Check(page, "Mark of the Wild too", x, y,
        function() return list.markToo ~= false end,
        function(checked) list.markToo = checked Refresh() end,
        "Everyone, you included, checked for Mark or Gift of the Wild. 3 or more in your party or raid needing it: one Gift of the Wild row for everyone (while you have Wild Thornroot); a Gift lands on the whole raid. Thorns is checked on tanks, you, anyone wearing yours and anyone you pin (/ep rebuff watch); in a party with no tank, on everyone.")
    y = y - 24
    K.Check(page, "Thorns on yourself too", x, y,
        function() return list.includeSelf ~= false end,
        function(checked) list.includeSelf = checked Refresh() end)
    y = y - 24
    K.Check(page, "Thorns warnings in chat", x, y,
        function() return list.alerts ~= false end,
        function(checked) list.alerts = checked end,
        "For the people who've worn your Thorns: \"Your Thorns fell off Morvessa.\", \"Leafy overwrote your Thorns on Morvessa.\", \"Morvessa has Thorns rank 4. You can cast rank 6.\" Once per change; what happens in a fight is told when it ends (the game hides buffs in combat). In a group.")
    y = y - 24
    K.Check(page, "Lock it in place", x, y,
        function() return list.locked == true end,
        function(checked) list.locked = checked end)
    y = y - 28
    K.Stepper(page, "List buffs with less than", x, y,
        function() return list.soon or 60 end,
        function(value) list.soon = value Refresh() end, 15, 15, 300,
        function(value) return string.format("%d sec", value) end,
        "A buff this close to running out is listed again, so you can refresh it before the pull.")
    y = y - 34
    K.Button(page, "Test: party", 110, x, y, function()
        ns.RebuffTest(false)
    end, "The list for a made-up party, for 30 seconds (clicks don't cast). Same as /ep rebuff test.")
    K.Button(page, "Test: 40-player raid", 160, x + 118, y, function()
        ns.RebuffTest(true)
    end, "The list for a made-up 40-player raid, for 30 seconds: Thorns on the tanks and whoever wears yours, Gift of the Wild for the raid groups that need Mark. Same as /ep rebuff test raid.")
    y = y - 38
    K.Header(page, "Buff key", x, y)
    y = y - 22
    y = K.Para(page, "One key that casts the list's next buff each time you press it. Out of combat only; works with the list hidden. Also under Key Bindings > ElipsPanels.", x, y, 480)
    local keyLabel = page.body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keyLabel:SetPoint("TOPLEFT", x, y - 6)
    local function ShowKey()
        local key = ns.BuffKeyText()
        keyLabel:SetText("Key: " .. (key and ("|cffffd100" .. key .. "|r") or "|cff999999none|r"))
    end
    ShowKey()
    local setKey
    setKey = K.Button(page, "Set key", 110, x + 150, y, function()
        if InCombatLockdown() then
            ns.Print("keys can't be changed in combat.")
            return
        end
        setKey.label:SetText("Press a key...")
        local catcher = setKey.catcher
        if not catcher then
            catcher = CreateFrame("Frame", nil, setKey)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("DIALOG")
            catcher:EnableMouse(false)
            setKey.catcher = catcher
            local modifiers = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
            catcher:SetScript("OnKeyDown", function(self, key)
                if modifiers[key] then
                    return
                end
                self:EnableKeyboard(false)
                self:Hide()
                setKey.label:SetText("Set key")
                if key ~= "ESCAPE" then
                    local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
                    ns.BindBuffKey(combo)
                end
                ShowKey()
            end)
        end
        catcher:Show()
        catcher:EnableKeyboard(true)
    end, "Click, then press the key you want (with Shift, Ctrl or Alt if you like). Esc cancels.")
    K.Button(page, "Clear", 70, x + 268, y, function()
        ns.BindBuffKey(nil)
        ShowKey()
    end)
    page.body:HookScript("OnShow", ShowKey)
end)

------------------------------------------------------------------------------
-- Threat panel
------------------------------------------------------------------------------

ns.panelSwitches[#ns.panelSwitches + 1] = { "Threat panel",
    function() return ns.db.threat.show ~= false end,
    function(checked)
        ns.db.threat.show = checked
        ns.RefreshThreat()
    end,
    "In a fight, above the target frame: your threat on your target, colored for whether you're tanking. Same as /ep threat." }

local THREAT_AS = { { "auto", "Automatic" }, { "tank", "A tank" }, { "other", "A damage dealer or healer" } }

ns.AddTab("threat", "Threat", function(page, x, y)
    ns.db.threat = type(ns.db.threat) == "table" and ns.db.threat or {}
    local threat = ns.db.threat
    y = K.Para(page, "In a fight, your threat on your target shows above the target frame (100% means it's on you, or about to be). Tanking, it wears the nameplate threat colors: tanking, about to lose it, on another tank, on a damage dealer or healer. Otherwise it's green when you're well below, turning yellow, orange (\"Pulling aggro!\") and red, and once the mob is on you the number grows and pulses. In a group, while the mob is on you, it names who's next and how close. Switch it on or off on the General tab.", x, y, 540)
    y = y - 4
    Choice(page, "Color it as", x, y, THREAT_AS,
        function() return threat.as or "auto" end,
        function(value) threat.as = value ns.RefreshThreat() end,
        "Automatic: a Druid in Bear Form and a Warrior in Defensive Stance count as tanking; any other class by its group role (tank, or main tank in a raid).")
    y = y - 34
    K.Check(page, "Threat and damage per second", x, y,
        function() return threat.tps ~= false end,
        function(checked) threat.tps = checked ns.RefreshThreat() end,
        "A line above your threat: threat per second on the target (last 15 seconds, without what a taunt hands you) and damage per second (from the game's damage meter, when it can be read in combat). A Druid's shows in Cat and Bear Form only.")
end)

