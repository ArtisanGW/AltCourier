-- You Got Mail
-- A vanilla addon: it uses only the game, never another addon.
-- When you open the Send Mail tab, fills a mail with your crafting reagents
-- for the alt you picked, then pelts and Bind on Equip items for theirs. It
-- never presses Send itself: you check the mail and press Send. After each
-- send, the next batch is filled in, until nothing is left.

local ADDON = ...

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local NUM_BAGS = NUM_BAG_SLOTS or 4
local CLASS_TRADESKILL = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
local SUBCLASS_LEATHER = 6 -- Trade Goods > Leather: leather, hides and pelts
local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Order matters: reagents go out first, then pelts, then Bind on Equip items.
local GROUPS = {
    { key = "reagents", label = "Reagents", subject = "Reagents" },
    { key = "pelts",    label = "Pelts",    subject = "Pelts" },
    { key = "boe",      label = "BoE",      subject = "Bind on Equip" },
}

local db
local myKey, myName, myRealm, myFaction
local connected = {}

-- What this mailbox visit is doing.
local state = {
    owned = false,   -- the send form holds a batch we filled in
    group = nil,     -- the group of that batch
    skipped = {},    -- groups skipped until the mailbox closes
    busy = false,    -- a fill is scheduled
    open = false,    -- the mailbox is open
    floating = false, -- the game's mailbox is out of sight (another mail window covers it)
}

local panel -- built at login, as part of the mailbox
local endVisit -- ends a mailbox visit (below)

