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
    window = K.Window("ElipsPanelsOptions", "ElipsPanels", 470, 400)
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
