-- Exclusions: items and words never sent, and /altc include undoing them.
-- Run from the repo root: luajit tests/exclusions_test.lua (run.sh runs it).
local addon = { settings = { exclude = { items = {}, words = {} } }, Print = function() end, Refresh = function() end }
assert(loadfile("Exclusions.lua"))("AltCourier", addon)
local Exclusions = addon.Exclusions
local link = "|Hitem:123:|h[Silk Cloth]|h"
assert(Exclusions.ItemIDOf(link) == 123 and Exclusions.NameOf(link) == "Silk Cloth", "reads an item link")
Exclusions.AddItem(123, "Silk Cloth"); Exclusions.AddWord("Potion"); Exclusions.AddWord("potion")
assert(Exclusions.Count() == 2, "one item and one word (a word is kept once, in lower case)")
assert(Exclusions.Has(123, "Silk Cloth"), "an excluded item")
assert(Exclusions.Has(9, "Greater Healing Potion"), "a name holding an excluded word")
assert(not Exclusions.Has(9, "Linen Cloth"), "anything else is sent")
Exclusions.Include("silk cloth"); Exclusions.Include("Potion")
assert(Exclusions.Count() == 0, "include by the item's name, and by the word")
print("exclusions_test: ok")
