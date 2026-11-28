-- A small popup list under a button: Picker.Open(owner, id, entries), with
-- entries = { { text = ..., onClick = fn }, ... }. Opening the same id again closes it.
local _, addon = ...
local Picker = {}
addon.Picker = Picker

local picker

function Picker.Close() if picker then picker:Hide() end end

function Picker.Open(owner, id, entries)
    if not picker then
        picker = CreateFrame("Frame", nil, addon.Panel.Frame(), "BackdropTemplate")
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
