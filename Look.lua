local _, addon = ...

-- The look: the game's own window pieces, as its Settings window is built
-- (flat panel background, a NineSlice border in the ButtonFrameTemplateNoPortrait
-- layout, a GameFontNormal title, an inset for text).
local Look = {}
addon.Look = Look

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
