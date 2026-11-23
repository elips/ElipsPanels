-- Core.lua
-- ElipsPanels: the suite's small panels, in one addon. Each can be shown
-- or hidden by itself (/ep, General).
--   Information bar   the time, latency, frames per second, gold and
--                     experience per hour, addon CPU and memory,
--                     durability, bag space and currencies (Info.lua)
--   Chase list        things to go after (items, reputations, quests,
--                     goals of your own), each with a note on how to get
--                     it (Chase.lua)
--   Group mana        each healer's and each Mage's mana, as a percent
--   Raid cooldowns    who has Rebirth, Reincarnation, Lay on Hands and the
--                     like ready, and when the others' are back (Group.lua)
--
-- This file: the settings, the few helpers the panels share (the panels'
-- look, fading away in a fight, moving them), and the slash command.

local ADDON, ns = ...
local K = ns.K
K.title = "ElipsPanels"
K.color = "ffdbb575"

ns.IsSecret, ns.Num, ns.Str, ns.Bool = K.IsSecret, K.Num, K.Str, K.Bool
ns.Print = K.Print
ns.On = K.On
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ElipsPanels", "Version")) or "?"

------------------------------------------------------------------------------
-- Messages between the parts
------------------------------------------------------------------------------
--   INIT          settings are loaded: set yourself up
--   COMBAT(now)   a fight began (true) or ended (false)
--   THEME         the accent color changed

