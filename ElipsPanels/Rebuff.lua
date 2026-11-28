-- Rebuff.lua
-- The Rebuff List: who in your group needs the buffs you can cast, with a
-- click (or one key) to cast them. It came from ArchDruid, and for now it
-- knows a Druid's two: Mark of the Wild (and Gift) and Thorns. Other
-- classes' buffs can be added here; until then the list is a Druid's, and
-- on any other class this file does nothing.

local _, ns = ...

local _, playerClass = UnitClass("player")
ns.rebuffClass = ns.Str(playerClass) == "DRUID"
if not ns.rebuffClass then
    ns.statusParts[#ns.statusParts + 1] = function()
        return "Rebuff List: nothing for this class yet."
    end
    ns.commands.rebuff = function()
        ns.Print("the Rebuff List has nothing for this class yet.")
    end
    return
end

------------------------------------------------------------------------------
-- Rebuff list: Thorns and Mark of the Wild
------------------------------------------------------------------------------
-- Out of combat, in a group, a small list of who needs your buffs. Click a
-- row to cast it.
--
-- Thorns: tanks (group role or main tank), you, anyone you've put Thorns on
-- in this group, and anyone you pin (`/ep rebuff watch`), in a party as in a
-- raid. A row when it's missing, a
-- lower rank than you can cast (yours or another druid's), or yours runs out
-- soon (a countdown).
--
-- Mark of the Wild: everyone, you too, the same three ways. When 3 or more
-- in the party or raid need it, one Gift of the Wild row takes their place
-- (while you have the reagent): on WoW Forever a Gift lands on the whole
-- raid, not one group of it.
--
-- One row per player, with an icon for each buff they need: a click casts
-- Mark first, then (once it lands) Thorns; right-click casts Thorns straight
-- away. Tanks needing Thorns first, then Gift rows, then everyone else:
-- missing, then lower rank, then soonest to run out.
--
-- The buff key: one key (Key Bindings > ElipsPanels, or /ep rebuff bind) that
-- casts the marked row's first buff, one press at a time; when the cast
-- lands it moves on to the next row at once. It works with the list turned
-- off, and never in combat.
--
-- The rows are the game's secure buttons (an addon can only cast through
-- those), which can't change in combat, so the list hides itself when a
-- fight starts and comes back after.

local MAX_ROWS = 10
local ROW_HEIGHT = 20
local WIDTH = 200
local HEADER = 26
local TANK_ICON = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t"
local GIFT_AT = 3              -- this many in the party or raid need Mark: one Gift instead
local THORNROOT = 17026        -- Wild Thornroot, Gift of the Wild's reagent

local REASON_COLORS = {
    missing = { 1.00, 0.40, 0.35 },
    rank = { 1.00, 0.65, 0.20 },
    soon = { 1.00, 0.90, 0.35 },
    gift = { 0.55, 0.90, 0.45 },
}

local listStatus = { shown = 0, rows = 0, checked = 0, why = "not built", casts = 0 }
ns.rebuffStatus = listStatus

local function Settings()
    ns.db.rebuff = ns.db.rebuff or {}
    return ns.db.rebuff
end

------------------------------------------------------------------------------
-- Ranks
------------------------------------------------------------------------------

local THORNS_IDS = { 467, 782, 1075, 8914, 9756, 9910 }
local MARK_IDS = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }
local GIFT_IDS = { 21849, 21850 }
-- Each buff's rank, as Mark of the Wild ranks (Gift rank 1 is as strong as
-- Mark rank 6, rank 2 as rank 7).
local THORNS_RANK, MARK_RANK = {}, {}
for rank, id in ipairs(THORNS_IDS) do
    THORNS_RANK[id] = rank
end
for rank, id in ipairs(MARK_IDS) do
    MARK_RANK[id] = rank
end
MARK_RANK[21849], MARK_RANK[21850] = 6, 7
MARK_RANK[1310503] = 7   -- WoW: Forever's own Mark of the Wild
-- A Gift's own rank. A Gift on someone is measured against your Gift, not
-- against your Mark: "Gift rank 1 is as strong as Mark rank 6" is the old
-- game's sum, and going by it a whole raid under another Druid's Gift showed
-- as "lower rank" than your Mark, with a Gift row that no cast would clear.
local GIFT_RANK = { [21849] = 1, [21850] = 2 }

local function Known(id)
    for _, test in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
        local fn = rawget(_G, test)
        if fn then
            local ok, known = pcall(fn, id)
            if ok and ns.Bool(known) then
                return true
            end
        end
    end
    local book = rawget(_G, "C_SpellBook")
    if book and book.IsSpellInSpellBook then
        local ok, known = pcall(book.IsSpellInSpellBook, id)
        if ok and ns.Bool(known) then
            return true
        end
    end
    return false
end

local names = {}
local function SpellName(id)
    if not names[id] then
        names[id] = (C_Spell and C_Spell.GetSpellName and ns.Str(C_Spell.GetSpellName(id))) or tostring(id)
    end
    return names[id]
end

