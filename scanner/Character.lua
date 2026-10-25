local addonName, ns = ...

-- Scanner état du personnage : XP reposé, équipement, ilvl.
--   ScanCharacterMeta  — XP, repos
--   ScanEquipment      — objets équipés + ilvl par slot, ilvl moyen
--   EstimateRestedPct  — projection de XP reposé hors ligne
-- Déclenchés depuis Init.lua.

local math_floor = math.floor
local time       = time
local ipairs     = ipairs

-- ── Scan des métadonnées du personnage ────────────────────────────

-- Méta : XP et repos.
function ns.ScanCharacterMeta()
    local charData = ns.GetCurrentCharData()
    if not charData then return end

    local maxXP = UnitXPMax("player")
    if maxXP and maxXP > 0 then
        local rawRested  = GetXPExhaustion() or 0
        charData.rested = {
            currentRestedXP = math_floor(rawRested),
            currentXP       = math_floor(UnitXP("player") or 0),
            maxXP           = maxXP,
            isRestingArea   = IsResting() and true or false,
            updatedAt       = time(),
        }
        charData.maxXP = maxXP
    end
end

-- ── Estimation du % de XP reposé (fonctionne hors ligne) ─────────

local RESTED_PER_8H  = 0.05
local SECONDS_PER_8H = 8 * 3600
local RESTED_CAP_MUL = 1.5

function ns.EstimateRestedPct(rested, maxXP)
    if not rested or not maxXP or maxXP <= 0 then return nil end

    local base      = rested.currentRestedXP or 0
    local updatedAt = rested.updatedAt       or 0
    local cap       = math_floor(maxXP * RESTED_CAP_MUL)
    local estimated = base

    -- Projection : gain de repos accumulé depuis updatedAt si en zone de repos.
    if rested.isRestingArea and updatedAt > 0 then
        local elapsed    = math.max(0, time() - updatedAt)
        local gainPerSec = (maxXP * RESTED_PER_8H) / SECONDS_PER_8H
        estimated = math.min(estimated + math_floor(elapsed * gainPerSec), cap)
    end

    estimated = math.max(0, estimated)
    if estimated <= 0 then return nil end
    return math.min(math_floor((estimated / maxXP) * 100), 150)
end

-- ── Scan de l'équipement porté ────────────────────────────────────

local SLOT_NAMES = {
    "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT",
    "WRISTSLOT", "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT",
    "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT",
    "MAINHANDSLOT", "SECONDARYHANDSLOT",
}

local SLOT_IDS = {}
local slotIDsReady = false

local function EnsureSlotIDs()
    if slotIDsReady then return end
    for _, name in ipairs(SLOT_NAMES) do
        SLOT_IDS[name] = GetInventorySlotInfo(name)
    end
    slotIDsReady = true
end

function ns.ScanEquipment()
    EnsureSlotIDs()
    local charData = ns.GetCurrentCharData()
    if not charData then return end

    charData.gear      = charData.gear      or {}
    charData.equipIlvl = charData.equipIlvl or {}

    local INVALID_EQUIP_LOC = {
        INVTYPE_BAG              = true,
        INVTYPE_QUIVER           = true,
        INVTYPE_AMMO             = true,
        INVTYPE_NON_EQUIP_IGNORE = true,
    }

    for _, slotName in ipairs(SLOT_NAMES) do
        local slotID = SLOT_IDS[slotName]
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local link = GetInventoryItemLink("player", slotID)
            if link then
                local _, _, _, itemEquipLoc = C_Item.GetItemInfoInstant(link)
                local isDefinitelyInvalid = itemEquipLoc ~= nil
                    and (itemEquipLoc == "" or INVALID_EQUIP_LOC[itemEquipLoc])

                if isDefinitelyInvalid then
                    charData.gear[slotName]      = nil
                    charData.equipIlvl[slotName] = nil
                else
                    charData.gear[slotName] = link:match("|H(.+)|h")
                    local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
                    if loc and loc:IsValid() then
                        local lvl = C_Item.GetCurrentItemLevel(loc)
                        if lvl then charData.equipIlvl[slotName] = lvl end
                    end
                end
            end
        else
            charData.gear[slotName]      = nil
            charData.equipIlvl[slotName] = nil
        end
    end

    -- Niveau d'objet moyen équipé.
    local _, avgEquipped = GetAverageItemLevel()
    local ilvl = math.floor(avgEquipped or 0)
    if ilvl > 0 then charData.ilvl = ilvl end
end

-- % de XP reposé estimé d'un personnage (nil si inconnu).
function ns.GetEstimatedRestedPct(charName, realmName)
    local d = ns.vl.GetCharacter(charName, realmName)
    if not d then return nil end
    return ns.EstimateRestedPct(d.rested, d.maxXP)
end
