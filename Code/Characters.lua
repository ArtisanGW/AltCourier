-- The characters mail can go to. Those you log into are saved on their own
-- (this account). Characters on another account can only be typed in, and are
-- only mailed once the player has turned on "Mail other accounts" in settings.
local _, addon = ...

local Characters = {}
addon.Characters = Characters

local connected = {}   -- realms connected to this one
Characters.current = {}     -- key, name, realm, faction of the character logged in

-- On this client characters have a first and a last name ("Reagents Artisan"),
-- and the mail To: field wants both, with a space and no realm.
function Characters.FullName(character)
    if character.last and character.last ~= "" then return character.name .. " " .. character.last end
    return character.name
end

function Characters.KeyOf(fullName, realm) return fullName .. "-" .. realm end

function Characters.ColoredName(key)
    local character = addon.settings.chars[key]
    if not character then return "|cff888888None|r" end
    local color = character.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
    local label = Characters.FullName(character)
    if color and color.colorStr then return "|c" .. color.colorStr .. label .. "|r" end
    return label
end

-- Can this character receive mail from the one logged in?
function Characters.CanMail(key)
    local character = key and addon.settings.chars[key]
    local current = Characters.current
    if not character or key == current.key then return false end
    if character.otherAccount and not addon.settings.crossAccount then return false end
    if character.faction and current.faction and character.faction ~= current.faction then return false end
    return character.realm == current.realm or connected[character.realm] == true
end

function Characters.MailName(key)
    return Characters.FullName(addon.settings.chars[key])
end

function Characters.Mailable()
    local list = {}
    for key in pairs(addon.settings.chars) do
        if Characters.CanMail(key) then list[#list + 1] = key end
    end
    table.sort(list)
    return list
end

-- Called at login: saves this character, and fixes what an older save held.
function Characters.RememberMe()
    local settings, current = addon.settings, Characters.current
    current.name = UnitName("player")
    current.realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("[%s%-]", "")
    current.faction = UnitFactionGroup("player")
    local last
    if UnitFullName then
        local first, second = UnitFullName("player")
        if first == current.name and type(second) == "string" and second ~= "" and second ~= current.realm then last = second end
    end
    local _, class = UnitClass("player")
    local saved = { name = current.name, last = last, realm = current.realm, faction = current.faction, class = class }
    current.key = Characters.KeyOf(Characters.FullName(saved), current.realm)
    settings.chars[current.key] = saved

    -- A key in the short form, "First-Realm": moved to this character's
    -- full-name key, and any category sending to it with it.
    local oldKey = Characters.KeyOf(current.name, current.realm)
    if oldKey ~= current.key and settings.chars[oldKey] and not settings.chars[oldKey].last then
        settings.chars[oldKey] = nil
        addon.Categories.RenameTarget(oldKey, current.key)
    end

    wipe(connected)
    if GetAutoCompleteRealms then
        for _, realm in ipairs(GetAutoCompleteRealms() or {}) do connected[realm] = true end
    end
end

-- Saves a character typed as "First Last" or "First Last-Realm"; returns its key.
-- otherAccount marks one from another account (see the settings page).
function Characters.Add(typedText, otherAccount)
    local typed, realm = typedText:match("^([^%-]+)%-?(.*)$")
    if not typed then return nil end
    local words = {}
    for word in typed:gmatch("%S+") do words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower() end
    if not words[1] then return nil end
    realm = realm ~= "" and realm or Characters.current.realm
    local character = { name = words[1], last = words[2], realm = realm, faction = Characters.current.faction,
        otherAccount = otherAccount or nil }
    local key = Characters.KeyOf(Characters.FullName(character), realm)
    addon.settings.chars[key] = addon.settings.chars[key] or character
    return key
end

-- Forgets a character given by key or name; returns whether one was found.
function Characters.Remove(text)
    local found
    for key, character in pairs(addon.settings.chars) do
        if key:lower() == text:lower()
            or (Characters.FullName(character):lower() == text:lower() and character.realm == Characters.current.realm) then
            found = key
        end
    end
    if not found or found == Characters.current.key then return false end
    addon.Categories.ForgetTarget(found)
    addon.settings.chars[found] = nil
    return true
end
