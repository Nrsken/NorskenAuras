---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local CreateFrame = CreateFrame
local format = string.format
local CopyTable = CopyTable
local floor = math.floor
local GetText = GetText
local UnitSex = UnitSex
local wipe = table.wipe
local pairs = pairs
local next = next
local type = type

local IsFactionParagonForCurrentPlayer = C_Reputation.IsFactionParagonForCurrentPlayer
local GetFactionGrantedByCurrency = C_CurrencyInfo.GetFactionGrantedByCurrency
local GetFriendshipReputationRanks = C_GossipInfo.GetFriendshipReputationRanks
local GetFriendshipReputation = C_GossipInfo.GetFriendshipReputation
local GetFactionParagonInfo = C_Reputation.GetFactionParagonInfo
local GetWatchedFactionData = C_Reputation.GetWatchedFactionData
local GetMajorFactionData = C_MajorFactions.GetMajorFactionData
local GetFactionDataByID = C_Reputation.GetFactionDataByID
local HasMaximumRenown = C_MajorFactions.HasMaximumRenown
local GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
local IsMajorFaction = C_Reputation.IsMajorFaction

local MAX_REPUTATION_REACTION = MAX_REPUTATION_REACTION
local RENOWN_LEVEL_LABEL = RENOWN_LEVEL_LABEL

local FACTION_ICON = 'Interface\\Icons\\Achievement_Reputation_01'
local LAST_CURRENCY = 5000 -- The highest in 12.1.5 is 3642

-- Every field a read holds, so one with no faction is complete too
local UNREAD = {
    known = false,
    name = '',
    standing = '',
    value = 0,
    total = 0,
    percent = 0,
    reaction = 0,
    kind = '',
    level = 0,
    maxLevel = 0,
    capped = false,
    atWar = false,
    bonusRep = false,
    paragon = false,
    paragonReward = false,
}

local NO_FACTION = CopyTable(UNREAD)
local factionLayers = {} ---@type table<CDMLayer, CDMTrigger>
local reads = {} ---@type table<number, table> by faction ID, shared by every layer on it
local fresh = {}
local inUse = {}
local stampCount = 0 -- One count for every read, so two factions never share a stamp
local watchedID ---@type number?
local currencyIcons ---@type table<number, number>? by faction ID, scanned on first use

-- Reputation --

---@param reaction number
---@return string
function CDM.StandingLabel(reaction)
    return GetText('FACTION_STANDING_LABEL' .. reaction, UnitSex('player'))
end

---@param trigger CDMTrigger
---@return number?
local function TriggerFaction(trigger)
    if not trigger.UseWatched then
        return trigger.FactionID
    end

    local watched = GetWatchedFactionData()
    return watched and watched.factionID
end

-- The progress Blizzard's reputation pane draws, then the paragon track once capped
---@param factionID number
local function ReadInto(factionID)
    for key, value in pairs(UNREAD) do
        fresh[key] = value
    end

    local data = GetFactionDataByID(factionID)
    if not data then return end

    local low, high, current = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    local capped = data.reaction == MAX_REPUTATION_REACTION
    local standing = CDM.StandingLabel(data.reaction)
    local reaction = data.reaction
    local kind, level, maxLevel = 'standard', data.reaction, MAX_REPUTATION_REACTION
    local friendship = GetFriendshipReputation(factionID)
    if friendship.friendshipFactionID > 0 then
        low, high, current = friendship.reactionThreshold, friendship.nextThreshold, friendship.standing
        capped = high == nil
        standing, reaction, kind = friendship.reaction, 0, 'friendship'
        -- Ranks like 4 / 5 or Level 80 / 80, a friendship without ranks is at its only one
        local ranks = GetFriendshipReputationRanks(friendship.friendshipFactionID)
        level, maxLevel = 1, 1
        if ranks.maxLevel > 0 then
            level, maxLevel = ranks.currentLevel, ranks.maxLevel
        end
    elseif IsMajorFaction(factionID) then
        local major = GetMajorFactionData(factionID)
        capped = HasMaximumRenown(factionID)
        reaction, kind = 0, 'renown'
        -- Can be nil, Blizzard's pane then draws an empty bar at renown 0
        low, high, current = 0, 0, 0
        level, maxLevel = 0, 0
        standing = format(RENOWN_LEVEL_LABEL, 0)
        if major then
            high, current = major.renownLevelThreshold, major.renownReputationEarned
            standing = format(RENOWN_LEVEL_LABEL, major.renownLevel)
            level, maxLevel = major.renownLevel, major.maxLevel
        end
    end
    fresh.kind, fresh.level, fresh.maxLevel = kind, level, maxLevel
    if capped then
        low, high, current = 0, 1, 1
    end

    if IsFactionParagonForCurrentPlayer(factionID) then
        local paragonValue, threshold, _, pending, tooLowLevel = GetFactionParagonInfo(factionID)
        fresh.paragon = true
        if paragonValue then
            low, high, current = 0, threshold, paragonValue % threshold
            fresh.paragonReward = pending and not tooLowLevel
            -- A waiting chest reads full, as Blizzard's bar does
            if fresh.paragonReward then
                current = threshold
            end
        end
    end

    fresh.known, fresh.name, fresh.standing = true, data.name, standing
    fresh.value, fresh.total = current - low, high - low
    fresh.percent = fresh.total > 0 and fresh.value / fresh.total * 100 or 0
    fresh.reaction, fresh.capped = reaction, capped
    fresh.atWar, fresh.bonusRep = data.atWarWith, data.hasBonusRepGain