local hooks = {}
function ns.Hook(message, fn)
    hooks[message] = hooks[message] or {}
    hooks[message][#hooks[message] + 1] = fn
end

function ns.Fire(message, ...)
    local list = hooks[message]
    if list then
        for index = 1, #list do
            list[index](...)
        end
    end
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

ns.DEFAULTS = {
    -- Whole panels kept from setting themselves up at all (after a reload).
    modules = {},
    -- Panels fade away in combat and come back under the mouse.
    quietPanels = true,
    -- The information bar (Info.lua): shown, its text size, what's on it
    -- (items[key] = false for a piece taken off), the currencies ticked.
    info = { show = true, size = 12, items = {}, currencies = {} },
    -- The chase list (Chase.lua): things to go after, kept per character in
    -- `lists`; the panel on screen (`show`, `hideInCombat`, `rows`), and
    -- whether it speaks up (`alerts`, `sound`, `tooltip`).
    chase = { show = true, hideInCombat = true, rows = 6, alerts = true, sound = true, tooltip = true },
    -- The group panels (Group.lua): the healers' and Mages' mana, and the
    -- raid's cooldowns. `where`: "group" (parties and raids) or "raid".
    -- `spells`: a cooldown's key -> watched or not (unset: its own default).
    -- `used` and `seen`: the cooldowns seen used, by player (kept by wall
    -- clock, so a reload doesn't forget them).
    group = { mana = { show = true, where = "group", rows = 8, self = false },
        cooldowns = { show = true, where = "group", rows = 8, spells = {} }, used = {}, seen = {} },
}

function ns.ModuleOn(key)
    local modules = ns.db and ns.db.modules
    return not (type(modules) == "table" and modules[key] == false)
end
local loadedModules = {}
function ns.ModuleLoaded(key)
    if loadedModules[key] == nil then
        loadedModules[key] = ns.ModuleOn(key)
    end
    return loadedModules[key]
end

------------------------------------------------------------------------------
-- The panels' look
------------------------------------------------------------------------------
-- Dark, rounded, with a thin edge of weathered bronze (the suite's kit).
-- The accent (a line along a panel's foot, a tick, a light under the
-- mouse) is antique gold; with ElipsUI installed and a class HUD running,
-- it is the HUD's theme color, and the panels get ElipsUI's gloss along
-- the top (its "Gloss on panels" switches that off for the whole suite).

local W = {}
ns.W = W
W.GOLD = K.GOLD
W.PANEL_EDGE = K.EDGE
local OWN_ACCENT = { K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3] }
W.NATURE = { OWN_ACCENT[1], OWN_ACCENT[2], OWN_ACCENT[3] }   -- the accent, repainted in place

local function Suite()
    local suite = rawget(_G, "ElipsUI")
    return type(suite) == "table" and suite or nil
end

-- Everything drawn in the accent registers how to repaint itself.
W.repaint = setmetatable({}, { __mode = "k" })
function W.OnRetheme(key, fn)
    W.repaint[key] = fn
end
W.themeStats = { repaints = 0, failed = 0 }
function W.Retheme()
    W.themeStats.repaints = W.themeStats.repaints + 1
    for _, fn in pairs(W.repaint) do
        if not pcall(fn) then
            W.themeStats.failed = W.themeStats.failed + 1
        end
    end
    ns.Fire("THEME")
end

local function TakeTheme()
    local suite = Suite()
    local theme
    if suite and type(suite.Theme) == "function" then
        local ok, got = pcall(suite.Theme)
        theme = ok and type(got) == "table" and type(got.main) == "table" and got or nil
    end
    local color = theme and theme.main or OWN_ACCENT
    if K.Num(color[1]) and K.Num(color[2]) and K.Num(color[3]) then
        W.NATURE[1], W.NATURE[2], W.NATURE[3] = color[1], color[2], color[3]
    end
    W.themeSource = theme and (theme.name or "a HUD's theme") or nil
    W.Retheme()
end
ns.TakeTheme = TakeTheme

function W.Gradient(texture, orientation, from, to)
    local createColor = rawget(_G, "CreateColor")
    if not (texture.SetGradient and createColor) then
        return false
    end
    return (pcall(texture.SetGradient, texture, orientation, createColor(unpack(from)), createColor(unpack(to))))
end

-- A thin line that runs from antique gold into the accent.
local function PaintAccentLine(texture, accent, alpha)
    texture:SetColorTexture(1, 1, 1, 1)
    if not W.Gradient(texture, "HORIZONTAL", { W.GOLD[1], W.GOLD[2], W.GOLD[3], alpha },
        { accent[1], accent[2], accent[3], alpha * 0.5 }) then
        texture:SetColorTexture(accent[1], accent[2], accent[3], alpha)
    end
end
function W.AccentLine(texture, accent, alpha)
    alpha = alpha or 0.6
    PaintAccentLine(texture, accent, alpha)
    W.OnRetheme(texture, function() PaintAccentLine(texture, accent, alpha) end)
end

-- A panel: `frame` gets the kit's rounded dark inside and bronze edge.
function W.PanelBackdrop(frame, alpha)
    local look = frame.kitLook or K.Rounded(frame, 7)
    look:Fill(K.FILL[1], K.FILL[2], K.FILL[3], alpha or 0.9)
    return true
end

-- The gloss along a panel's top: ElipsUI's, when it is installed and has
-- one to give. Returns the panel's pieces ({ glow = texture }).
local function GlossColor()
    local suite = Suite()
    if suite and type(suite.GlossColor) == "function" then
        local ok, color = pcall(suite.GlossColor)
        if ok and type(color) == "table" and K.Num(color[1]) and K.Num(color[2]) and K.Num(color[3]) then
            return color
        end
    end
    return nil
end
local function PaintGloss(theme)
    local color = GlossColor()
    if color then
        theme.glow:SetColorTexture(1, 1, 1, 1)
        if not W.Gradient(theme.glow, "VERTICAL", { color[1], color[2], color[3], 0 }, { color[1], color[2], color[3], 0.22 }) then
            theme.glow:SetColorTexture(color[1], color[2], color[3], 0.1)
        end
    end
    theme.glow:SetShown(color ~= nil)
end
function W.ThemePanel(frame)
    local theme = frame.elipsTheme
    if not theme then
        theme = {}
        theme.glow = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
        theme.glow:SetPoint("TOPLEFT", 3, -3)
        theme.glow:SetPoint("TOPRIGHT", -3, -3)
        theme.glow:SetHeight(30)
        frame.elipsTheme = theme
        W.OnRetheme(theme, function() PaintGloss(theme) end)
    end
    PaintGloss(theme)
    return theme
end

------------------------------------------------------------------------------
-- Panels step aside in a fight
------------------------------------------------------------------------------
-- In combat a panel registered here fades away, and comes back while the
-- mouse is over where it sits (and for a moment after), so the screen is
-- clear for the fight and anything is still a glance away. Out of combat
-- they're as they were. Faded, not hidden: a hidden frame can't be pointed
-- at. Setting: db.quietPanels (on unless switched off; /ep, General).
-- The group mana panel isn't registered: it's for the fight.
local quiet = {}             -- frame -> { also = fn giving a second frame that goes with it, alpha, keep }
local QUIET_FADE = 0.15      -- seconds to fade out or in
local QUIET_HOLD = 0.4       -- seconds a panel stays after the mouse leaves it
local QUIET_STEP = 0.05      -- seconds between looks while something is fading
local QUIET_WATCH = 0.1      -- and while nothing is: only watching for the mouse
local quietLooping, quietLast = false, nil
W.quietStats = { fades = 0, shows = 0 }

function W.QuietOn()
    return not (ns.db and ns.db.quietPanels == false)
end

local function QuietOver(frame, also)
    -- (Turning the camera with the mouse held: the pointer isn't pointing.)
    local looking = rawget(_G, "IsMouselooking")
    if looking and looking() then
        return false
    end
    if frame:IsShown() and frame:IsMouseOver() then
        return true
    end
    return also ~= nil and also:IsShown() and also:IsMouseOver()
end

local function QuietPass()
    quietLooping = false
    local active = ns.inCombat == true and W.QuietOn()
    local now = GetTime()
    local step = math.min(1, math.max(QUIET_STEP, now - (quietLast or now)) / QUIET_FADE)
    quietLast = now
    local settled = true
    for frame, entry in pairs(quiet) do
        local also = entry.also and entry.also() or nil
        local want = 1
        if active then
            if QuietOver(frame, also) then
                if not entry.keep or now >= entry.keep then
                    W.quietStats.shows = W.quietStats.shows + 1
                end
                entry.keep = now + QUIET_HOLD
            end
            want = (entry.keep and now < entry.keep) and 1 or 0
        else
            entry.keep = nil
        end
        local alpha = entry.alpha or 1
        if alpha ~= want then
            alpha = (want > alpha) and math.min(1, alpha + step) or math.max(0, alpha - step)
            if alpha < 0.01 then
                alpha = 0
            end
            entry.alpha = alpha
            frame:SetAlpha(alpha)
            if alpha == 0 then
                W.quietStats.fades = W.quietStats.fades + 1
            end
            settled = settled and alpha == want
        end
        if also and entry.alsoAlpha ~= alpha then
            entry.alsoAlpha = alpha
            also:SetAlpha(alpha)
        end
    end
    if active or not settled then
        quietLooping = true
        C_Timer.After(settled and QUIET_WATCH or QUIET_STEP, QuietPass)
    else
        quietLast = nil
    end
end

-- `also`: a function giving a second frame that belongs with this one (a
-- list that opens under it), or nil.
function W.QuietInCombat(frame, also)
    quiet[frame] = quiet[frame] or {}
    quiet[frame].also = also or quiet[frame].also
end

-- The setting changed, or a fight began or ended.
function W.ApplyQuiet()
    if not quietLooping then
        QuietPass()
    end
end

ns.Hook("COMBAT", function()
    W.ApplyQuiet()
end)

-- Puts a panel where it was last left: `pos` is { x, y } from the screen's
-- bottom left corner to the panel's top left corner (or its center, with
-- `center`); with none saved, `default` is { point, relativePoint, x, y }.
function W.PlacePanel(frame, pos, default, center)
    frame:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" then
        frame:SetPoint(center and "CENTER" or "TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        frame:SetPoint(default[1], UIParent, default[2], default[3], default[4])
    end
end

------------------------------------------------------------------------------
-- A window, buttons and a box to type in, for a panel that has a window
------------------------------------------------------------------------------

W.TITLE_HEIGHT = 34   -- a window's title and the rule under it, from its top edge

function W.Window(name, title, width, height)
    return K.Window(name, title, width, height)
end

-- A button (not placed: the caller sets its point). button:SetText changes
-- what it says.
function W.Button(parent, text, width, onClick, height)
    local button = K.Button({ body = parent }, text, width, 0, 0, onClick)
    button:ClearAllPoints()
    if height then
        button:SetHeight(height)
    end
    function button:SetText(newText)
        self.label:SetText(newText)
    end
    return button
end

-- A box to type in: `hintText` shows in grey while it's empty.
function W.TextBox(parent, name, hintText, width)
    local box = CreateFrame("EditBox", name, parent)
    box:SetSize(width or 200, 22)
    box:SetAutoFocus(false)
    box:SetFontObject(rawget(_G, "GameFontHighlightSmall") or "GameFontHighlightSmall")
    box:SetTextInsets(7, 6, 0, 0)
    local look = K.Rounded(box, 6)
    look:Fill(0.045, 0.039, 0.032, 1)
    look:Edge(K.EDGE_DIM[1], K.EDGE_DIM[2], K.EDGE_DIM[3], 1)
    local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 7, 0)
    hint:SetText(hintText or "")
    box.hint = hint
    box:HookScript("OnTextChanged", function(self)
        hint:SetShown((self:GetText() or "") == "")
    end)
    -- (Brighter while you type in it.)
    box:HookScript("OnEditFocusGained", function() look:Edge(K.EDGE_LIT[1], K.EDGE_LIT[2], K.EDGE_LIT[3], 1) end)
    box:HookScript("OnEditFocusLost", function() look:Edge(K.EDGE_DIM[1], K.EDGE_DIM[2], K.EDGE_DIM[3], 1) end)
    return box
end

-- One line to your group: instance chat, raid chat or party chat,
-- whichever you're in.
local CHAT_LIMIT = 250
function ns.SendGroupLine(text)
    local chatType
    local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
    if instance and IsInGroup and ns.Bool(IsInGroup(instance)) then
        chatType = "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        chatType = "RAID"
    elseif IsInGroup and IsInGroup() then
        chatType = "PARTY"
    end
    if not chatType then
        ns.Print("you're not in a group.")
        return false
    end
    local chat = rawget(_G, "C_ChatInfo")
    if chat and chat.InChatMessagingLockdown then
        local ok, locked = pcall(chat.InChatMessagingLockdown)
        if ok and ns.Bool(locked) then
            ns.Print("chat is locked right now (during a boss fight); try again after it.")
            return false
        end
    end
    if #text > CHAT_LIMIT then
        text = text:sub(1, CHAT_LIMIT - 3) .. "..."
    end
    local send = (chat and chat.SendChatMessage) or rawget(_G, "SendChatMessage")
    if not send then
        return false
    end
    return (pcall(send, text, chatType))
end

------------------------------------------------------------------------------
-- Moving the panels
------------------------------------------------------------------------------
-- /ep move puts a blue box where each panel sits (shown or not): drag one
-- and its panel moves there, right-click it to put the panel back where it
-- started. The boxes line up with the middle of the screen and with the
-- suite's other frames as you drag (hold Shift not to), and are put away
-- in a fight. A panel says how with ns.RegisterMover:
--   { key, label, width, height, default = { point, relativePoint, x, y },
--     center = true when its place is its center, get(), set(pos) }
local movers, boxes = {}, {}
local moving = false
ns.movers = movers

local function PlaceBox(box, spec)
    box:SetSize(spec.width, spec.height)
    W.PlacePanel(box, spec.get(), spec.default, spec.center)
end

local function Box(spec)
    local box = boxes[spec.key]
    if box then
        return box
    end
    box = CreateFrame("Frame", "ElipsPanelsMover_" .. spec.key, UIParent)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    local shade = box:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.20, 0.50, 1.00, 0.40)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 3, 0)
    label:SetPoint("RIGHT", -3, 0)
    label:SetJustifyH("CENTER")
    label:SetText(spec.label)
    K.Drag(box, box, function(x, y)
        local pos
        if spec.center then
            pos = { math.floor(x + 0.5), math.floor(y + 0.5) }
        else
            local left, top = K.Num(box:GetLeft()), K.Num(box:GetTop())
            pos = left and top and { math.floor(left + 0.5), math.floor(top + 0.5) } or nil
        end
        if pos then
            spec.set(pos)
            PlaceBox(box, spec)
        end
    end)
    box:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            spec.set(nil)
            PlaceBox(box, spec)
        end
    end)
    box:Hide()
    boxes[spec.key] = box
    return box
