-- A popup that looks like the game's own: its dialog border (DialogBorderTemplate,
-- the frame of the game's popups), its fonts and buttons. A message, an optional
-- line to type in, and one or two buttons.
--   addon.Popup.Show({ text = "...", input = true,
--       buttons = { { text = "Add", onClick = function(typed) end }, { text = "Cancel" } } })
-- A button without onClick just closes the popup.
--
-- On the controller UI, while it's open, the controller's bottom face button (A)
-- clicks the first button and the right one (B) the last, through the popup's own
-- override bindings, cleared when it closes. It's our own frame, not the game's
-- StaticPopup (shared windows the controller steers: our code in them breaks its
-- navigation).
local _, addon = ...

local Popup = { WIDTH = 440, BUTTON_WIDTH = 170, BUTTON_HEIGHT = 24, BUTTONS = 2, HINT_HEIGHT = 18 }
addon.Popup = Popup

local frame

local function controllerUIOn()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

-- A controller button's name as the game shows it, else a plain letter.
local function buttonLabel(key, fallback)
    local text = type(GetBindingText) == "function" and GetBindingText(key) or nil
    if type(text) ~= "string" or text == "" or text == key then return fallback end
    return text
end

local function releaseControllerButtons()
    if frame and type(ClearOverrideBindings) == "function" and not InCombatLockdown() then
        ClearOverrideBindings(frame)
    end
end

local function build()
    frame = CreateFrame("Frame", "AltCourierPopup", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetWidth(Popup.WIDTH)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -135)   -- where the game's popups open
    frame.Border = CreateFrame("Frame", nil, frame, "DialogBorderTemplate")
    frame.Border:SetAllPoints()

    frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame, "TOP", 0, -20)
    frame.text:SetWidth(Popup.WIDTH - 50)

    frame.editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.editBox:SetSize(Popup.WIDTH - 70, 24)
    frame.editBox:SetPoint("TOP", frame.text, "BOTTOM", 0, -12)
    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    frame.buttons = {}
    for index = 1, Popup.BUTTONS do
        local button = CreateFrame("Button", "AltCourierPopupButton" .. index, frame, "UIPanelButtonTemplate")
        button:SetSize(Popup.BUTTON_WIDTH, Popup.BUTTON_HEIGHT)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function(self)
            local onClick, typed = self.onClick, frame.editBox:GetText()
            frame:Hide()
            if onClick then onClick(typed) end
        end)
        frame.buttons[index] = button
    end
    frame.hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    frame:SetScript("OnHide", releaseControllerButtons)
end

-- A confirms the first button, B the last, while the popup is open. Returns the
-- hint line's height (0 when there is no controller UI).
local function takeControllerButtons(first, last)
    frame.hint:SetText("")
    if not (controllerUIOn() and type(SetOverrideBindingClick) == "function" and not InCombatLockdown()) then return 0 end
    local confirmKey, backKey = GAMEPAD_FACE_BOTTOM or "PAD1", GAMEPAD_FACE_RIGHT or "PAD2"
    ClearOverrideBindings(frame)
    SetOverrideBindingClick(frame, true, confirmKey, first:GetName(), "LeftButton")
    local hint = buttonLabel(confirmKey, "A") .. ": " .. first:GetText()
    if last ~= first then
        SetOverrideBindingClick(frame, true, backKey, last:GetName(), "LeftButton")
        hint = hint .. "      " .. buttonLabel(backKey, "B") .. ": " .. last:GetText()
    end
    frame.hint:SetText(hint)
    return Popup.HINT_HEIGHT
end

function Popup.Show(options)
    if not frame then build() end
    frame.text:SetText(options.text or "")
    frame.text:SetJustifyH("CENTER")
    local height = 20 + (frame.text:GetStringHeight() or 40) + 16
    frame.editBox:SetShown(options.input == true)
    frame.editBox:SetText("")
    if options.input then height = height + 36 end

    local shown = {}
    for _, button in ipairs(frame.buttons) do button:Hide() end
    for index, spec in ipairs(options.buttons or { { text = CLOSE or "Close" } }) do
        local button = frame.buttons[index]
        if not button then break end
        button.onClick = spec.onClick
        button:SetText(spec.text)
        shown[#shown + 1] = button
    end
    -- The buttons in a centered row at the bottom, as the game's popups have them.
    local gap = 10
    local rowWidth = #shown * Popup.BUTTON_WIDTH + (#shown - 1) * gap
    for _, button in ipairs(shown) do
        button:ClearAllPoints()
        button:Show()
    end
    local hintHeight = takeControllerButtons(shown[1], shown[#shown])
    for index, button in ipairs(shown) do
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOM", -rowWidth / 2 + (index - 1) * (Popup.BUTTON_WIDTH + gap), 16 + hintHeight)
    end
    frame:SetHeight(height + Popup.BUTTON_HEIGHT + 16 + hintHeight)
    frame:Show()
    if options.input then frame.editBox:SetFocus() end
end

function Popup.Hide() if frame then frame:Hide() end end