end

-- Reads the game again, the stamp moves when anything did
---@param read table
---@param factionID number
---@return boolean changed
local function ReadFaction(read, factionID)
    ReadInto(factionID)
    local changed = false
    for key in pairs(UNREAD) do
        if read[key] ~= fresh[key] then
            read[key] = fresh[key]
            changed = true
        end
    end
    if changed then
        stampCount = stampCount + 1
        read.stamp = stampCount
    end
    return changed
end

---@param factionID number?
---@return table
local function GetRead(factionID)
    if not factionID then
        return NO_FACTION
    end

    local read = reads[factionID]
    if not read then
        read = { factionID = factionID }
        reads[factionID] = read
        ReadFaction(read, factionID)
    end
    return read
end

-- Nil until its trigger resolved, a text styled before that writes nothing
---@param layer CDMLayer
---@return table
local function LayerRead(layer)
    return layer.state.faction or NO_FACTION
end

-- No API names a faction's icon, but its reputation currency has one
---@param factionID number?
---@return number|string
local function FactionIcon(factionID)
    if not currencyIcons then
        currencyIcons = {}
        for currencyID = 1, LAST_CURRENCY do
            local grants = GetFactionGrantedByCurrency(currencyID)
            if grants and not currencyIcons[grants] then
                currencyIcons[grants] = GetCurrencyInfo(currencyID).iconFileID
            end
        end
    end
    if currencyIcons[factionID] then
        return currencyIcons[factionID]
    end
    local friendship = factionID and GetFriendshipReputation(factionID)
    if friendship and friendship.friendshipFactionID > 0 and friendship.texture > 0 then
        return friendship.texture
    end
    return FACTION_ICON
end

-- Events --

local eventFrame ---@type Frame?
local FACTION_TYPES = { faction = true }

---@return boolean changed
local function Refresh()
    local watched = GetWatchedFactionData()
    local factionID = watched and watched.factionID
    local changed = factionID ~= watchedID
    watchedID = factionID

    wipe(inUse)
    for _, trigger in pairs(factionLayers) do
        local id = trigger.UseWatched and factionID or trigger.FactionID
        if id then
            inUse[id] = true
        end
    end
    -- Factions no layer follows any more are dropped, the rest read again
    for id, read in pairs(reads) do
        if not inUse[id] then
            reads[id] = nil
        elseif ReadFaction(read, id) then
            changed = true
        end
    end
    return changed
end

-- These fire on every quest step and reputation tick, most change nothing we show
local function OnFactionEvent()
    if Refresh() then
        CDM:UpdateAllTriggers(FACTION_TYPES)
    end
end

local function StartWatching()
    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnFactionEvent)
    end

    -- What Blizzard's reputation pane refreshes on, the quest log for paragon rewards
    eventFrame:RegisterEvent('UPDATE_FACTION')
    eventFrame:RegisterEvent('MAJOR_FACTION_RENOWN_LEVEL_CHANGED')
    eventFrame:RegisterEvent('MAJOR_FACTION_UNLOCKED')
    eventFrame:RegisterEvent('QUEST_LOG_UPDATE')
    Refresh()
