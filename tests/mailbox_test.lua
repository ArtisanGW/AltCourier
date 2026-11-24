-- A mailbox visit with stand-ins for the game: the game's mailbox on screen (open),
-- or covered by another addon's mail window (covered). No other addon is loaded.
-- Run from the repo root: luajit tests/mailbox_test.lua open|covered
local mode = arg[1]
local handlers, calls = {}, {}
local function frame(name)
  local fakeFrame = { shown = true, parent = nil, text = nil }
  local frameMetatable = { __index = function(indexed, key) if type(key) == "string" and key:match("^%u") then return function() end end end }
  setmetatable(fakeFrame, frameMetatable)
  fakeFrame.RegisterEvent = function() end
  fakeFrame.SetScript = function(self, scriptName, handler) if scriptName == "OnEvent" then handlers[#handlers + 1] = handler end self[scriptName] = handler end
  fakeFrame.HookScript = function(self, scriptName, handler) self["hook" .. scriptName] = handler end
  fakeFrame.IsShown = function(self) return self.shown end
  fakeFrame.Show = function(self) self.shown = true; calls[#calls + 1] = "Show " .. tostring(self.name) end
  fakeFrame.Hide = function(self) self.shown = false end
  fakeFrame.SetParent = function(self, newParent) self.parent = newParent end
  fakeFrame.GetWidth = function() return 120 end
  fakeFrame.CreateFontString = function() local fontString = setmetatable({}, frameMetatable); fontString.SetText = function(_, newText) fontString.text = newText end; return fontString end
  fakeFrame.SetText = function(self, newText) self.text = newText end
  fakeFrame.name = name
  return fakeFrame
end
CreateFrame = function(_, name, parent, template)
  local fakeFrame = frame(name)
  if name == "AltCourierPanel" then _G.courierPanel = fakeFrame end
  if template == "UIPanelCloseButton" and not _G.CLOSE then _G.CLOSE = fakeFrame end -- the panel's own, made before any row
  return fakeFrame
end
CreateFramePool = function(_, parent) return { Acquire = function() return frame("row") end, ReleaseAll = function() end } end
local timers = {}; C_Timer = { After = function(_, handler) timers[#timers + 1] = handler end }
local function run() for _ = 1, 5 do local dueTimers = timers; timers = {}; for _, handler in ipairs(dueTimers) do handler() end end end
wipe = function(wiped) for key in pairs(wiped) do wiped[key] = nil end return wiped end
UnitName = function() return "Reagents" end; UnitFullName = function() return "Reagents", "Artisan" end
GetNormalizedRealmName = function() return "Forever" end; UnitFactionGroup = function() return "Alliance" end
UnitClass = function() return "Mage", "MAGE" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }; SlashCmdList = {}
UIParent = frame("UIParent"); UIParent.GetEffectiveScale = function() return 1 end
UIParent.GetWidth = function() return 1920 end; UIParent.GetHeight = function() return 1080 end
MailFrame = frame("MailFrame"); SendMailFrame = frame("SendMailFrame"); SendMailFrame.shown = false
MailFrame.GetEffectiveAlpha = function() return 1 end; MailFrame.GetEffectiveScale = function() return 1 end
MailFrame.GetLeft = function() return 100 end; MailFrame.GetRight = function() return 450 end
MailFrame.GetBottom = function() return 300 end; MailFrame.GetTop = function() return 800 end
MailFrame.IsVisible = function() return mode == "open" end   -- covered: parked under a hidden frame by another mail window
local items = { { id = 1, name = "Sword", class = 2, sub = 7, bind = 2 }, { id = 3, name = "Linen Cloth", class = 7, sub = 5, bind = 0 } }
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and #items or 0 end,
  GetContainerItemInfo = function(bag, slot) local item = bag == 0 and items[slot]; if not item then return nil end
    return { itemID = item.id, hyperlink = "|Hitem:" .. item.id .. ":|h[" .. item.name .. "]|h", isLocked = false } end,
  PickupContainerItem = function(bag, slot) picked = items[slot] end }
local byId = {}; for _, item in ipairs(items) do byId[item.id] = item end
C_Item = { GetItemInfoInstant = function(id) local item = byId[id]; return id, nil, nil, nil, nil, item.class, item.sub end,
  GetItemInfo = function(itemLink) local id = type(itemLink) == "number" and itemLink or tonumber(itemLink:match("item:(%d+)")); local itemInfo = {}; itemInfo[14] = byId[id].bind; return unpack(itemInfo, 1, 17) end }
local attached = {}; HasSendMailItem = function(i) return attached[i] ~= nil end
ClickSendMailItemButton = function(i) attached[i] = picked.name; picked = nil end
CursorHasItem = function() return false end; ClearCursor = function() end
local recipient; SendMailNameEditBox = frame("to"); SendMailNameEditBox.SetText = function(_, newText) recipient = newText end; SendMailNameEditBox.GetText = function() return recipient or "" end
local subject; SendMailSubjectEditBox = frame("subject"); SendMailSubjectEditBox.SetText = function(_, newText) subject = newText end
AltCourierDB = { chars = { ["Bob Smith-Forever"] = { name = "Bob", last = "Smith", realm = "Forever", faction = "Alliance" } },
  categories = { { rule = "boe", target = "Bob Smith-Forever" }, { rule = "reagents", target = "Bob Smith-Forever" } } }
require = nil
local addon = dofile("tests/loader.lua")("AltCourier")
local function fire(event, argument) for _, handler in ipairs(handlers) do handler(nil, event, argument) end end
fire("ADDON_LOADED", "AltCourier"); fire("PLAYER_LOGIN")
fire("MAIL_SHOW"); run()
local function plain(text) return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
print(mode .. ": panel parent=" .. tostring(courierPanel.parent and courierPanel.parent.name), "status=" .. plain(courierPanel.status.text))
assert(not next(attached), "nothing is attached before Start")
courierPanel.start.OnClick(courierPanel.start); run()
if mode == "open" then
  assert(not next(attached), "Start does nothing until the Send Mail tab is open")
  SendMailFrame.shown = true; SendMailFrame.hookOnShow(); courierPanel.start.OnClick(courierPanel.start); run()
end
print("  attached:", attached[1] or "none", "| To:", recipient, "| status:", plain(courierPanel.status.text))
for _, call in ipairs(calls) do if call:find("MailFrame") then print("  !! addon showed a game window:", call) end end

-- Typing in the mail takes it from us: it stops.
SendMailNameEditBox.hookOnTextChanged(SendMailNameEditBox, true)
assert(courierPanel.status.text:find("stopped"), "typing in the mail stops the run")
-- The game's mailbox goes away without MAIL_CLOSED (it sat under another window).
MailFrame.shown = false
if courierPanel.OnUpdate then courierPanel.OnUpdate(courierPanel, 0.3) end
print("  mailbox gone, no event -> panel shown:", courierPanel.shown)
-- Next visit, then the X.
MailFrame.shown = true; fire("MAIL_SHOW"); run()
print("  next visit -> panel shown:", courierPanel.shown)
if CLOSE and CLOSE.OnClick then CLOSE.OnClick(CLOSE) print("  X pressed -> panel shown:", courierPanel.shown) end

-- Checks
for _, call in ipairs(calls) do assert(not call:find("MailFrame"), "the addon never shows the game's windows: " .. call) end
assert(attached[1] == "Sword" and attached[2] == "Linen Cloth", "both kinds for the same alt go in one mail")
assert(subject == "Items", "a mixed mail is subject Items")
assert(recipient == "Bob Smith", "To: gets the full name")
if mode == "open" then
  assert(courierPanel.parent == MailFrame, "the panel sits on the game's mailbox")
else
  assert(courierPanel.parent == UIParent, "under another mail window, the panel floats")
  assert(courierPanel.shown == false, "the X hides the floating panel")
end

print("mailbox_test " .. mode .. ": ok")
