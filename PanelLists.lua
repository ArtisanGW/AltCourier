-- The panel's popup lists: who gets a category, which category to add, and
-- what's never sent. Each choice saves, redraws the panel and fills again.
local _, addon = ...
local PanelLists = {}
addon.PanelLists = PanelLists

local function changed()
    addon.Refresh()
    addon.Run.Refill()
end

function PanelLists.Recipients(owner, category)
    local Characters = addon.Characters
    local function choose(key)
        category.target = key
        changed()
    end
    local entries = { { text = "|cff888888None|r", onClick = function() choose(nil) end } }
    for _, key in ipairs(Characters.Mailable()) do
        entries[#entries + 1] = { text = Characters.ColoredName(key), onClick = function() choose(key) end }
    end
    addon.Picker.Open(owner, category.rule, entries)
    if #entries == 1 then
        addon.Print("No alts known yet. Log into each alt once with Alt Courier on, or use /ac add First Last.")
    end
end

function PanelLists.AddCategory(owner)
    local entries = {}
    for _, rule in ipairs(addon.Categories.Unused()) do
        entries[#entries + 1] = { text = rule.label, onClick = function()
            addon.Categories.Add(rule.id)
            changed()
        end }
    end
    if #entries == 0 then entries[1] = { text = "|cff888888All added|r" } end
    addon.Picker.Open(owner, "add", entries)
end

function PanelLists.Excluded(owner)
    local Exclusions = addon.Exclusions
    local entries = {}
    for _, word in ipairs(Exclusions.Words()) do
        entries[#entries + 1] = { text = "Name has \"" .. word .. "\"  |cffff5555x|r", onClick = function()
            Exclusions.RemoveWord(word)
            changed()
        end }
    end
    for _, item in ipairs(Exclusions.Items()) do
        entries[#entries + 1] = { text = item.name .. "  |cffff5555x|r", onClick = function()
            Exclusions.RemoveItem(item.itemID)
            changed()
        end }
    end
    if #entries == 0 then
        entries[1] = { text = "|cff888888Alt-click an attached item|r" }
    end
    addon.Picker.Open(owner, "excluded", entries)
end
