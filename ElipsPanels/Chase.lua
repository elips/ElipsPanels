local _, ns = ...
local W = ns.W

------------------------------------------------------------------------------
-- The chase list: things to go after
------------------------------------------------------------------------------
-- A list of what you're chasing, each with a short note on how to get it:
--   an item        by link (shift-click it into the box) or by its ID; done
--                  when you own it (bags, bank or worn), or that many of it
--   a reputation   by its name (it has to be in your reputation list); done
--                  at Exalted
--   a quest        "quest 1234"; done when the game has it flagged complete
--   a goal         anything else ("Winterspring frostsaber", "Rank 10"):
--                  ticked off by hand
-- The note: the game doesn't tell addons where an item comes from, so it's
-- yours to write (after " - " when adding: "12345 - Drakkisath, UBRS"; or
-- typed in the list window). Left empty, ElipsPanels fills it in where it
-- can: the dungeon journal addons (OneForAll, FojjiCore's Dungeon Journal,
-- DungeonJournal) carry loot tables, and if one is installed the boss,
-- dungeon and drop chance are read from it ("General Drakkisath, Upper
-- Blackrock Spire (13%)"). Their data is only read, never copied; with
-- none of them installed, nothing is filled in.
--
-- On screen, a small panel lists the first few still to get, with how far
-- along each is; hovering a row shows the note. `/ep chase` opens the list
-- window: add, write notes, move up and down, tick off, remove. The list is
-- kept per character.
--
-- It also speaks up:
--   - an item on the list comes up for a roll or lies in a loot window:
--     a line in chat, a notice on screen and a sound
--   - an item's tooltip says it's on your list, with the note
--   - something is done (you got the item, hit the standing, finished the
--     quest): "Chase complete"
--
-- /ep status lists what this client reports for the things not tracked yet
-- (mounts, transmog, PvP rank, a dungeon journal), to see what can be.

local PANEL_WIDTH, ROW_HEIGHT, HEADER = 240, 18, 30
local DEFAULT_SPOT = { "TOPRIGHT", "RIGHT", -40, 140 }
local EXALTED = 8
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local KIND_ICON = { rep = "Interface\\Icons\\Achievement_Reputation_01", quest = "Interface\\Icons\\INV_Misc_Book_08",
    goal = "Interface\\Icons\\INV_Misc_Map_01" }
local GREY, GREEN, GOLD = { 0.62, 0.62, 0.62 }, { 0.40, 0.90, 0.40 }, { 1.00, 0.82, 0.00 }

local status = { added = 0, completed = 0, spotted = 0, tips = 0, last = "nothing yet", hooks = "" }
ns.chaseStatus = status

local panel, window
local fighting = false   -- from the fight's start (the game's own "in combat" comes a moment later)
local Refresh   -- (defined below)

local function Settings()
    ns.db.chase = ns.db.chase or {}
    local settings = ns.db.chase
    settings.lists = settings.lists or {}
    return settings
end
ns.ChaseSettings = Settings

-- One list for each character.
local function List()
    local settings = Settings()
    local realm = rawget(_G, "GetRealmName")
    local key = tostring(UnitName("player") or "?") .. "-" .. tostring(realm and realm() or "")
    settings.lists[key] = settings.lists[key] or {}
    return settings.lists[key]
end
ns.ChaseList = List

local function Plain(value)
    return value ~= nil and not ns.IsSecret(value)
end

-- A game function called safely: nil if it isn't there or errors.
local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c, d, e, f
end

-- The date and time, as a number (for "added" and "got").
local function Now()
    local clock = rawget(_G, "time")
    return clock and clock() or math.floor(GetTime())
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------------------------
-- Where an item comes from, read from a dungeon journal addon
------------------------------------------------------------------------------
-- Three addons keep loot tables in tables ElipsPanels can reach:
--   OneForAll                  OneForAll.DUNGEONS[n] = { name, bosses = { { name,
--                              loot = { { id = itemID } } } }, trashLoot = { { id } },
--                              quests = { { name, rewards = { { id } } } } },
--                              and OneForAll.DUNGEON_DROP_CHANCE[dungeon][boss][itemID]
--   DungeonJournal             ForeverDungeonJournal_NS.DB[dungeon] = { bosses = { { name,
--                              loot = { { itemID, ... } } } }, quests = { { name,
--                              rewardItems = { { itemID } } } } }
--   FojjiCore: Dungeon Journal FojjiCoreNS.DJ.Dungeons[n] = { name, bosses =
--                              { { n = boss, loot = { itemIDs }, odds = { percents } } } }
-- Read once, when first asked (and again after another addon loads).

-- (`items` and `byName`: the names those tables give their items, for
-- finding an item by typing its name.)
local sources = { built = false, byItem = {}, seen = {}, from = {}, items = {}, byName = {} }
ns.chaseSources = sources

local function PutSource(id, what, where, chance, from, name, quality)
    if type(id) ~= "number" or type(what) ~= "string" or type(where) ~= "string" then
        return
    end
    if type(name) == "string" and name ~= "" and not sources.items[id] then
        local lower = name:lower()
        sources.items[id] = { id = id, name = name, lower = lower, quality = type(quality) == "number" and quality or nil }
        sources.byName[lower] = sources.byName[lower] or id
    end
    local key = id .. "\0" .. what:lower() .. "\0" .. where:lower()
    if sources.seen[key] then
        return   -- the same drop, from a second addon
    end
    sources.seen[key] = true
    local text = what .. ", " .. where
    if type(chance) == "number" and chance > 0 then
        text = text .. " (" .. tostring(chance) .. "%)"
    end
    sources.byItem[id] = sources.byItem[id] or {}
    table.insert(sources.byItem[id], text)
    sources.from[from] = (sources.from[from] or 0) + 1
end

-- OneForAll's and DungeonJournal's shapes: a table of dungeons, keyed by
-- name or a list of them with .name; a loot row is { itemID, ... },
-- { id = itemID, ... } or the ID itself.
local function RowID(row)
    if type(row) == "table" then
        return row.id or row[1]
    end
    return row
end

-- A row's item name and quality (`qualityAt`: where a list-shaped row keeps it).
local function RowName(row, qualityAt)
    if type(row) ~= "table" then
        return nil
    end
    return row.name or row[2], row.quality or row[qualityAt]
end

