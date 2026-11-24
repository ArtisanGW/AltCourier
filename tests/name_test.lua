-- Full names ("First Last"), moving old first-name entries, /ac add and list.
-- Run from the repo root: luajit tests/name_test.lua
local chat = {}
-- Stand-ins for the game, enough to run login + /rpost and read the To: name.
local handlers, frames = {}, {}
local function frame()
  local fakeFrame = setmetatable({}, {__index=function(indexed,key) if type(key)=="string" and key:match("^%u") then return function() end end end})
  fakeFrame.RegisterEvent=function() end
  fakeFrame.SetScript=function(self,scriptName,handler) if scriptName=="OnEvent" then handlers[#handlers+1]=handler end end
  return fakeFrame
end
CreateFrame=function() return frame() end
CreateFramePool=function() return {} end
C_Timer={After=function() end}
wipe=function(wiped) for key in pairs(wiped) do wiped[key]=nil end return wiped end
UnitName=function() return "Reagents" end
UnitFullName=function() return "Reagents", "Artisan" end
GetNormalizedRealmName=function() return "Forever" end
UnitFactionGroup=function() return "Alliance" end
UnitClass=function() return "Mage","MAGE" end
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) chat[#chat+1]=(message:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end}
SlashCmdList={}
-- Saved from before: this character and a picker keyed by first name only.
AltCourierDB={chars={["Reagents-Forever"]={name="Reagents",realm="Forever",faction="Alliance"}}, categories={{rule="reagents",target="Reagents-Forever"}}}
dofile("tests/loader.lua")("AltCourier")
local function fire(event,argument) for _,handler in ipairs(handlers) do handler(nil,event,argument) end end
fire("ADDON_LOADED","AltCourier"); fire("PLAYER_LOGIN")
for key,character in pairs(AltCourierDB.chars) do print("saved:", key, character.name, character.last) end
print("reagents category ->", AltCourierDB.categories[1].target)
SlashCmdList.ALTCOURIER("add skinny hidesworth")
for key,character in pairs(AltCourierDB.chars) do print("saved:", key, character.name, character.last) end
-- Log in as the alt and check what goes in To:
UnitName=function() return "Skinny" end; UnitFullName=function() return "Skinny","Hidesworth" end
fire("PLAYER_LOGIN"); AltCourierDB.categories[2]={rule="leather",target="Reagents Artisan-Forever"}
SlashCmdList.ALTCOURIER("list")

-- Checks
local settings = AltCourierDB
assert(settings.chars["Reagents Artisan-Forever"] and settings.chars["Reagents Artisan-Forever"].last == "Artisan", "login records the last name")
assert(settings.chars["Reagents-Forever"] == nil, "the old first-name entry is moved")
assert(settings.categories[1].target == "Reagents Artisan-Forever", "a category sending to the old entry follows it")
assert(settings.chars["Skinny Hidesworth-Forever"] and settings.chars["Skinny Hidesworth-Forever"].last == "Hidesworth", "/ac add takes First Last")
local listed = table.concat(chat, "\n")
assert(listed:find("Other reagents to Reagents Artisan", 1, true), "/ac list shows full names")
print("name_test: ok")
