-- Full names ("First Last"), moving old first-name entries, /ygm add and list.
-- Run from the repo root: luajit tests/name_test.lua
local chat = {}
-- Stand-ins for the game, enough to run login + /rpost and read the To: name.
local handlers, frames = {}, {}
local function frame()
  local f = setmetatable({}, {__index=function(t,k) return function(...) end end})
  f.RegisterEvent=function() end
  f.SetScript=function(self,n,fn) if n=="OnEvent" then handlers[#handlers+1]=fn end end
  return f
end
CreateFrame=function() return frame() end
C_Timer={After=function() end}
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
UnitName=function() return "Reagents" end
UnitFullName=function() return "Reagents", "Artisan" end
GetNormalizedRealmName=function() return "Forever" end
UnitFactionGroup=function() return "Alliance" end
UnitClass=function() return "Mage","MAGE" end
DEFAULT_CHAT_FRAME={AddMessage=function(_,m) chat[#chat+1]=(m:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end}
SlashCmdList={}
-- Saved from before: this character and a picker keyed by first name only.
YouGotMailDB={chars={["Reagents-Forever"]={name="Reagents",realm="Forever",faction="Alliance"}}, targets={reagents="Reagents-Forever"}}
local chunk=assert(loadfile("YouGotMail.lua")); chunk("YouGotMail")
local function fire(e,a) for _,fn in ipairs(handlers) do fn(nil,e,a) end end
fire("ADDON_LOADED","YouGotMail"); fire("PLAYER_LOGIN")
for k,c in pairs(YouGotMailDB.chars) do print("saved:", k, c.name, c.last) end
print("reagents picker ->", YouGotMailDB.targets.reagents)
SlashCmdList.YOUGOTMAIL("add skinny hidesworth")
for k,c in pairs(YouGotMailDB.chars) do print("saved:", k, c.name, c.last) end
-- Log in as the alt and check what goes in To:
UnitName=function() return "Skinny" end; UnitFullName=function() return "Skinny","Hidesworth" end
fire("PLAYER_LOGIN"); YouGotMailDB.targets.pelts="Reagents Artisan-Forever"
SlashCmdList.YOUGOTMAIL("list")

-- Checks
local db = YouGotMailDB
assert(db.chars["Reagents Artisan-Forever"] and db.chars["Reagents Artisan-Forever"].last == "Artisan", "login records the last name")
assert(db.chars["Reagents-Forever"] == nil, "the old first-name entry is moved")
assert(db.targets.reagents == "Reagents Artisan-Forever", "a picker set to the old entry follows it")
assert(db.chars["Skinny Hidesworth-Forever"] and db.chars["Skinny Hidesworth-Forever"].last == "Hidesworth", "/ygm add takes First Last")
local listed = table.concat(chat, "\n")
assert(listed:find("Reagents to Reagents Artisan", 1, true), "/ygm list shows full names")
print("name_test: ok")
