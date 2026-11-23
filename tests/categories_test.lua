-- Categories (add, remove, who claims an item), moving an old save, and mailing
-- other accounts only when the player has agreed. Run from the repo root.
local handlers = {}
local function frame()
  local f = setmetatable({}, {__index=function(_,k) if type(k)=="string" and k:match("^%u") then return function() end end end})
  f.SetScript=function(self,n,fn) if n=="OnEvent" then handlers[#handlers+1]=fn end end
  return f
end
CreateFrame=function() return frame() end
CreateFramePool=function() return {} end
C_Timer={After=function() end}
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
UnitName=function() return "Me" end; UnitFullName=function() return "Me","Mage" end
GetNormalizedRealmName=function() return "Forever" end; UnitFactionGroup=function() return "Alliance" end
UnitClass=function() return "Mage","MAGE" end
DEFAULT_CHAT_FRAME={AddMessage=function() end}; SlashCmdList={}
-- An old save: one alt per fixed kind.
AltCourierDB={chars={["Bob Smith-Forever"]={name="Bob",last="Smith",realm="Forever",faction="Alliance"}},
  targets={reagents="Bob Smith-Forever", pelts="Bob Smith-Forever"}}
local addon=dofile("tests/loader.lua")("AltCourier")
local function fire(e,a) for _,fn in ipairs(handlers) do fn(nil,e,a) end end
fire("ADDON_LOADED","AltCourier"); fire("PLAYER_LOGIN")
local settings, Categories, Rules, Characters = AltCourierDB, addon.Categories, addon.Rules, addon.Characters

-- The old save moves over.
assert(settings.targets == nil, "old targets are gone")
assert(Categories.Find("reagents").target == "Bob Smith-Forever" and Categories.Find("leather").target == "Bob Smith-Forever", "old pickers kept")
assert(Categories.Find("boe") and Categories.Find("boe").target == nil, "BoE stays, with no alt")

-- Add and remove.
Categories.Add("herbs"); Categories.Add("herbs")
local count = 0; for _, c in ipairs(settings.categories) do if c.rule == "herbs" then count = count + 1 end end
assert(count == 1, "a kind is added once")
Categories.Remove("herbs"); assert(not Categories.Find("herbs"), "a category can be removed")

-- Who claims an item: BoE first, a profession before the catch-alls.
Categories.Add("herbs"); Categories.Add("everything")
local ordered = Categories.Ordered()
local ids = {}; for _, c in ipairs(ordered) do ids[#ids+1] = c.rule end
assert(table.concat(ids, ",") == "boe,herbs,leather,reagents,everything", "order: " .. table.concat(ids, ","))
local function claimed(item) local c = Categories.Claim(ordered, item); return c and c.rule end
assert(claimed({ classID = 7, subclassID = 9 }) == "herbs", "an herb goes to Herbalism")
assert(claimed({ classID = 7, subclassID = 6 }) == "leather", "leather goes to Skinning")
assert(claimed({ classID = 7, subclassID = 5 }) == "reagents", "cloth with no Tailoring category goes to other reagents")
assert(claimed({ classID = 2, subclassID = 7, bindType = 2 }) == "boe", "BoE gear goes to BoE")
assert(claimed({ classID = 0, subclassID = 1 }) == "everything", "a potion goes to everything else")
Categories.Remove("everything"); ordered = Categories.Ordered()
assert(claimed({ classID = 0, subclassID = 1 }) == nil, "without everything else, a potion stays")

-- One alt, forgotten: no category sends to them.
settings.chars["Eve Jones-Forever"] = { name = "Eve", last = "Jones", realm = "Forever", faction = "Alliance" }
assert(Characters.CanMail("Eve Jones-Forever"), "same account, same realm: mailable")
assert(Characters.Remove("Bob Smith-Forever") and Categories.Find("reagents").target == nil, "removing an alt clears their categories")

-- Other accounts: typed in, and mailed only after the player agreed.
local key = Characters.Add("Zed Other", true)
assert(settings.chars[key].otherAccount, "typed-in other-account character is marked")
assert(not Characters.CanMail(key), "not mailable until agreed")
settings.crossAccount = true
assert(Characters.CanMail(key), "mailable once agreed")
settings.crossAccount = false
assert(not Characters.CanMail(key), "and not any more when turned off")
assert(settings.crossAccount == false, "off by default")
print("categories_test: ok")
