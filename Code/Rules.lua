-- What kinds of items a category can take. Most kinds follow the game's
-- professions: a crafting material is a Trade Goods item whose subclass says
-- which profession uses it (herbs for Herbalism, ore for Mining, ...).
-- An item can fit several kinds; the one with the lowest priority number
-- claims it (a Bind on Equip item goes to the Bind on Equip category before
-- anything else, "Everything else" only gets what no other kind wants).
local _, addon = ...

local Rules = {}
addon.Rules = Rules

local CLASS_TRADESKILL = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

Rules.PRIORITY = { BIND_ON_EQUIP = 1, PROFESSION = 2, REAGENTS = 3, EVERYTHING = 4 }

-- In the order the "Add a category" list shows them.
Rules.list = {}
Rules.byId = {}

local function addRule(rule)
    Rules.list[#Rules.list + 1] = rule
    Rules.byId[rule.id] = rule
end

-- A profession's materials: Trade Goods items of these subclasses.
local function addProfession(id, label, subject, detail, subclasses)
    local wanted = {}
    for _, subclassID in ipairs(subclasses) do wanted[subclassID] = true end
    addRule({
        id = id, label = label, subject = subject, detail = detail,
        priority = Rules.PRIORITY.PROFESSION,
        matches = function(item) return item.classID == CLASS_TRADESKILL and wanted[item.subclassID] == true end,
    })
end

addRule({
    id = "boe", label = "Bind on Equip", subject = "Bind on Equip",
    detail = "Gear that isn't bound to you yet.",
    priority = Rules.PRIORITY.BIND_ON_EQUIP,
    matches = function(item) return item.bindType == BIND_ON_EQUIP end,
})
-- Trade Goods subclass numbers (Enum.ItemTradeGoodsSubclass): 1 parts, 2 explosives,
-- 3 devices, 4 jewelcrafting, 5 cloth, 6 leather, 7 metal and stone, 8 cooking,
-- 9 herbs, 12 enchanting, 16 inscription.
addProfession("herbs", "Herbalism", "Herbs", "Herbs.", { 9 })
addProfession("ore", "Mining", "Ore and stone", "Ore, bars and stone.", { 7 })
addProfession("leather", "Skinning", "Pelts", "Leather, hides and pelts.", { 6 })
addProfession("cloth", "Tailoring", "Cloth", "Cloth.", { 5 })
addProfession("cooking", "Cooking", "Cooking", "Meat, fish and other cooking ingredients.", { 8 })
addProfession("enchanting", "Enchanting", "Enchanting", "Dusts, essences and shards.", { 12 })
addProfession("jewelcrafting", "Jewelcrafting", "Jewelcrafting", "Gems and what is cut from them.", { 4 })
addProfession("engineering", "Engineering", "Engineering", "Parts, explosives and devices.", { 1, 2, 3 })
addProfession("inscription", "Inscription", "Inscription", "Pigments, inks and parchment.", { 16 })

addRule({
    id = "reagents", label = "Other reagents", subject = "Reagents",
    detail = "Any crafting material the categories above don't take.",
    priority = Rules.PRIORITY.REAGENTS,
    matches = function(item) return item.classID == CLASS_TRADESKILL or item.isCraftingReagent == true end,
})
addRule({
    id = "everything", label = "Everything else", subject = "Items",
    detail = "Anything that isn't bound to you and that no other category takes.\n\nFor one bank alt that gets it all.",
    priority = Rules.PRIORITY.EVERYTHING,
    matches = function() return true end,
})

-- The old fixed kinds, before categories could be added or removed.
Rules.DEFAULT_IDS = { "reagents", "leather", "boe" }

-- What the rules need to know about an item in a bag.
-- info: C_Container.GetContainerItemInfo
function Rules.Describe(info)
    local link = info.hyperlink or info.itemID
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(info.itemID)
    return {
        classID = classID,
        subclassID = subclassID,
        bindType = select(14, GetItemInfo(link)),
        -- Some crafting materials live outside Trade Goods; the item says so.
        isCraftingReagent = select(17, GetItemInfo(info.itemID)) and true or false,
    }
end
