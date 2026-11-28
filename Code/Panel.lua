-- The panel beside the mailbox: one row per category (what it takes, who gets
-- it), a status box, and the Start/Stop, Skip, Never sent and Settings buttons.
-- Built once at login (Panel.Build); where it sits is Mailbox.lua's job.
local _, addon = ...
local Panel = {}
addon.Panel = Panel

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local PANEL_WIDTH, ROW_HEIGHT, TOP_SPACE, STATUS_HEIGHT = 260, 26, 34, 64

local panel

function Panel.Frame() return panel end
function Panel.IsBuilt() return panel ~= nil end
function Panel.SetStatus(text) if panel then panel.status:SetText(text) end end
function Panel.Update() if panel then panel:Update() end end

-- Alt-click an attachment on the send form: take it out and never send it again.
-- Mouse only: a controller button can't be heard without taking every button
-- from the game's cursor (an OnGamePadButtonDown frame does that, 2026-11-24).
local function hookAttachments()
    local Exclusions = addon.Exclusions
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
                Exclusions.AddItem(Exclusions.ItemIDOf(link), Exclusions.NameOf(link))
                addon.Run.Refill()
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
    local Look = addon.Look
    row:SetSize(PANEL_WIDTH, ROW_HEIGHT)
    row.label = Look.Text(row)
    row.label:SetPoint("LEFT", 14, 0)
    row.label:SetWidth(96)
    row.label:SetJustifyH("LEFT")
    -- The label's tooltip says what the kind takes.
    row.info = CreateFrame("Button", nil, row)
    row.info:SetAllPoints(row.label)
    Look.Tooltip(row.info, function()
        local rule = addon.Rules.byId[row.rule]
        return rule and (rule.label .. "\n\n" .. rule.detail .. "\n\nWith no one picked, these items stay in your bags.")
    end)

    row.pick = Look.Button(row, "", 100, 22)
    row.pick:SetPoint("LEFT", 116, 0)
    row.pick:SetScript("OnClick", function(self) addon.PanelLists.Recipients(self, addon.Categories.Find(row.rule)) end)

    row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.remove:SetSize(24, 24)
    row.remove:SetPoint("RIGHT", -8, 0)
    row.remove:SetScript("OnClick", function()
        addon.Picker.Close()
        addon.Categories.Remove(row.rule)
        panel:Update()
        addon.Run.Refill()
    end)
    Look.Tooltip(row.remove, "Stops sending this kind.\n\nIts items stay in your bags.")
end

-- Rows from the saved categories, and everything under them in place.
local function update(self)
    local Characters, Run = addon.Characters, addon.Run
    self.rows:ReleaseAll()
    local ordered = addon.Categories.Ordered()
    for index, category in ipairs(ordered) do
        local row = self.rows:Acquire()
        if not row.label then buildRow(row) end
        row.rule = category.rule
        row.label:SetText(addon.Rules.byId[category.rule].label)
        local target = category.target
        local known = addon.settings.chars[target]
        if target and not Characters.CanMail(target) and known then
            row.pick.Label("|cffff5555" .. Characters.FullName(known) .. "|r")
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

    self.excluded.Label(("Never sent (%d)"):format(addon.Exclusions.Count()))
    self.start.Label(Run.IsRunning() and "Stop" or "Start")
    self.skip:SetEnabled(Run.HoldsBatch() == true)
end

local function buildButtons()
    local Look, Run, Picker = addon.Look, addon.Run, addon.Picker
    panel.add = Look.Button(panel, "Add a category", PANEL_WIDTH - 24, 22)
    panel.add:SetScript("OnClick", function(self) addon.PanelLists.AddCategory(self) end)
    Look.Tooltip(panel.add, "Adds a kind of item to send.\n\nYou can add and remove them any time.")

    panel.statusBox = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    panel.statusBox:SetSize(PANEL_WIDTH - 24, STATUS_HEIGHT)
    panel.status = Look.Text(panel.statusBox)
    panel.status:SetPoint("TOPLEFT", 8, -8)
    panel.status:SetPoint("BOTTOMRIGHT", -8, 8)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetJustifyV("TOP")

    panel.excluded = Look.Button(panel, "", 114, 22)
    panel.excluded:SetScript("OnClick", function(self) addon.PanelLists.Excluded(self) end)
    Look.Tooltip(panel.excluded, "Items Alt Courier never sends.\n\nAlt-click an attached item to add one.")

    panel.settings = Look.Button(panel, "Settings", 114, 22)
    panel.settings:SetScript("OnClick", function() Picker.Close(); addon.OpenSettings() end)
    Look.Tooltip(panel.settings, "Opens Alt Courier's settings.\n\nThe place to turn on mailing your other accounts.")

    panel.start = Look.Button(panel, "Start", 114, 24)
    panel.start:SetScript("OnClick", function()
        Picker.Close()
        if Run.IsRunning() then Run.Stop() else Run.Start() end
    end)
    Look.Tooltip(panel.start, function()
        if Run.IsRunning() then return "Stops, and takes our items out of the mail.\n\nWhat you already sent stays sent." end
        return "Fills the mail with the next batch.\n\nNothing is attached until you press it. You check the mail and press Send."
    end)

    panel.skip = Look.Button(panel, "Skip", 114, 24)
    panel.skip:SetScript("OnClick", function()
        Picker.Close()
        Run.Skip()
    end)
    Look.Tooltip(panel.skip, "Leaves this batch in your bags until the mailbox closes.")
end

-- The game's send form tells the run what the player does with it.
local function hookSendForm()
    local Run = addon.Run
    -- The panel is a child of the mailbox, so it shows and hides with it; the
    -- addon never calls Show on the game's windows. If the Send Mail tab is
    -- left and opened again during a run, the run goes on.
    if SendMailFrame then SendMailFrame:HookScript("OnShow", Run.SendTabShown) end
    -- Typing in the mail we filled takes it from us (set by us, it isn't "user input").
    for _, editBox in ipairs({ SendMailNameEditBox, SendMailSubjectEditBox }) do
        editBox:HookScript("OnTextChanged", function(_, userInput)
            if userInput then Run.PlayerTookOver() end
        end)
    end
end

function Panel.Build()
    if panel or not MailFrame then return end
    panel = CreateFrame("Frame", "AltCourierPanel", MailFrame)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    addon.Look.Shell(panel, "Alt Courier")

    -- Hides the panel until the mailbox opens again.
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
        addon.Picker.Close()
        panel:Hide()
    end)

    -- Rows come and go as categories are added and removed: a pool.
    panel.rows = CreateFramePool("Frame", panel)
    buildButtons()
    panel.Update = update

    -- Dragged by its top when it floats on its own; the spot is kept.
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if addon.Mailbox.IsFloating() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not addon.Mailbox.IsFloating() then return end
        local point, _, relativePoint, x, y = self:GetPoint(1)
        addon.settings.floatAt = { point, relativePoint, x, y }
    end)

    hookAttachments()
    panel:SetScript("OnHide", addon.Picker.Close)
    hookSendForm()
end
