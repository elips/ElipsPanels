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

ns.AddTab("info", "Information bar", function(page, x, y)
    local info = ns.InfoSettings()
    y = K.Para(page, "A thin bar, centered at the top of the screen to start with: the time, latency, frames per second, experience and gold per hour, what the addons take of each frame and of memory, your most worn piece of gear, free bag slots and the currencies you tick.", x, y, 430)
    y = y - 4
    y = K.Para(page, "Right-click the bar to choose what it shows, your currencies included. Shift-click it to start the per-hour counts again. Point at it for the details.", x, y, 430)
    y = y - 8
    K.Stepper(page, "Text size", x, y,
        function() return tonumber(info.size) or 12 end,
        function(value)
            info.size = value
            ns.ApplyInfoBar()
        end, 1, 9, 18,
        function(value) return string.format("%d", value) end)
end)
