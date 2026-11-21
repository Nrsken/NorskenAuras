---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local IsEncounterInProgress = IsEncounterInProgress
local InCombatLockdown = InCombatLockdown
local UnitIsFeignDeath = UnitIsFeignDeath
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local UnitGUID = UnitGUID
local GetTime = GetTime
local pairs = pairs
local next = next

CDM.EVENT_NAMES = {
    enterCombat = L['Enter Combat'],
    leaveCombat = L['Leave Combat'],
    unitDied    = L['Unit Died'],
}

local NAMES = CDM.EVENT_NAMES

local eventLayers = {} ---@type table<CDMLayer, CDMTrigger>
local regenCombat = false
local inEncounter = false

-- Combat --

-- With Encounter Combat a boss fight counts as combat from its start to its end
---@param trigger CDMTrigger
---@param regen boolean
---@param encounter boolean
---@return boolean
local function InFight(trigger, regen, encounter)
    return regen or (trigger.EncounterCombat == true and encounter)
end

---@param regen boolean
---@param encounter boolean
local function OnCombatChange(regen, encounter)
    for layer, trigger in pairs(eventLayers) do
        local was, is = InFight(trigger, regenCombat, inEncounter), InFight(trigger, regen, encounter)
        if (trigger.Event == 'enterCombat' and is and not was) or (trigger.Event == 'leaveCombat' and was and not is) then
            CDM.StartCountdown(layer)
        end
    end
    regenCombat, inEncounter = regen, encounter
end

-- Deaths --

-- A wipe's deaths come in a burst, so a group trigger fires DeathLimit times a window
---@param layer CDMLayer
---@param trigger CDMTrigger
---@param now number
---@return boolean
local function DeathShows(layer, trigger, now)
    if trigger.Unit ~= 'group' then return true end

    if not layer.deathWindowStart or now - layer.deathWindowStart > trigger.DeathWindow then
        layer.deathWindowStart, layer.deathCount = now, 0
    end
    if layer.deathCount >= trigger.DeathLimit then return false end

    layer.deathCount = layer.deathCount + 1
    return true
end

---@param guid string
local function OnUnitDied(guid)
    if issecretvalue(guid) then return end

    -- UnitTokenFromGUID never answers a group token, so the group is searched
    local unit
    if guid == NRSKNUI.MyGUID then
        unit = 'player'
    else
        for groupUnit in NRSKNUI:IterateGroupUnits() do
            -- A group member's identity is never secret
            ---@diagnostic disable-next-line: secret-comparison
            if UnitGUID(groupUnit) == guid then
                unit = groupUnit
                break
            end
        end
    end
    -- UNIT_DIED fires for feign death too
    if not unit or UnitIsFeignDeath(unit) then return end

    local isPlayer = unit == 'player'
    local now = GetTime()
    for layer, trigger in pairs(eventLayers) do
        local follows = trigger.Event == 'unitDied' and (trigger.Unit == 'player') == isPlayer
        if follows and DeathShows(layer, trigger, now) then
            layer.state.unitGUID, layer.state.role = guid, UnitGroupRolesAssigned(unit)
            CDM.StartCountdown(layer)
        end
    end
end

-- Events --

local eventFrame ---@type Frame?

local handlers = {
    PLAYER_REGEN_DISABLED = function() OnCombatChange(true, inEncounter) end,
    PLAYER_REGEN_ENABLED = function() OnCombatChange(false, inEncounter) end,
    ENCOUNTER_START = function() OnCombatChange(regenCombat, true) end,
    ENCOUNTER_END = function() OnCombatChange(regenCombat, false) end,
    UNIT_DIED = OnUnitDied,
}

local function OnEvent(_, event, ...)
    handlers[event](...)
end

-- UNIT_DIED fires for every mob in a raid, so only a death trigger listens to it
local function WatchEvents()
    if not next(eventLayers) then
        if eventFrame then
            eventFrame:UnregisterAllEvents()
        end
        return
    end

    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnEvent)
    end
    -- A reload mid-fight misses the start events
    if not eventFrame:IsEventRegistered('PLAYER_REGEN_DISABLED') then
        regenCombat, inEncounter = InCombatLockdown(), IsEncounterInProgress()
        eventFrame:RegisterEvent('PLAYER_REGEN_DISABLED')
        eventFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
        eventFrame:RegisterEvent('ENCOUNTER_START')
        eventFrame:RegisterEvent('ENCOUNTER_END')
    end

    local deaths = false
    for _, trigger in pairs(eventLayers) do
        if trigger.Event == 'unitDied' then
            deaths = true
            break
        end
    end
    if deaths then
        eventFrame:RegisterEvent('UNIT_DIED')
    else
        eventFrame:UnregisterEvent('UNIT_DIED')
    end
end

-- Trigger --

-- Active for Duration after its event, %unitName the unit that died
CDM.TriggerTypes.event = {
    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        if not CDM.IsChoice(CDM.EVENTS, trigger.Event) then
            trigger.Event = nil
        end
        if not CDM.IsChoice(CDM.EVENT_UNITS, trigger.Unit) then
            trigger.Unit = nil
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        layer.spellID, layer.baseSpellID = nil, nil
        layer.timerLength = trigger.Duration
        eventLayers[layer] = trigger
        WatchEvents()
        CDM:SetIconTexture(layer, nil)
    end,

    ---@param layer CDMLayer
    ---@param _ NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, _, trigger)
        -- Styling happens before the window opens, so the player stands in here while previewing
        local unitGUID = layer.state.unitGUID or (CDM.IsPreviewingLayer(layer) and NRSKNUI.MyGUID or nil)
        CDM:SetLayerName(layer, NAMES[trigger.Event], unitGUID)
        CDM.UpdateCountdown(layer)
    end,

    IsActive = CDM.IsCountdownActive,

    ---@param id string
    Unwatch = function(id)
        for layer in pairs(eventLayers) do
            if layer.owner.id == id then
                eventLayers[layer] = nil
                layer.state.unitGUID, layer.state.role = nil, nil
            end
        end
        WatchEvents()
    end,

    ---@param trigger CDMTrigger
    ---@return string? name
    Name = function(trigger) return NAMES[trigger.Event] end,
}

-- Conditions --

-- Active and Remaining Time read the countdown as a Cast Timer's do
CDM.ConditionChecks.event = {
    active = CDM.ConditionChecks.timer.active,
    remaining = CDM.ConditionChecks.timer.remaining,
    unitRole = { type = 'select', options = 'role', match = function(role, layer) return layer.state.role == role end },
}
