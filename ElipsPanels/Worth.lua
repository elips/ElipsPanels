-- Worth.lua
-- What the things you loot are worth, for the information bar's gold per
-- hour. Only with Auctionator installed: the prices are from its latest
-- scan. Without it nothing here counts anything, and gold per hour is the
-- coin you've gained, as it always was.

local _, ns = ...

------------------------------------------------------------------------------
-- What counts
------------------------------------------------------------------------------
-- - Each item you loot (the game's "You receive loot" line; not a quest's
--   reward, not something bought or made) is worth what Auctionator last
--   saw it listed for, times how many.
-- - What can't be sold at auction (bind on pickup, quest items), greys,
--   and anything Auctionator has no price for, or a lower one than a
--   vendor pays, counts at the vendor's price.
-- - Coin that comes in while a vendor's window or the mailbox is open is
--   set aside: it's the price of things already counted when they were
--   looted (or of things from before the session), and adding it on top
--   would count them twice. What you spend there still counts against you.

local CALLER = "ElipsPanels"   -- who's asking, for Auctionator
local BIND_ON_PICKUP, BIND_QUEST = 1, 4

local tally = { value = 0, items = 0, stacks = 0, auction = 0, vendor = 0, unpriced = 0, aside = 0, hidden = 0 }
local moneyBefore
local atVendor, atMail = false, false

-- Auctionator's prices, for other addons to ask: nil without it.
local function Prices()
    local auctionator = rawget(_G, "Auctionator")
    local api = type(auctionator) == "table" and type(auctionator.API) == "table" and auctionator.API.v1 or nil
    if type(api) == "table" and type(api.GetAuctionPriceByItemLink) == "function" then
        return api
    end
    return nil
end

function ns.PricesKnown()
    return Prices() ~= nil
end

local function ItemInfo(link)
    local info = (rawget(_G, "C_Item") and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    if not info then
        return nil
    end
    local ok, name, _, quality, _, _, _, _, _, _, _, sellPrice, _, _, bindType = pcall(info, link)
    if not ok or name == nil then
        return nil
    end
    return ns.Num(quality), ns.Num(sellPrice) or 0, ns.Num(bindType)
end

-- One of them, in copper, and where the price is from: "auction", "vendor",
-- or nil when nothing is known of it.
local function Worth(link)
    local api = Prices()
    if not api then
        return nil
    end
    local quality, vendor, bind = ItemInfo(link)
    local known = vendor ~= nil
    vendor = vendor or 0
    if bind == BIND_ON_PICKUP or bind == BIND_QUEST or quality == 0 then
        return vendor, "vendor"
    end
    local ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
    price = ok and ns.Num(price) or nil
    if price and price > vendor then
        return price, "auction"
    end
    if known and vendor > 0 then
        return vendor, "vendor"
    end
    return 0, nil
end
ns.ItemWorth = Worth

-- "You receive loot: %s." as a pattern that finds what filled it in.
local function AsPattern(sentence)
    if type(sentence) ~= "string" then
        return nil
    end
    local pattern = sentence:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    pattern = pattern:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    pattern = pattern:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. pattern .. "$"
end

local patterns
local function Looted(text)
    if not patterns then
        patterns = {}
        -- (The one with a count first: the plain one would match it too.)
        for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do
            local pattern = AsPattern(rawget(_G, name))
            if pattern then
                patterns[#patterns + 1] = pattern
            end
        end
    end
    for _, pattern in ipairs(patterns) do
        local link, count = text:match(pattern)
        if link then
            return link, tonumber(count) or 1
        end
    end
end

local function LootLine(text)
    if not Prices() then
        return
    end
    if ns.IsSecret(text) then
        tally.hidden = tally.hidden + 1   -- (hidden from addons in some fights)
        return
    end
    if type(text) ~= "string" then
        return
    end
    local link, count = Looted(text)
    if not link then
        return
    end
    local each, from = Worth(link)
    tally.stacks = tally.stacks + 1
    tally.items = tally.items + count
    tally.value = tally.value + (each or 0) * count
    if from == "auction" then
        tally.auction = tally.auction + count
    elseif from == "vendor" then
        tally.vendor = tally.vendor + count
    else
        tally.unpriced = tally.unpriced + count
    end
end

-- Is one of the game's windows really open? (Its closing can go unsaid;
-- the window itself is the better witness when the client has it.)
local function Open(flag, frameName)
    if not flag then
        return false
    end
    local frame = rawget(_G, frameName)
    if type(frame) == "table" and frame.IsShown then
        return frame:IsShown() and true or false
    end
    return true
end

local function MoneyChanged()
    local fn = rawget(_G, "GetMoney")
    local now = fn and ns.Num(fn()) or nil
    local before = moneyBefore
    moneyBefore = now
    if not (now and before) or now <= before or not Prices() then
        return
    end
    if Open(atVendor, "MerchantFrame") or Open(atMail, "MailFrame") then
        tally.aside = tally.aside + (now - before)
    end
end

-- The session's tally: value (copper) of what was looted, how many items,
-- and the coin set aside. The same table for as long as the UI is loaded.
function ns.LootTally()
    return tally
end

-- What to add to the coin gained for the session's earnings.
function ns.LootEarnings()
    return tally.value - tally.aside
end

function ns.LootTallyRestart()
    for key in pairs(tally) do
        tally[key] = 0
    end
    local fn = rawget(_G, "GetMoney")
    moneyBefore = fn and ns.Num(fn()) or nil
end

ns.Hook("INIT", function()
    local fn = rawget(_G, "GetMoney")
    moneyBefore = fn and ns.Num(fn()) or nil
    ns.On("CHAT_MSG_LOOT", LootLine)
    ns.On("PLAYER_MONEY", MoneyChanged)
    ns.On("MERCHANT_SHOW", function() atVendor = true end)
    ns.On("MERCHANT_CLOSED", function() atVendor = false end)
    ns.On("MAIL_SHOW", function() atMail = true end)
    ns.On("MAIL_CLOSED", function() atMail = false end)
end)

ns.statusParts[#ns.statusParts + 1] = function()
    if not Prices() then
        return "Loot value: Auctionator isn't here, so gold per hour is coin alone."
    end
    return string.format("Loot value: %d copper from %d items in %d pick-ups (%d at auction prices, %d at vendor prices, %d with no price) | coin set aside at vendors and the mailbox %d | loot lines hidden from addons %d",
        tally.value, tally.items, tally.stacks, tally.auction, tally.vendor, tally.unpriced, tally.aside, tally.hidden)
end
