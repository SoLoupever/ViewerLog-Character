local addonName, ns = ...

-- Scanner réputations (C_Reputation + C_MajorFactions).
-- Scan complet : positionnel, headers dépliés (login, nouvelle faction, logout).
-- Rafraîchissement : par factionID, sans toucher aux headers.

local math_floor = math.floor
local math_min   = math.min
local time       = time
local debugprofilestop = debugprofilestop

local TICK_BUDGET_MS = 1.0
local TICK_BATCH     = 5
local DEBOUNCE_SEC   = 2.0

local FIELDS = {
    "name", "reaction", "standing", "bottom", "top",
    "expansionGroup", "expansionOrder", "isAccountWide",
    "isMajor", "renown", "renownEarned", "renownCap", "maxRenown", "isUnlocked",
    "paragonValue", "paragonCap", "paragonLevel", "paragonReady",
}
local NUM_FIELDS = #FIELDS

local scratch = {}          -- tampon réutilisé : aucune table créée si rien n'a changé
local _ids                  -- factionIDs connus (nil = scan complet requis)
local _buildIds             -- liste en cours de construction
local _repTimer
local _scanFrame
local _scanToken = 0
local _scanning  = false
local _pendingAfterClose = false
local _closeWatcher      = false

local function GetCharData()
    local api = _G.ViewerLogAPI
    return api and api.GetCurrentCharData and api.GetCurrentCharData()
end

local function Fill(fid, data, expGroup, expOrder)
    local s = scratch
    s.name           = data.name
    s.reaction       = data.reaction
    s.standing       = data.currentStanding
    s.bottom         = data.currentReactionThreshold
    s.top            = data.nextReactionThreshold
    s.expansionGroup = expGroup
    s.expansionOrder = expOrder
    s.isAccountWide  = data.isAccountWide or nil
    s.isMajor, s.renown, s.renownEarned, s.renownCap, s.maxRenown, s.isUnlocked = nil

    if C_MajorFactions and C_Reputation.IsMajorFaction(fid) then
        local mfd = C_MajorFactions.GetMajorFactionData(fid)
        if mfd then
            s.isMajor      = true
            s.renown       = mfd.renownLevel
            s.renownEarned = mfd.renownReputationEarned
            s.renownCap    = mfd.renownLevelThreshold
            s.maxRenown    = mfd.maxLevel
            s.isUnlocked   = mfd.isUnlocked or nil
        end
    end

    s.paragonValue, s.paragonCap, s.paragonLevel, s.paragonReady = nil
    if C_Reputation.IsFactionParagon(fid) then
        local cur, cap, _, hasReward = C_Reputation.GetFactionParagonInfo(fid)
        if cur and cap and cap > 0 then
            s.paragonValue = cur % cap
            s.paragonCap   = cap
            s.paragonLevel = math_floor(cur / cap)
            s.paragonReady = hasReward or nil
        end
    end
end

local function SameAsScratch(old)
    for i = 1, NUM_FIELDS do
        local k = FIELDS[i]
        if old[k] ~= scratch[k] then return false end
    end
    return true
end

-- N'alloue et n'horodate que si la faction a changé.
local function Commit(reps, fid, now)
    local old = reps[fid]
    if old and SameAsScratch(old) then return end
    local e = { updatedAt = now }
    for i = 1, NUM_FIELDS do
        local k = FIELDS[i]
        e[k] = scratch[k]
    end
    reps[fid] = e
end

