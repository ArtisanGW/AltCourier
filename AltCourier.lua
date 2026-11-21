-- Alt Courier
-- A vanilla addon: it uses only the game, never another addon.
-- A panel beside the mailbox lists your categories (a kind of item, and the alt
-- who gets it). Nothing is attached until you press Start: then the mail is
-- filled with the first batch, you check it and press Send, and the next batch
-- follows, until nothing is left or you press Stop. It never presses Send itself.
-- What each part does is in the other files: Rules (kinds of items), Categories,
-- Characters (who can be mailed), Popup, Settings.

local ADDON, addon = ...

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local NUM_BAGS = NUM_BAG_SLOTS or 4

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local Characters, Categories, Rules

local db

-- What this mailbox visit is doing.
local state = {
    running = false,  -- the player pressed Start and the run isn't over
    owned = false,    -- the send form holds a batch we filled in
    batch = nil,      -- that batch: { target = key, items = {...}, rules = {...} }
    skipped = {},     -- rule ids skipped until the mailbox closes
    busy = false,     -- a fill is scheduled
    open = false,     -- the mailbox is open
    floating = false, -- the game's mailbox is out of sight (another mail window covers it)
}

local panel -- built at login, as part of the mailbox
local endVisit -- ends a mailbox visit (below)

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffAlt Courier:|r " .. message)
end

function addon.Refresh()
    if panel then panel:Update() end
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
    local count = #db.exclude.words
    for _ in pairs(db.exclude.items) do count = count + 1 end
    return count
end

-- Every bag item a category takes: ordered categories, and the slots of each by rule id.
local function scanBags()
    local ordered = Categories.Ordered()
    local slotsByRule = {}
    for bag = 0, NUM_BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not info.isLocked
                and not isExcluded(info.itemID, nameOf(info.hyperlink)) then
                local category = Categories.Claim(ordered, Rules.Describe(info))
                if category then
                    slotsByRule[category.rule] = slotsByRule[category.rule] or {}
                    table.insert(slotsByRule[category.rule], { bag = bag, slot = slot })
                end
            end
        end
    end
    return ordered, slotsByRule
end

local function isSendable(category, slotsByRule, skipped)
    return slotsByRule[category.rule] ~= nil and not skipped[category.rule] and Characters.CanMail(category.target)
end

