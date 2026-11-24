-- /altcourier (or /altc): alts, exclusions, the list and the settings by command.
local _, addon = ...

local function excludedList()
    local Exclusions, out = addon.Exclusions, {}
    for _, word in ipairs(Exclusions.Words()) do out[#out + 1] = "\"" .. word .. "\"" end
    for _, item in ipairs(Exclusions.Items()) do out[#out + 1] = item.name end
    return out
end

local function printList()
    local Characters = addon.Characters
    for _, category in ipairs(addon.Categories.Ordered()) do
        addon.Print(addon.Rules.byId[category.rule].label .. " to " .. Characters.ColoredName(category.target) .. ".")
    end
    local names = {}
    for index, key in ipairs(Characters.Mailable()) do names[index] = Characters.ColoredName(key) end
    addon.Print(#names > 0 and ("Alts you can mail from here: " .. table.concat(names, ", "))
        or "No alts you can mail from here yet.")
end

local function printHelp()
    addon.Print("Open a mailbox and set up your categories in the panel beside it, then press Start.")
    addon.Print("/altc list - who gets what, and which alts are known")
    addon.Print("/altc add First Last - add an alt you haven't logged into yet")
    addon.Print("/altc remove Name - forget an alt")
    addon.Print("/altc exclude word|[item] - never send items with that word in their name, or that item")
    addon.Print("/altc include word|[item] - send it again")
    addon.Print("/altc excluded - what's never sent (or Alt-click an attachment to add one)")
    addon.Print("/altc settings - open the settings (mailing other accounts)")
end

SLASH_ALTCOURIER1 = "/altcourier"
SLASH_ALTCOURIER2 = "/altc"
SlashCmdList.ALTCOURIER = function(message)
    local Characters, Exclusions, Run = addon.Characters, addon.Exclusions, addon.Run
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
        local itemID = Exclusions.ItemIDOf(rest)
        if itemID then Exclusions.AddItem(itemID, Exclusions.NameOf(rest)) else Exclusions.AddWord(rest) end
        if Run.HoldsBatch() then Run.Refill() end
    elseif command == "include" and rest ~= "" then
        Exclusions.Include(rest)
        addon.Print("Will send " .. rest .. " again.")
        if Run.HoldsBatch() then Run.Refill() end
    elseif command == "excluded" then
        local out = excludedList()
        addon.Print(#out > 0 and ("Never sent: " .. table.concat(out, ", ")) or "Nothing excluded.")
    elseif command == "list" then
        printList()
    elseif command == "settings" then
        addon.OpenSettings()
    else
        printHelp()
    end
    addon.Refresh()
end