local function ReadRegistry(registry, chances, from)
    if type(registry) ~= "table" then
        return
    end
    for key, data in pairs(registry) do
        local dungeon = type(data) == "table" and (type(key) == "string" and key or data.name) or nil
        if type(dungeon) == "string" then
            local dungeonOdds = type(chances) == "table" and chances[dungeon] or nil
            for _, boss in ipairs(type(data.bosses) == "table" and data.bosses or {}) do
                if type(boss) == "table" and type(boss.name) == "string" then
                    local odds = type(dungeonOdds) == "table" and dungeonOdds[boss.name] or nil
                    for _, row in ipairs(type(boss.loot) == "table" and boss.loot or {}) do
                        local id = RowID(row)
                        PutSource(id, boss.name, dungeon, type(odds) == "table" and odds[id] or nil, from, RowName(row, 4))
                    end
                end
            end
            for _, row in ipairs(type(data.trashLoot) == "table" and data.trashLoot or {}) do
                PutSource(RowID(row), "Trash", dungeon, nil, from, RowName(row, 4))
            end
            for _, quest in ipairs(type(data.quests) == "table" and data.quests or {}) do
                if type(quest) == "table" and type(quest.name) == "string" then
                    local rewards = quest.rewards or quest.rewardItems
                    for _, reward in ipairs(type(rewards) == "table" and rewards or {}) do
                        PutSource(RowID(reward), "Quest: " .. quest.name, dungeon, nil, from, RowName(reward, 3))
                    end
                end
            end
        end
    end
end

-- FojjiCore's shape.
local function ReadFojji(dungeons, from)
    if type(dungeons) ~= "table" then
        return
    end
    for _, dungeon in ipairs(dungeons) do
        if type(dungeon) == "table" and type(dungeon.name) == "string" then
            for _, boss in ipairs(type(dungeon.bosses) == "table" and dungeon.bosses or {}) do
                if type(boss) == "table" and type(boss.n) == "string" and type(boss.loot) == "table" then
                    for index, id in ipairs(boss.loot) do
                        PutSource(id, boss.n, dungeon.name, type(boss.odds) == "table" and boss.odds[index] or nil, from)
                    end
                end
            end
        end
    end
end

local function BuildSources()
    sources.built, sources.byItem, sources.seen, sources.from = true, {}, {}, {}
    sources.items, sources.byName = {}, {}
    local oneForAll = rawget(_G, "OneForAll")
    if type(oneForAll) == "table" then
        -- (It builds DUNGEONS from its registry at load and drops the registry.)
        local chances = rawget(oneForAll, "DUNGEON_DROP_CHANCE")
        pcall(ReadRegistry, rawget(oneForAll, "DUNGEONS"), chances, "OneForAll")
        pcall(ReadRegistry, rawget(oneForAll, "DUNGEON_REGISTRY"), chances, "OneForAll")
    end
    local journal = rawget(_G, "ForeverDungeonJournal_NS")
    if type(journal) == "table" then
        pcall(ReadRegistry, rawget(journal, "DB"), nil, "DungeonJournal")
    end
    local fojji = rawget(_G, "FojjiCoreNS")
    local fojjiJournal = type(fojji) == "table" and rawget(fojji, "DJ") or nil
    if type(fojjiJournal) == "table" then
        pcall(ReadFojji, rawget(fojjiJournal, "Dungeons"), "FojjiCore")
    end
end

