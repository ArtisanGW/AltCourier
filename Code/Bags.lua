-- What's in the bags to send: every bag item a category takes (not bound,
-- not locked, not excluded), and the next mail made from them.
local _, addon = ...
local Bags = {}
addon.Bags = Bags

local NUM_BAGS = NUM_BAG_SLOTS or 4

-- Every bag item a category takes: ordered categories, and the slots of each by rule id.
local function scanBags()
    local Categories, Exclusions = addon.Categories, addon.Exclusions
    local ordered = Categories.Ordered()
    local slotsByRule = {}
    for bag = 0, NUM_BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not info.isLocked
                and not Exclusions.Has(info.itemID, Exclusions.NameOf(info.hyperlink)) then
                local category = Categories.Claim(ordered, addon.Rules.Describe(info))
                if category then
                    slotsByRule[category.rule] = slotsByRule[category.rule] or {}
                    table.insert(slotsByRule[category.rule], { bag = bag, slot = slot })
                end
            end
        end
    end
    return ordered, slotsByRule
end

local function isSendable(category, slotsByRule, skipped)
    return slotsByRule[category.rule] ~= nil and not skipped[category.rule] and addon.Characters.CanMail(category.target)
end

-- The next mail: the first category with something to send and an alt to get it,
-- plus every other category going to that same alt, so one bank alt gets one
-- mail, not one per kind. nil when nothing is left. skipped: { [rule id] = true }.
function Bags.NextBatch(skipped)
    local ordered, slotsByRule = scanBags()
    for _, category in ipairs(ordered) do
        if isSendable(category, slotsByRule, skipped) then
            local batch = { target = category.target, items = {}, rules = {} }
            for _, other in ipairs(ordered) do
                if other.target == category.target and isSendable(other, slotsByRule, skipped) then
                    batch.rules[#batch.rules + 1] = other.rule
                    for _, item in ipairs(slotsByRule[other.rule]) do batch.items[#batch.items + 1] = item end
                end
            end
            return batch
        end
    end
end

-- What is ready to go, said in a line: "14 items for Bob, 3 for Carol".
function Bags.ReadySummary(skipped)
    local ordered, slotsByRule = scanBags()
    local countByTarget, targets = {}, {}
    for _, category in ipairs(ordered) do
        if isSendable(category, slotsByRule, skipped) then
            if not countByTarget[category.target] then
                countByTarget[category.target] = 0
                targets[#targets + 1] = category.target
            end
            countByTarget[category.target] = countByTarget[category.target] + #slotsByRule[category.rule]
        end
    end
    local parts = {}
    for _, target in ipairs(targets) do
        parts[#parts + 1] = ("%d for %s"):format(countByTarget[target], addon.Characters.ColoredName(target))
    end
    return table.concat(parts, ", ")
end
