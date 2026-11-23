-- FromArchDruid.lua
-- These panels were part of ArchDruid (a Druid HUD) before they were
-- ElipsPanels'. This file is the only place ElipsPanels knows anything
-- about ArchDruid: it brings each panel's old settings over, once (ArchDruid
-- leaves its saved settings where they are), and can be dropped when nobody
-- is coming from there any more.

local _, ns = ...

local function Copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, inner in pairs(value) do
        out[key] = Copy(inner)
    end
    return out
end

-- { part, what it takes (returns true when it took something), its name in a sentence }
ns.CARRY = {
    { "info", function(old, db)
        if type(old.info) ~= "table" then
            return false
        end
        db.info = Copy(old.info)
        return true
    end, "information bar" },
    -- (The lists themselves come along: every character's.)
    { "chase", function(old, db)
        if type(old.chase) ~= "table" then
            return false
        end
        db.chase = Copy(old.chase)
        if type(old.modules) == "table" and old.modules.chase == false then
            db.chase.show = false   -- (it was switched off there as a whole)
        end
        return true
    end, "chase list" },
    -- (With the cooldowns seen used, so nothing counts as ready that isn't.)
    { "group", function(old, db)
        if type(old.group) ~= "table" then
            return false
        end
        db.group = Copy(old.group)
        if type(old.modules) == "table" and old.modules.group == false then
            -- (They were switched off there as a whole.)
            for _, part in ipairs({ "mana", "cooldowns" }) do
                db.group[part] = type(db.group[part]) == "table" and db.group[part] or {}
                db.group[part].show = false
            end
        end
        return true
    end, "group panel" },
    { "quiet", function(old, db)
        if type(old.quietPanels) ~= "boolean" then
            return false
        end
        db.quietPanels = old.quietPanels
        return false   -- (not worth a mention by itself)
    end },
}

-- Run at login, once the game has loaded every addon's settings. Returns a
-- line saying what came over, or nil.
function ns.Migrate()
    local db = ns.db
    local old = rawget(_G, "ArchDruidDB")
    if type(db.carried) ~= "table" then
        db.carried = {}
    end
    local words = {}
    for _, entry in ipairs(ns.CARRY) do
        local part = entry[1]
        if not db.carried[part] then
            db.carried[part] = true
            if type(old) == "table" then
                local ok, took = pcall(entry[2], old, db)
                if ok and took and entry[3] then
                    words[#words + 1] = entry[3]
                end
            end
        end
    end
    if #words == 0 then
        return nil
    end
    local what = #words == 1 and words[1] or (table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words])
    return "your " .. what .. " settings came over from ArchDruid."
end