-- "General Drakkisath, Upper Blackrock Spire (13%)", or nil if no installed
-- addon knows. Two places at most, then "+N more".
local function Source(id)
    if not sources.built then
        BuildSources()
    end
    local list = sources.byItem[id]
    if not list or #list == 0 then
        return nil
    end
    local text = list[1]
    if list[2] then
        text = text .. "; " .. list[2]
    end
    if #list > 2 then
        text = text .. string.format("; +%d more", #list - 2)
    end
    return text
end
ns.ChaseSource = Source

-- An item by its exact name (any capitals), from those tables: its ID.
local function ItemByName(name)
    if not sources.built then
        BuildSources()
    end
    return sources.byName[Trim(name):lower()]
end

-- Items whose names have `text` in them, best first: names starting with
-- it, then a word starting with it, then anywhere. Up to `limit`, plus how
-- many matched in all.
local function SearchItems(text, limit)
    if not sources.built then
        BuildSources()
    end
    local want = Trim(text):lower()
    if #want < 3 then
        return {}, 0
    end
    local tiers = { {}, {}, {} }
    for _, item in pairs(sources.items) do
        local at = item.lower:find(want, 1, true)
        if at == 1 then
            table.insert(tiers[1], item)
        elseif at and item.lower:sub(at - 1, at - 1) == " " then
            table.insert(tiers[2], item)
        elseif at then
            table.insert(tiers[3], item)
        end
    end
    local found, total = {}, 0
    for _, tier in ipairs(tiers) do
        table.sort(tier, function(a, b) return a.lower < b.lower end)
        total = total + #tier
        for _, item in ipairs(tier) do
            if #found < (limit or 8) then
                found[#found + 1] = item
            end
        end
    end
    return found, total
end
ns.ChaseSearch = SearchItems

------------------------------------------------------------------------------
-- What the game says about each kind
------------------------------------------------------------------------------

local function ItemCount(id)
    local items = rawget(_G, "C_Item")
    local count = items and Call(items.GetItemCount, id, true)
    if count == nil then
        count = Call(rawget(_G, "GetItemCount"), id, true)
    end
    return Plain(count) and tonumber(count) or nil
end

-- A reputation by its ID: name, standing (1 Hated to 8 Exalted), how far
-- into that standing, and how long the standing is.
local function Faction(id)
    local reputation = rawget(_G, "C_Reputation")
    local data = reputation and Call(reputation.GetFactionDataByID, id)
    if type(data) == "table" and Plain(data.reaction) then
        local floor, ceiling, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
        if Plain(floor) and Plain(ceiling) and Plain(value) then
            return Plain(data.name) and data.name or nil, data.reaction, value - floor, ceiling - floor
        end
        return Plain(data.name) and data.name or nil, data.reaction
    end
    local name, _, standing, low, high, value = Call(rawget(_G, "GetFactionInfoByID"), id)
    if Plain(standing) then
        if Plain(low) and Plain(high) and Plain(value) then
            return Plain(name) and name or nil, standing, value - low, high - low
        end
        return Plain(name) and name or nil, standing
    end
    return nil
end

-- The ID of a reputation in your list by its name (or the start of it).
local function FactionByName(text)
    local want = Trim(text):lower()
    if want == "" then
        return nil
    end
    local reputation = rawget(_G, "C_Reputation")
    local found, partial, partials = nil, nil, 0
    local function Try(name, id, header)
        if header or not (Plain(name) and Plain(id)) or type(name) ~= "string" or id == 0 then
            return   -- (a heading in the list, or nothing usable)
        end
        local lower = name:lower()
        if lower == want then
            found = found or { id, name }
        elseif lower:sub(1, #want) == want then
            partials = partials + 1
            partial = partial or { id, name }
        end
    end
    if reputation and reputation.GetNumFactions and reputation.GetFactionDataByIndex then
        for index = 1, Call(reputation.GetNumFactions) or 0 do
            local data = Call(reputation.GetFactionDataByIndex, index)
            if type(data) == "table" then
                Try(data.name, data.factionID, data.isHeader and not data.isHeaderWithRep)
            end
        end
    else
        local count, info = rawget(_G, "GetNumFactions"), rawget(_G, "GetFactionInfo")
        for index = 1, Call(count) or 0 do
            local values = { pcall(info or error, index) }
            if values[1] then
                Try(values[2], values[15], values[10] and not values[12])
            end
        end
    end
    if found then
        return found[1], found[2]
    elseif partial and partials == 1 and #want >= 4 then
        return partial[1], partial[2]
    end
    return nil
end

local function QualityColor(quality)
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local color = type(colors) == "table" and quality and colors[quality]
    if type(color) == "table" and color.r then
        return { color.r, color.g, color.b }
    end
    return { 1, 1, 1 }
end

local function Standing(reaction)
    return rawget(_G, "FACTION_STANDING_LABEL" .. tostring(reaction)) or ("Standing " .. tostring(reaction))
end

-- Where an entry stands: { name, icon, color, text (how far along), done }.
local function State(entry)
    local state = { name = entry.name or "?", icon = KIND_ICON[entry.kind] or QUESTION, color = { 1, 1, 1 }, text = "", done = false }
    if entry.kind == "item" then
        local items = rawget(_G, "C_Item") or {}
        local name = Call(items.GetItemNameByID, entry.id)
        if Plain(name) and name ~= "" then
            entry.name = name
        elseif items.RequestLoadItemDataByID then
            pcall(items.RequestLoadItemDataByID, entry.id)   -- the game fetches it: GET_ITEM_INFO_RECEIVED follows
        end
        state.name = entry.name or ("Item " .. tostring(entry.id))
        local icon = Call(items.GetItemIconByID, entry.id)
        state.icon = Plain(icon) and icon or QUESTION
        local quality = Call(items.GetItemQualityByID, entry.id)
        state.color = QualityColor(Plain(quality) and quality or nil)
        -- No note of your own: where it comes from, if an installed
        -- dungeon journal says (unless you emptied the note yourself).
        if (entry.note == nil or entry.note == "") and not entry.noAuto and not entry.got then
            local from = Source(entry.id)
            if from then
                entry.note, entry.auto = from:sub(1, 160), true
            end
        end
        local have, want = ItemCount(entry.id), entry.want or 1
        if have then
            state.done = have >= want
            if want > 1 then
                state.text = string.format("%d/%d", math.min(have, want), want)
            end
        end
    elseif entry.kind == "rep" then
        local name, reaction, into, span = Faction(entry.id)
        if name then
            entry.name = name
        end
        state.name = entry.name or ("Reputation " .. tostring(entry.id))
        state.color = { 0.55, 0.80, 1.00 }
        if reaction then
            state.done = reaction >= (entry.want or EXALTED)
            state.text = Standing(reaction)
            if into and span and span > 0 and not state.done then
                state.text = string.format("%s %d/%d", state.text, into, span)
            end
        end
    elseif entry.kind == "quest" then
        local log = rawget(_G, "C_QuestLog") or {}
        local title = Call(log.GetTitleForQuestID, entry.id)
        if Plain(title) and title ~= "" then
            entry.name = title
        end
        state.name = entry.name or ("Quest " .. tostring(entry.id))
        state.color = { 1.00, 0.90, 0.45 }
        local complete = Call(log.IsQuestFlaggedCompleted, entry.id)
        if complete == nil then
            complete = Call(rawget(_G, "IsQuestFlaggedCompleted"), entry.id)
        end
        state.done = Plain(complete) and complete == true
        local onIt = Call(log.IsOnQuest, entry.id)
        if not state.done and Plain(onIt) and onIt == true then
            state.text = "in your log"
        end
    else
        state.done = entry.done == true
    end
    if entry.got or state.done then
        state.done = true
        if entry.kind == "item" then
            state.text = "Got it"
        elseif not (entry.kind == "rep" and state.text ~= "") then
            state.text = "Done"
        end
    end
    return state
end
ns.ChaseState = State

------------------------------------------------------------------------------
-- Adding, removing, ordering
------------------------------------------------------------------------------

local function Find(kind, id)
    for index, entry in ipairs(List()) do
        if entry.kind == kind and entry.id == id then
            return entry, index
        end
    end
    return nil
end

local function Dirty()
    if Refresh then
        Refresh()
    end
end

-- What a typed line means: kind, id (or the goal's text), and the note.
local function Parse(text)
    text = Trim(text)
    if text == "" then
        return nil
    end
    -- An item or quest link, with the note after it.
    local itemID, afterItem = text:match("|Hitem:(%d+).-|h.-|h|?r?(.*)$")
    if itemID then
        return "item", tonumber(itemID), Trim(afterItem:gsub("^%s*%-%s*", ""))
    end
    local questLink, afterQuest = text:match("|Hquest:(%d+).-|h.-|h|?r?(.*)$")
    if questLink then
        return "quest", tonumber(questLink), Trim(afterQuest:gsub("^%s*%-%s*", ""))
    end
    -- Everything else: the note after " - ".
    local head, note = text:match("^(.-)%s+%-%s+(.+)$")
    if not head then
        head, note = text, ""
    end
    head, note = Trim(head), Trim(note)
    local lower = head:lower()
    local quest = lower:match("^quest%s+(%d+)$") or lower:match("^q%s+(%d+)$")
    if quest then
        return "quest", tonumber(quest), note
    end
    local item, count = lower:match("^item%s+(%d+)%s*x?%s*(%d*)$")
    if not item then
        item, count = lower:match("^(%d+)%s*x?%s*(%d*)$")
    end
    if item then
        return "item", tonumber(item), note, tonumber(count)
    end
    local repName = head:match("^[Rr]ep%s+(.+)$") or head:match("^[Rr]eputation%s+(.+)$")
    local factionID, factionName = FactionByName(repName or head)
    if factionID then
        return "rep", factionID, note, nil, factionName
    end
    if repName then
        return nil, nil, nil, nil, nil, string.format("\"%s\" isn't in your reputation list (it has to be one you've met).", repName)
    end
    -- An item's exact name, where an installed dungeon journal knows it.
    local named = ItemByName((head:gsub("^[Ii]tem%s+", "")))
    if named then
        return "item", named, note
    end
    return "goal", head, note
end
ns.ChaseParse = Parse

-- Adds what a line says. Returns the entry, or nil and why not.
function ns.ChaseAdd(text)
    local kind, id, note, count, name, problem = Parse(text)
    if not kind then
        return nil, problem or "nothing to add"
    end
    local list = List()
    local entry
    if kind == "goal" then
        for _, other in ipairs(list) do
            if other.kind == "goal" and other.name and other.name:lower() == id:lower() then
                return nil, "that goal is already on your list"
            end
        end
        entry = { kind = "goal", name = id, note = note }
    else
        if Find(kind, id) then
            return nil, "that's already on your list"
        end
        entry = { kind = kind, id = id, note = note, name = name }
        if kind == "item" and count and count > 1 then
            entry.want = count
        end
    end
    entry.added = Now()
    list[#list + 1] = entry
    status.added = status.added + 1
    local state = State(entry)
    if state.done and kind ~= "goal" then
        entry.got = Now()   -- already yours: straight to the done pile, without the fanfare
    end
    status.last = "added " .. tostring(state.name)
    Dirty()
    return entry, state
end

function ns.ChaseRemove(entry)
    local list = List()
    for index, other in ipairs(list) do
        if other == entry then
            table.remove(list, index)
            Dirty()
            return true
        end
    end
    return false
end

-- Up (-1) or down (+1) among the ones still to get.
function ns.ChaseMove(entry, direction)
    local list = List()
    for index, other in ipairs(list) do
        if other == entry then
            local swap = index + direction
            while list[swap] and list[swap].got do
                swap = swap + direction
            end
            if list[swap] then
                list[index], list[swap] = list[swap], list[index]
                Dirty()
                return true
            end
            return false
        end
    end
    return false
end

-- A goal ticked off (or back on); anything else put back on the list.
function ns.ChaseToggleDone(entry)
    if entry.got then
        entry.got, entry.done = nil, nil
    else
        entry.got, entry.done = Now(), true
    end
    Dirty()
end

function ns.ChaseClearDone()
    local list, removed = List(), 0
    for index = #list, 1, -1 do
        if list[index].got then
            table.remove(list, index)
            removed = removed + 1
        end
    end
    Dirty()
    return removed
end

-- Still to get, in order; and the done ones after.
local function Split()
    local open, done = {}, {}
    for _, entry in ipairs(List()) do
        if entry.got then
            done[#done + 1] = entry
        else
            open[#open + 1] = entry
        end
    end
    return open, done
end

------------------------------------------------------------------------------
-- Speaking up
------------------------------------------------------------------------------

local function Notice(text, color)
    local notice, frame = rawget(_G, "RaidNotice_AddMessage"), rawget(_G, "RaidWarningFrame")
    if notice and frame then
        pcall(notice, frame, text, { r = color[1], g = color[2], b = color[3] })
    end
end

local function Sound(id)
    local play = rawget(_G, "PlaySound")
    if play and Settings().sound ~= false then
        pcall(play, id, "Master")
    end
end

local function Link(entry, state)
    if entry.kind == "item" then
        local items = rawget(_G, "C_Item")
        local _, link = Call(items and items.GetItemInfo or rawget(_G, "GetItemInfo"), entry.id)
        if Plain(link) and type(link) == "string" then
            return link
        end
    end
    return "[" .. tostring(state.name) .. "]"
end

local function Celebrate(entry, state)
    status.completed = status.completed + 1
    status.last = "complete: " .. tostring(state.name)
    if Settings().alerts == false then
        return
    end
    ns.Print("chase complete: " .. Link(entry, state) .. "!")
    Notice("Chase complete: " .. tostring(state.name), GREEN)
    Sound(8960)   -- the ready check: a clear, short tone
end

-- An item seen in a roll or a loot window.
local seenAt = {}
local function Spotted(link, where)
    if Settings().alerts == false or not Plain(link) or type(link) ~= "string" then
        return false
    end
    local id = tonumber(link:match("item:(%d+)"))
    local entry = id and Find("item", id)
    if not entry or entry.got then
        return false
    end
    local now = GetTime()
    if seenAt[id] and now - seenAt[id] < 20 then
        return false   -- said already (the roll and the loot window are the same drop)
    end
    seenAt[id] = now
    status.spotted = status.spotted + 1
    status.last = where .. ": " .. tostring(entry.name or id)
    ns.Print(string.format("%s %s: it's on your chase list!%s", link, where,
        (entry.note and entry.note ~= "") and (" (" .. entry.note .. ")") or ""))
    Notice("On your chase list: " .. tostring(entry.name or ("item " .. id)), GOLD)
    Sound(8959)   -- the raid warning sound
    return true
end
ns.ChaseSpotted = Spotted

-- On an item's tooltip: that it's on the list, and the note.
local function OnItemTip(tooltip, data)
    if Settings().tooltip == false or type(tooltip) ~= "table" or not tooltip.AddLine then
        return
    end
    if tooltip.IsForbidden and tooltip:IsForbidden() then
        return
    end
    local id = type(data) == "table" and rawget(data, "id") or nil
    if not Plain(id) then
        return
    end
    local entry = Find("item", tonumber(id))
    if not entry or entry.got then
        return
    end
    local nature = W.NATURE
    tooltip:AddLine("On your chase list", nature[1], nature[2], nature[3])
    if entry.note and entry.note ~= "" then
        tooltip:AddLine(entry.note, 0.8, 0.8, 0.8, true)
    end
    status.tips = status.tips + 1
end

------------------------------------------------------------------------------
-- The panel on screen
------------------------------------------------------------------------------

local function Text(parent, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function ShowTip(owner, entry, state, anchor)
    local tip = rawget(_G, "GameTooltip")
    if not tip then
        return
    end
    tip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    local shown = false
    if entry.kind == "item" and tip.SetItemByID then
        shown = pcall(tip.SetItemByID, tip, entry.id)   -- (its tooltip adds the note itself)
    end
    if not shown then
        tip:SetText(state.name, state.color[1], state.color[2], state.color[3])
        if state.text ~= "" then
            tip:AddLine(state.text, 1, 1, 1)
        end
        if entry.note and entry.note ~= "" then
            tip:AddLine(entry.note, 0.8, 0.8, 0.8, true)
        end
    end
    if owner.hint then
        tip:AddLine(owner.hint, 0.5, 0.5, 0.5)
    end
    tip:Show()
end

local function HideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip then
        tip:Hide()
    end
end

local function SavePanelSpot()
    local x, top = panel:GetLeft(), panel:GetTop()
    if x and top then
        Settings().pos = { math.floor(x + 0.5), math.floor(top + 0.5) }
    end
end

local function CreatePanel()
    local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsChase", UIParent, "BackdropTemplate")
    panel = (ok and made) or CreateFrame("Frame", "ElipsPanelsChase", UIParent)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    W.PanelBackdrop(panel, 0.88)
    W.ThemePanel(panel, nil, W.NATURE)
    W.QuietInCombat(panel)   -- (with that on, it fades in a fight rather than hiding: the mouse brings it back)
    local crest = panel:CreateTexture(nil, "ARTWORK")
    crest:SetTexture("Interface\\AddOns\\ElipsPanels\\Media\\ElipsPanels")
    crest:SetSize(18, 18)
    crest:SetPoint("TOPLEFT", 8, -7)
    panel.title = Text(panel, "GameFontNormal")
    panel.title:SetPoint("LEFT", crest, "RIGHT", 6, 0)
    panel.title:SetText("Chase")
    panel.count = Text(panel)
    panel.count:SetPoint("RIGHT", panel, "TOPRIGHT", -12, -16)
    panel.count:SetJustifyH("RIGHT")
    panel.count:SetTextColor(GREY[1], GREY[2], GREY[3])
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 8, -HEADER)
    line:SetPoint("TOPRIGHT", -8, -HEADER)
    W.AccentLine(line, W.NATURE, 0.6)
    panel.titleLine = line
    panel.rows = {}
    panel.more = Text(panel, "GameFontDisableSmall")

    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        panel.offset = (panel.offset or 0) - delta
        HideTip()   -- (the row under the pointer has changed)
        Dirty()
    end)
    -- The header: click it to fold the panel to just this line, right-click
    -- for the list window, drag to move.
    local header = CreateFrame("Button", nil, panel)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        header.dragged = true
        if not Settings().locked then
            panel:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        SavePanelSpot()
        C_Timer.After(0.05, function()
            header.dragged = false
        end)
    end)
    header:SetScript("OnClick", function(_, button)
        if header.dragged then
            header.dragged = false
            return
        end
        if button == "RightButton" then
            ns.ToggleChaseWindow()
        else
            Settings().collapsed = not Settings().collapsed
            Dirty()
        end
    end)
    header:SetScript("OnEnter", function(self)
        local tip = rawget(_G, "GameTooltip")
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText("Chase list", 1, 1, 1)
            tip:AddLine("Click: fold or open. Right-click: the list window. Drag: move.", 0.8, 0.8, 0.8)
            tip:Show()
        end
    end)
    header:SetScript("OnLeave", HideTip)
    panel.header = header

    W.PlacePanel(panel, Settings().pos, DEFAULT_SPOT)
    panel:Hide()
    ns.RegisterMover({
        key = "chase", label = "Chase list", width = PANEL_WIDTH, height = 120, default = DEFAULT_SPOT,
        get = function() return Settings().pos end,
        set = function(pos)
            Settings().pos = pos
            W.PlacePanel(panel, pos, DEFAULT_SPOT)
        end,
    })
end

local function PanelRow(index)
    local row = panel.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 8, -(HEADER + 4 + (index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -8, -(HEADER + 4 + (index - 1) * ROW_HEIGHT))
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.value = Text(row)
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    row.name = Text(row)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    row.hint = "Click: the list window"
    row:SetScript("OnEnter", function(self)
        if self.entry then
            ShowTip(self, self.entry, self.state)
        end
    end)
    row:SetScript("OnLeave", HideTip)
    row:SetScript("OnClick", function()
        ns.ToggleChaseWindow(true)
    end)
    panel.rows[index] = row
    return row
end

local function DrawPanel(open, done)
    if not panel then
        return
    end
    local settings = Settings()
    local hidden = settings.show == false or #open == 0
        or (settings.hideInCombat ~= false and (fighting or InCombatLockdown()) and not W.QuietOn())
    if hidden then
        panel:Hide()
        return
    end
    panel.count:SetText(#done > 0 and string.format("%d to get · %d done", #open, #done) or string.format("%d to get", #open))
    local shown = 0
    local limit = settings.rows or 6
    -- (The mouse wheel moves through a list longer than the rows shown.)
    panel.offset = math.max(0, math.min(panel.offset or 0, math.max(0, #open - limit)))
    local offset = panel.offset
    if not settings.collapsed then
        for index = 1, math.min(#open - offset, limit) do
            local entry = open[index + offset]
            local state = State(entry)
            local row = PanelRow(index)
            row.entry, row.state = entry, state
            row.icon:SetTexture(state.icon)
            row.name:SetText(state.name)
            row.name:SetTextColor(state.color[1], state.color[2], state.color[3])
            row.value:SetText(state.text)
            row.value:SetTextColor(GREY[1], GREY[2], GREY[3])
            row:Show()
            shown = index
        end
        if #open > limit then
            local below = #open - limit - offset
            panel.more:ClearAllPoints()
            panel.more:SetPoint("TOPLEFT", 8, -(HEADER + 6 + shown * ROW_HEIGHT))
            panel.more:SetText(offset == 0 and string.format("+%d more", below)
                or below > 0 and string.format("%d above · %d below", offset, below) or string.format("%d above", offset))
            panel.more:Show()
        else
            panel.more:Hide()
        end
    else
        panel.more:Hide()
    end
    for index = shown + 1, #panel.rows do
        panel.rows[index]:Hide()
    end
    panel.titleLine:SetShown(not settings.collapsed)
    local more = (not settings.collapsed and #open > limit) and 16 or 0
    panel:SetHeight(settings.collapsed and HEADER or (HEADER + 10 + shown * ROW_HEIGHT + more))
    panel:Show()
end

------------------------------------------------------------------------------
-- The list window
------------------------------------------------------------------------------

local WINDOW_WIDTH, WINDOW_HEIGHT, LINE_HEIGHT, LINES = 580, 500, 46, 8

-- Matches under the box while you type an item's name (from the loot
-- tables of an installed dungeon journal): click one to add that item.
local SUGGESTIONS, SUGGEST_HEIGHT = 8, 22

local function HideSuggestions()
    if window and window.suggest then
        window.suggest:Hide()
    end
end

-- The text in the box: what's searched for, and the note after " - ".
local function BoxParts()
    local text = window.box:GetText() or ""
    local head, note = text:match("^(.-)%s+%-%s+(.*)$")
    if not head then
        head, note = text, ""
    end
    return Trim(head), Trim(note)
end

local function SuggestRow(index)
    local suggest = window.suggest
    local row = suggest.rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, suggest)
    row:SetHeight(SUGGEST_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -(4 + (index - 1) * SUGGEST_HEIGHT))
    row:SetPoint("TOPRIGHT", -4, -(4 + (index - 1) * SUGGEST_HEIGHT))
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = Text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.from = Text(row, "GameFontDisableSmall")
    row.from:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.from:SetPoint("RIGHT", -6, 0)
    row.from:SetJustifyH("RIGHT")
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(W.NATURE[1], W.NATURE[2], W.NATURE[3], 0.22)
    row:SetScript("OnEnter", function(self)
        local tip = rawget(_G, "GameTooltip")
        if tip and self.item then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            if not (tip.SetItemByID and pcall(tip.SetItemByID, tip, self.item.id)) then
                tip:SetText(self.item.name, 1, 1, 1)
            end
            tip:Show()
        end
    end)
    row:SetScript("OnLeave", HideTip)
    row:SetScript("OnClick", function(self)
        if not self.item then
            return
        end
        local _, note = BoxParts()
        local entry, state = ns.ChaseAdd(tostring(self.item.id) .. (note ~= "" and (" - " .. note) or ""))
        if entry then
            window.box:SetText("")
            window.say:SetText(entry.got and ("You already have " .. tostring(state.name) .. ": it's with the done ones.")
                or ("Added " .. tostring(state.name) .. "."))
            window.say:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        else
            window.say:SetText("Not added: " .. tostring(state) .. ".")
            window.say:SetTextColor(1, 0.5, 0.4)
        end
        HideSuggestions()
    end)
    suggest.rows[index] = row
    return row
end

local function UpdateSuggestions()
    if not (window and window.suggest) then
        return
    end
    local head = BoxParts()
    local lower = head:lower()
    local found, total = {}, 0
    -- (Not for a link, an ID, a quest or a reputation.)
    if not (head:find("|H", 1, true) or lower:match("^%d") or lower:match("^quest%s") or lower:match("^q%s") or lower:match("^rep")) then
        found, total = SearchItems((head:gsub("^[Ii]tem%s+", "")), SUGGESTIONS)
    end
    local suggest = window.suggest
    if #found == 0 then
        suggest:Hide()
        return
    end
    local items = rawget(_G, "C_Item") or {}
    for index, item in ipairs(found) do
        local row = SuggestRow(index)
        row.item = item
        local icon = Call(items.GetItemIconByID, item.id)
        row.icon:SetTexture(Plain(icon) and icon or QUESTION)
        local quality = Call(items.GetItemQualityByID, item.id)
        local color = QualityColor(Plain(quality) and quality or item.quality)
        row.name:SetText(item.name)
        row.name:SetTextColor(color[1], color[2], color[3])
        row.from:SetText(Source(item.id) or "")
        row:Show()
    end
    for index = #found + 1, #suggest.rows do
        suggest.rows[index]:Hide()
    end
    suggest.more:SetShown(total > #found)
    suggest.more:SetText(total > #found and string.format("+%d more: keep typing", total - #found) or "")
    suggest:SetHeight(8 + #found * SUGGEST_HEIGHT + (total > #found and 16 or 0))
    suggest:Show()
end
ns.ChaseSuggest = UpdateSuggestions

local function AddFromBox(box)
    local text = box:GetText() or ""
    if Trim(text) == "" then
        return
    end
    local entry, state = ns.ChaseAdd(text)
    HideSuggestions()
    if entry then
        box:SetText("")
        window.say:SetText(entry.got and ("You already have " .. tostring(state.name) .. ": it's with the done ones.")
            or ("Added " .. tostring(state.name) .. "."))
        window.say:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    else
        window.say:SetText("Not added: " .. tostring(state) .. ".")
        window.say:SetTextColor(1, 0.5, 0.4)
    end
end

local function WindowLine(index)
    local line = window.lines[index]
    if line then
        return line
    end
    line = CreateFrame("Frame", nil, window)
    line:SetHeight(LINE_HEIGHT - 4)
    line:SetPoint("TOPLEFT", 14, window.listTop - (index - 1) * LINE_HEIGHT)
    line:SetPoint("TOPRIGHT", -14, window.listTop - (index - 1) * LINE_HEIGHT)
    local back = line:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0.06)
    -- The icon: hover it for the tooltip.
    line.iconButton = CreateFrame("Button", nil, line)
    line.iconButton:SetSize(30, 30)
    line.iconButton:SetPoint("LEFT", 6, 0)
    line.icon = line.iconButton:CreateTexture(nil, "ARTWORK")
    line.icon:SetAllPoints()
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.iconButton:SetScript("OnEnter", function(self)
        if line.entry then
            ShowTip(self, line.entry, line.state, "ANCHOR_RIGHT")
        end
    end)
    line.iconButton:SetScript("OnLeave", HideTip)
    -- Buttons, from the right: remove, done, down, up.
    line.remove = W.Button(line, "X", 24, function()
        local name = line.state and line.state.name
        if line.entry and ns.ChaseRemove(line.entry) then
            window.say:SetText("Removed " .. tostring(name) .. ".")
            window.say:SetTextColor(GREY[1], GREY[2], GREY[3])
        end
    end)
    line.remove:SetPoint("RIGHT", -6, 0)
    line.tick = W.Button(line, "Done", 50, function()
        if line.entry then
            ns.ChaseToggleDone(line.entry)
        end
    end)
    line.tick:SetPoint("RIGHT", line.remove, "LEFT", -4, 0)
    line.down = W.Button(line, "Dn", 30, function()
        if line.entry then
            ns.ChaseMove(line.entry, 1)
        end
    end)
    line.down:SetPoint("RIGHT", line.tick, "LEFT", -4, 0)
    line.up = W.Button(line, "Up", 30, function()
        if line.entry then
            ns.ChaseMove(line.entry, -1)
        end
    end)
    line.up:SetPoint("RIGHT", line.down, "LEFT", -4, 0)
    -- (The four buttons and their gaps take 152 on the right.)
    line.value = Text(line, "GameFontHighlightSmall")
    line.value:SetPoint("TOPRIGHT", line, "TOPRIGHT", -160, -6)
    line.value:SetJustifyH("RIGHT")
    line.name = Text(line, "GameFontNormal")
    line.name:SetPoint("TOPLEFT", line, "TOPLEFT", 44, -5)
    line.name:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
    -- The note: how to get it.
    line.note = W.TextBox(line, nil, "How to get it (type here, then Enter)", 100)
    line.note:SetHeight(18)
    line.note:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 42, 3)
    line.note:SetPoint("RIGHT", line, "RIGHT", -160, 0)
    line.note:SetMaxLetters(160)
    local function Save()
        local entry = line.entry
        if entry then
            local text = Trim(line.note:GetText())
            if text ~= (entry.note or "") then
                -- Yours now: an emptied note isn't filled in again.
                entry.note, entry.auto, entry.noAuto = text, nil, (text == "") or nil
            end
        end
    end
    line.note:SetScript("OnEnterPressed", function(self)
        Save()
        self:ClearFocus()
    end)
    line.note:SetScript("OnEditFocusLost", Save)
    line.note:SetScript("OnEscapePressed", function(self)
        self:SetText(line.entry and line.entry.note or "")
        self:ClearFocus()
    end)
    window.lines[index] = line
    return line
end

local function DrawWindow(open, done)
    if not (window and window:IsShown()) then
        return
    end
    local all = {}
    for _, entry in ipairs(open) do
        all[#all + 1] = entry
    end
    for _, entry in ipairs(done) do
        all[#all + 1] = entry
    end
    window.offset = math.max(0, math.min(window.offset or 0, math.max(0, #all - LINES)))
    for index = 1, LINES do
        local entry = all[index + window.offset]
        local line = WindowLine(index)
        if entry then
            local state = State(entry)
            line.entry, line.state = entry, state
            line.icon:SetTexture(state.icon)
            line.icon:SetDesaturated(entry.got and true or false)
            line.name:SetText(state.name)
            if entry.got then
                line.name:SetTextColor(GREY[1], GREY[2], GREY[3])
                line.value:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
            else
                line.name:SetTextColor(state.color[1], state.color[2], state.color[3])
                line.value:SetTextColor(0.85, 0.85, 0.85)
            end
            line.value:SetText(state.text)
            if not ns.Bool(line.note:HasFocus(), true) then
                line.note:SetText(entry.note or "")
            end
            -- A goal is ticked off by hand; the rest tick themselves, and can
            -- only be put back.
            line.tick:SetText(entry.got and "Again" or "Done")
            local ticks = entry.got ~= nil or entry.kind == "goal"
            line.tick:SetShown(ticks)
            -- (No gap beside the X where there's no Done button.)
            line.down:ClearAllPoints()
            line.down:SetPoint("RIGHT", ticks and line.tick or line.remove, "LEFT", -4, 0)
            line.up:SetShown(not entry.got)
            line.down:SetShown(not entry.got)
            line:Show()
        else
            line.entry = nil
            line:Hide()
        end
    end
    local below = #all - LINES - window.offset
    window.foot:SetText(#all == 0 and "Nothing on your list yet. Shift-click an item into the box above, or type a goal."
        or string.format("%d to get, %d done%s", #open, #done,
            (window.offset > 0 or below > 0) and string.format("  ·  scroll for more (%d above, %d below)", window.offset, math.max(0, below)) or ""))
    window.clear:SetShown(#done > 0)
end

local function CreateWindow()
    local title = "Chase list"
    local frame = W.Window("ElipsPanelsChaseFrame", title, WINDOW_WIDTH, WINDOW_HEIGHT)
    local top = -(W.TITLE_HEIGHT + 12)
    if not frame then
        local ok, made = pcall(CreateFrame, "Frame", "ElipsPanelsChaseFrame", UIParent, "BasicFrameTemplateWithInset")
        if not ok or not made then
            return nil
        end
        frame = made
        frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        if frame.TitleText then
            frame.TitleText:SetText(title)
        end
        top = -36
    end
    frame:SetPoint("CENTER", 0, 20)
    frame:SetToplevel(true)
    frame:Hide()
    window = frame
    window.lines, window.offset = {}, 0

    local add = W.Button(frame, "Add", 60, function()
        AddFromBox(window.box)
    end)
    add:SetPoint("TOPRIGHT", -14, top)
    local box = W.TextBox(frame, "ElipsPanelsChaseBox", "Shift-click an item here, or type its name or ID, a reputation, \"quest 1234\" or a goal", 100)
    box:SetPoint("TOPLEFT", 14, top)
    box:SetPoint("RIGHT", add, "LEFT", -6, 0)
    box:SetMaxLetters(300)
    box:SetScript("OnEnterPressed", function(self)
        AddFromBox(self)
    end)
    box:SetScript("OnEscapePressed", function(self)
        HideSuggestions()
        self:ClearFocus()
    end)
    window.box = box
    -- The matches for a typed name, over the list, under the box.
    local okSuggest, suggest = pcall(CreateFrame, "Frame", nil, frame, "BackdropTemplate")
    if not (okSuggest and suggest) then
        suggest = CreateFrame("Frame", nil, frame)
    end
    suggest:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    suggest:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    suggest:SetFrameLevel(frame:GetFrameLevel() + 30)
    suggest:EnableMouse(true)
    W.PanelBackdrop(suggest, 0.98)
    suggest.rows = {}
    suggest.more = Text(suggest, "GameFontDisableSmall")
    suggest.more:SetPoint("BOTTOMLEFT", 10, 6)
    suggest:Hide()
    window.suggest = suggest
    box:HookScript("OnTextChanged", function()
        UpdateSuggestions()
    end)
    window.say = Text(frame, "GameFontDisableSmall")
    window.say:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    window.say:SetPoint("RIGHT", -14, 0)
    window.say:SetText("Add how to get it after \" - \", like: 12345 - General Drakkisath, Upper Blackrock Spire")
    window.listTop = top - 48

    window.foot = Text(frame, "GameFontDisableSmall")
    window.foot:SetPoint("BOTTOMLEFT", 16, 16)
    window.clear = W.Button(frame, "Clear the done ones", 150, function()
        local removed = ns.ChaseClearDone()
        window.say:SetText(string.format("Cleared %d done.", removed))
        window.say:SetTextColor(GREY[1], GREY[2], GREY[3])
    end)
    window.clear:SetPoint("BOTTOMRIGHT", -14, 10)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        window.offset = (window.offset or 0) - delta
        Dirty()
    end)
    frame:SetScript("OnShow", Dirty)
    frame:HookScript("OnHide", HideSuggestions)
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" then
        special[#special + 1] = "ElipsPanelsChaseFrame"   -- Escape closes it
    end
    return frame
end

function ns.ToggleChaseWindow(open)
    if not window and not CreateWindow() then
        ns.Print("the chase list window couldn't be made on this client.")
        return
    end
    if open or not window:IsShown() then
        window:Show()
        Dirty()
    else
        HideSuggestions()
        window:Hide()
    end
end

------------------------------------------------------------------------------
-- Keeping it current
------------------------------------------------------------------------------

Refresh = function()
    if not ns.db then
        return
    end
    local combat = fighting or InCombatLockdown()
    if not combat then
        -- What's done since last time (never judged in a fight: the game
        -- hides too much then).
        for _, entry in ipairs(List()) do
            if not entry.got and entry.kind ~= "goal" then
                local state = State(entry)
                if state.done then
                    entry.got = Now()
                    Celebrate(entry, state)
                end
            end
        end
    end
    local open, done = Split()
    DrawPanel(open, done)
    DrawWindow(open, done)
end
ns.RefreshChase = Refresh

-- Several events in a row: one refresh a moment later.
local waiting = false
local function Soon()
    if waiting then
        return
    end
    waiting = true
    C_Timer.After(0.4, function()
        waiting = false
        Refresh()
    end)
end

-- A link shift-clicked while the add box (or a note) has the cursor goes
-- into it.
local lastLink, lastLinkAt = nil, 0
local function LinkClicked(text)
    if not (window and window:IsShown()) or type(text) ~= "string" or ns.IsSecret(text) then
        return
    end
    local now = GetTime()
    if text == lastLink and now - lastLinkAt < 0.2 then
        return   -- the same click, heard through both of the game's functions
    end
    local box = window.box
    if box and ns.Bool(box:HasFocus(), false) then
        lastLink, lastLinkAt = text, now
        box:Insert(text)
    end
end

function ns.ChaseCommand(message)
    local sub, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    if sub == "" then
        ns.ToggleChaseWindow()
    elseif sub == "add" then
        local entry, state = ns.ChaseAdd(rest)
        if entry then
            ns.Print(entry.got and ("you already have " .. tostring(state.name) .. ": it's with the done ones.")
                or ("added to your chase list: " .. tostring(state.name) .. "."))
        else
            ns.Print("not added: " .. tostring(state) .. ". Use /ep chase add [item link], an item ID, a reputation's name, quest 1234, or any goal; a note goes after \" - \".")
        end
    elseif sub == "show" or sub == "hide" then
        Settings().show = sub == "show"
        Refresh()
        ns.Print(sub == "show" and "the chase panel is shown (while there's something to get)." or "the chase panel is hidden. /ep chase still opens the list.")
    else
        ns.Print("/ep chase opens the list; /ep chase add [link], ID, reputation or goal adds to it; /ep chase show and /ep chase hide for the panel on screen.")
    end
end

-- For /ep status: the list, and what this client reports for the things not
-- tracked yet.
function ns.ChaseDiagLines()
    local open, done = Split()
    local lines = { string.format("%d to get, %d done | added %d, completed %d, spotted in loot %d, tooltips tagged %d | hooks: %s | last: %s",
        #open, #done, status.added, status.completed, status.spotted, status.tips, status.hooks ~= "" and status.hooks or "none",
        status.last) }
    do
        if not sources.built then
            pcall(BuildSources)
        end
        local parts = {}
        for _, from in ipairs({ "OneForAll", "DungeonJournal", "FojjiCore" }) do
            parts[#parts + 1] = string.format("%s %d", from, sources.from[from] or 0)
        end
        lines[#lines + 1] = "  where items drop, read from other addons (drops known): " .. table.concat(parts, ", ")
    end
    for index, entry in ipairs(open) do
        if index > 6 then
            break
        end
        local ok, state = pcall(State, entry)
        lines[#lines + 1] = string.format("  %s %s: %s%s", entry.kind, tostring(entry.id or ""),
            ok and (tostring(state.name) .. (state.text ~= "" and (" (" .. state.text .. ")") or "")) or ("couldn't read: " .. tostring(state)),
            (entry.note and entry.note ~= "") and " | note" or "")
    end
    -- What else the client could tell us.
    local function Probe(label, fn, ...)
        if type(fn) ~= "function" then
            return label .. " absent"
        end
        local values = { pcall(fn, ...) }
        if not values[1] then
            return label .. " error"
        end
        local parts = {}
        for index = 2, math.min(#values, 5) do
            local value = values[index]
            parts[#parts + 1] = ns.IsSecret(value) and "hidden" or (type(value) == "table" and "table") or tostring(value)
        end
        return label .. " " .. (#parts > 0 and table.concat(parts, "/") or "nothing")
    end
    local function In(space, name)
        local holder = rawget(_G, space)
        return type(holder) == "table" and holder[name] or nil
    end
    local sample = (open[1] and open[1].kind == "item" and open[1].id) or 6948
    lines[#lines + 1] = "  can be tracked? " .. table.concat({
        Probe("mounts:", In("C_MountJournal", "GetNumMounts")),
        Probe("mount IDs:", In("C_MountJournal", "GetMountIDs")),
        Probe("transmog source for an item:", In("C_TransmogCollection", "GetItemInfo"), sample),
        Probe("has transmog:", In("C_TransmogCollection", "PlayerHasTransmog"), sample),
        Probe("PvP rank:", rawget(_G, "UnitPVPRank"), "player"),
        Probe("lifetime PvP:", rawget(_G, "GetPVPLifetimeStats")),
        Probe("this week's PvP:", rawget(_G, "GetPVPThisWeekStats")),
        Probe("currencies:", In("C_CurrencyInfo", "GetCurrencyListSize")),
    }, " | ")
    lines[#lines + 1] = "  where things drop? " .. table.concat({
        Probe("journal tiers:", rawget(_G, "EJ_GetNumTiers")),
        Probe("journal instance 1:", rawget(_G, "EJ_GetInstanceByIndex"), 1, false),
        Probe("journal loot count:", In("C_EncounterJournal", "GetLootInfoByIndex"), 1),
        Probe("loot journal sets:", In("C_LootJournal", "GetItemSets")),
        Probe("achievement categories:", rawget(_G, "GetCategoryList")),
    }, " | ")
    return lines
end

ns.Hook("INIT", function()
    if not ns.ModuleLoaded("chase") then
        return
    end
    CreatePanel()
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "UPDATE_FACTION", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "GET_ITEM_INFO_RECEIVED",
        "PLAYER_ENTERING_WORLD", "PLAYERBANKSLOTS_CHANGED" }) do
        pcall(ns.On, event, Soon)
    end
    ns.Hook("COMBAT", function(inCombat)
        fighting = inCombat and true or false
        Refresh()
    end)
    -- Another addon loading may bring loot tables: read them again when next asked.
    pcall(ns.On, "ADDON_LOADED", function()
        sources.built = false
    end)
    -- Drops: a roll starting, a loot window opening.
    pcall(ns.On, "START_LOOT_ROLL", function(rollID)
        local link = Call(rawget(_G, "GetLootRollItemLink"), rollID)
        pcall(Spotted, link, "is up for a roll")
    end)
    pcall(ns.On, "LOOT_OPENED", function()
        local slots, slotLink = rawget(_G, "GetNumLootItems"), rawget(_G, "GetLootSlotLink")
        for slot = 1, Call(slots) or 0 do
            pcall(Spotted, Call(slotLink, slot), "dropped")
        end
    end)
    -- Item tooltips.
    local hooks = {}
    local processor = rawget(_G, "TooltipDataProcessor")
    local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if type(processor) == "table" and processor.AddTooltipPostCall and itemType ~= nil then
        if pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
            pcall(OnItemTip, tooltip, data)
        end) then
            hooks[#hooks + 1] = "item tooltips"
        end
    end
    -- Shift-clicked links.
    if type(rawget(_G, "ChatEdit_InsertLink")) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", function(text)
            pcall(LinkClicked, text)
        end)
        hooks[#hooks + 1] = "ChatEdit_InsertLink"
    end
    local util = rawget(_G, "ChatFrameUtil")
    if type(util) == "table" and type(util.InsertLink) == "function" then
        hooksecurefunc(util, "InsertLink", function(text)
            pcall(LinkClicked, text)
        end)
        hooks[#hooks + 1] = "ChatFrameUtil.InsertLink"
    end
    status.hooks = table.concat(hooks, ", ")
    Soon()
end)

ns.commands.chase = ns.ChaseCommand
ns.statusParts[#ns.statusParts + 1] = function()
    if not ns.ModuleLoaded("chase") then
        return "Chase list: switched off."
    end
    local lines = ns.ChaseDiagLines()
    if lines[1] then
        lines[1] = "Chase list: " .. lines[1]
    end
    return lines
end
