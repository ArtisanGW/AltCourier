-- The characters mail can go to. Those you log into are saved on their own
-- (this account). Characters on another account can only be typed in, and are
-- only mailed once the player has turned on "Mail other accounts" in settings.
local _, addon = ...

local Characters = {}
addon.Characters = Characters

local connected = {}   -- realms connected to this one
Characters.me = {}     -- key, name, realm, faction of the character logged in

-- On this client characters have a first and a last name ("Reagents Artisan"),
-- and the mail To: field wants both, with a space and no realm.
function Characters.FullName(character)
    if character.last and character.last ~= "" then return character.name .. " " .. character.last end
    return character.name
end

function Characters.KeyOf(fullName, realm) return fullName .. "-" .. realm end

function Characters.ColoredName(key)
    local character = addon.db.chars[key]
    if not character then return "|cff888888None|r" end
    local color = character.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class]
    local label = Characters.FullName(character)
    if color and color.colorStr then return "|c" .. color.colorStr .. label .. "|r" end
    return label
end

-- Can this character receive mail from the one logged in?
function Characters.CanMail(key)
    local character = key and addon.db.chars[key]
    local me = Characters.me
    if not character or key == me.key then return false end
    if character.otherAccount and not addon.db.crossAccount then return false end
    if character.faction and me.faction and character.faction ~= me.faction then return false end
    return character.realm == me.realm or connected[character.realm] == true
end

function Characters.MailName(key)
    return Characters.FullName(addon.db.chars[key])
end

function Characters.Mailable()
    local list = {}
    for key in pairs(addon.db.chars) do
        if Characters.CanMail(key) then list[#list + 1] = key end
    end
    table.sort(list)
    return list
end

-- Called at login: saves this character, and fixes what an older save held.
function Characters.RememberMe()
    local db, me = addon.db, Characters.me
    me.name = UnitName("player")
    me.realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("[%s%-]", "")
    me.faction = UnitFactionGroup("player")
    local last
    if UnitFullName then
        local first, second = UnitFullName("player")
        if first == me.name and type(second) == "string" and second ~= "" and second ~= me.realm then last = second end
    end
    local _, class = UnitClass("player")
    local saved = { name = me.name, last = last, realm = me.realm, faction = me.faction, class = class }
    me.key = Characters.KeyOf(Characters.FullName(saved), me.realm)
    db.chars[me.key] = saved

    -- A key in the short form, "First-Realm": moved to this character's
    -- full-name key, and any category sending to it with it.
    local oldKey = Characters.KeyOf(me.name, me.realm)
    if oldKey ~= me.key and db.chars[oldKey] and not db.chars[oldKey].last then
        db.chars[oldKey] = nil
        addon.Categories.RenameTarget(oldKey, me.key)
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
    realm = realm ~= "" and realm or Characters.me.realm
    local character = { name = words[1], last = words[2], realm = realm, faction = Characters.me.faction,
        otherAccount = otherAccount or nil }
    local key = Characters.KeyOf(Characters.FullName(character), realm)
    addon.db.chars[key] = addon.db.chars[key] or character
    return key
end

-- Forgets a character given by key or name; returns whether one was found.
function Characters.Remove(text)
    local found
    for key, character in pairs(addon.db.chars) do
        if key:lower() == text:lower()
            or (Characters.FullName(character):lower() == text:lower() and character.realm == Characters.me.realm) then
            found = key
        end
    end
    if not found or found == Characters.me.key then return false end
    addon.Categories.ForgetTarget(found)
    addon.db.chars[found] = nil
    return true
end