-- ── Scan complet ──────────────────────────────────────────────────
local function ScanRange(reps, from, to, numFac, expGroup, expOrder, now)
    for i = from, to do
        local data = C_Reputation.GetFactionDataByIndex(i)
        if not data then
            return numFac + 1, expGroup, expOrder
        end
        if data.isHeader and not data.isChild then
            expOrder = expOrder + 1
            expGroup = data.name
        end
        if not data.isHeader or data.isHeaderWithRep then
            local fid = data.factionID
            if fid and fid > 0 then
                Fill(fid, data, expGroup, expOrder)
                Commit(reps, fid, now)
                _buildIds[#_buildIds + 1] = fid
            end
        end
    end
    return to + 1, expGroup, expOrder
end

local function ScanFullSync()
    local charData = GetCharData()
    if not charData then return end
    charData.reputations = charData.reputations or {}

    _buildIds = {}
    C_Reputation.ExpandAllFactionHeaders()
    local numFac = C_Reputation.GetNumFactions()
    ScanRange(charData.reputations, 1, numFac, numFac, nil, 0, time())
    C_Reputation.CollapseAllFactionHeaders()
    _ids, _buildIds = _buildIds, nil
end

local function EnsureCloseWatcher()
    if _closeWatcher or not ReputationFrame then return end
    _closeWatcher = true
    ReputationFrame:HookScript("OnHide", function()
        if _pendingAfterClose then
            _pendingAfterClose = false
            ns.ScanReputations(true)
        end
    end)
end

local function ScanFullChunked()
    -- Expand/Collapse referme la faction ouverte dans la fenêtre native.
    if ReputationFrame and ReputationFrame:IsShown() then
        _pendingAfterClose = true
        EnsureCloseWatcher()
        return
    end

    local charData = GetCharData()
    if not charData then return end
    charData.reputations = charData.reputations or {}
    local reps = charData.reputations

    _buildIds = {}
    C_Reputation.ExpandAllFactionHeaders()
    local numFac = C_Reputation.GetNumFactions()
    local now = time()
    local nextIndex, expGroup, expOrder = 1, nil, 0

    _scanToken = _scanToken + 1
    local myToken = _scanToken
    _scanning = true
    _scanFrame = _scanFrame or CreateFrame("Frame")

    _scanFrame:SetScript("OnUpdate", function(self)
        if myToken ~= _scanToken then
            self:SetScript("OnUpdate", nil)
            return
        end
        local startTime = debugprofilestop()
        repeat
            local toIndex = math_min(nextIndex + TICK_BATCH - 1, numFac)
            nextIndex, expGroup, expOrder =
                ScanRange(reps, nextIndex, toIndex, numFac, expGroup, expOrder, now)
        until nextIndex > numFac or (debugprofilestop() - startTime) >= TICK_BUDGET_MS

        if nextIndex > numFac then
            self:SetScript("OnUpdate", nil)
            C_Reputation.CollapseAllFactionHeaders()
            _ids, _buildIds = _buildIds, nil
            _scanning = false
        end
    end)
end

-- ── Rafraîchissement léger ────────────────────────────────────────
local function RefreshKnown()
    local charData = GetCharData()
    local reps = charData and charData.reputations
    if not reps then return end
    local now = time()
    for i = 1, #_ids do
        local fid  = _ids[i]
        local data = C_Reputation.GetFactionDataByID(fid)
        if data then
            local old = reps[fid]
            Fill(fid, data, old and old.expansionGroup, old and old.expansionOrder or 0)
            Commit(reps, fid, now)
        end
    end
end

-- ── API publique ──────────────────────────────────────────────────
-- debounce : délai puis scan différé. Sinon scan complet synchrone (logout).
-- full : force un scan complet (nouvelle faction possible).
function ns.ScanReputations(debounce, full)
    if full then _ids = nil end

    if debounce then
        if _repTimer then _repTimer:Cancel() end
        _repTimer = C_Timer.NewTimer(DEBOUNCE_SEC, function()
            _repTimer = nil
            if _scanning then return end
            if _ids then RefreshKnown() else ScanFullChunked() end
        end)
        return
    end

    if _repTimer then _repTimer:Cancel(); _repTimer = nil end
    _scanToken = _scanToken + 1
    _scanning = false
    if _scanFrame then _scanFrame:SetScript("OnUpdate", nil) end
    ScanFullSync()
end