end

local function ShowBoxes(shown)
    for _, spec in ipairs(movers) do
        local box = Box(spec)
        if shown and (spec.loaded == nil or spec.loaded()) then
            PlaceBox(box, spec)
            box:Show()
        else
            box:Hide()
        end
    end
end

function ns.RegisterMover(spec)
    movers[#movers + 1] = spec
    if moving and not ns.inCombat then
        ShowBoxes(true)
    end
end

function ns.Move(on)
    if on == nil then
        on = not moving
    end
    if on and ns.inCombat then
        K.Print("not in a fight: the panels can be moved when it's over.")
        return false
    end
    moving = on and true or false
    ShowBoxes(moving)
    return moving
end

function ns.Moving()
    return moving
end

ns.Hook("COMBAT", function(now)
    if moving then
        ShowBoxes(not now)
    end
end)

ns.moverInternals = { boxes = boxes }

------------------------------------------------------------------------------
-- Start-up
------------------------------------------------------------------------------

K.On("ADDON_LOADED", function(name)
    if name ~= ADDON or ns.db then
        return
    end
    ns.firstRun = rawget(_G, "ElipsPanelsDB") == nil
    ns.db = K.Settings("ElipsPanelsDB", ns.DEFAULTS)
end)

K.On("PLAYER_LOGIN", function()
    if not ns.db then
        ns.db = K.Settings("ElipsPanelsDB", ns.DEFAULTS)
    end
    ns.inCombat = K.Bool(InCombatLockdown(), false)
    -- Settings from before these panels were ElipsPanels', if a file here
    -- knows of any: by now every addon's saved settings are loaded.
    local cameOver = ns.Migrate and ns.Migrate()
    -- The accent follows the class HUD's theme, told through ElipsUI.
    local suite = Suite()
    if suite and type(suite.OnTheme) == "function" then
        pcall(suite.OnTheme, function() TakeTheme() end)
    end
    if suite and type(suite.OnGloss) == "function" then
        pcall(suite.OnGloss, function() W.Retheme() end)
    end
    TakeTheme()
    ns.Fire("INIT")
    ns.ready = true
    if cameOver then
        K.Print(cameOver .. " /ep for settings.")
    elseif ns.firstRun then
        K.Print("the information bar is at the top of the screen: right-click it to choose what it shows. /ep for settings.")
    end
end)
K.On("PLAYER_REGEN_DISABLED", function()
    ns.inCombat = true
    ns.Fire("COMBAT", true)
end)
K.On("PLAYER_REGEN_ENABLED", function()
    ns.inCombat = false
    ns.Fire("COMBAT", false)
end)

-- What each part says of itself (/ep status): parts add a function.
ns.statusParts = {}
function ns.StatusLines()
    local lines = { "ElipsPanels " .. tostring(ns.VERSION) .. " | accent: " .. (W.themeSource or "its own antique gold")
        .. " | fading in a fight: " .. (W.QuietOn() and "on" or "off") }
    for _, part in ipairs(ns.statusParts) do
        local ok, text = pcall(part)
        if ok and type(text) == "table" then
            for _, line in ipairs(text) do
                lines[#lines + 1] = line
            end
        else
            lines[#lines + 1] = ok and text or ("(a part couldn't say: " .. tostring(text) .. ")")
        end
    end
    return lines
end

-- Commands the panels add: ns.commands[word] = function(rest).
ns.commands = {}

SLASH_ELIPSPANELS1 = "/ep"
SLASH_ELIPSPANELS2 = "/elipspanels"
SlashCmdList["ELIPSPANELS"] = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if not ns.db then
        return
    end
    if command == "status" then
        for _, line in ipairs(ns.StatusLines()) do
            K.Print(line)
        end
    elseif command == "move" or command == "unlock" or command == "lock" then
        local on = ns.Move(command == "lock" and false or nil)
        if on then
            K.Print("drag a blue box to move its panel (right-click one to put it back); /ep move again when done.")
        elseif not ns.inCombat then
            K.Print("panels locked.")
        end
    elseif ns.commands[command] then
        ns.commands[command](rest)
    elseif command == "help" or command == "?" then
        K.Print("/ep: settings. /ep move: move the panels. /ep info: show or hide the information bar. /ep chase: the chase list. /ep group test: a made-up raid for the group panels. /ep status: how each panel stands.")
    else
        ns.ToggleOptions()
    end
end