local function print_(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffYou Got Mail:|r " .. msg)
end

---------------------------------------------------------------------------
-- Characters on this account
---------------------------------------------------------------------------

-- On this client characters have a first and a last name ("Reagents Artisan"),
-- and the mail To: field wants both, with a space and no realm.
local function fullName(c)
    if c.last and c.last ~= "" then return c.name .. " " .. c.last end
    return c.name
end

local function keyOf(full, realm) return full .. "-" .. realm end

local function coloredName(key)
    local c = db.chars[key]
    if not c then return "|cff888888None|r" end
    local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local label = fullName(c)
    if color and color.colorStr then return "|c" .. color.colorStr .. label .. "|r" end
    return label
end

-- Can this character receive mail from the one logged in?
local function canMail(key)
    local c = key and db.chars[key]
    if not c or key == myKey then return false end
    if c.faction and myFaction and c.faction ~= myFaction then return false end
    return c.realm == myRealm or connected[c.realm] == true
end

local function mailName(key)
    local c = db.chars[key]
    return fullName(db.chars[key])
end

local function mailableChars()
    local list = {}
    for key in pairs(db.chars) do
        if canMail(key) then list[#list + 1] = key end
    end
    table.sort(list)
    return list
end

local function rememberMe()
    myName = UnitName("player")
    myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("[%s%-]", "")
    myFaction = UnitFactionGroup("player")
    local last
    if UnitFullName then
        local first, second = UnitFullName("player")
        if first == myName and type(second) == "string" and second ~= "" and second ~= myRealm then last = second end
    end
    local _, class = UnitClass("player")
    local me = { name = myName, last = last, realm = myRealm, faction = myFaction, class = class }
    myKey = keyOf(fullName(me), myRealm)
    db.chars[myKey] = me

    -- A key in the short form, "First-Realm": moved to this character's
    -- full-name key, and any picker set to it with it.
    local old = keyOf(myName, myRealm)
    if old ~= myKey and db.chars[old] and not db.chars[old].last then
        db.chars[old] = nil
        for g, target in pairs(db.targets) do
            if target == old then db.targets[g] = myKey end
        end
    end

    wipe(connected)
    if GetAutoCompleteRealms then
        for _, realm in ipairs(GetAutoCompleteRealms() or {}) do connected[realm] = true end
    end
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

local function itemIDOf(link) return link and tonumber(link:match("item:(%d+)")) end
local function nameOf(link) return link and link:match("%[(.-)%]") end

-- Never mailed: items picked one by one, or any item whose name holds a word.
local function isExcluded(itemID, name)
    if db.exclude.items[itemID] then return true end
    name = name and name:lower()
    if name then
        for _, word in ipairs(db.exclude.words) do
            if name:find(word, 1, true) then return true end
        end
    end
    return false
end

local function excludedCount()
    local n = #db.exclude.words
    for _ in pairs(db.exclude.items) do n = n + 1 end
    return n
end

-- Which group a bag slot belongs to, or nil.
local function groupOf(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID or info.isBound or info.isLocked then return nil end
    if isExcluded(info.itemID, nameOf(info.hyperlink)) then return nil end
    -- Bind on Equip and not bound yet (bound items were skipped above).
    if select(14, GetItemInfo(info.hyperlink or info.itemID)) == BIND_ON_EQUIP then return "boe" end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(info.itemID)
    if classID == CLASS_TRADESKILL then
        return subclassID == SUBCLASS_LEATHER and "pelts" or "reagents"
    end
    -- Some crafting materials live outside Trade Goods; the item says so.
    if select(17, GetItemInfo(info.itemID)) then return "reagents" end
    return nil
end

local function itemsFor(groupKey)
    local items = {}
    for bag = 0, NUM_BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if groupOf(bag, slot) == groupKey then
                items[#items + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return items
end

---------------------------------------------------------------------------
-- The send form
---------------------------------------------------------------------------

-- The addon never switches tabs or shows the game's windows itself. When it
-- opened the Send Mail tab through the game's tab function, closing the game
-- menu later failed a protected controller call (SetPreferredGamepadInteractTarget)
-- and the game blamed this addon. So the player opens the Send Mail tab,
-- and the mail is filled when it shows.
-- When another mail window covers the game's (another addon's), there is
-- no Send Mail tab to wait for: attachments go in through the game's send
-- functions at once, and that window shows them.
local function sendTabOpen()
    return state.floating or (SendMailFrame and SendMailFrame:IsShown())
end

local function clearOurAttachments()
    if not state.owned then return end
    for i = 1, MAX_ATTACH do
        if HasSendMailItem(i) then
            ClickSendMailItemButton(i, true)
            if CursorHasItem() then ClearCursor() end
        end
    end
    state.owned, state.group = false, nil
end

local function setStatus(text)
    if panel then panel.status:SetText(text) end
end

local function fill()
    state.busy = false
    if not state.open then return end
    if CursorHasItem() then ClearCursor() end

    for _, g in ipairs(GROUPS) do
        local target = db.targets[g.key]
        if not state.skipped[g.key] and canMail(target) then
            local items = itemsFor(g.key)
            if #items > 0 and not sendTabOpen() then
                setStatus(("%d %s item%s ready for %s.\nOpen the |cffffd100Send Mail|r tab to fill the mail.")
                    :format(#items, g.label, #items == 1 and "" or "s", coloredName(target)))
                return
            end
            if #items > 0 then
                local attached, slot = 0, 1
                for _, it in ipairs(items) do
                    while slot <= MAX_ATTACH and HasSendMailItem(slot) do slot = slot + 1 end
                    if slot > MAX_ATTACH then break end
                    C_Container.PickupContainerItem(it.bag, it.slot)
                    ClickSendMailItemButton(slot)
                    if CursorHasItem() then -- the game refused it
                        ClearCursor()
                    else
                        attached = attached + 1
                        slot = slot + 1
                    end
                end
                if attached > 0 then
                    SendMailNameEditBox:SetText(mailName(target))
                    SendMailSubjectEditBox:SetText(g.subject)
                    state.owned, state.group = true, g
                    local left = #items - attached
                    local more = left > 0 and (", " .. left .. " more after this") or ""
                    local s = attached == 1 and "" or "s"
                    if state.floating then
                        -- That window has its own To: field, out of this addon's reach.
                        setStatus(("%s for %s: %d item%s attached%s.\nType |cffffd100%s|r in To:, then press Send.")
                            :format(g.label, coloredName(target), attached, s, more, mailName(target)))
                    else
                        setStatus(("%s for %s: %d item%s attached%s.\nPress |cffffd100Send|r. Alt-click an item to never send it.")
                            :format(g.label, coloredName(target), attached, s, more))
                    end
                    return
                end
            end
        end
    end

    if not next(db.targets) then
        setStatus("Pick who gets your reagents, pelts and BoE items.")
    else
        setStatus("Nothing left to send.")
    end
end

-- Clear what we put in, then fill again a moment later (the game needs a
-- frame or two to hand cleared attachments back to the bags).
local function refill(delay)
    clearOurAttachments()
    if state.busy then return end
    state.busy = true
    C_Timer.After(delay or 0.2, fill)
end

---------------------------------------------------------------------------
-- Panel beside the mailbox
---------------------------------------------------------------------------

-- The look: the game's own templates.
local Look = {}

local DIALOG_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function Look.Shell(f)
    f:SetBackdrop(DIALOG_BACKDROP)
end

function Look.Text(parent, size)
    return parent:CreateFontString(nil, "OVERLAY", size == "head" and "GameFontNormal" or "GameFontHighlightSmall")
end

-- A button whose words can change: b.Label(text).
function Look.Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    function b.Label(words) b:SetText(words) end
    b:SetSize(width, height)
    b.Label(text)
    return b
end

local picker

local function closePicker() if picker then picker:Hide() end end

-- A small popup list under `owner`. entries = { { text = ..., onClick = fn }, ... }
local function openList(owner, id, entries)
    if not picker then
        picker = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        picker:SetFrameStrata("DIALOG")
        picker:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        picker:SetBackdropColor(0, 0, 0, 0.95)
        picker.rows = {}
    end
    if picker:IsShown() and picker.id == id then picker:Hide() return end
    picker.id = id

    for i, entry in ipairs(entries) do
        local row = picker.rows[i]
        if not row then
            row = CreateFrame("Button", nil, picker)
            row:SetHeight(18)
            row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
            row:SetPoint("RIGHT", -6, 0)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            picker.rows[i] = row
        end
        row.text:SetText(entry.text)
        row:SetScript("OnClick", function()
            picker:Hide()
            if entry.onClick then entry.onClick() end
        end)
        row:Show()
    end
    for i = #entries + 1, #picker.rows do picker.rows[i]:Hide() end

    picker:SetSize(math.max(owner:GetWidth(), 150), 12 + #entries * 18)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    picker:Show()
end

local function openPicker(owner, groupKey)
    local entries = { { text = "|cff888888None|r", onClick = function()
        db.targets[groupKey] = nil
        panel:Update()
        refill()
    end } }
    for _, key in ipairs(mailableChars()) do
        entries[#entries + 1] = { text = coloredName(key), onClick = function()
            db.targets[groupKey] = key
            panel:Update()
            refill()
        end }
    end
    openList(owner, groupKey, entries)
    if #entries == 1 then
        print_("No alts known yet. Log into each alt once with You Got Mail on, or use /ygm add First Last.")
    end
end

local function excludeItem(itemID, name)
    if not itemID then return end
    db.exclude.items[itemID] = name or db.exclude.items[itemID] or ("item " .. itemID)
    print_("Won't send " .. db.exclude.items[itemID] .. " any more. /ygm excluded to undo.")
    if panel then panel:Update() end
end

local function excludeWord(word)
    word = word:lower()
    for _, w in ipairs(db.exclude.words) do if w == word then return end end
    table.insert(db.exclude.words, word)
    print_("Won't send items with \"" .. word .. "\" in their name.")
    if panel then panel:Update() end
end

local function openExcluded(owner)
    local entries = {}
    for _, word in ipairs(db.exclude.words) do
        entries[#entries + 1] = { text = "Name has \"" .. word .. "\"  |cffff5555x|r", onClick = function()
            for i, w in ipairs(db.exclude.words) do
                if w == word then table.remove(db.exclude.words, i) break end
            end
            panel:Update(); refill()
        end }
    end
    local ids = {}
    for itemID in pairs(db.exclude.items) do ids[#ids + 1] = itemID end
    table.sort(ids, function(a, b) return db.exclude.items[a] < db.exclude.items[b] end)
    for _, itemID in ipairs(ids) do
        entries[#entries + 1] = { text = db.exclude.items[itemID] .. "  |cffff5555x|r", onClick = function()
            db.exclude.items[itemID] = nil
            panel:Update(); refill()
        end }
    end
    if #entries == 0 then
        entries[1] = { text = "|cff888888Alt-click an attached item|r" }
    end
    openList(owner, "excluded", entries)
end

-- Alt-click an attachment on the send form: take it out and never send it again.
local function hookAttachments()
    for i = 1, MAX_ATTACH do
        local button = _G["SendMailAttachment" .. i]
        if button then
            button:HookScript("PreClick", function(self)
                self.rpExclude = IsAltKeyDown() and HasSendMailItem(i) and GetSendMailItemLink(i) or nil
            end)
            button:HookScript("PostClick", function(self)
                local link = self.rpExclude
                if not link then return end
                self.rpExclude = nil
                if CursorHasItem() then ClearCursor() end -- the click picked it up; back to the bags
                excludeItem(itemIDOf(link), nameOf(link))
                refill()
            end)
            button:HookScript("OnEnter", function()
                if GameTooltip:IsOwned(button) and HasSendMailItem(i) then
                    GameTooltip:AddLine("Alt-click: never send this (You Got Mail)", 0.4, 0.73, 1)
                    GameTooltip:Show()
                end
            end)
        end
    end
end

local function buildPanel()
    panel = CreateFrame("Frame", "YouGotMailPanel", MailFrame, "BackdropTemplate")
    panel:SetSize(220, 200 + (#GROUPS - 2) * 28)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    Look.Shell(panel)

    local title = Look.Text(panel, "head")
    title:SetPoint("TOP", 0, -12)
    title:SetText("You Got Mail")

    -- Hides the panel until the mailbox opens again.
    local function dismiss()
        closePicker()
        panel:Hide()
    end
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", dismiss)

    panel.pick = {}
    for i, g in ipairs(GROUPS) do
        local label = Look.Text(panel, "small")
        label:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 28)
        label:SetText(g.label .. " to:")

        local btn = Look.Button(panel, "", 122, 22)
        btn:SetPoint("TOPRIGHT", -12, -31 - (i - 1) * 28)
        btn:SetScript("OnClick", function(self) openPicker(self, g.key) end)
        panel.pick[g.key] = btn
    end

    panel.status = Look.Text(panel, "small")
    panel.status:SetPoint("TOPLEFT", 14, -38 - #GROUPS * 28)
    panel.status:SetPoint("RIGHT", -14, 0)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetJustifyV("TOP")
    panel.status:SetHeight(40)

    local excluded = Look.Button(panel, "", 196, 22)
    excluded:SetPoint("BOTTOMLEFT", 12, 38)
    excluded:SetPoint("BOTTOMRIGHT", -12, 38)
    excluded:SetScript("OnClick", function(self) openExcluded(self) end)
    panel.excluded = excluded

    local again = Look.Button(panel, "Fill again", 94, 22)
    again:SetPoint("BOTTOMLEFT", 12, 12)
    again:SetScript("OnClick", function() closePicker(); refill() end)

    local skip = Look.Button(panel, "Skip", 94, 22)
    skip:SetPoint("BOTTOMRIGHT", -12, 12)
    skip:SetScript("OnClick", function()
        closePicker()
        if state.group then state.skipped[state.group.key] = true end
        refill()
    end)
    skip.tooltip = "Leave this kind of item in your bags until the mailbox closes."
    skip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    skip:HookScript("OnLeave", GameTooltip_Hide)

    function panel:Update()
        for key, btn in pairs(self.pick) do
            local target = db.targets[key]
            if target and not canMail(target) and db.chars[target] then
                btn.Label("|cffff5555" .. fullName(db.chars[target]) .. "|r")
            else
                btn.Label(coloredName(target))
            end
        end
        self.excluded.Label(("Never sent (%d)"):format(excludedCount()))
    end

    -- Dragged by its top when it floats on its own; the spot is kept.
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if state.floating then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not state.floating then return end
        local point, _, relPoint, x, y = self:GetPoint(1)
        db.floatAt = { point, relPoint, x, y }
    end)

    hookAttachments()

    panel:SetScript("OnHide", closePicker)
    -- The panel is a child of the mailbox, so it shows and hides with it; the
    -- addon never calls Show on the game's windows. Opening the Send Mail tab fills the mail.
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function() if not state.owned then refill(0.1) end end)
    end

end

-- Is the game's own mailbox on screen? Another addon's mail window may keep it open out of sight: under a hidden frame, see-through
-- or moved off screen. Then the panel floats on its own instead.
local function gameMailboxOnScreen()
    if not (MailFrame and MailFrame:IsVisible()) then return false end
    if (MailFrame:GetEffectiveAlpha() or 1) < 0.05 then return false end
    local l, r, b, t = MailFrame:GetLeft(), MailFrame:GetRight(), MailFrame:GetBottom(), MailFrame:GetTop()
    if not (l and r and b and t) then return false end
    local k = MailFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l, r, b, t = l * k, r * k, b * k, t * k
    return r > 0 and t > 0 and l < UIParent:GetWidth() and b < UIParent:GetHeight()
end

-- Beside the game's mailbox, or on its own (shown and hidden by the addon,
-- since it is the addon's own frame) when that mailbox is out of sight.
-- The mailbox visit is over: the game said so (MAIL_CLOSED), or the game's
-- mailbox went away while the panel floated. Under another mail window the
-- game's mailbox may get no OnHide, and MAIL_CLOSED can wait until you walk
-- away, so the floating panel watches it too.
endVisit = function()
    state.open = false
    state.owned, state.group = false, nil
    wipe(state.skipped)
    closePicker()
    if panel then
        panel:SetScript("OnUpdate", nil)
        if state.floating then panel:Hide() end
    end
end

local watchWait = 0
local function watchMailbox(_, elapsed)
    watchWait = watchWait + (elapsed or 0)
    if watchWait < 0.2 then return end
    watchWait = 0
    if not (MailFrame and MailFrame:IsShown()) then endVisit() end
end

local function placePanel()
    state.floating = not gameMailboxOnScreen()
    panel:ClearAllPoints()
    panel:SetScript("OnUpdate", state.floating and watchMailbox or nil)
    if state.floating then
        panel:SetParent(UIParent)
        panel:SetFrameStrata("HIGH")
        local at = db.floatAt
        if at then
            panel:SetPoint(at[1], UIParent, at[2], at[3], at[4])
        else
            panel:SetPoint("LEFT", UIParent, "CENTER", 330, 60)
        end
        panel:Show()
    else
        panel:SetParent(MailFrame)
        panel:SetFrameStrata(MailFrame:GetFrameStrata())
        panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
        if not panel:IsShown() then panel:Show() end -- closed with its X last visit
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_SEND_SUCCESS")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        YouGotMailDB = YouGotMailDB or {}
        db = YouGotMailDB
        db.chars = db.chars or {}
        db.targets = db.targets or {}
        db.exclude = db.exclude or {}
        db.exclude.items = db.exclude.items or {}
        db.exclude.words = db.exclude.words or {}
    elseif event == "PLAYER_LOGIN" then
        rememberMe()
        if MailFrame and not panel then buildPanel() end
    elseif event == "MAIL_SHOW" then
        if not panel then return end
        state.open = true
        wipe(state.skipped)
        state.owned, state.group = false, nil
        setStatus("")
        -- A moment later, so a mail window that covers the game's has done so.
        -- Then: says what's ready, and fills once the Send Mail tab is open
        -- (at once when the panel floats).
        C_Timer.After(0.2, function()
            if not state.open then return end
            placePanel()
            panel:Update()
            refill(0)
        end)
    elseif event == "MAIL_CLOSED" then
        endVisit()
    elseif event == "MAIL_SEND_SUCCESS" then
        if state.owned then
            -- The game already emptied the form; fill the next batch once the
            -- sent items have left the bags.
            state.owned, state.group = false, nil
            refill(0.5)
        end
    end
end)

---------------------------------------------------------------------------
-- /yougotmail (or /ygm)
---------------------------------------------------------------------------

SLASH_YOUGOTMAIL1 = "/yougotmail"
SLASH_YOUGOTMAIL2 = "/ygm"
SlashCmdList.YOUGOTMAIL = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "add" and rest ~= "" then
        local typed, realm = rest:match("^([^%-]+)%-?(.*)$")
        local words = {}
        for w in typed:gmatch("%S+") do words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2):lower() end
        local name, last = words[1], words[2]
        realm = realm ~= "" and realm or myRealm
        local c = { name = name, last = last, realm = realm, faction = myFaction }
        local key = keyOf(fullName(c), realm)
        db.chars[key] = db.chars[key] or c
        print_("Added " .. coloredName(key) .. ".")
    elseif cmd == "remove" and rest ~= "" then
        local found
        for key, c in pairs(db.chars) do
            if key:lower() == rest:lower() or (fullName(c):lower() == rest:lower() and c.realm == myRealm) then
                found = key
            end
        end
        if not found or found == myKey then print_("No such alt: " .. rest) return end
        for g, target in pairs(db.targets) do
            if target == found then db.targets[g] = nil end
        end
        db.chars[found] = nil
        print_("Removed " .. rest .. ".")
    elseif cmd == "exclude" and rest ~= "" then
        local itemID = itemIDOf(rest)
        if itemID then excludeItem(itemID, nameOf(rest)) else excludeWord(rest) end
        if state.owned then refill() end
    elseif cmd == "include" and rest ~= "" then
        local itemID = itemIDOf(rest)
        local word = rest:lower()
        if itemID then db.exclude.items[itemID] = nil end
        for i, w in ipairs(db.exclude.words) do
            if w == word then table.remove(db.exclude.words, i) break end
        end
        for id, name in pairs(db.exclude.items) do
            if name:lower() == word then db.exclude.items[id] = nil end
        end
        print_("Will send " .. rest .. " again.")
        if state.owned then refill() end
    elseif cmd == "excluded" then
        local out = {}
        for _, w in ipairs(db.exclude.words) do out[#out + 1] = "\"" .. w .. "\"" end
        for _, name in pairs(db.exclude.items) do out[#out + 1] = name end
        print_(#out > 0 and ("Never sent: " .. table.concat(out, ", ")) or "Nothing excluded.")
    elseif cmd == "list" then
        print_("Reagents to " .. coloredName(db.targets.reagents) .. ", pelts to " .. coloredName(db.targets.pelts)
            .. ", BoE items to " .. coloredName(db.targets.boe) .. ".")
        local list = mailableChars()
        print_(#list > 0 and ("Alts you can mail from here: " .. table.concat((function()
            local out = {}
            for i, key in ipairs(list) do out[i] = coloredName(key) end
            return out
        end)(), ", ")) or "No alts you can mail from here yet.")
    else
        print_("Open a mailbox and pick your alts in the panel beside it.")
        print_("/ygm list - who gets what, and which alts are known")
        print_("/ygm add First Last - add an alt you haven't logged into yet")
        print_("/ygm remove Name - forget an alt")
        print_("/ygm exclude word|[item] - never send items with that word in their name, or that item")
        print_("/ygm include word|[item] - send it again")
        print_("/ygm excluded - what's never sent (or Alt-click an attachment to add one)")
    end
    if panel then panel:Update() end
end
