-- The settings page, in the game's own Settings window: only a checkbox and a
-- button (controller-safe). Mailing characters on another account takes two
-- steps from the player: ticking the box, then agreeing in a popup that says
-- what it means. Adding such a character is a third.
local _, addon = ...

local CROSS_ACCOUNT_WARNING = "Mail to your other accounts\n\n"
    .. "Alt Courier will fill in the character name you typed, and the game sends the mail when you press Send. "
    .. "Alt Courier can't check that the name is right.\n\n"
    .. "A typo or a wrong name sends your items to someone else, and mail can't be taken back. "
    .. "Alt Courier is not responsible for that. It is entirely your own responsibility."

local confirmedNow = false

local function askToAddCharacter()
    if not addon.db.crossAccount then
        addon.Print("Tick \"Mail other accounts\" first.")
        return
    end
    addon.Popup.Show({
        text = "Type the character's name: First Last, then -Realm if it isn't on this realm.\n\n"
            .. "Check it twice: Alt Courier can't.",
        input = true,
        buttons = {
            { text = "Add", onClick = function(typed)
                local key = addon.Characters.Add(typed or "", true)
                if not key then return end
                addon.Print("Added " .. addon.Characters.ColoredName(key) .. " (other account).")
                addon.Refresh()
            end },
            { text = CANCEL or "Cancel" },
        },
    })
end

function addon.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("Alt Courier")
    addon.category = category

    local variableName = "AltCourier_crossAccount"
    local setting = Settings.RegisterAddOnSetting(category, variableName, "crossAccount", addon.db,
        Settings.VarType.Boolean, "Mail other accounts", false)
    Settings.SetOnValueChangedCallback(variableName, function(_, _, value)
        addon.Refresh()
        if value ~= true or confirmedNow then return end
        -- Not on until the player has agreed in the popup.
        setting:SetValue(false)
        addon.Popup.Show({
            text = CROSS_ACCOUNT_WARNING,
            buttons = {
                { text = "I understand", onClick = function()
                    confirmedNow = true
                    setting:SetValue(true)
                    confirmedNow = false
                end },
                { text = CANCEL or "Cancel" },
            },
        })
    end)
    Settings.CreateCheckbox(category, setting,
        "Lets you mail characters on your other accounts.\n\nTurning it on asks you to confirm.")

    if type(CreateSettingsButtonInitializer) == "function" then
        layout:AddInitializer(CreateSettingsButtonInitializer("Other account", "Add character", askToAddCharacter,
            "Adds a character from another account.\n\nOnly works with \"Mail other accounts\" ticked.", true))
    end

    Settings.RegisterAddOnCategory(category)
end

function addon.OpenSettings()
    if addon.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(addon.category:GetID())
    end
end
