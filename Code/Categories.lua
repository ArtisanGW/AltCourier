-- The categories the player keeps: each is one kind of item (Rules.lua) and the
-- alt who gets it. They can be added and removed; one alt can have several, a
-- category can have no alt (its items stay in the bags).
-- Saved as settings.categories = { { rule = "herbs", target = "Bob Smith-Forever" }, ... }.
local _, addon = ...

local Categories = {}
addon.Categories = Categories

local function database() return addon.settings end

-- Starts a new player with the old fixed three, and moves an older save's
-- settings.targets (one alt per fixed kind) over to categories.
function Categories.Load()
    local settings = database()
    if settings.categories then return end
    local oldTargets = settings.targets or {}
    local oldNames = { reagents = "reagents", leather = "pelts", boe = "boe" }
    settings.categories = {}
    for _, ruleId in ipairs(addon.Rules.DEFAULT_IDS) do
        settings.categories[#settings.categories + 1] = { rule = ruleId, target = oldTargets[oldNames[ruleId]] }
    end
    settings.targets = nil
end

function Categories.Find(ruleId)
    for _, category in ipairs(database().categories) do
        if category.rule == ruleId then return category end
    end
end

local function ruleIndex(ruleId)
    for index, rule in ipairs(addon.Rules.list) do
        if rule.id == ruleId then return index end
    end
    return math.huge
end

-- Who claims an item first: lowest priority number, then the order of Rules.list.
-- Returned as a new list, so the saved one keeps the order it was added in.
function Categories.Ordered()
    local ordered = {}
    for _, category in ipairs(database().categories) do
        if addon.Rules.byId[category.rule] then ordered[#ordered + 1] = category end
    end
    table.sort(ordered, function(first, second)
        local firstRule, secondRule = addon.Rules.byId[first.rule], addon.Rules.byId[second.rule]
        if firstRule.priority ~= secondRule.priority then return firstRule.priority < secondRule.priority end
        return ruleIndex(first.rule) < ruleIndex(second.rule)
    end)
    return ordered
end

-- The kinds that aren't a category yet, for the "Add a category" list.
function Categories.Unused()
    local unused = {}
    for _, rule in ipairs(addon.Rules.list) do
        if not Categories.Find(rule.id) then unused[#unused + 1] = rule end
    end
    return unused
end

function Categories.Add(ruleId)
    if not addon.Rules.byId[ruleId] or Categories.Find(ruleId) then return end
    local categories = database().categories
    categories[#categories + 1] = { rule = ruleId }
end

function Categories.Remove(ruleId)
    local categories = database().categories
    for index, category in ipairs(categories) do
        if category.rule == ruleId then table.remove(categories, index) return end
    end
end

-- Which category takes an item: the first of `ordered` whose kind fits it.
function Categories.Claim(ordered, item)
    for _, category in ipairs(ordered) do
        if addon.Rules.byId[category.rule].matches(item) then return category end
    end
end

-- An alt was forgotten: no category sends to them any more.
function Categories.ForgetTarget(key)
    for _, category in ipairs(database().categories) do
        if category.target == key then category.target = nil end
    end
end

-- An alt's saved key changed (the same character, saved under a better name).
function Categories.RenameTarget(oldKey, newKey)
    for _, category in ipairs(database().categories) do
        if category.target == oldKey then category.target = newKey end
    end
end
