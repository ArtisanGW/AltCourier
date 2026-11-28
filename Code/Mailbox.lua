-- A mailbox visit: it starts (MAIL_SHOW) and ends (MAIL_CLOSED, or the game's
-- mailbox going away), and the panel sits beside the game's mailbox, or floats
-- on its own when another mail window covers it.
local _, addon = ...
local Mailbox = {}
addon.Mailbox = Mailbox

local floating = false -- the game's mailbox is out of sight (another mail window covers it)

function Mailbox.IsFloating() return floating end

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
function Mailbox.EndVisit()
    addon.Run.EndVisit()
    addon.Picker.Close()
    local panel = addon.Panel.Frame()
    if panel then
        panel:SetScript("OnUpdate", nil)
        if floating then panel:Hide() end
    end
end

local watchWait = 0
local function watchMailbox(_, elapsed)
    watchWait = watchWait + (elapsed or 0)
    if watchWait < 0.2 then return end
    watchWait = 0
    if not (MailFrame and MailFrame:IsShown()) then Mailbox.EndVisit() end
end

-- Beside the game's mailbox, or on its own (shown and hidden by the addon,
-- since it is the addon's own frame) when that mailbox is out of sight.
local function placePanel(panel)
    floating = not gameMailboxOnScreen()
    panel:ClearAllPoints()
    panel:SetScript("OnUpdate", floating and watchMailbox or nil)
    if floating then
        panel:SetParent(UIParent)
        panel:SetFrameStrata("HIGH")
        local savedPoint = addon.settings.floatAt
        if savedPoint then
            panel:SetPoint(savedPoint[1], UIParent, savedPoint[2], savedPoint[3], savedPoint[4])
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

function Mailbox.BeginVisit()
    local panel = addon.Panel.Frame()
    if not panel then return end
    addon.Run.BeginVisit()
    addon.Panel.SetStatus("")
    -- A moment later, so a mail window that covers the game's has done so.
    -- Then it says what's ready; nothing is attached until Start.
    C_Timer.After(0.2, function()
        if not addon.Run.IsOpen() then return end
        placePanel(panel)
        panel:Update()
        addon.Run.ShowIdle()
    end)
end
