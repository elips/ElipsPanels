-- Threat.lua
-- The threat panel above the target frame: your threat on your target, as
-- the game counts it (100% means you have, or are about to take, its
-- attention). It came from ArchDruid; here it's for any class.

local _, ns = ...
local W = ns.W

------------------------------------------------------------------------------
-- Threat, above the target frame
------------------------------------------------------------------------------
-- A small panel above the target frame's name, in a fight, on a target you
-- can attack. Its color depends on whether you're tanking:
--   tanking    the nameplate threat colors (tanking, about to lose it, on
--              another tank, on a damage dealer or healer), no words
--   otherwise  green when you're well below, yellow getting close, orange
--              about to pull, red when it's on you
-- Not tanking, "Pulling aggro!" just before you pull, and once the mob is
-- on you the number grows, bold, and pulses with a red edge. While the mob
-- is on you in a group: who's next and how close.
--
-- Tanking is worked out ("Color it as", Automatic): a Druid in Bear Form, a
-- Warrior in Defensive Stance; any other class by its group role (tank, or
-- main tank in a raid). It can be set to always or never instead.
--
-- A line above can show your threat per second and damage per second (a
-- Druid's only in Cat and Bear Form, where they mean something).

local function Settings()
    local db = ns.db
    if type(db.threat) ~= "table" then
        db.threat = {}
    end
    return db.threat
end

-- Can you attack your target? (Not known: taken as yes.)
local function Attackable()
    local ok, can = pcall(UnitCanAttack, "player", "target")
    if not ok or ns.IsSecret(can) then
        return true
    end
    return can == true
end

local _, playerClass = UnitClass("player")
playerClass = ns.Str(playerClass)

-- The forms and stances a tank fights in, and the ones a Druid fights in at
-- all (as the game numbers them).
local TANK_FORMS = { DRUID = { [5] = true, [8] = true }, WARRIOR = { [18] = true } }   -- Bear, Dire Bear; Defensive Stance
local DRUID_FIGHTING_FORMS = { [1] = true, [5] = true, [8] = true }                    -- Cat, Bear, Dire Bear

local function FormID()
    local fn = rawget(_G, "GetShapeshiftFormID")
    if not fn then
        return nil, false
    end
    local ok, id = pcall(fn)
    if not ok or ns.IsSecret(id) then
        return nil, false
    end
    return id, true
end

-- Are you tanking? As set, or worked out: by form or stance for the classes
-- that have one for it, else by your role in the group.
local function Tanking()
    local as = Settings().as
    if as == "tank" then
        return true
    elseif as == "other" then
        return false
    end
    local forms = playerClass and TANK_FORMS[playerClass]
    if forms then
        local id, known = FormID()
        if known then
            return id ~= nil and forms[id] == true
        end
    end
    local okRole, role = pcall(UnitGroupRolesAssigned, "player")
    if okRole and not ns.IsSecret(role) and role == "TANK" then
        return true
    end
    local assigned = rawget(_G, "GetPartyAssignment")
    if assigned then
        local ok, yes = pcall(assigned, "MAINTANK", "player")
        if ok and not ns.IsSecret(yes) and yes == true then
            return true
        end
    end
    return false
end

-- Does the threat and damage per second line mean something now? Always,
-- but for a Druid out of Cat and Bear Form.
local function Fighting()
    if playerClass ~= "DRUID" then
        return true
    end
    local id, known = FormID()
    return known and id ~= nil and DRUID_FIGHTING_FORMS[id] == true
end

local THREAT_PANEL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local GREEN, YELLOW, ORANGE, RED = { 0.25, 1, 0.25 }, { 1, 0.9, 0.2 }, { 1, 0.55, 0.1 }, { 1, 0.22, 0.2 }
ns.threatStatus = "not shown yet"

local function TargetBox()
    local frame = _G.TargetFrame
    if not frame then
        return nil
    end
    local content = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    return (content and content.HealthBarsContainer) or frame.healthbar or frame, frame
end

local threatPanel, threatValue, threatNote

local function CreateThreatPanel()
    local box, targetFrame = TargetBox()
    if not box then
        ns.threatStatus = "no target frame"
        return
    end
    local ok, panel = pcall(CreateFrame, "Frame", "ElipsPanelsThreat", targetFrame, "BackdropTemplate")
    if not (ok and panel) then
        panel = CreateFrame("Frame", "ElipsPanelsThreat", targetFrame)
    end
    panel:SetSize(60, 18)
    -- Just above the gold box around the target's name.
    panel:SetPoint("BOTTOM", box, "TOP", 0, 24)
    panel:SetFrameStrata("MEDIUM")
    if panel.SetBackdrop then
        panel:SetBackdrop(THREAT_PANEL)
        panel:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
        panel:SetBackdropBorderColor(0.85, 0.68, 0.30, 1)
    end
    -- The suite's gloss along the top, when there is one.
    local theme = W.ThemePanel(panel)
    theme.glow:SetHeight(12)
    threatValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    threatValue:SetPoint("LEFT", 7, 0)
    local font, size = threatValue:GetFont()
    panel.font, panel.fontSize = font, size or 12
    -- When the mob is on you (and you're not tanking): bigger, bolder numbers and
    -- a pulsing red edge instead of words.
    local ok2, alert = pcall(CreateFrame, "Frame", nil, panel, "BackdropTemplate")
    if not (ok2 and alert) then
        alert = CreateFrame("Frame", nil, panel)
    end
    alert:SetPoint("TOPLEFT", -2, 2)
    alert:SetPoint("BOTTOMRIGHT", 2, -2)
    alert:SetFrameLevel(panel:GetFrameLevel() + 1)
    if alert.SetBackdrop then
        alert:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        alert:SetBackdropBorderColor(1, 0.15, 0.1, 1)
    end
    local pulse = alert:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.15)
    fade:SetDuration(0.45)
    fade:SetSmoothing("IN_OUT")
    alert.pulse = pulse
    local textPulse = threatValue:CreateAnimationGroup()
    textPulse:SetLooping("BOUNCE")
    local textFade = textPulse:CreateAnimation("Alpha")
    textFade:SetFromAlpha(1)
    textFade:SetToAlpha(0.45)
    textFade:SetDuration(0.45)
    textFade:SetSmoothing("IN_OUT")
    alert.textPulse = textPulse
    alert:Hide()
    panel.alert = alert
    threatNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    threatNote:SetPoint("LEFT", threatValue, "RIGHT", 5, 0)
    -- Your threat and damage per second, on a line above.
    panel.tps = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.tps:SetPoint("TOPLEFT", 7, -6)
    panel.tps:SetTextColor(0.85, 0.85, 0.85)
    panel.tps:Hide()
    -- Damage per second: one label per entry in the game's damage meter,
    -- only yours showing (which entry is you may be hidden in combat).
    panel.dpsLabels = {}
    for i = 1, 8 do
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", panel.tps, "RIGHT", 5, 0)
        label:SetTextColor(1, 0.82, 0.45)
        label:Hide()
        panel.dpsLabels[i] = label
    end
    panel:Hide()
    threatPanel = panel
    ns.threatPanel = panel
end

-- Who's next on the target's threat while you tank: the group member (or
-- pet) with the most threat after you, and how much.
local function NextInLine(mob)
    mob = mob or "target"
    if not IsInGroup() then
        return nil
    end
    local best, bestName
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    end
    local function Check(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, unit, mob)
            if ok and scaled and not ns.IsSecret(scaled) and (not best or scaled > best) then
                best, bestName = scaled, UnitName(unit)
            end
        end
    end
    for i = 1, count do
        Check(prefix .. i)
        Check(prefix .. "pet" .. i)
    end
    Check("pet")
    return best, bestName
end

-- Tanking, the same colors as the nameplates: tanking, about to lose it, on
-- another tank, or on a damage dealer or healer.
-- Otherwise, threat by its number: green when well below, yellow from
-- 70%, orange from 90% (or about to pull), red once it's on you.
local function NumberColor(status, scaled)
    if status and status >= 2 then
        return RED
    elseif status == 1 or scaled >= 90 then
        return ORANGE
    elseif scaled >= 70 then
        return YELLOW
    end
    return GREEN
end
ns.ThreatNumberColor = NumberColor

-- The four colors are ElipsUI's settings when it's installed (the same
-- ones its nameplates wear); otherwise the usual green, orange, red, blue.
local PLATE_FALLBACK = { tank = { 0.35, 1.00, 0.35 }, losing = { 1.00, 0.55, 0.10 }, dps = { 1.00, 0.30, 0.25 }, otherTank = { 0.35, 0.70, 1.00 } }
local function PlateColor(status)
    local which
    if status == 3 then
        which = "tank"
    elseif status == 2 then
        which = "losing"
    else
        which = "dps"
        local okRole, role = pcall(UnitGroupRolesAssigned, "targettarget")
        local okTank, mainTank = pcall(GetPartyAssignment, "MAINTANK", "targettarget")
        local onPlayer = UnitExists("targettarget") and UnitIsPlayer("targettarget")
        if (okRole and not ns.IsSecret(role) and role == "TANK") or (okTank and not ns.IsSecret(mainTank) and mainTank == true)
            or (not ns.IsSecret(onPlayer) and UnitExists("targettarget") and onPlayer == false) then
            which = "otherTank"
        end
    end
    local shared = rawget(_G, "ElipsUI")
    if shared and shared.PlateColor then
        local ok, color = pcall(shared.PlateColor, which)
        if ok and type(color) == "table" then
            return color
        end
    end
    return PLATE_FALLBACK[which]
end

local function Paint(color)
    threatValue:SetTextColor(color[1], color[2], color[3])
end

-- The big, pulsing look while the mob is on you (and you're not tanking).
local function SetAlarm(on)
    local panel = threatPanel
    if panel.alarm == on then
        return
    end
    panel.alarm = on
    if panel.font then
        pcall(threatValue.SetFont, threatValue, panel.font, on and (panel.fontSize + 5) or panel.fontSize, on and "THICKOUTLINE" or "")
    end
    local alert = panel.alert
    alert:SetShown(on)
    if on then
        alert.pulse:Play()
        alert.textPulse:Play()
    else
        alert.pulse:Stop()
        alert.textPulse:Stop()
        threatValue:SetAlpha(1)
    end
end

-- Threat per second: how fast your threat on the target grows, over the
-- last 15 seconds. Only threat you earn counts: what a taunt adds by
-- lifting you to the top is left out. Starts over
-- on a new target, when your threat drops (a wipe, a knockback), and out of
-- combat.
local TPS_WINDOW = 15
local TAUNT_JUMP = 1   -- the first threat gain this soon after a taunt is the taunt's
local tps = { samples = {}, earned = 0 }
ns.tpsState = tps
local lastTauntAt = 0
-- The taunts: Growl, Challenging Roar; Taunt, Challenging Shout, Mocking
-- Blow; Righteous Defense.
local TAUNTS = { [6795] = true, [5209] = true, [355] = true, [1161] = true, [694] = true, [7400] = true, [7402] = true,
    [20559] = true, [20560] = true, [31789] = true }

local function ResetTPS()
    tps.samples, tps.key, tps.value, tps.earned, tps.lastThreat = {}, nil, nil, 0, nil
end

local function CastLanded(unit, _, spellID)
    if ns.IsSecret(unit) or unit ~= "player" then
        return
    end
    spellID = ns.Num(spellID)
    if spellID and TAUNTS[spellID] then
        lastTauntAt = GetTime()
        tps.tauntPending = true
        tps.taunts = (tps.taunts or 0) + 1
    end
end

local function SampleTPS(threat)
    if threat == nil or ns.IsSecret(threat) then
        tps.value = nil
        return
    end
    local ok, guid = pcall(UnitGUID, "target")
    local key = (ok and guid ~= nil and not ns.IsSecret(guid)) and guid or "target"
    local now = GetTime()
    if key ~= tps.key or (tps.lastThreat and threat < tps.lastThreat) then
        ResetTPS()
        tps.key = key
    end
    -- What you earned since the last look (not what a taunt handed you).
    if tps.lastThreat then
        local gained = threat - tps.lastThreat
        if tps.tauntPending and now - lastTauntAt > TAUNT_JUMP then
            tps.tauntPending = false   -- the taunt changed nothing (you were already on top)
        end
        -- A taunt's jump is far bigger than a moment's normal gain (more than
        -- a second and a half's worth); a taunt that changed nothing (you were
        -- already on top) leaves the next ordinary gain alone.
        if tps.tauntPending and gained > 0 and gained > (tps.value or 0) * 1.5 then
            tps.tauntPending = false
            tps.skipped = (tps.skipped or 0) + gained
        else
            tps.earned = tps.earned + gained
        end
    end
    tps.lastThreat = threat
    local samples = tps.samples
    samples[#samples + 1] = { now, tps.earned }
    while #samples > 2 and now - samples[2][1] >= TPS_WINDOW do
        table.remove(samples, 1)
    end
    local first = samples[1]
    local span = now - first[1]
    -- This client gives threat as is (not in hundredths, as some do).
    tps.value = span >= 1.5 and (tps.earned - first[2]) / span or nil
end

-- Damage per second, from the game's own damage meter (the one Details and
-- the like read). Read once a second; in combat the game may hide it.
local DPS_EVERY = 1
local DPS_FORMAT = "|cff888888|||r  %d DPS"   -- "TPS | DPS": a grey divider first
local dpsState = { status = "not read yet" }
ns.dpsState = dpsState
local DM_DAMAGE = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
local DM_CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1

local function HideDPS(panel)
    for _, label in ipairs(panel.dpsLabels) do
        label:Hide()
    end
end

-- Returns true if something is showing.
local function ShowDPS(panel)
    local labels = panel.dpsLabels
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        dpsState.status = "no damage meter in this client"
        HideDPS(panel)
        return false
    end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, DM_CURRENT, DM_DAMAGE)
    if not ok or session == nil then
        dpsState.status = ok and "no fight in the damage meter (is it enabled?)" or ("couldn't read: " .. tostring(session))
        HideDPS(panel)
        return false
    end
    if ns.IsSecret(session) then
        dpsState.status = "hidden by the game"
        HideDPS(panel)
        return false
    end
    local shownAny = false
    local okRead, err = pcall(function()
        local sources = session.combatSources
        if sources == nil or ns.IsSecret(sources) then
            dpsState.status = "entries hidden by the game"
            return
        end
        for i, label in ipairs(labels) do
            local source = sources[i]
            if source and not ns.IsSecret(source) then
                local isMe = source.isLocalPlayer
                if ns.IsSecret(isMe) then
                    label:SetFormattedText(DPS_FORMAT, source.amountPerSecond)
                    if label.SetAlphaFromBoolean and pcall(label.SetAlphaFromBoolean, label, isMe, 1, 0) then
                        label:Show()
                        shownAny = true
                        dpsState.status = "shown (which entry is you: hidden)"
                    else
                        label:Hide()
                    end
                elseif isMe then
                    label:SetFormattedText(DPS_FORMAT, source.amountPerSecond)
                    label:SetAlpha(1)
                    label:Show()
                    shownAny = true
                    dpsState.status = ns.IsSecret(source.amountPerSecond) and "shown (number hidden)" or "shown"
                else
                    label:Hide()
                end
            else
                label:Hide()
            end
        end
    end)
    if not okRead then
        dpsState.status = "couldn't read: " .. tostring(err)
        HideDPS(panel)
        return false
    end
    if not shownAny and dpsState.status:find("^shown") then
        dpsState.status = "you're not in it yet"
    end
    return shownAny
end

local function UpdateThreat()
    if not threatPanel then
        return
    end
    local show = Settings().show ~= false and not ns.PanelsHidden() and UnitExists("target") and Attackable()
    local ok, tanking, status, scaled, threat = false, nil, nil, nil, nil
    if show then
        ok, tanking, status, scaled, _, threat = pcall(UnitDetailedThreatSituation, "player", "target")
    end
    if not (show and ok) or (not ns.IsSecret(scaled) and scaled == nil) then
        SetAlarm(false)
        threatPanel:Hide()
        ns.threatStatus = show and "not on its threat list" or "off (no target or setting)"
        return
    end
    local note = ""
    local alarm = false
    if ns.IsSecret(scaled) or ns.IsSecret(status) then
        -- Hidden: the number and the game's own threat color still work.
        threatValue:SetFormattedText("%d%%", scaled)
        local okColor, r, g, b = pcall(GetThreatStatusColor, status)
        if okColor then
            pcall(threatValue.SetTextColor, threatValue, r, g, b)
        end
        ns.threatStatus = "shown (hidden values)"
    else
        threatValue:SetFormattedText("%d%%", math.floor(scaled + 0.5))
        if Tanking() then
            -- No words: the nameplate threat colors say it.
            Paint(PlateColor(status))
        else
            local color = NumberColor(status, scaled)
            Paint(color)
            if color == RED then
                alarm = true
            elseif color == ORANGE then
                note = "Pulling aggro!"
            end
        end
        if tanking == true then
            local nextScaled, nextName = NextInLine()
            if nextScaled and nextName then
                local nextText = string.format("|cffaaaaaa%s %d%%|r", nextName, math.floor(nextScaled + 0.5))
                note = note ~= "" and (note .. "  " .. nextText) or nextText
            end
        end
        ns.threatStatus = "shown: " .. threatValue:GetText() .. (note ~= "" and (" " .. note) or "")
    end
    SetAlarm(alarm)
    threatNote:SetText(note)
    local width = (ns.Num(threatValue:GetStringWidth()) or 30) + 14
    if note ~= "" then
        width = width + 5 + (ns.Num(threatNote:GetStringWidth()) or 60)
    end
    -- Threat and damage per second above.
    local tpsText = threatPanel.tps
    local showTPS = Settings().tps ~= false and Fighting()
    if showTPS then
        SampleTPS(threat)
        if tps.value then
            tpsText:SetFormattedText("%d TPS", math.floor(math.max(0, tps.value) + 0.5))
        else
            tpsText:SetText("... TPS")
        end
        local now = GetTime()
        if not threatPanel.dpsAt or now >= threatPanel.dpsAt then
            threatPanel.dpsAt = now + DPS_EVERY
            threatPanel.dpsShown = ShowDPS(threatPanel)
        end
        -- The damage number's width may be hidden: room for one.
        width = math.max(width, (ns.Num(tpsText:GetStringWidth()) or 40) + 14 + (threatPanel.dpsShown and 64 or 0))
    elseif threatPanel.dpsShown then
        threatPanel.dpsShown = false
        HideDPS(threatPanel)
    end
    if showTPS ~= threatPanel.showingTPS then
        threatPanel.showingTPS = showTPS
        threatPanel.valueShift = nil
        tpsText:SetShown(showTPS)
        threatValue:ClearAllPoints()
        if not showTPS then
            threatValue:SetPoint("LEFT", 7, 0)
        end
    end
    if showTPS then
        -- Your threat centered under the TPS line (with the note beside it,
        -- the two centered together).
        local shift = 0
        if note ~= "" then
            shift = -((ns.Num(threatNote:GetStringWidth()) or 0) + 5) / 2
        end
        if threatPanel.valueShift ~= shift then
            threatPanel.valueShift = shift
            threatValue:ClearAllPoints()
            threatValue:SetPoint("BOTTOM", threatPanel, "BOTTOM", shift, 5)
        end
    end
    -- Tall enough for the TPS line and for the bigger numbers while the mob
    -- is on you (both can show at once).
    threatPanel:SetHeight((showTPS and 37 or 18) + (alarm and 8 or 0))
    threatPanel:SetWidth(width)
    threatPanel:Show()
end
ns.UpdateThreat = UpdateThreat

-- Events bring it up; while it shows, it also refreshes four times a second
-- (who's next in a group changes without an event of ours). Hidden, the
-- refresher sleeps.
local threatWatcher = CreateFrame("Frame")
local sinceThreat = 0
local function UpdateThreatAndSleep()
    UpdateThreat()
    threatWatcher:SetShown(threatPanel ~= nil and threatPanel:IsShown())
end
threatWatcher:SetScript("OnEvent", UpdateThreatAndSleep)
threatWatcher:SetScript("OnUpdate", function(_, elapsed)
    sinceThreat = sinceThreat + elapsed
    if sinceThreat >= 0.25 then
        sinceThreat = 0
        UpdateThreatAndSleep()
    end
end)

ns.Hook("INIT", function()
    Settings()
    CreateThreatPanel()
    pcall(threatWatcher.RegisterUnitEvent, threatWatcher, "UNIT_THREAT_LIST_UPDATE", "target")
    pcall(threatWatcher.RegisterUnitEvent, threatWatcher, "UNIT_THREAT_SITUATION_UPDATE", "player")
    threatWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    ns.On("PLAYER_REGEN_ENABLED", ResetTPS)
    ns.On("UNIT_SPELLCAST_SUCCEEDED", CastLanded)
    threatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    threatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- (A form or stance, a role: what "tanking" goes by.)
    pcall(threatWatcher.RegisterEvent, threatWatcher, "UPDATE_SHAPESHIFT_FORM")
    pcall(threatWatcher.RegisterEvent, threatWatcher, "PLAYER_ROLES_ASSIGNED")
    ns.Hook("BATTLEGROUND", UpdateThreatAndSleep)
    UpdateThreatAndSleep()
end)

-- The settings changed: look again.
function ns.RefreshThreat()
    UpdateThreatAndSleep()
end

------------------------------------------------------------------------------
-- /ep threat, /ep status
------------------------------------------------------------------------------

-- /ep threat: on or off (show, hide, on, off say which).
ns.commands.threat = function(rest)
    local settings = Settings()
    local word = (rest or ""):lower()
    local on = settings.show == false
    if word == "show" or word == "on" then
        on = true
    elseif word == "hide" or word == "off" then
        on = false
    end
    settings.show = on
    UpdateThreatAndSleep()
    ns.Print(on and "threat panel on (it shows above the target frame in a fight)." or "threat panel off.")
end

ns.statusParts[#ns.statusParts + 1] = function()
    local settings = Settings()
    return {
        string.format("Threat panel: %s | colored as %s (%s) | now: %s", settings.show == false and "off" or "on",
            settings.as == "tank" and "a tank, always" or settings.as == "other" and "a damage dealer or healer, always" or "worked out",
            Tanking() and "tanking" or "not tanking", tostring(ns.threatStatus)),
        string.format("    Threat per second: %s, %s (taunts %d, taunt threat left out %.0f) | damage per second: %s",
            settings.tps == false and "off" or "on", tps.value and string.format("%.0f", tps.value) or "none yet", tps.taunts or 0,
            tps.skipped or 0, tostring(dpsState.status)),
    }
end

-- For the tests.
ns.ThreatInternals = { Tanking = Tanking, Fighting = Fighting, Panel = function() return threatPanel end }
