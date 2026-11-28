-- A run at the mailbox: nothing is attached until you press Start; then the
-- mail is filled with the first batch (Bags.lua), you check it and press Send,
-- and the next batch follows, until nothing is left or you press Stop. It
-- never presses Send itself. What the panel says comes from here (Panel.SetStatus).
local _, addon = ...
local Run = {}
addon.Run = Run

local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12

-- What this mailbox visit is doing.
local state = {
    running = false,  -- the player pressed Start and the run isn't over
    owned = false,    -- the send form holds a batch we filled in
    batch = nil,      -- that batch: { target = key, items = {...}, rules = {...} }
    skipped = {},     -- rule ids skipped until the mailbox closes
    busy = false,     -- a fill is scheduled
    open = false,     -- the mailbox is open
}

function Run.IsRunning() return state.running end
function Run.HoldsBatch() return state.owned end   -- the send form holds a batch we filled in
function Run.IsOpen() return state.open end

local function setStatus(text) addon.Panel.SetStatus(text) end

-- The addon never switches tabs or shows the game's windows itself. When it
-- opened the Send Mail tab through the game's tab function, closing the game
-- menu later failed a protected controller call (SetPreferredGamepadInteractTarget)
-- and the game blamed this addon. So the player opens the Send Mail tab.
-- When another mail window covers the game's (another addon's), there is
-- no Send Mail tab to wait for: attachments go in through the game's send
-- functions at once, and that window shows them.
local function sendTabOpen()
    return addon.Mailbox.IsFloating() or (SendMailFrame and SendMailFrame:IsShown())
end

-- Is the send form holding something the player put there?
local function sendFormInUse()
    for index = 1, MAX_ATTACH do
        if HasSendMailItem(index) then return true end
    end
    return not addon.Mailbox.IsFloating() and SendMailNameEditBox and (SendMailNameEditBox:GetText() or "") ~= ""
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

-- What the panel says when nothing is being sent.
function Run.ShowIdle()
    if not addon.Panel.IsBuilt() then return end
    local summary = addon.Bags.ReadySummary(state.skipped)
    if summary ~= "" then
        setStatus("Ready: " .. summary .. ".\nPress |cffffd100Start|r when you want to send.")
    elseif #addon.settings.categories == 0 then
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
    if #batch.rules == 1 then return addon.Rules.byId[batch.rules[1]].label end
    return "Items"
end

local function fill()
    state.busy = false
    if not (state.open and state.running) then return end
    if CursorHasItem() then ClearCursor() end

    local batch = addon.Bags.NextBatch(state.skipped)
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

    local Characters = addon.Characters
    local subject = #batch.rules == 1 and addon.Rules.byId[batch.rules[1]].subject or "Items"
    local mailName = Characters.MailName(batch.target)
    SendMailNameEditBox:SetText(mailName)
    SendMailSubjectEditBox:SetText(subject)
    state.owned, state.batch = true, batch
    local more = #batch.items - attached
    local moreText = more > 0 and (", " .. more .. " more after this") or ""
    local plural = attached == 1 and "" or "s"
    if addon.Mailbox.IsFloating() then
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
function Run.Refill(delay)
    if not state.running then
        Run.ShowIdle()
        return
    end
    clearOurAttachments()
    if state.busy then return end
    state.busy = true
    C_Timer.After(delay or 0.2, fill)
end

function Run.Start()
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
    Run.Refill(0)
end

function Run.Stop()
    clearOurAttachments()
    state.running = false
    Run.ShowIdle()
    addon.Refresh()
end

-- Leaves this batch in the bags until the mailbox closes.
function Run.Skip()
    if state.batch then
        for _, ruleId in ipairs(state.batch.rules) do state.skipped[ruleId] = true end
    end
    Run.Refill()
end

-- The player typed in the mail we filled: it's theirs now. Nothing more is
-- filled, and what's attached stays where it is.
function Run.PlayerTookOver()
    if not (state.running and state.owned) then return end
    state.running, state.owned, state.batch = false, false, nil
    setStatus("You changed the mail, so Alt Courier stopped.\nThe mail is yours to send.")
    addon.Refresh()
end

-- The Send Mail tab opened again during a run: the run goes on.
function Run.SendTabShown()
    if state.running and not state.owned then Run.Refill(0.1) end
end

-- The mail we filled was sent: the game already emptied the form; the next
-- batch once the sent items have left the bags.
function Run.Sent()
    if not state.owned then return end
    state.owned, state.batch = false, nil
    addon.Refresh()
    Run.Refill(0.5)
end

-- A mailbox visit starts, or ends: nothing running, nothing skipped.
local function reset(open)
    state.open = open
    state.running, state.owned, state.batch = false, false, nil
    wipe(state.skipped)
end
function Run.BeginVisit() reset(true) end
function Run.EndVisit() reset(false) end
