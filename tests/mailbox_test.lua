-- A mailbox visit with stand-ins for the game: the game's mailbox on screen (open),
-- or covered by another addon's mail window (covered). No other addon is loaded.
-- Run from the repo root: luajit tests/mailbox_test.lua open|covered
local mode = arg[1]
local handlers, calls = {}, {}
local function frame(name)
  local f = { shown = true, parent = nil, text = nil }
  local mt = { __index = function(t, k) if type(k) == "string" and k:match("^%u") then return function() end end end }
  setmetatable(f, mt)
  f.RegisterEvent = function() end
  f.SetScript = function(self, n, fn) if n == "OnEvent" then handlers[#handlers + 1] = fn end self[n] = fn end
  f.HookScript = function(self, n, fn) self["hook" .. n] = fn end
  f.IsShown = function(self) return self.shown end
  f.Show = function(self) self.shown = true; calls[#calls + 1] = "Show " .. tostring(self.name) end
  f.Hide = function(self) self.shown = false end
  f.SetParent = function(self, p) self.parent = p end
  f.GetWidth = function() return 120 end
  f.CreateFontString = function() local s = setmetatable({}, mt); s.SetText = function(_, t) s.text = t end; return s end
  f.SetText = function(self, t) self.text = t end
  f.name = name
  return f
end
CreateFrame = function(_, name, parent, template)
  local f = frame(name)
  if name == "AltCourierPanel" then _G.P = f end
  if template == "UIPanelCloseButton" and not _G.CLOSE then _G.CLOSE = f end -- the panel's own, made before any row
  return f
end
CreateFramePool = function(_, parent) return { Acquire = function() return frame("row") end, ReleaseAll = function() end } end
local timers = {}; C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function run() for _ = 1, 5 do local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
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
C_Container = { GetContainerNumSlots = function(b) return b == 0 and #items or 0 end,
  GetContainerItemInfo = function(b, s) local it = b == 0 and items[s]; if not it then return nil end
    return { itemID = it.id, hyperlink = "|Hitem:" .. it.id .. ":|h[" .. it.name .. "]|h", isLocked = false } end,
  PickupContainerItem = function(b, s) picked = items[s] end }
local byId = {}; for _, it in ipairs(items) do byId[it.id] = it end
C_Item = { GetItemInfoInstant = function(id) local it = byId[id]; return id, nil, nil, nil, nil, it.class, it.sub end,
  GetItemInfo = function(l) local id = type(l) == "number" and l or tonumber(l:match("item:(%d+)")); local r = {}; r[14] = byId[id].bind; return unpack(r, 1, 17) end }
local attached = {}; HasSendMailItem = function(i) return attached[i] ~= nil end
ClickSendMailItemButton = function(i) attached[i] = picked.name; picked = nil end
CursorHasItem = function() return false end; ClearCursor = function() end
local to; SendMailNameEditBox = frame("to"); SendMailNameEditBox.SetText = function(_, t) to = t end; SendMailNameEditBox.GetText = function() return to or "" end
local subject; SendMailSubjectEditBox = frame("subject"); SendMailSubjectEditBox.SetText = function(_, t) subject = t end
AltCourierDB = { chars = { ["Bob Smith-Forever"] = { name = "Bob", last = "Smith", realm = "Forever", faction = "Alliance" } },
  categories = { { rule = "boe", target = "Bob Smith-Forever" }, { rule = "reagents", target = "Bob Smith-Forever" } } }
require = nil
local addon = dofile("tests/loader.lua")("AltCourier")
local function fire(e, a) for _, fn in ipairs(handlers) do fn(nil, e, a) end end
fire("ADDON_LOADED", "AltCourier"); fire("PLAYER_LOGIN")
fire("MAIL_SHOW"); run()
local function plain(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
print(mode .. ": panel parent=" .. tostring(P.parent and P.parent.name), "status=" .. plain(P.status.text))
assert(not next(attached), "nothing is attached before Start")
P.start.OnClick(P.start); run()
if mode == "open" then
  assert(not next(attached), "Start does nothing until the Send Mail tab is open")
  SendMailFrame.shown = true; SendMailFrame.hookOnShow(); P.start.OnClick(P.start); run()
end
print("  attached:", attached[1] or "none", "| To:", to, "| status:", plain(P.status.text))
for _, c in ipairs(calls) do if c:find("MailFrame") then print("  !! addon showed a game window:", c) end end

-- Typing in the mail takes it from us: it stops.
SendMailNameEditBox.hookOnTextChanged(SendMailNameEditBox, true)
assert(P.status.text:find("stopped"), "typing in the mail stops the run")
-- The game's mailbox goes away without MAIL_CLOSED (it sat under another window).
MailFrame.shown = false
if P.OnUpdate then P.OnUpdate(P, 0.3) end
print("  mailbox gone, no event -> panel shown:", P.shown)
-- Next visit, then the X.
MailFrame.shown = true; fire("MAIL_SHOW"); run()
print("  next visit -> panel shown:", P.shown)
if CLOSE and CLOSE.OnClick then CLOSE.OnClick(CLOSE) print("  X pressed -> panel shown:", P.shown) end

-- Checks
for _, c in ipairs(calls) do assert(not c:find("MailFrame"), "the addon never shows the game's windows: " .. c) end
assert(attached[1] == "Sword" and attached[2] == "Linen Cloth", "both kinds for the same alt go in one mail")
assert(subject == "Items", "a mixed mail is subject Items")
assert(to == "Bob Smith", "To: gets the full name")
if mode == "open" then
  assert(P.parent == MailFrame, "the panel sits on the game's mailbox")
else
  assert(P.parent == UIParent, "under another mail window, the panel floats")
  assert(P.shown == false, "the X hides the floating panel")
end
print("mailbox_test " .. mode .. ": ok")
