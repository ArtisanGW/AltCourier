-- Alt Courier
-- A vanilla addon: it uses only the game, never another addon.
-- A panel beside the mailbox lists your categories (a kind of item, and the alt
-- who gets it). Nothing is attached until you press Start: then the mail is
-- filled with the first batch, you check it and press Send, and the next batch
-- follows, until nothing is left or you press Stop. It never presses Send itself.
-- This file: the saved settings and the game's events. One job per file:
--   Rules (kinds of items), Categories, Characters (who can be mailed),
--   Exclusions (never sent), Bags (what to send), Run (filling the mail),
--   Look, Picker, PanelLists, Panel (the panel), Gamepad (Y never sends),
--   Mailbox (a visit, where the panel sits), Popup, Settings, Commands (/ac).

local ADDON, addon = ...

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffAlt Courier:|r " .. message)
end

function addon.Refresh() addon.Panel.Update() end

local function loadSettings()
    AltCourierDB = AltCourierDB or {}
    local settings = AltCourierDB
    addon.settings = settings
    settings.chars = settings.chars or {}
    settings.exclude = settings.exclude or {}
    settings.exclude.items = settings.exclude.items or {}
    settings.exclude.words = settings.exclude.words or {}
    settings.crossAccount = settings.crossAccount == true   -- off until the player agrees (Settings.lua)
    addon.Categories.Load()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("BAG_UPDATE_DELAYED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        loadSettings()
    elseif event == "PLAYER_LOGIN" then
        addon.Characters.RememberMe()
        addon.Panel.Build()
        addon.RegisterSettings()
    elseif event == "MAIL_SHOW" then
        addon.Mailbox.BeginVisit()
    elseif event == "MAIL_CLOSED" then
        addon.Mailbox.EndVisit()
    elseif event == "MAIL_SEND_SUCCESS" then
        addon.Run.Sent()
    elseif event == "BAG_UPDATE_DELAYED" then
        local panel = addon.Panel.Frame()
        if addon.Run.IsOpen() and not addon.Run.IsRunning() and panel and panel:IsShown() then addon.Run.ShowIdle() end
    end
end)
