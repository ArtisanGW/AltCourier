-- Alt Courier
-- A vanilla addon: it uses only the game, never another addon.
-- A panel beside the mailbox lists your categories (a kind of item, and the alt
-- who gets it). Nothing is attached until you press Start: then the mail is
-- filled with the first batch, you check it and press Send, and the next batch
-- follows, until nothing is left or you press Stop. It never presses Send itself.
-- This file: the saved settings and the game's events.
--
-- Files, one job each (in the .toc's load order):
--   Rules.lua       what kinds of items a category can take
--   Categories.lua  your categories: a kind of item and the alt who gets it
--   Characters.lua  the characters mail can go to
--   Exclusions.lua  items never mailed: picked, or by a word in their name
--   Bags.lua        what's in the bags to send, and the next mail made from it
--   Run.lua         a run at the mailbox: Start, check, Send, the next batch
--   Look.lua        the look: the game's own window pieces
--   Picker.lua      a small popup list under a button
--   PanelLists.lua  the panel's lists: who gets a category, what to add, what's never sent
--   Panel.lua       the panel beside the mailbox: rows, status, buttons
--   Mailbox.lua     a mailbox visit, and where the panel sits
--   Popup.lua       a popup in the game's style
--   Settings.lua    the settings page
--   Commands.lua    /altc: alts, exclusions, the list and settings by command
--   AltCourier.lua  saved settings and the game's events

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