-- The next mail: the first category with something to send and an alt to get it,
-- plus every other category going to that same alt, so one bank alt gets one
-- mail, not one per kind. nil when nothing is left.
local function nextBatch()
    local ordered, slotsByRule = scanBags()
    for _, category in ipairs(ordered) do
        if isSendable(category, slotsByRule, state.skipped) then
            local batch = { target = category.target, items = {}, rules = {} }
            for _, other in ipairs(ordered) do
                if other.target == category.target and isSendable(other, slotsByRule, state.skipped) then
                    batch.rules[#batch.rules + 1] = other.rule
                    for _, item in ipairs(slotsByRule[other.rule]) do batch.items[#batch.items + 1] = item end
                end
            end
            return batch
        end
    end
end

-- What is ready to go, said in a line: "14 items for Bob, 3 for Carol".
local function readySummary()
    local ordered, slotsByRule = scanBags()
    local countByTarget, targets = {}, {}
    for _, category in ipairs(ordered) do
        if isSendable(category, slotsByRule, state.skipped) then
            if not countByTarget[category.target] then
                countByTarget[category.target] = 0
                targets[#targets + 1] = category.target
            end
            countByTarget[category.target] = countByTarget[category.target] + #slotsByRule[category.rule]
        end
    end
    local parts = {}
    for _, target in ipairs(targets) do
        parts[#parts + 1] = ("%d for %s"):format(countByTarget[target], Characters.ColoredName(target))
    end
    return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- The send form
---------------------------------------------------------------------------

-- The addon never switches tabs or shows the game's windows itself. When it
-- opened the Send Mail tab through the game's tab function, closing the game
-- menu later failed a protected controller call (SetPreferredGamepadInteractTarget)
-- and the game blamed this addon. So the player opens the Send Mail tab.
-- When another mail window covers the game's (another addon's), there is
-- no Send Mail tab to wait for: attachments go in through the game's send
-- functions at once, and that window shows them.
local function sendTabOpen()
    return state.floating or (SendMailFrame and SendMailFrame:IsShown())
end

-- Is the send form holding something the player put there?
local function sendFormInUse()
    for index = 1, MAX_ATTACH do
        if HasSendMailItem(index) then return true end
    end
    return not state.floating and SendMailNameEditBox and (SendMailNameEditBox:GetText() or "") ~= ""
end

local function clearOurAttachments()
    if not state.owned then return end
    for index = 1, MAX_ATTACH do
        if HasSendMailItem(index) then
            ClickSendMailItemButton(index, true)
            if CursorHasItem() then ClearCursor() end
        end
    end
    state.owned, state.batch = false, nil
end

local function setStatus(text)
    if panel then panel.status:SetText(text) end
end

-- What the panel says when nothing is being sent.
local function showIdle()
    if not panel then return end
    local summary = readySummary()
    if summary ~= "" then
        setStatus("Ready: " .. summary .. ".\nPress |cffffd100Start|r when you want to send.")
    elseif #db.categories == 0 then
        setStatus("Add a kind of item to send.")
    else
        setStatus("Nothing to send yet.\nPick who gets each kind of item.")
    end
end

local function finishRun(message)
    state.running, state.owned, state.batch = false, false, nil
    setStatus(message)
    addon.Refresh()
end

local function rulesLabel(batch)
    if #batch.rules == 1 then return Rules.byId[batch.rules[1]].label end
    return "Items"
end

local function fill()
    state.busy = false
    if not (state.open and state.running) then return end
    if CursorHasItem() then ClearCursor() end

    local batch = nextBatch()
    if not batch then return finishRun("Done: nothing left to send.") end
    if not sendTabOpen() then
        setStatus("Open the |cffffd100Send Mail|r tab to go on.")
        return
    end

    local attached, slot = 0, 1
    for _, item in ipairs(batch.items) do
        while slot <= MAX_ATTACH and HasSendMailItem(slot) do slot = slot + 1 end
        if slot > MAX_ATTACH then break end
        C_Container.PickupContainerItem(item.bag, item.slot)
        ClickSendMailItemButton(slot)
        if CursorHasItem() then -- the game refused it
            ClearCursor()
        else
            attached = attached + 1
            slot = slot + 1
        end
    end
    if attached == 0 then
        -- The game took none of them: leave these kinds out and try the next.
        for _, ruleId in ipairs(batch.rules) do state.skipped[ruleId] = true end
        return fill()
    end

    local subject = #batch.rules == 1 and Rules.byId[batch.rules[1]].subject or "Items"
    local mailName = Characters.MailName(batch.target)
    SendMailNameEditBox:SetText(mailName)
    SendMailSubjectEditBox:SetText(subject)
    state.owned, state.batch = true, batch
    local more = #batch.items - attached
    local moreText = more > 0 and (", " .. more .. " more after this") or ""
    local plural = attached == 1 and "" or "s"
    if state.floating then
        -- That window has its own To: field, out of this addon's reach.
        setStatus(("%s for %s: %d item%s attached%s.\nType |cffffd100%s|r in To:, then press Send.")
            :format(rulesLabel(batch), Characters.ColoredName(batch.target), attached, plural, moreText, mailName))
    else
        setStatus(("%s for %s: %d item%s attached%s.\nPress |cffffd100Send|r. Alt-click an item to never send it.")
            :format(rulesLabel(batch), Characters.ColoredName(batch.target), attached, plural, moreText))
    end
    addon.Refresh()
end

-- Clear what we put in, then fill again a moment later (the game needs a
-- frame or two to hand cleared attachments back to the bags). Only during a run.
local function refill(delay)
    if not state.running then
        showIdle()
        return
    end
    clearOurAttachments()
    if state.busy then return end
    state.busy = true
    C_Timer.After(delay or 0.2, fill)
end

local function startRun()
    if not state.open then return end
    if not sendTabOpen() then
        setStatus("Open the |cffffd100Send Mail|r tab first, then press Start.")
        return
    end
    if sendFormInUse() then
        setStatus("The mail already has something in it.\nSend it or clear it, then press Start.")
        return
    end
    wipe(state.skipped)
    state.running = true
    addon.Refresh()
    refill(0)
end

local function stopRun()
    clearOurAttachments()
    state.running = false
    showIdle()
    addon.Refresh()
end

-- The player typed in the mail we filled: it's theirs now. Nothing more is
-- filled, and what's attached stays where it is.
local function playerTookOver()
    if not (state.running and state.owned) then return end
    state.running, state.owned, state.batch = false, false, nil
    setStatus("You changed the mail, so Alt Courier stopped.\nThe mail is yours to send.")
    addon.Refresh()
end

---------------------------------------------------------------------------
-- Panel beside the mailbox
---------------------------------------------------------------------------

local PANEL_WIDTH, ROW_HEIGHT, TOP_SPACE, STATUS_HEIGHT = 260, 26, 34, 64

-- The look: the game's own window pieces, as its Settings window is built
-- (flat panel background, a NineSlice border in the ButtonFrameTemplateNoPortrait
-- layout, a GameFontNormal title, an inset for text).
local Look = {}

function Look.Shell(frame, titleText)
    frame.Bg = CreateFrame("Frame", nil, frame, "FlatPanelBackgroundTemplate")
    frame.Bg:SetFrameLevel(frame:GetFrameLevel())
    frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -18)
    frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.NineSlice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    frame.NineSlice:SetAllPoints()
    if type(NineSliceUtil) == "table" and type(NineSliceUtil.ApplyLayoutByName) == "function" then
        NineSliceUtil.ApplyLayoutByName(frame.NineSlice, "ButtonFrameTemplateNoPortrait")
    end
    frame.title = frame.NineSlice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
    frame.title:SetText(titleText)
end

function Look.Text(parent)
    return parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
end

-- A game button whose words can change: button.Label(text).
function Look.Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    function button.Label(words) button:SetText(words) end
    button:SetSize(width, height)
    button.Label(text)
    return button
end

-- A tooltip in the game's style: a short sentence, a blank line, then the details.
-- text can be a function, for words that change.
function Look.Tooltip(frame, text)
    frame:HookScript("OnEnter", function(self)
        local words = type(text) == "function" and text() or text
        if not words then return end
        local title, details = words:match("^(.-)\n\n(.*)$")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or words, 1, 1, 1, 1, true)
        if details then GameTooltip:AddLine(details, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
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

    for index, entry in ipairs(entries) do
        local row = picker.rows[index]
        if not row then
            row = CreateFrame("Button", nil, picker)
            row:SetHeight(18)
            row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 18)
            row:SetPoint("RIGHT", -6, 0)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            picker.rows[index] = row
        end
        row.text:SetText(entry.text)
        row:SetScript("OnClick", function()
            picker:Hide()
            if entry.onClick then entry.onClick() end
        end)
        row:Show()
    end
    for index = #entries + 1, #picker.rows do picker.rows[index]:Hide() end

    picker:SetSize(math.max(owner:GetWidth(), 150), 12 + #entries * 18)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    picker:Show()
end

local function openRecipientList(owner, category)
    local function choose(key)
        category.target = key
        panel:Update()
        refill()
    end
    local entries = { { text = "|cff888888None|r", onClick = function() choose(nil) end } }
    for _, key in ipairs(Characters.Mailable()) do
        entries[#entries + 1] = { text = Characters.ColoredName(key), onClick = function() choose(key) end }
    end
    openList(owner, category.rule, entries)
    if #entries == 1 then
        addon.Print("No alts known yet. Log into each alt once with Alt Courier on, or use /ac add First Last.")
    end
end

local function openAddCategoryList(owner)
    local entries = {}
    for _, rule in ipairs(Categories.Unused()) do
        entries[#entries + 1] = { text = rule.label, onClick = function()
            Categories.Add(rule.id)
            panel:Update()
            refill()
        end }
    end
    if #entries == 0 then entries[1] = { text = "|cff888888All added|r" } end
    openList(owner, "add", entries)
end

local function excludeItem(itemID, name)
    if not itemID then return end
    db.exclude.items[itemID] = name or db.exclude.items[itemID] or ("item " .. itemID)
    addon.Print("Won't send " .. db.exclude.items[itemID] .. " any more. /ac excluded to undo.")
    addon.Refresh()
end

local function excludeWord(word)
    word = word:lower()
    for _, existing in ipairs(db.exclude.words) do if existing == word then return end end
    table.insert(db.exclude.words, word)
    addon.Print("Won't send items with \"" .. word .. "\" in their name.")
    addon.Refresh()
end

local function openExcluded(owner)
    local entries = {}
    for _, word in ipairs(db.exclude.words) do
        entries[#entries + 1] = { text = "Name has \"" .. word .. "\"  |cffff5555x|r", onClick = function()
            for index, existing in ipairs(db.exclude.words) do
                if existing == word then table.remove(db.exclude.words, index) break end
            end
            panel:Update(); refill()
        end }
    end
    local ids = {}
    for itemID in pairs(db.exclude.items) do ids[#ids + 1] = itemID end
    table.sort(ids, function(first, second) return db.exclude.items[first] < db.exclude.items[second] end)
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
    for index = 1, MAX_ATTACH do
        local button = _G["SendMailAttachment" .. index]
        if button then
            button:HookScript("PreClick", function(self)
                self.altCourierExclude = IsAltKeyDown() and HasSendMailItem(index) and GetSendMailItemLink(index) or nil
            end)
            button:HookScript("PostClick", function(self)
                local link = self.altCourierExclude
                if not link then return end
                self.altCourierExclude = nil
                if CursorHasItem() then ClearCursor() end -- the click picked it up; back to the bags
                excludeItem(itemIDOf(link), nameOf(link))
                refill()
            end)
            button:HookScript("OnEnter", function()
                if GameTooltip:IsOwned(button) and HasSendMailItem(index) then
                    GameTooltip:AddLine("Alt-click: never send this (Alt Courier)", 0.4, 0.73, 1)
                    GameTooltip:Show()
                end
            end)
        end
    end
end

-- One category's row: what it takes, who gets it, and a button to remove it.
local function buildRow(row)
    row:SetSize(PANEL_WIDTH, ROW_HEIGHT)
    row.label = Look.Text(row)
    row.label:SetPoint("LEFT", 14, 0)
    row.label:SetWidth(96)
    row.label:SetJustifyH("LEFT")
    -- The label's tooltip says what the kind takes.
    row.info = CreateFrame("Button", nil, row)
    row.info:SetAllPoints(row.label)
    Look.Tooltip(row.info, function()
        local rule = Rules.byId[row.rule]
        return rule and (rule.label .. "\n\n" .. rule.detail .. "\n\nWith no one picked, these items stay in your bags.")
    end)

    row.pick = Look.Button(row, "", 100, 22)
    row.pick:SetPoint("LEFT", 116, 0)
    row.pick:SetScript("OnClick", function(self) openRecipientList(self, Categories.Find(row.rule)) end)

    row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.remove:SetSize(24, 24)
    row.remove:SetPoint("RIGHT", -8, 0)
    row.remove:SetScript("OnClick", function()
        closePicker()
        Categories.Remove(row.rule)
        panel:Update()
        refill()
    end)
    Look.Tooltip(row.remove, "Stops sending this kind.\n\nIts items stay in your bags.")
end

local function buildPanel()
    panel = CreateFrame("Frame", "AltCourierPanel", MailFrame)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    Look.Shell(panel, "Alt Courier")

    -- Hides the panel until the mailbox opens again.
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        closePicker()
        panel:Hide()
    end)

    -- Rows come and go as categories are added and removed: a pool.
    panel.rows = CreateFramePool("Frame", panel)

    panel.add = Look.Button(panel, "Add a category", PANEL_WIDTH - 24, 22)
    panel.add:SetScript("OnClick", function(self) openAddCategoryList(self) end)
    Look.Tooltip(panel.add, "Adds a kind of item to send.\n\nYou can add and remove them any time.")

    panel.statusBox = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    panel.statusBox:SetSize(PANEL_WIDTH - 24, STATUS_HEIGHT)
    panel.status = Look.Text(panel.statusBox)
    panel.status:SetPoint("TOPLEFT", 8, -8)
    panel.status:SetPoint("BOTTOMRIGHT", -8, 8)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetJustifyV("TOP")

    panel.excluded = Look.Button(panel, "", 114, 22)
    panel.excluded:SetScript("OnClick", function(self) openExcluded(self) end)
    Look.Tooltip(panel.excluded, "Items Alt Courier never sends.\n\nAlt-click an attached item to add one.")

    panel.settings = Look.Button(panel, "Settings", 114, 22)
    panel.settings:SetScript("OnClick", function() closePicker(); addon.OpenSettings() end)
    Look.Tooltip(panel.settings, "Opens Alt Courier's settings.\n\nThe place to turn on mailing your other accounts.")

    panel.start = Look.Button(panel, "Start", 114, 24)
    panel.start:SetScript("OnClick", function()
        closePicker()
        if state.running then stopRun() else startRun() end
    end)
    Look.Tooltip(panel.start, function()
        if state.running then return "Stops, and takes our items out of the mail.\n\nWhat you already sent stays sent." end
        return "Fills the mail with the next batch.\n\nNothing is attached until you press it. You check the mail and press Send."
    end)

    panel.skip = Look.Button(panel, "Skip", 114, 24)
    panel.skip:SetScript("OnClick", function()
        closePicker()
        if state.batch then
            for _, ruleId in ipairs(state.batch.rules) do state.skipped[ruleId] = true end
        end
        refill()
    end)
    Look.Tooltip(panel.skip, "Leaves this batch in your bags until the mailbox closes.")

    -- Rows from the saved categories, and everything under them in place.
    function panel:Update()
        self.rows:ReleaseAll()
        local ordered = Categories.Ordered()
        for index, category in ipairs(ordered) do
            local row = self.rows:Acquire()
            if not row.label then buildRow(row) end
            row.rule = category.rule
            row.label:SetText(Rules.byId[category.rule].label)
            local target = category.target
            if target and not Characters.CanMail(target) and db.chars[target] then
                row.pick.Label("|cffff5555" .. Characters.FullName(db.chars[target]) .. "|r")
            else
                row.pick.Label(Characters.ColoredName(target))
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(TOP_SPACE + (index - 1) * ROW_HEIGHT))
            row:Show()
        end

        local y = TOP_SPACE + #ordered * ROW_HEIGHT
        local function place(widget, left, top)
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", self, "TOPLEFT", left, -top)
        end
        place(self.add, 12, y + 4)
        place(self.statusBox, 12, y + 34)
        place(self.excluded, 12, y + 34 + STATUS_HEIGHT + 6)
        place(self.settings, PANEL_WIDTH - 12 - 114, y + 34 + STATUS_HEIGHT + 6)
        place(self.start, 12, y + 34 + STATUS_HEIGHT + 34)
        place(self.skip, PANEL_WIDTH - 12 - 114, y + 34 + STATUS_HEIGHT + 34)
        self:SetHeight(y + 34 + STATUS_HEIGHT + 34 + 24 + 14)

        self.excluded.Label(("Never sent (%d)"):format(excludedCount()))
        self.start.Label(state.running and "Stop" or "Start")
        self.skip:SetEnabled(state.owned == true)
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
        local point, _, relativePoint, x, y = self:GetPoint(1)
        db.floatAt = { point, relativePoint, x, y }
    end)

    hookAttachments()

    panel:SetScript("OnHide", closePicker)
    -- The panel is a child of the mailbox, so it shows and hides with it; the
    -- addon never calls Show on the game's windows. If the Send Mail tab is
    -- left and opened again during a run, the run goes on.
    if SendMailFrame then
        SendMailFrame:HookScript("OnShow", function()
            if state.running and not state.owned then refill(0.1) end
        end)
    end
    -- Typing in the mail we filled takes it from us (set by us, it isn't "user input").
    for _, editBox in ipairs({ SendMailNameEditBox, SendMailSubjectEditBox }) do
        editBox:HookScript("OnTextChanged", function(_, userInput)
            if userInput then playerTookOver() end
        end)
    end
end

-- Is the game's own mailbox on screen? Another addon's mail window may keep it open out of sight: under a hidden frame, see-through
-- or moved off screen. Then the panel floats on its own instead.
local function gameMailboxOnScreen()
    if not (MailFrame and MailFrame:IsVisible()) then return false end
    if (MailFrame:GetEffectiveAlpha() or 1) < 0.05 then return false end
    local left, right, bottom, top = MailFrame:GetLeft(), MailFrame:GetRight(), MailFrame:GetBottom(), MailFrame:GetTop()
    if not (left and right and bottom and top) then return false end
    local scale = MailFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, right, bottom, top = left * scale, right * scale, bottom * scale, top * scale
    return right > 0 and top > 0 and left < UIParent:GetWidth() and bottom < UIParent:GetHeight()
end

-- The mailbox visit is over: the game said so (MAIL_CLOSED), or the game's
-- mailbox went away while the panel floated. Under another mail window the
-- game's mailbox may get no OnHide, and MAIL_CLOSED can wait until you walk
-- away, so the floating panel watches it too.
endVisit = function()
    state.open = false
    state.running, state.owned, state.batch = false, false, nil
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

-- Beside the game's mailbox, or on its own (shown and hidden by the addon,
-- since it is the addon's own frame) when that mailbox is out of sight.
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
events:RegisterEvent("BAG_UPDATE_DELAYED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        Characters, Categories, Rules = addon.Characters, addon.Categories, addon.Rules
        AltCourierDB = AltCourierDB or {}
        db = AltCourierDB
        addon.db = db
        db.chars = db.chars or {}
        db.exclude = db.exclude or {}
        db.exclude.items = db.exclude.items or {}
        db.exclude.words = db.exclude.words or {}
        db.crossAccount = db.crossAccount == true   -- off until the player agrees (Settings.lua)
        Categories.Load()
    elseif event == "PLAYER_LOGIN" then
        Characters.RememberMe()
        if MailFrame and not panel then buildPanel() end
        addon.RegisterSettings()
    elseif event == "MAIL_SHOW" then
        if not panel then return end
        state.open = true
        state.running, state.owned, state.batch = false, false, nil
        wipe(state.skipped)
        setStatus("")
        -- A moment later, so a mail window that covers the game's has done so.
        -- Then it says what's ready; nothing is attached until Start.
        C_Timer.After(0.2, function()
            if not state.open then return end
            placePanel()
            panel:Update()
            showIdle()
        end)
    elseif event == "MAIL_CLOSED" then
        endVisit()
    elseif event == "MAIL_SEND_SUCCESS" then
        if state.owned then
            -- The game already emptied the form; fill the next batch once the
            -- sent items have left the bags.
            state.owned, state.batch = false, nil
            addon.Refresh()
            refill(0.5)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if state.open and not state.running and panel and panel:IsShown() then showIdle() end
    end
end)

---------------------------------------------------------------------------
-- /altcourier (or /ac)
---------------------------------------------------------------------------

SLASH_ALTCOURIER1 = "/altcourier"
SLASH_ALTCOURIER2 = "/ac"
SlashCmdList.ALTCOURIER = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "add" and rest ~= "" then
        local key = Characters.Add(rest, false)
        if key then addon.Print("Added " .. Characters.ColoredName(key) .. ".") end
    elseif command == "remove" and rest ~= "" then
        if Characters.Remove(rest) then
            addon.Print("Removed " .. rest .. ".")
        else
            addon.Print("No such alt: " .. rest)
        end
    elseif command == "exclude" and rest ~= "" then
        local itemID = itemIDOf(rest)
        if itemID then excludeItem(itemID, nameOf(rest)) else excludeWord(rest) end
        if state.owned then refill() end
    elseif command == "include" and rest ~= "" then
        local itemID = itemIDOf(rest)
        local word = rest:lower()
        if itemID then db.exclude.items[itemID] = nil end
        for index, existing in ipairs(db.exclude.words) do
            if existing == word then table.remove(db.exclude.words, index) break end
        end
        for id, name in pairs(db.exclude.items) do
            if name:lower() == word then db.exclude.items[id] = nil end
        end
        addon.Print("Will send " .. rest .. " again.")
        if state.owned then refill() end
    elseif command == "excluded" then
        local out = {}
        for _, word in ipairs(db.exclude.words) do out[#out + 1] = "\"" .. word .. "\"" end
        for _, name in pairs(db.exclude.items) do out[#out + 1] = name end
        addon.Print(#out > 0 and ("Never sent: " .. table.concat(out, ", ")) or "Nothing excluded.")
    elseif command == "list" then
        for _, category in ipairs(Categories.Ordered()) do
            addon.Print(Rules.byId[category.rule].label .. " to " .. Characters.ColoredName(category.target) .. ".")
        end
        local names = {}
        for index, key in ipairs(Characters.Mailable()) do names[index] = Characters.ColoredName(key) end
        addon.Print(#names > 0 and ("Alts you can mail from here: " .. table.concat(names, ", "))
            or "No alts you can mail from here yet.")
    elseif command == "settings" then
        addon.OpenSettings()
    else
        addon.Print("Open a mailbox and set up your categories in the panel beside it, then press Start.")
        addon.Print("/ac list - who gets what, and which alts are known")
        addon.Print("/ac add First Last - add an alt you haven't logged into yet")
        addon.Print("/ac remove Name - forget an alt")
        addon.Print("/ac exclude word|[item] - never send items with that word in their name, or that item")
        addon.Print("/ac include word|[item] - send it again")
        addon.Print("/ac excluded - what's never sent (or Alt-click an attachment to add one)")
        addon.Print("/ac settings - open the settings (mailing other accounts)")
    end
    addon.Refresh()
end