end

local function StopWatching()
    eventFrame:UnregisterAllEvents()
    wipe(reads)
end

-- Trigger --

-- %p the progress in the current standing, %t its size, active while the faction exists
CDM.TriggerTypes.faction = {
    Value = true,
    Decimals = 0,

    Tokens = {
        standing = function(layer) return LayerRead(layer).standing end,
        standingId = function(layer) return format('%d', LayerRead(layer).reaction) end,
        percentRep = function(layer) return format('%d', floor(LayerRead(layer).percent)) end,
        level = function(layer) return format('%d', LayerRead(layer).level) end,
        maxLevel = function(layer) return format('%d', LayerRead(layer).maxLevel) end,
    },

    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        if type(trigger.FactionID) ~= 'number' then
            trigger.FactionID = nil
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        layer.spellID, layer.baseSpellID = nil, nil
        if not next(factionLayers) then
            StartWatching()
        end
        factionLayers[layer] = trigger
        local read = GetRead(TriggerFaction(trigger))
        layer.state.faction = read
        CDM:SetIconTexture(layer, FactionIcon(read.factionID))
    end,

    ---@param layer CDMLayer
    ---@param _ NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, _, trigger)
        local state = layer.state
        local read = GetRead(TriggerFaction(trigger))
        -- The watched faction can change under it
        if read ~= state.faction then
            state.faction = read
            CDM:SetIconTexture(layer, FactionIcon(read.factionID))
        end
        if read.stamp ~= state.stamp then
            state.stamp = read.stamp
            CDM:RefreshLayerTokens(layer)
        end

        local name = read.name
        if name == '' and CDM.IsPreviewingLayer(layer) then
            name = L['Faction']
        end
        CDM:SetLayerName(layer, name)
        layer.value, layer.max = read.value, read.total
        CDM:SetLayerValue(layer, read.value, read.total)
        CDM:UpdateTexts(layer)
    end,

    ---@param layer CDMLayer
    ---@return boolean
    IsActive = function(layer)
        return LayerRead(layer).known or CDM.IsPreviewingLayer(layer)
    end,

    ---@param id string
    Unwatch = function(id)
        local watching = next(factionLayers) ~= nil
        for layer in pairs(factionLayers) do
            if layer.owner.id == id then
                factionLayers[layer] = nil
            end
        end

        if watching and not next(factionLayers) then
            StopWatching()
        end
    end,

    ---@param trigger CDMTrigger
    ---@return string?
    Name = function(trigger)
        local name = GetRead(TriggerFaction(trigger)).name
        if name == '' then return nil end
        return name
    end,

    ---@param trigger CDMTrigger
    ---@return number|string icon
    Texture = function(trigger) return FactionIcon(TriggerFaction(trigger)) end,
}

-- Conditions --

CDM.ConditionChecks.faction = {
    active = { type = 'bool', get = function(layer) return CDM.TriggerTypes.faction.IsActive(layer) end },
    reputation = { type = 'number', get = function(layer) return LayerRead(layer).value end },
    totalReputation = { type = 'number', get = function(layer) return LayerRead(layer).total end },
    percent = { type = 'number', get = function(layer) return LayerRead(layer).percent end },
    -- Only a plain reputation has one, friendship and renown factions read 0
    standing = {
        type = 'select',
        options = 'standing',
        match = function(reaction, layer) return LayerRead(layer).reaction == reaction end,
    },
    -- Standing 1 to 8, a friendship's rank or the renown level, whichever the faction has
    level = { type = 'number', get = function(layer) return LayerRead(layer).level end },
    maxLevel = { type = 'number', get = function(layer) return LayerRead(layer).maxLevel end },
    reputationKind = {
        type = 'select',
        options = 'reputationKind',
        match = function(kind, layer) return LayerRead(layer).kind == kind end,
    },
    capped = { type = 'bool', get = function(layer) return LayerRead(layer).capped end },
    atWar = { type = 'bool', get = function(layer) return LayerRead(layer).atWar end },
    bonusRep = { type = 'bool', get = function(layer) return LayerRead(layer).bonusRep end },
    paragon = { type = 'bool', get = function(layer) return LayerRead(layer).paragon end },
    paragonReward = { type = 'bool', get = function(layer) return LayerRead(layer).paragonReward end },
}