-- The rank the game would cast for a buff's name: asked by name, it answers
-- with the one in your spellbook.
local function ByName(ids)
    local name = SpellName(ids[#ids])
    local info = C_Spell and C_Spell.GetSpellInfo
    if not info or tonumber(name) then
        return nil   -- (no name to ask by)
    end
    local ok, found = pcall(info, name)
    local id = ok and type(found) == "table" and ns.Num(found.spellID) or nil
    for rank, known in ipairs(ids) do
        if known == id then
            return rank, known
        end
    end
    return nil
end

-- Your highest rank of a buff: its rank and spell ID. `byName`: ask the game
-- by the buff's name first.
local function Highest(byName, ids)
    if byName then
        local rank, id = ByName(ids)
        if rank then
            return rank, id
        end
    end
    for rank = #ids, 1, -1 do
        if Known(ids[rank]) then
            return rank, ids[rank]
        end
    end
end

-- Your highest rank of Gift of the Wild (its spell ID), if you know it.
function ns.HighestGift()
    local _, id = Highest(nil, GIFT_IDS)
    return id
end

local function ItemCount(itemID)
    local item = rawget(_G, "C_Item")
    local count = item and item.GetItemCount and ns.Num(item.GetItemCount(itemID))
    if not count then
        local old = rawget(_G, "GetItemCount")
        count = old and ns.Num(old(itemID))
    end
    return count or 0
end

------------------------------------------------------------------------------
-- Reading the group
------------------------------------------------------------------------------

local given = {}    -- names you've put Thorns on in this group
local pinned = {}   -- names pinned with /ep rebuff watch
-- Buffs that just landed (from your cast), skipped for a few seconds until
-- the game shows them on the player: "mark:Name", "thorns:Name", "gift:0".
local pending = {}
local PENDING_SECONDS = 4

local function PendingKey(kind, row)
    if kind == "gift" then
        return "gift:" .. tostring(row.group)
    end
    return kind .. ":" .. row.who.name
end

local function IsTank(unit)
    -- The ways the game marks a tank's role, not the stance or form.
    local role = UnitGroupRolesAssigned and ns.Str(UnitGroupRolesAssigned(unit))
    if role == "TANK" then
        return true
    end
    local assigned = rawget(_G, "GetPartyAssignment")
    if assigned then
        local ok, yes = pcall(assigned, "MAINTANK", unit)
        if ok and ns.Bool(yes) then
            return true
        end
    end
    return false
end

-- `named`: the aura was found under the buff's own name. Then it is that
-- buff whatever its spell ID: one this file has no rank for (WoW Forever has
-- its own versions, and another Druid's may not be yours) counts as a full
-- one, not as missing. (It was counted as missing: another Druid's Gift of
-- the Wild over yours, and the whole raid needed it again.) The ID is kept
-- for /ep status, so its rank can be filled in.
local UNRANKED = 99
local function Buff(aura, ranks, named)
    local id = ns.Num(aura.spellId)
    local rank = id and ranks[id]
    local unranked = false
    if not rank then
        if not named then
            return nil
        end
        rank, unranked = UNRANKED, true
        if id then
            listStatus.unranked = listStatus.unranked or {}
            listStatus.unranked[id] = ns.Str(aura.name) or "?"
        end
    end
    local source = aura.sourceUnit
    local mine = source ~= nil and not ns.IsSecret(source) and UnitIsUnit and ns.Bool(UnitIsUnit(source, "player")) or false
    local expires = ns.Num(aura.expirationTime)
    local caster
    if not mine and source ~= nil and not ns.IsSecret(source) then
        local ok, name = pcall(UnitName, source)
        caster = ok and ns.Str(name) or nil
    end
    -- A Gift of the Wild: by its ID, or by its name.
    local giftName = ns.Str(aura.name)
    local gift = (id ~= nil and GIFT_RANK[id] ~= nil) or (ranks == MARK_RANK and giftName ~= nil and giftName == SpellName(21850))
        or (ranks == MARK_RANK and giftName == "Gift of the Wild")
    if ranks == MARK_RANK and id then
        listStatus.marksSeen = listStatus.marksSeen or {}
        listStatus.marksSeen[id] = string.format("%s%s", giftName or (gift and "Gift" or "Mark"), unranked and ", no rank known" or (", rank " .. rank))
    end
    return { rank = rank, unranked = unranked, mine = mine, left = (expires and expires > 0) and (expires - GetTime()) or nil,
        id = id, caster = caster, gift = gift or nil, giftRank = id and GIFT_RANK[id] or nil }
end

-- The names each buff goes by: the spells' names in your game's language,
-- and the English ones.
local THORNS_NAMES, MARK_NAMES
local function BuffNames()
    if not THORNS_NAMES then
        local function List(ids, ...)
            local list, seen = {}, {}
            local function add(name)
                if name and not seen[name] and not name:match("^%d+$") then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
            for _, id in ipairs(ids) do
                add(SpellName(id))
            end
            for index = 1, select("#", ...) do
                add((select(index, ...)))
            end
            return list, seen
        end
        local thornsSet, markSet
        THORNS_NAMES, thornsSet = List({ 9910 }, "Thorns")
        MARK_NAMES, markSet = List({ 9885, 21850, 1310503 }, "Mark of the Wild", "Gift of the Wild")
        THORNS_NAMES.set, MARK_NAMES.set = thornsSet, markSet
    end
    return THORNS_NAMES, MARK_NAMES
end

-- Their Thorns and Mark: { rank, mine, left } each, or nil when they have none.
-- Their Thorns and Mark, and whether the game let their buffs be read at
-- all: "read", "refused" (asking failed), "secret" (a hidden answer), or
-- "empty" (neither buff, and no buff of any kind to be seen on them: either
-- they have none, or the game is keeping theirs to itself without saying).
local function BuffsOn(unit)
    local auras = C_UnitAuras
    if not auras then
        return nil, nil, "read"
    end
    local thorns, mark
    local state = "read"
    local thornsNames, markNames = BuffNames()
    local byName = auras.GetAuraDataBySpellName
    if byName then
        local function Find(list, ranks)
            for _, name in ipairs(list) do
                local ok, aura = pcall(byName, unit, name, "HELPFUL")
                if not ok then
                    state = "refused"
                elseif ns.IsSecret(aura) then
                    state = "secret"
                elseif aura ~= nil then
                    local found = Buff(aura, ranks, true)
                    if found then
                        return found
                    end
                end
            end
        end
        thorns = Find(thornsNames, THORNS_RANK)
        mark = Find(markNames, MARK_RANK)
        if state == "read" and not thorns and not mark and auras.GetAuraDataByIndex then
            local ok, first = pcall(auras.GetAuraDataByIndex, unit, 1, "HELPFUL")
            state = (not ok and "refused") or (ns.IsSecret(first) and "secret") or (first == nil and "empty") or state
        end
        return thorns, mark, state
    end
    if not auras.GetAuraDataByIndex then
        return nil, nil, state
    end
    for index = 1, 40 do
        local ok, aura = pcall(auras.GetAuraDataByIndex, unit, index, "HELPFUL")
        if not ok then
            state = "refused"
            break
        elseif ns.IsSecret(aura) then
            state = "secret"
            break
        elseif aura == nil then
            state = index == 1 and "empty" or state
            break
        end
        local name = ns.Str(aura.name)
        thorns = thorns or Buff(aura, THORNS_RANK, name ~= nil and thornsNames.set[name] == true)
        mark = mark or Buff(aura, MARK_RANK, name ~= nil and markNames.set[name] == true)
        if thorns and mark then
            break
        end
    end
    return thorns, mark, state
end

local function InRange(unit, spellID)
    if unit == "player" then
        return true
    end
    local spell = rawget(_G, "C_Spell")
    if spell and spell.IsSpellInRange and spellID then
        local ok, inRange = pcall(spell.IsSpellInRange, spellID, unit)
        if ok and inRange ~= nil and not ns.IsSecret(inRange) then
            return inRange == true or inRange == 1
        end
    end
    return true
end

-- A record of the last clicks on the list (and presses of the buff key):
-- who the row was for, what the button was really set to cast and on whom,
-- how that player stood at that moment, and a moment after the cast, who
-- the buff is on. For /ep status, to find out why a click now and then casts
-- on you instead.
local clicks = {}
local CLICKS_KEPT = 6

local function Flag(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then
        return "?"
    end
    local ok, value = pcall(fn, ...)
    if not ok or ns.IsSecret(value) then
        return "?"
    end
    return value and "yes" or "no"
end

local function NoteClick(button, mouseButton, viaKey)
    local row = button.row
    if not row then
        return
    end
    local now = GetTime()
    local last = clicks[#clicks]
    if last and now - last.at < 0.3 and last.who == (row.who and row.who.name) then
        return   -- the release of the same click
    end
    local right = mouseButton == "RightButton" and not viaKey
    local unit = row.unit
    local cvar = rawget(_G, "GetCVar")
    local okCvar, selfCast = pcall(function() return cvar and cvar("autoSelfCast") end)
    local note = {
        at = now, who = row.who and row.who.name or "?", kind = row.kind, unit = unit, via = viaKey and "key" or (right and "right" or "left"),
        setUnit = button:GetAttribute("unit"), setSpell = button:GetAttribute(right and "spell2" or "spell"),
        setType = button:GetAttribute(right and "type2" or "type"),
        isYou = unit and Flag("UnitIsUnit", unit, "player") or "?", exists = unit and Flag("UnitExists", unit) or "?",
        visible = unit and Flag("UnitIsVisible", unit) or "?", dead = unit and Flag("UnitIsDeadOrGhost", unit) or "?",
        assist = unit and Flag("UnitCanAssist", "player", unit) or "?", connected = unit and Flag("UnitIsConnected", unit) or "?",
        inRange = unit and InRange(unit, row.spell) and "yes" or "no", combat = InCombatLockdown() and "yes" or "no",
        selfKey = Flag("IsModifiedClick", "SELFCAST"), autoSelf = okCvar and tostring(selfCast) or "?",
        level = unit and ns.Num(UnitLevel(unit)) or "?", result = "no cast seen",
    }
    -- What's on them and on you now, to tell afterwards where the buff went.
    if not InCombatLockdown() then
        local function Mine(who)
            local thorns, mark = BuffsOn(who)
            return { thorns = thorns and thorns.mine and (thorns.left or 0) or nil, mark = mark and mark.mine and (mark.left or 0) or nil }
        end
        note.before = { them = unit and Mine(unit) or {}, you = Mine("player") }
    end
    clicks[#clicks + 1] = note
    if #clicks > CLICKS_KEPT then
        table.remove(clicks, 1)
    end
end

-- A moment after one of your buffs lands: who has a fresh one from you?
local function NoteLanding(family)
    local note = clicks[#clicks]
    if not note or GetTime() - note.at > 4 or note.result ~= "no cast seen" then
        return
    end
    note.result = "cast went off"
    if family == "gift" or InCombatLockdown() or not note.before then
        return
    end
    C_Timer.After(0.8, function()
        -- Fresh: yours, and newer than what was there at the click.
        local function Fresh(unit, before)
            local thorns, mark = BuffsOn(unit)
            local buff = family == "thorns" and thorns or mark
            if not (buff and buff.mine) then
                return false
            end
            return before[family] == nil or (buff.left or 0) > before[family] + 5
        end
        local onThem = note.unit and Fresh(note.unit, note.before.them)
        local onYou = note.isYou ~= "yes" and Fresh("player", note.before.you)
        note.result = onYou and not onThem and "LANDED ON YOU, not them" or onThem and "landed on them"
            or "cast went off, no fresh buff found on them or you"
        if onYou and not onThem then
            ns.Print(string.format("that buff landed on you, not on %s. /ep status has the details of the click.", note.who))
        end
    end)
end

function ns.RebuffClickLines()
    local lines = {}
    for _, note in ipairs(clicks) do
        lines[#lines + 1] = string.format(
            "%ds ago %s (%s, %s click): button set to %s %s on %s | row unit %s, you %s, exists %s, visible %s, dead %s, "
                .. "can assist %s, online %s, in range %s, level %s | combat %s, self-cast key %s, auto self-cast %s | %s",
            math.floor(GetTime() - note.at), note.who, tostring(note.kind), note.via, tostring(note.setType), tostring(note.setSpell),
            tostring(note.setUnit), tostring(note.unit), note.isYou, note.exists, note.visible, note.dead, note.assist,
            note.connected, note.inRange, tostring(note.level), note.combat, note.selfKey, note.autoSelf, note.result)
    end
    return lines
end

------------------------------------------------------------------------------
-- Where the game hides buffs (a battleground, the whole time)
------------------------------------------------------------------------------
-- There nobody's buffs can be read, and the list had everyone down as
-- missing everything: "36 need it" with the whole raid under another
-- Druid's Gift. So there it goes by what can still be seen:
--   * what someone had when buffs were last readable, until it runs out;
--   * your own casts: Thorns or Mark on who you cast it at, a Gift on
--     everyone alive in the raid (on WoW Forever a Gift lands on them all);
--   * another Druid's Gift of the Wild, by their cast: everyone alive too;
--   * dying takes a player's buffs.
-- Someone nothing is known about is left off the list: saying "40 need it"
-- about a raid another Druid may have just buffed is worse than saying
-- nothing. (/ep status, in Alterac Valley: every player's buffs refused, your
-- own included, and not one of 136 casts by other players readable. So
-- another Druid's Gift can't be seen there at all, and dying puts a player
-- back to "not known", since someone may have buffed them since.)
-- So in a battleground the list is about the buffs you gave: who they're
-- on, and when they run out.
-- A player's name -> { thorns, thornsMine, mark, markMine }: when each runs
-- out; false: known not to have it; nil: not known.
local believed = {}
local LASTS = { thorns = 10 * 60, mark = 30 * 60, gift = 60 * 60 }   -- seconds
local hiddenStatus = { scans = 0, casts = 0, gifts = 0, others = 0, deaths = 0, fromYours = 0,
    castsSeen = 0, castsRead = 0, castsFromID = 0, castsUnread = 0, answers = "none yet" }
local lastGiftTill          -- when the Gift on you runs out, as last seen (to tell a new one)
ns.rebuffHiddenStatus = hiddenStatus

local function AurasHidden()
    local secrets = rawget(_G, "C_Secrets")
    if secrets and secrets.ShouldAurasBeSecret then
        local ok, hidden = pcall(secrets.ShouldAurasBeSecret)
        return ok and ns.Bool(hidden, true) == true
    end
    return false
end

-- Kept while buffs are readable, for when they aren't.
local function Remember(name, thorns, mark)
    local now = GetTime()
    local entry = believed[name] or {}
    entry.thorns = thorns and (now + (thorns.left or LASTS.thorns)) or false
    entry.thornsMine = thorns and thorns.mine or nil
    entry.mark = mark and (now + (mark.left or LASTS.mark)) or false
    entry.markMine = mark and mark.mine or nil
    believed[name] = entry
end

-- A player's Thorns and Mark as believed: with no rank known (so never "a
-- lower rank"), and yours counting down as usual. Then, for each, whether
-- nothing is known about it.
local function BelievedOn(name)
    local entry = believed[name]
    if not entry then
        return nil, nil, true, true
    end
    local now = GetTime()
    local function As(till, mine)
        if till and till > now then
            return { rank = UNRANKED, unranked = true, mine = mine == true, left = till - now, believed = true }
        end
    end
    return As(entry.thorns, entry.thornsMine), As(entry.mark, entry.markMine), entry.thorns == nil, entry.mark == nil
end

-- A buff seen going onto `name` (nil: everyone alive in the group), until
-- `till` (or for as long as it lasts from now).
local function Believe(family, name, mine, till)
    local now = GetTime()
    local function Put(who)
        local entry = believed[who] or {}
        if family == "thorns" then
            entry.thorns, entry.thornsMine = till or (now + LASTS.thorns), mine
        else
            entry.mark, entry.markMine = till or (now + LASTS[family]), mine
        end
        believed[who] = entry
    end
    if name then
        Put(name)
        return
    end
    local raid = IsInRaid and IsInRaid()
    for index = raid and 1 or 0, raid and 40 or 4 do
        local unit = raid and ("raid" .. index) or (index == 0 and "player" or ("party" .. index))
        if UnitExists(unit) and not ns.Bool(UnitIsDeadOrGhost(unit)) then
            local who = ns.Str(UnitName(unit))
            if who then
                Put(who)
            end
        end
    end
end

-- Everyone in the group, with what they're wearing.
local function ReadRoster()
    local roster = {}
    local raid = IsInRaid and IsInRaid()
    local units = {}
    if raid then
        -- You're one of the raid's units (that's where your raid group comes from).
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
        end
    else
        units[1] = "player"
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    local rosterInfo = rawget(_G, "GetRaidRosterInfo")
    local connected = rawget(_G, "UnitIsConnected")
    local seen = {}
    local hidden = AurasHidden()
    local answers = {}
    local inGroup = {}
    listStatus.hidden = hidden
    if hidden then
        hiddenStatus.scans = hiddenStatus.scans + 1
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = ns.Str(UnitName(unit))
            if name then
                inGroup[name] = true
            end
            if name and believed[name] and ns.Bool(UnitIsDeadOrGhost(unit)) then
                -- Dying takes their buffs; and what they get next (from you,
                -- or another Druid) isn't known until it's seen.
                believed[name] = nil
                if hidden then
                    hiddenStatus.deaths = hiddenStatus.deaths + 1
                end
            end
            local online = not connected or ns.Bool(connected(unit), true)
            -- Someone far away (another zone, out of sight range): their
            -- buffs can't be read, nor buffed; left out until they're back.
            local visibleFn = rawget(_G, "UnitIsVisible")
            local visible = not visibleFn or unit == "player" or ns.Bool(visibleFn(unit), true)
            if name and not seen[name] and online and visible and not ns.Bool(UnitIsDeadOrGhost(unit)) then
                seen[name] = true
                local you = unit == "player" or (UnitIsUnit and ns.Bool(UnitIsUnit(unit, "player")))
                local group = 1
                local index = raid and tonumber(unit:match("^raid(%d+)$"))
                if index and rosterInfo then
                    local ok, _, _, subgroup = pcall(rosterInfo, index)
                    group = ok and ns.Num(subgroup) or 1
                end
                local _, class = UnitClass(unit)
                local thorns, mark, state = BuffsOn(unit)
                answers[state] = (answers[state] or 0) + 1
                -- (For /ep status: whether the most health they can have is
                -- readable, which a Gift of the Wild moves.)
                answers.people = (answers.people or 0) + 1
                if not you and ns.Num(UnitHealthMax(unit)) then
                    answers.healthMax = (answers.healthMax or 0) + 1
                end
                roster[#roster + 1] = { unit = you and "player" or unit, name = name, class = ns.Str(class), you = you,
                    tank = IsTank(unit), group = group, thorns = thorns, mark = mark, state = state }
            end
        end
    end
    -- Read where the game lets them be; believed where it doesn't: everywhere
    -- at once (the game says buffs are hidden), for a player it refuses, and
    -- for one with no buff to be seen at all while you wear a Gift of the
    -- Wild (on WoW Forever a Gift lands on everyone: they have it, and the
    -- game isn't showing it).
    local you
    for _, who in ipairs(roster) do
        you = who.you and who or you
    end
    local yourGift = you and not hidden and you.state == "read" and you.mark and you.mark.gift and you.mark or nil
    local someUnread = false
    for _, who in ipairs(roster) do
        who.unread = hidden or who.state == "refused" or who.state == "secret"
            or (who.state == "empty" and yourGift ~= nil and not who.you) or nil
        if who.unread then
            someUnread = someUnread or not who.you
        else
            Remember(who.name, who.thorns, who.mark)
        end
    end
    -- A new Gift on you is on all of them, until yours runs out.
    if yourGift and yourGift.left then
        local till = GetTime() + yourGift.left
        if someUnread and (not lastGiftTill or math.abs(till - lastGiftTill) > 5) then
            hiddenStatus.fromYours = hiddenStatus.fromYours + 1
            Believe("gift", nil, yourGift.mine == true, till)
        end
        lastGiftTill = till
    elseif you and not hidden and you.state == "read" then
        lastGiftTill = nil
    end
    -- (Kept only for who is in the group now: near or far.)
    for name in pairs(believed) do
        if not inGroup[name] then
            believed[name] = nil
        end
    end
    local unknown = 0
    for _, who in ipairs(roster) do
        if who.unread then
            who.thorns, who.mark, who.unknownThorns, who.unknownMark = BelievedOn(who.name)
            if who.unknownMark then
                unknown = unknown + 1
            end
        end
    end
    hiddenStatus.unknown = unknown
    listStatus.unread = someUnread
    hiddenStatus.answers = string.format("read %d, no buffs to see %d, refused %d, secret %d (their most health readable for %d of %d)",
        answers.read or 0, answers.empty or 0, answers.refused or 0, answers.secret or 0, answers.healthMax or 0,
        math.max(0, (answers.people or 0) - 1))
    return roster, raid
end

------------------------------------------------------------------------------
-- Who needs what (from a roster: the real group, or the made-up test one)
------------------------------------------------------------------------------

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("0:%02d", seconds)
end

-- What a row says on its right, kept short (the icons already say which
-- buffs): nothing for a missing buff, "r4" for a lower rank, and the time
-- left for one about to run out. `text` is the long form, for the row's
-- tooltip.
local function ShortText(reason, buff)
    if reason == "rank" then
        return buff.unranked and "r?" or (buff.gift and buff.giftRank and ("Gift r" .. buff.giftRank)) or ("r" .. buff.rank)
    elseif reason == "soon" then
        return Clock(buff.left)
    end
    return nil
end

-- Is theirs a lower rank than you can cast? One with no rank known isn't;
-- a Gift is only against your own Gift (`myGift`: its rank, nil when you
-- have none), where both ranks are known.
local function Lower(buff, myRank, myGift)
    if buff.unranked then
        return false
    end
    if buff.gift then
        return myGift ~= nil and buff.giftRank ~= nil and buff.giftRank < myGift
    end
    return buff.rank < myRank
end

-- What's wrong with a buff: reason and order.
local function Need(buff, myRank, soon, myGift)
    if not buff then
        return "missing", 1
    elseif Lower(buff, myRank, myGift) then
        return "rank", 2
    elseif buff.mine and buff.left and buff.left < soon then
        return "soon", 3
    end
end

local function Rows(roster, raid, test)
    local settings = Settings()
    local soon = settings.soon or 60
    local thornsRank, thornsID = Highest("thorns", THORNS_IDS)
    local markRank, markID = Highest("motw", MARK_IDS)
    local giftRank, giftID = Highest(nil, GIFT_IDS)
    listStatus.mine = string.format("Mark rank %s (%s), Gift rank %s (%s)", tostring(markRank), tostring(markID), tostring(giftRank), tostring(giftID))
    if test then
        thornsRank, thornsID, markRank, markID, giftRank, giftID = 6, 9910, 7, 9885, 2, 21850
    end
    local rows = {}

    -- Thorns.
    if thornsRank then
        local checked = {}
        for _, who in ipairs(roster) do
            local buffed = who.thorns and who.thorns.mine
            if buffed and not test then
                given[who.name] = true
            end
            local includeYou = who.you and settings.includeSelf ~= false
            local watched = buffed or pinned[who.name] or (not test and given[who.name])
            if who.tank or includeYou or (not who.you and watched) then
                checked[#checked + 1] = who
            end
        end
        -- (In a party too, only the tanks and the rest above: until 1.9.0 a
        -- party with no tank marked had everyone checked.)
        listStatus.checked = #checked
        for _, who in ipairs(checked) do
            local reason, order = Need(who.thorns, thornsRank, soon)
            if reason and not who.unknownThorns then
                local text = reason == "missing" and "no Thorns" or reason == "rank" and ("Thorns r" .. who.thorns.rank)
                    or ("Thorns " .. Clock(who.thorns.left))
                rows[#rows + 1] = { kind = "thorns", who = who, reason = reason, order = order, text = text,
                    short = ShortText(reason, who.thorns), spell = thornsID, unit = who.unit, left = who.thorns and who.thorns.left }
            end
        end
    end

    -- Mark of the Wild, and one Gift when enough need it. On WoW Forever a
    -- Gift of the Wild lands on everyone in the raid, not just one group,
    -- so the whole group is counted together and one row covers them all.
    if markRank and settings.markToo ~= false then
        local needing, you = {}, nil
        for _, who in ipairs(roster) do
            if who.you then
                you = who
            end
            local reason, order = Need(who.mark, markRank, soon, giftRank)
            if reason and not who.unknownMark then
                local text = reason == "missing" and "no Mark"
                    or reason == "rank" and (who.mark.gift and ("Gift r" .. tostring(who.mark.giftRank)) or ("Mark r" .. who.mark.rank))
                    or ("Mark " .. Clock(who.mark.left))
                local row = { kind = "mark", who = who, reason = reason, order = order, text = text,
                    short = ShortText(reason, who.mark), spell = markID,
                    unit = who.unit, left = who.mark and who.mark.left }
                needing[#needing + 1] = row
            end
        end
        local roots = test and 12 or ItemCount(THORNROOT)
        if giftRank and roots > 0 and #needing >= GIFT_AT then
            -- Cast on yourself (you're in the raid, and always in range);
            -- failing that, on someone needing it who's in range.
            local target = you
            if not target then
                for _, row in ipairs(needing) do
                    if InRange(row.who.unit, giftID) or test then
                        target = target or row.who
                    end
                end
            end
            target = target or needing[1].who
            -- Why they need it. When every one of them already wears one
            -- and it's only a lower rank than yours (another Druid's Gift,
            -- say), the row says so, in the lower-rank color: "5 need it"
            -- under a Gift cast a moment ago read as the list not seeing it.
            local none, lower, running, lowerWhat, lowerFrom = 0, 0, 0, nil, nil
            for _, row in ipairs(needing) do
                if row.reason == "rank" then
                    lower = lower + 1
                    local buff = row.who.mark
                    lowerWhat = lowerWhat or (buff.gift and buff.giftRank and ("Gift rank " .. buff.giftRank)) or ("Mark rank " .. buff.rank)
                    lowerFrom = lowerFrom or buff.caster
                elseif row.reason == "soon" then
                    running = running + 1
                else
                    none = none + 1
                end
            end
            local parts = {}
            if none > 0 then
                parts[#parts + 1] = string.format("%d without one", none)
            end
            if running > 0 then
                parts[#parts + 1] = string.format("%d with yours running out", running)
            end
            if lower > 0 then
                parts[#parts + 1] = string.format("%d with a lower rank than yours (%s%s)", lower, lowerWhat,
                    lowerFrom and (", from " .. lowerFrom) or "")
            end
            local allLower = lower == #needing
            local short = string.format(allLower and "%d lower rank" or "%d need it", #needing)
            listStatus.gift = string.format("%d need it: %s", #needing, table.concat(parts, ", "))
            rows[#rows + 1] = { kind = "gift", group = 0, reason = "gift", order = 0, spell = giftID,
                unit = target.unit, who = target, count = #needing, roots = roots, lower = lower,
                tint = allLower and "rank" or nil, text = listStatus.gift, short = short }
        else
            for _, row in ipairs(needing) do
                rows[#rows + 1] = row
            end
        end
    end

    -- Skip what just landed (the game shows it on them a moment later).
    local now = GetTime()
    local kept = {}
    for _, need in ipairs(rows) do
        local until_ = pending[PendingKey(need.kind, need)]
        if not (until_ and until_ > now and not test) then
            kept[#kept + 1] = need
        end
    end
    rows = kept

    -- One row per player: what they need, Mark first, then Thorns (a click
    -- casts the first; when it lands, the row moves on to the next).
    local byName, list = {}, {}
    for _, need in ipairs(rows) do
        if need.kind == "gift" then
            list[#list + 1] = need
        else
            local person = byName[need.who.name]
            if not person then
                person = { kind = "player", who = need.who, unit = need.unit, needs = {} }
                byName[need.who.name] = person
                list[#list + 1] = person
            end
            if need.kind == "mark" then
                table.insert(person.needs, 1, need)
            else
                person.needs[#person.needs + 1] = need
            end
        end
    end
    for _, person in ipairs(list) do
        if person.kind == "player" then
            local first = person.needs[1]
            local parts, shorts, worst, left = {}, {}, 9, nil
            for _, need in ipairs(person.needs) do
                parts[#parts + 1] = need.text
                shorts[#shorts + 1] = need.short
                if need.order < worst then
                    worst = need.order
                    person.reason = need.reason
                end
                if need.left and (not left or need.left < left) and need.reason == "soon" then
                    left = need.left
                end
                if need.kind == "thorns" then
                    person.thornsSpell = need.spell
                end
            end
            person.order, person.left = worst, left
            person.spell = first.spell
            person.text = table.concat(parts, " · ")
            person.short = table.concat(shorts, " · ")
            person.tankThorns = person.who.tank and person.thornsSpell ~= nil
        end
    end
    -- Tanks needing Thorns first, then Gift rows, then everyone else: missing,
    -- lower rank, soonest to run out.
    local function Band(row)
        if row.kind == "gift" then
            return 2
        end
        return row.tankThorns and 1 or 3
    end
    table.sort(list, function(a, b)
        local aBand, bBand = Band(a), Band(b)
        if aBand ~= bBand then
            return aBand < bBand
        end
        if a.kind == "gift" then
            return a.group < b.group
        end
        if a.order ~= b.order then
            return a.order < b.order
        end
        if a.order == 3 then
            return (a.left or 0) < (b.left or 0)
        end
        return a.who.name < b.who.name
    end)
    for _, row in ipairs(list) do
        row.inRange = test and row.who.testRange ~= false or (not test and InRange(row.unit, row.spell))
    end
    return list
end

------------------------------------------------------------------------------
-- Thorns warnings in chat
------------------------------------------------------------------------------
-- For the people who've worn your Thorns: a line in chat when it falls off,
-- when another druid's replaces it, and when someone wears a lower rank than
-- you can cast. Once per change. Auras are only readable out of combat, so
-- what happens in a fight is told when it ends. Someone dead, offline or out
-- of the group isn't judged (they're not in the roster) until they're back.

local warnStatus = { told = 0, last = "none yet" }
ns.rebuffWarnStatus = warnStatus
local lastSeen = {}   -- name -> { mine, rank } as last read
local toldRank = {}   -- name -> the lower rank already told about

local function Warn(text)
    warnStatus.told = warnStatus.told + 1
    warnStatus.last = text
    ns.Print(text)
end

local function CheckWarnings(roster)
    if AurasHidden() then
        -- Nothing is read here to tell of. (And no "fell off" for everyone
        -- once buffs can be read again.)
        lastSeen, toldRank = {}, {}
        return
    end
    local settings = Settings()
    local myRank = Highest("thorns", THORNS_IDS)
    if not myRank then
        return
    end
    local thornsName = SpellName(9910)
    for _, who in ipairs(roster) do
        if not who.you then
            local name, now, before = who.name, who.thorns, lastSeen[who.name]
            local tell = settings.alerts ~= false and (given[name] or (before and before.mine))
            if tell and before and before.mine then
                if not now then
                    Warn(string.format("Your %s fell off %s.", thornsName, name))
                elseif not now.mine then
                    Warn(string.format("%s overwrote your %s on %s.", now.caster or "Someone", thornsName, name))
                end
            end
            if now and now.rank < myRank then
                if tell and toldRank[name] ~= now.rank then
                    Warn(string.format("%s has %s rank %d. You can cast rank %d.", name, thornsName, now.rank, myRank))
                end
                toldRank[name] = now.rank
            else
                toldRank[name] = nil
            end
            lastSeen[name] = now and { mine = now.mine, rank = now.rank } or false
        end
    end
end

local function WhoNeedsIt()
    if not Highest("thorns", THORNS_IDS) and not Highest("motw", MARK_IDS) then
        return {}, "you don't know Thorns or Mark"
    end
    if not (IsInGroup and IsInGroup()) then
        return {}, "not in a group"
    end
    local roster, raid = ReadRoster()
    CheckWarnings(roster)
    return Rows(roster, raid)
end

------------------------------------------------------------------------------
-- A made-up group, for /ep rebuff test (and test raid)
------------------------------------------------------------------------------

local TEST_NAMES = { "Morvessa", "Vex", "Korrak", "Lia", "Tamsin", "Brom", "Iska", "Dreth", "Ophe", "Galen",
    "Rusk", "Nimra", "Pell", "Quarn", "Sabe", "Toll", "Ulma", "Varn", "Wex", "Yorra", "Zed", "Ama", "Bix", "Cael",
    "Dova", "Eld", "Fen", "Gorm", "Hale", "Ivo", "Jask", "Kell", "Lorn", "Mab", "Nox", "Orrin", "Pim", "Quill", "Ros" }
local TEST_CLASSES = { "WARRIOR", "ROGUE", "SHAMAN", "PRIEST", "MAGE", "WARLOCK", "HUNTER", "PALADIN", "DRUID" }

local function TestRoster(raid)
    local now = 0
    local roster = { { unit = "player", name = ns.Str(UnitName("player")) or "You", class = "DRUID", you = true, group = 1,
        thorns = { rank = 6, mine = true, left = 500 }, mark = { rank = 7, mine = true, left = 1700 } } }
    local size = raid and 40 or 5
    for i = 2, size do
        local name = TEST_NAMES[i - 1]
        local who = { unit = "test" .. i, name = name, class = TEST_CLASSES[(i - 2) % #TEST_CLASSES + 1], group = math.ceil(i / 5) }
        who.tank = (i == 2) or (raid and i == 7)
        if i == 2 then
            who.thorns, who.mark = nil, { rank = 7, mine = true, left = 900 }
        elseif i == 3 then
            who.thorns, who.mark = { rank = 4, mine = false, left = 400 }, nil
            pinned[name] = pinned[name] or "test"
        elseif i == 4 then
            who.thorns, who.mark = { rank = 6, mine = true, left = 42 }, { rank = 5, mine = false, left = 800 }
        elseif i == 7 then
            who.thorns, who.mark = { rank = 6, mine = true, left = 20 }, { rank = 7, mine = true, left = 1200 }
        else
            -- In the raid: groups 3, 5 and 6 mostly unmarked, a few loose ones.
            local group = who.group
            local unmarked = (group == 3 or group == 5 or group == 6) and (i % 5 ~= 0) or (i == 12 or i == 29)
            who.mark = (not unmarked) and { rank = 7, mine = true, left = 1500 + now } or nil
            who.testRange = (i ~= 29)
        end
        roster[#roster + 1] = who
    end
    return roster
end

------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------

local holder, panel, keyButton
local DEFAULT_SPOT = { "TOPLEFT", "LEFT", 40, -60 }
local rowButtons = {}
local keyStatus = { presses = 0, target = "none", landed = 0 }
ns.buffKeyStatus = keyStatus
local KEY_BINDING = "CLICK ElipsPanelsBuffKey:LeftButton"
_G["BINDING_NAME_" .. KEY_BINDING] = "Rebuff List: cast the next buff"

local function BoundKey()
    local get = rawget(_G, "GetBindingKey")
    local key = get and get(KEY_BINDING)
    if not key then
        return nil
    end
    local text = rawget(_G, "GetBindingText")
    return (text and text(key, true)) or key
end
ns.BuffKeyText = BoundKey
local testUntil, testRaid

local function SavePosition()
    local x, top = panel:GetLeft(), panel:GetTop()
    if x and top then
        Settings().pos = { math.floor(x + 0.5), math.floor(top + 0.5) }
    end
end

local function CreateRow(index)
    local button = CreateFrame("Button", "ElipsPanelsRebuffRow" .. index, panel, "SecureActionButtonTemplate")
    button:SetHeight(ROW_HEIGHT)
    button:SetPoint("TOPLEFT", 6, -HEADER - (index - 1) * ROW_HEIGHT)
    button:SetPoint("TOPRIGHT", -6, -HEADER - (index - 1) * ROW_HEIGHT)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("type2", "spell")
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    -- An icon for each buff they need: the one a click casts first, then
    -- the next, a little dimmer.
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("LEFT", 2, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon2 = button:CreateTexture(nil, "ARTWORK")
    button.icon2:SetSize(16, 16)
    button.icon2:SetPoint("LEFT", button.icon, "RIGHT", 2, 0)
    button.icon2:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.nameText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.nameText:SetPoint("LEFT", button.icon2, "RIGHT", 5, 0)
    button.nameText:SetJustifyH("LEFT")
    button.nameText:SetWordWrap(false)
    button.reasonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.reasonText:SetPoint("RIGHT", -4, 0)
    button.reasonText:SetJustifyH("RIGHT")
    button.nameText:SetPoint("RIGHT", button.reasonText, "LEFT", -6, 0)
    -- What the row is short for, on hover.
    button:HookScript("OnEnter", function(self)
        local tip, row = rawget(_G, "GameTooltip"), self.row
        if not (tip and row) then
            return
        end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(row.kind == "gift" and "Gift of the Wild" or (row.who.you and "You" or row.who.name), 1, 1, 1)
        tip:AddLine(row.text, 0.8, 0.8, 0.8)
        tip:Show()
    end)
    button:HookScript("OnLeave", function()
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:Hide()
        end
    end)
    -- The row the buff key casts next: a soft wash in the theme color, with
    -- an edge on the left.
    button.keyWash = button:CreateTexture(nil, "BACKGROUND")
    button.keyWash:SetAllPoints()
    button.keyEdge = button:CreateTexture(nil, "ARTWORK")
    -- On the row's own left edge, clear of the panel's border (which it
    -- used to sit on).
    button.keyEdge:SetPoint("TOPLEFT", -1, 0)
    button.keyEdge:SetPoint("BOTTOMLEFT", -1, 0)
    button.keyEdge:SetWidth(2)
    local function PaintKey()
        local nature = ns.W.NATURE
        button.keyWash:SetColorTexture(1, 1, 1, 1)
        if not ns.W.Gradient(button.keyWash, "HORIZONTAL", { nature[1], nature[2], nature[3], 0.25 },
            { nature[1], nature[2], nature[3], 0.03 }) then
            button.keyWash:SetColorTexture(nature[1], nature[2], nature[3], 0.12)
        end
        button.keyEdge:SetColorTexture(nature[1], nature[2], nature[3], 1)
    end
    PaintKey()
    ns.W.OnRetheme(button, PaintKey)
    button.keyWash:Hide()
    button.keyEdge:Hide()
    button:SetScript("PreClick", function(self, mouseButton)
        local row = self.row
        NoteClick(self, mouseButton)
        if row then
            local kind = row.kind == "gift" and "gift" or ((mouseButton == "RightButton" and row.thornsSpell) and "thorns"
                or row.needs[1].kind)
            ns.RebuffAttempt(kind, row)
        end
    end)
    button:SetScript("PostClick", function()
        listStatus.casts = listStatus.casts + 1
    end)
    button:Hide()
    rowButtons[index] = button
    return button
end

local function Build()
    if holder then
        return true
    end
    if InCombatLockdown() then
        return false
    end
    -- The holder hides in combat by itself (the game's own rule for secure
    -- frames); the panel inside is shown and hidden by the list, only out
    -- of combat.
    holder = CreateFrame("Frame", "ElipsPanelsRebuffHolder", UIParent)
    holder:SetAllPoints(UIParent)
    holder:SetFrameStrata("MEDIUM")
    local driver = rawget(_G, "RegisterStateDriver")
    if driver then
        pcall(driver, holder, "visibility", "[combat] hide; show")
    end

    local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsRebuff", holder, "BackdropTemplate")
    panel = (ok and made) or CreateFrame("Frame", "ElipsPanelsRebuff", holder)
    panel:SetWidth(WIDTH)
    panel:SetClampedToScreen(true)
    ns.W.PanelBackdrop(panel, 0.88)
    local crest = panel:CreateTexture(nil, "ARTWORK")
    crest:SetTexture("Interface\\AddOns\\ElipsPanels\\Media\\ElipsPanels")
    crest:SetSize(18, 18)
    crest:SetPoint("TOPLEFT", 7, -5)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("LEFT", crest, "RIGHT", 5, 0)
    panel.title:SetText("Rebuff List")
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.count:SetPoint("RIGHT", panel, "TOPRIGHT", -10, -14)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -HEADER + 2)
    line:SetPoint("TOPRIGHT", -8, -HEADER + 2)
    ns.W.ThemePanel(panel, nil, ns.W.NATURE)
    ns.W.AccentLine(line, ns.W.NATURE)

    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not Settings().locked and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    ns.W.PlacePanel(panel, Settings().pos, DEFAULT_SPOT)
    for index = 1, MAX_ROWS do
        CreateRow(index)
    end
    -- The buff key: a hidden button that casts whatever the list's marked
    -- row needs first (bound under Key Bindings > ElipsPanels, or /ep rebuff bind).
    keyButton = CreateFrame("Button", "ElipsPanelsBuffKey", UIParent, "SecureActionButtonTemplate")
    keyButton:SetSize(1, 1)
    keyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    keyButton:SetAlpha(0)
    keyButton:EnableMouse(false)
    keyButton:RegisterForClicks("AnyUp", "AnyDown")
    keyButton:SetAttribute("type", "spell")
    -- And in case a fight starts before it's cleared: the game itself turns
    -- it into a button that does nothing while you're in combat.
    local attributeDriver = rawget(_G, "RegisterAttributeDriver")
    if attributeDriver then
        pcall(attributeDriver, keyButton, "type", "[combat] none; spell")
    end
    keyButton:SetScript("PreClick", function(self)
        local row = self.row
        NoteClick(self, nil, true)
        if row then
            ns.RebuffAttempt(row.kind == "gift" and "gift" or row.needs[1].kind, row)
        elseif not InCombatLockdown() and (not self.saidAt or GetTime() - self.saidAt > 2) then
            self.saidAt = GetTime()
            ns.Print(IsInGroup and IsInGroup() and "nothing to buff right now." or "the buff key works in a group.")
        end
    end)
    keyButton:SetScript("PostClick", function()
        keyStatus.presses = keyStatus.presses + 1
    end)
    panel:Hide()
    listStatus.why = "built"
    return true
end

local function ClassColored(name, class)
    local colors = rawget(_G, "RAID_CLASS_COLORS")
    local color = class and colors and colors[class]
    if not color then
        return name
    end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255), math.floor(color.g * 255),
        math.floor(color.b * 255), name)
end

local ICONS = { thorns = 9910, mark = 9885, gift = 21850 }
local function IconOf(kind)
    local id = ICONS[kind]
    local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return texture or "Interface\\Icons\\Spell_Nature_Regeneration"
end

local function Show(rows, test, raid, hidePanel)
    -- The buff key's row: the first one in range (the first one, if none are).
    local keyIndex
    for index, row in ipairs(rows) do
        if index <= MAX_ROWS and row.inRange ~= false then
            keyIndex = index
            break
        end
    end
    keyIndex = keyIndex or (rows[1] and 1)
    local keyRow = keyIndex and rows[keyIndex]
    if keyButton then
        keyButton.row = (not test) and keyRow or nil
        keyButton:SetAttribute("unit", (not test and keyRow) and keyRow.unit or nil)
        keyButton:SetAttribute("spell", (not test and keyRow) and SpellName(keyRow.spell) or nil)
        keyStatus.target = (keyRow and not test) and string.format("%s on %s", SpellName(keyRow.spell),
            keyRow.kind == "gift" and "everyone" or keyRow.who.name) or "none"
    end
    for index, button in ipairs(rowButtons) do
        button.keyWash:SetShown(index == keyIndex)
        button.keyEdge:SetShown(index == keyIndex)
        local row = rows[index]
        if row then
            -- What a click casts (your highest rank, on them; nothing in the
            -- test): left, the first buff they need; right, Thorns when they
            -- need it.
            button:SetAttribute("unit", (not test) and row.unit or nil)
            button:SetAttribute("spell", (not test) and row.spell and SpellName(row.spell) or nil)
            local second = row.thornsSpell or row.spell
            button:SetAttribute("spell2", (not test) and second and SpellName(second) or nil)
            if row.kind == "gift" then
                button.icon:SetTexture(IconOf("gift"))
                button.icon2:Hide()
                button.icon2:SetWidth(1)
            else
                button.icon:SetTexture(IconOf(row.needs[1].kind))
                local next = row.needs[2]
                button.icon2:SetShown(next ~= nil)
                button.icon2:SetWidth(next and 16 or 1)
                if next then
                    button.icon2:SetTexture(IconOf(next.kind))
                    button.icon2:SetAlpha(0.6)
                end
            end
            local label
            if row.kind == "gift" then
                label = "Gift of the Wild"
            else
                label = (row.who.tank and (TANK_ICON .. " ") or "")
                    .. ClassColored(row.who.you and "You" or row.who.name, row.who.class)
            end
            button.nameText:SetText(label)
            local color = REASON_COLORS[row.tint or row.reason] or REASON_COLORS.missing
            button.reasonText:SetText(row.short or "")
            button.reasonText:SetTextColor(color[1], color[2], color[3])
            button:SetAlpha(row.inRange == false and 0.45 or 1)
            button.row = row
            button:Show()
        else
            button:SetAttribute("unit", nil)
            button.row = nil
            button:Hide()
        end
    end
    local shown = math.min(#rows, MAX_ROWS)
    local more = #rows - shown
    local key = BoundKey()
    panel.count:SetText((test and "test  " or "") .. (more > 0 and string.format("+%d more", more)
        or string.format("%d to cast", #rows)) .. (key and ("  |cffffd100" .. key .. "|r") or ""))
    panel:SetHeight(HEADER + shown * ROW_HEIGHT + 8)
    if panel:IsShown() and shown == 0 then
        listStatus.lastHide = "nothing left to cast, %d sec ago"
        listStatus.hiddenAt = GetTime()
    end
    panel:SetShown(shown > 0 and not hidePanel)
    listStatus.rows = shown
end

local OnUpdate   -- below

local function Update()
    if InCombatLockdown() or not Build() then
        return
    end
    if not holder.ticking then
        holder.ticking = true
        holder:SetScript("OnUpdate", OnUpdate)
    end
    if testUntil then
        if GetTime() < testUntil then
            Show(Rows(TestRoster(testRaid), testRaid, true), true, testRaid)
            return
        end
        testUntil = nil
        for name, value in pairs(pinned) do
            if value == "test" then
                pinned[name] = nil
            end
        end
    end
    -- The list works out who needs what even when it's turned off: the buff
    -- key goes by it.
    local away = ns.PanelsHidden()
    local off = Settings().show == false or away
    local rows, why = WhoNeedsIt()
    listStatus.why = (away and "hidden in a battleground (the buff key still works); " or off and "turned off (the buff key still works); " or "")
        .. (why or string.format("%d checked for Thorns, %d rows", listStatus.checked, #rows))
    Show(rows, false, IsInRaid and IsInRaid(), off)
    if #rows > 0 then
        listStatus.shown = listStatus.shown + 1
    end
end
ns.UpdateRebuffList = Update

-- Looked at again soon after a change; while up, every second in a party
-- and every 3 seconds in a raid (countdowns, range).
local updateSoon = false
local function UpdateSoon()
    if updateSoon then
        return
    end
    updateSoon = true
    C_Timer.After(0.3, function()
        updateSoon = false
        Update()
    end)
end

local elapsed = 0
OnUpdate = function(_, dt)
    elapsed = elapsed + dt
    local every = (IsInRaid and IsInRaid() and not testUntil) and 3 or 1
    if elapsed >= every then
        elapsed = 0
        Update()
    end
end

function ns.RebuffTest(raid)
    testUntil = GetTime() + 30
    testRaid = raid and true or false
    Update()
    ns.Print(raid and "A made-up 40-player raid for 30 seconds (clicks don't cast)."
        or "A made-up party for 30 seconds (clicks don't cast). /ep rebuff test raid for a raid.")
end

-- What a click or the key just tried to cast, so the cast landing can be
-- matched to it (the game says a spell landed, not on whom).
local attempt
function ns.RebuffAttempt(kind, row)
    attempt = { kind = kind, key = PendingKey(kind, row), at = GetTime() }
end

local FAMILY = {}
for id in pairs(THORNS_RANK) do
    FAMILY[id] = "thorns"
end
for id in pairs(MARK_RANK) do
    FAMILY[id] = "mark"
end
for _, id in ipairs(GIFT_IDS) do
    FAMILY[id] = "gift"
end

-- Who your last buff was sent at: a first name (Forever's casts name their
-- target by both names, units go by the first), nil when the game doesn't say.
local sentAt

local function CastLanded(spellID)
    spellID = ns.Num(spellID)
    local family = spellID and FAMILY[spellID]
    if family then
        NoteLanding(family)
        -- For where buffs can't be read: it went on them (a Gift, on everyone).
        hiddenStatus.casts = hiddenStatus.casts + 1
        if family == "gift" then
            Believe("gift", nil, true)
        else
            -- On who the cast named; failing that, the row that was clicked
            -- or keyed; failing that, you.
            local who = sentAt
            if not who and attempt and attempt.kind == family and GetTime() - attempt.at <= 4 then
                who = attempt.key:match(":(.+)$")
            end
            Believe(family, who or ns.Str(UnitName("player")), true)
        end
        sentAt = nil
    end
    if not (family and attempt) or attempt.kind ~= family or GetTime() - attempt.at > 4 then
        return
    end
    pending[attempt.key] = GetTime() + PENDING_SECONDS
    attempt = nil
    keyStatus.landed = keyStatus.landed + 1
    if not InCombatLockdown() then
        Update()   -- the key moves on to the next one right away
    end
end

-- /ep rebuff bind KEY, and the settings' key button.
function ns.BindBuffKey(key)
    if InCombatLockdown() then
        ns.Print("keys can't be changed in combat.")
        return false
    end
    local setClick, setBinding = rawget(_G, "SetBindingClick"), rawget(_G, "SetBinding")
    local save, set = rawget(_G, "SaveBindings"), rawget(_G, "GetCurrentBindingSet")
    if not (setClick and setBinding) then
        return false
    end
    local get = rawget(_G, "GetBindingKey")
    local old = get and get(KEY_BINDING)
    if old then
        setBinding(old)
    end
    if key and key ~= "" then
        setClick(key:upper(), "ElipsPanelsBuffKey", "LeftButton")
    end
    if save then
        pcall(save, set and set() or 1)
    end
    Update()
    local now = BoundKey()
    ns.Print(now and ("buff key: " .. now .. ". Press it out of combat to cast the next buff on the Rebuff List.")
        or "buff key cleared.")
    return true
end

-- /ep rebuff: on or off.
function ns.ToggleRebuffList(on)
    local settings = Settings()
    if on == nil then
        on = settings.show == false
    end
    settings.show = on
    Update()
    ns.Print(on and "rebuff list on (it shows when someone needs a buff, out of combat, in a group)." or "rebuff list off.")
end

function ns.RebuffWatch(name)
    if not name or name == "" then
        name = UnitExists("target") and ns.Str(UnitName("target")) or nil
    end
    if not name then
        ns.Print("Target someone in your group (or /ep rebuff watch Name).")
        return
    end
    if pinned[name] then
        pinned[name] = nil
        ns.Print(name .. " is off the rebuff list for Thorns (unless they need it as a tank).")
    else
        pinned[name] = true
        ns.Print(name .. " is on the rebuff list for Thorns this session.")
    end
    Update()
end

ns.Hook("COMBAT", function(inCombat)
    if inCombat then
        testUntil = nil
        -- The key never casts mid-fight: cleared as the fight starts.
        if keyButton and not InCombatLockdown() then
            keyButton.row = nil
            keyButton:SetAttribute("spell", nil)
            keyButton:SetAttribute("unit", nil)
        end
        if panel and panel:IsShown() then
            listStatus.lastHide = "combat started (it comes back after), %d sec ago"
            listStatus.hiddenAt = GetTime()
        end
        -- In case the game has no state driver: hidden as the fight starts.
        if holder and not InCombatLockdown() and not rawget(_G, "RegisterStateDriver") then
            panel:Hide()
        end
    else
        C_Timer.After(0.5, Update)
    end
end)

ns.Hook("INIT", function()
    ns.RegisterMover({
        key = "rebuff", label = "Rebuff List", width = WIDTH, height = HEADER + 4 * ROW_HEIGHT, default = DEFAULT_SPOT,
        get = function() return Settings().pos end,
        set = function(pos)
            Settings().pos = pos
            -- (Its rows cast spells, so the game only lets it move out of combat.)
            if panel and not InCombatLockdown() then
                ns.W.PlacePanel(panel, pos, DEFAULT_SPOT)
            end
        end,
    })
    ns.On("UNIT_AURA", function(unit)
        if ns.inCombat then
            return   -- the list is hidden in combat (and a raid's auras change many times a second)
        end
        if unit and not ns.IsSecret(unit) and (unit == "player" or unit:find("^party") or unit:find("^raid")) then
            UpdateSoon()
        end
    end)
    ns.On("GROUP_ROSTER_UPDATE", function()
        if not (IsInGroup and IsInGroup()) then
            for name in pairs(given) do
                given[name] = nil
            end
            lastSeen, toldRank = {}, {}
        end
        UpdateSoon()
    end)
    ns.On("PLAYER_ROLES_ASSIGNED", UpdateSoon)
    ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
        if not ns.IsSecret(unit) and unit == "player" then
            CastLanded(spellID)
        end
    end)
    ns.On("UNIT_SPELLCAST_SENT", function(unit, target, _, spellID)
        if ns.IsSecret(unit) or unit ~= "player" then
            return
        end
        local id = ns.Num(spellID)
        if id and FAMILY[id] then
            local name = ns.Str(target)
            sentAt = name and name:match("^([^%s%-]+)") or nil
        end
    end)
    -- Another Druid's Gift of the Wild, by their cast: for where buffs can't
    -- be read. (The spell's ID from the event, or from the cast's own ID.)
    ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
        if ns.IsSecret(unit) or type(unit) ~= "string" or not (unit:find("^raid%d") or unit:find("^party%d")) then
            return
        end
        if UnitIsUnit and ns.Bool(UnitIsUnit(unit, "player")) then
            return      -- yours: above
        end
        hiddenStatus.castsSeen = hiddenStatus.castsSeen + 1
        local id = ns.Num(spellID)
        if id then
            hiddenStatus.castsRead = hiddenStatus.castsRead + 1
        elseif not ns.IsSecret(castGUID) and type(castGUID) == "string" then
            id = tonumber(castGUID:match("^Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
            if id then
                hiddenStatus.castsFromID = hiddenStatus.castsFromID + 1
            end
        end
        if not id then
            hiddenStatus.castsUnread = hiddenStatus.castsUnread + 1
        end
        if id and (FAMILY[id] == "gift" or SpellName(id) == SpellName(21850) or SpellName(id) == "Gift of the Wild") then
            hiddenStatus.others = hiddenStatus.others + 1
            Believe("gift", nil, false)
            if not ns.inCombat then
                UpdateSoon()
            end
        end
    end)
    ns.On("UPDATE_BINDINGS", UpdateSoon)
    ns.Hook("BATTLEGROUND", function()
        UpdateSoon()
    end)
    ns.On("BAG_UPDATE_DELAYED", UpdateSoon)
    ns.On("SPELLS_CHANGED", function()
        names = {}
        UpdateSoon()
    end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        -- A new zone: start watching afresh (no "fell off" for buffs that
        -- ran out while loading).
        lastSeen, toldRank = {}, {}
        C_Timer.After(2, function()
            Update()
            -- The key bound when the list was ArchDruid's comes along (once
            -- the button it's for is there).
            if keyButton and ns.CarryBuffKey then
                local key = ns.CarryBuffKey(KEY_BINDING, "ElipsPanelsBuffKey")
                if key then
                    ns.Print("your buff key (" .. key .. ") came over from ArchDruid.")
                    Update()
                end
            end
        end)
    end)
end)

ns.RebuffInternals = { WhoNeedsIt = WhoNeedsIt, CheckWarnings = CheckWarnings, Rows = Rows, TestRoster = TestRoster, Update = Update,
    Key = function() return keyButton end, CastLanded = CastLanded, Pending = pending,
    Buttons = rowButtons, Panel = function() return panel end, Given = given, Believed = believed }

------------------------------------------------------------------------------
-- /ep rebuff, /ep status
------------------------------------------------------------------------------

-- /ep rebuff (show or hide), on, off, test, test raid, watch [Name],
-- bind KEY, unbind. A name keeps its capitals.
ns.commands.rebuff = function(rest)
    local sub, more = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    if sub == "" or sub == "show" or sub == "hide" or sub == "on" or sub == "off" then
        local want = nil
        if sub == "show" or sub == "on" then
            want = true
        elseif sub == "hide" or sub == "off" then
            want = false
        end
        ns.ToggleRebuffList(want)
    elseif sub == "bind" then
        if more == "" then
            local key = BoundKey()
            ns.Print(key and ("buff key: " .. key .. ".") or "no buff key yet: /ep rebuff bind F (any key, e.g. SHIFT-B).")
        else
            ns.BindBuffKey(more)
        end
    elseif sub == "unbind" then
        ns.BindBuffKey(nil)
    elseif sub == "test" then
        ns.RebuffTest((more or ""):lower() == "raid")
    elseif sub == "watch" then
        ns.RebuffWatch(more)
    else
        ns.Print("/ep rebuff: show or hide the Rebuff List. /ep rebuff test (or test raid): a made-up group. /ep rebuff watch: pin your target for Thorns. /ep rebuff bind KEY, /ep rebuff unbind: the buff key.")
    end
end

ns.statusParts[#ns.statusParts + 1] = function()
    local list, hidden, warn, key = listStatus, hiddenStatus, warnStatus, keyStatus
    local lines = {}
    local function Add(text, ...)
        lines[#lines + 1] = string.format(text, ...)
    end
    Add("Rebuff List: %s | rows now %s, shown %s times, clicks %s | last hid: %s",
        tostring(list.why or "not loaded"), tostring(list.rows or 0), tostring(list.shown or 0), tostring(list.casts or 0),
        list.lastHide and list.lastHide:format(math.floor(GetTime() - (list.hiddenAt or GetTime()))) or "not yet")
    Add("    Buffs hidden here: the game says %s; last look at people's buffs: %s; some unread %s | while hidden: %d looks, your buff casts %d, other Druids' Gifts seen %d, taken from the Gift on you %d, deaths noticed %d",
        tostring(list.hidden), tostring(hidden.answers), tostring(list.unread), hidden.scans or 0, hidden.casts or 0,
        hidden.others or 0, hidden.fromYours or 0, hidden.deaths or 0)
    Add("    Other players' casts: %d seen | spell given %d, read from the cast's ID %d, not readable %d | players nothing is known about (left off the list): %s",
        hidden.castsSeen or 0, hidden.castsRead or 0, hidden.castsFromID or 0, hidden.castsUnread or 0, tostring(hidden.unknown or 0))
    if list.mine or list.marksSeen then
        local seen = {}
        for id, what in pairs(list.marksSeen or {}) do
            seen[#seen + 1] = string.format("%d (%s)", id, what)
        end
        table.sort(seen)
        Add("    Yours: %s | Mark and Gift buffs seen on people: %s", tostring(list.mine or "?"), #seen > 0 and table.concat(seen, ", ") or "none yet")
        Add("    Last Gift row: %s", tostring(list.gift or "none yet"))
    end
    if list.unranked then
        local seen = {}
        for id, name in pairs(list.unranked) do
            seen[#seen + 1] = string.format("%s (%d)", name, id)
        end
        table.sort(seen)
        Add("    Buffs seen with a spell ID the list has no rank for (counted as full): %s", table.concat(seen, ", "))
    end
    for _, line in ipairs(ns.RebuffClickLines()) do
        Add("    Click: %s", line)
    end
    Add("    Thorns warnings: %s | told %s, last: %s", Settings().alerts == false and "off" or "on",
        tostring(warn.told or 0), tostring(warn.last or "none yet"))
    Add("    Buff key: %s | next: %s | presses %s, casts landed %s", tostring(BoundKey() or "not bound"),
        tostring(key.target or "none"), tostring(key.presses or 0), tostring(key.landed or 0))
    return lines
end

