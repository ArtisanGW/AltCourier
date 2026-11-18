-- The mailbox, on its own (vanilla) and as a Daylight UI plugin with the game's mailbox
-- covered by another window (daylight).
-- Run from the repo root: luajit tests/plugin_test.lua DeliveriesForever.lua vanilla|daylight
local file, mode = arg[1], arg[2]
local handlers, calls = {}, {}
local function frame(name)
  local f = { shown = true, parent = nil, text = nil }
  local mt = { __index = function(t, k) return function() end end }
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
CreateFrame = function(_, name) local f = frame(name); if name == "DeliveriesForeverPanel" then _G.P = f end return f end
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
MailFrame.IsVisible = function() return mode == "vanilla" end   -- parked under a hidden frame by another mail window
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
local to; SendMailNameEditBox = { SetText = function(_, t) to = t end }; SendMailSubjectEditBox = { SetText = function() end }
if mode == "daylight" then
  local reg = {}
  local API = { major = 1, minor = 10,
    For = function(name) reg.handle = name; return { On = function(ev) reg["on" .. ev] = true end,
      RegisterCommand = function(n) reg.command = n end } end,
    Skin = function(f, o) reg.skinned = (reg.skinned or 0) + 1 end,
    Text = function(parent) reg.texts = (reg.texts or 0) + 1; return parent:CreateFontString() end,
    Button = function(parent, t, h) reg.buttons = (reg.buttons or 0) + 1; return frame("dui button") end,
    Menu = function(owner, keys, values, cur, onPick) reg.menu = values end,
    Close = function(parent, fn) reg.close = fn; return frame("dui close") end,
    Colors = function() return { TEXT = { 0.9, 0.9, 0.9 }, TITLE = { 1, 1, 1 } } end }
  DaylightUI = { API = API, RegisterPlugin = function(self, name, o) reg.plugin = name; reg.needs = o.needs end }
  REG = reg
end
DeliveriesForeverDB = { chars = { ["Bob Smith-Forever"] = { name = "Bob", last = "Smith", realm = "Forever", faction = "Alliance" } },
  targets = { boe = "Bob Smith-Forever", reagents = "Bob Smith-Forever" } }
assert(loadfile(file))("DeliveriesForever")
local function fire(e, a) for _, fn in ipairs(handlers) do fn(nil, e, a) end end
fire("ADDON_LOADED", "DeliveriesForever"); fire("PLAYER_LOGIN")
fire("MAIL_SHOW"); run()
local function plain(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
print(mode .. ": panel parent=" .. tostring(P.parent and P.parent.name), "status=" .. plain(P.status.text))
print("  attached before Send tab:", next(attached) and attached[1] or "none")
if mode == "vanilla" then SendMailFrame.shown = true; SendMailFrame.hookOnShow(); run() end
print("  attached:", attached[1] or "none", "| To:", to, "| status:", plain(P.status.text))
for _, c in ipairs(calls) do if c:find("MailFrame") then print("  !! addon showed a game window:", c) end end
if REG then print("  daylight: plugin=" .. tostring(REG.plugin), "needs=" .. table.concat(REG.needs, "."), "skinned=" .. tostring(REG.skinned),
  "buttons=" .. tostring(REG.buttons), "/dui " .. tostring(REG.command), "StyleChanged=" .. tostring(REG.onStyleChanged)) end

-- The game's mailbox goes away without MAIL_CLOSED (it sat under another window).
MailFrame.shown = false
if P.OnUpdate then P.OnUpdate(P, 0.3) end
print("  mailbox gone, no event -> panel shown:", P.shown)
-- Next visit, then the X.
MailFrame.shown = true; fire("MAIL_SHOW"); run()
print("  next visit -> panel shown:", P.shown)
if REG and REG.close then REG.close() print("  X pressed -> panel shown:", P.shown) end

-- Checks
for _, c in ipairs(calls) do assert(not c:find("MailFrame"), "the addon never shows the game's windows: " .. c) end
assert(attached[1] == "Linen Cloth", "the reagent is attached")
assert(to == "Bob Smith", "To: gets the full name")
if mode == "vanilla" then
  assert(P.parent == MailFrame, "on its own, the panel sits on the game's mailbox")
else
  assert(P.parent == UIParent, "under another mail window, the panel floats")
  assert(REG.plugin == "DeliveriesForever" and REG.skinned and REG.buttons and REG.command == "deliveries", "registers as a Daylight UI plugin, with its look and /dui command")
  assert(P.shown == false, "the X hides the floating panel")
end
print("plugin_test " .. mode .. ": ok")
