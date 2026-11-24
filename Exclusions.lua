-- Items never mailed: picked one by one (Alt-click an attachment, /ac exclude [item]),
-- or any item whose name holds a word (/ac exclude word). Kept in
-- AltCourierDB.exclude = { items = { [itemID] = name }, words = { word } }.
local _, addon = ...
local Exclusions = {}
addon.Exclusions = Exclusions

local function excluded() return addon.settings.exclude end

function Exclusions.ItemIDOf(link) return link and tonumber(link:match("item:(%d+)")) end
function Exclusions.NameOf(link) return link and link:match("%[(.-)%]") end

-- Never mailed: items picked one by one, or any item whose name holds a word.
function Exclusions.Has(itemID, name)
    if excluded().items[itemID] then return true end
    name = name and name:lower()
    if name then
        for _, word in ipairs(excluded().words) do
            if name:find(word, 1, true) then return true end
        end
    end
    return false
end

function Exclusions.Count()
    local count = #excluded().words
    for _ in pairs(excluded().items) do count = count + 1 end
    return count
end

function Exclusions.AddItem(itemID, name)
    if not itemID then return end
    local items = excluded().items
    items[itemID] = name or items[itemID] or ("item " .. itemID)
    addon.Print("Won't send " .. items[itemID] .. " any more. /ac excluded to undo.")
    addon.Refresh()
end

function Exclusions.AddWord(word)
    word = word:lower()
    for _, existing in ipairs(excluded().words) do if existing == word then return end end
    table.insert(excluded().words, word)
    addon.Print("Won't send items with \"" .. word .. "\" in their name.")
    addon.Refresh()
end

function Exclusions.RemoveWord(word)
    for index, existing in ipairs(excluded().words) do
        if existing == word then table.remove(excluded().words, index) break end
    end
end

function Exclusions.RemoveItem(itemID) excluded().items[itemID] = nil end

-- /ac include: an item link, a word, or an excluded item's name, sent again.
function Exclusions.Include(text)
    local itemID = Exclusions.ItemIDOf(text)
    local word = text:lower()
    if itemID then Exclusions.RemoveItem(itemID) end
    Exclusions.RemoveWord(word)
    for id, name in pairs(excluded().items) do
        if name:lower() == word then excluded().items[id] = nil end
    end
end

function Exclusions.Words() return excluded().words end

-- The excluded items, by name: { { itemID, name } }.
function Exclusions.Items()
    local list = {}
    for itemID, name in pairs(excluded().items) do list[#list + 1] = { itemID = itemID, name = name } end
    table.sort(list, function(first, second) return first.name < second.name end)
    return list
end
