---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local L = NRSKNUI.Libs.AL

local UnitEmpoweredStagePercentages = UnitEmpoweredStagePercentages
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local GetNetStats = GetNetStats
local GetTime = GetTime
local ipairs = ipairs
local select = select
local pairs = pairs

local CreateDuration = C_DurationUtil.CreateDuration
local GetSpellTexture = C_Spell.GetSpellTexture
local IsSpellKnown = C_SpellBook.IsSpellKnown
local GetSpellName = C_Spell.GetSpellName
local NewTimer = C_Timer.NewTimer

local INTERRUPTED = INTERRUPTED
local FAILED = FAILED

local PREVIEW_CAST = 10
local MAX_LATENCY = 1 -- A SENT older than this belongs to another cast attempt

local CHANNEL_TICKS = {
    [755] = 5,
    [740] = 4,
    [5143] = 4,
    [15407] = 6,
    [48045] = 6,
    [64843] = 4,
    [64902] = 5,
    [113656] = 4,
    [12051] = 6,
    [120360] = 15,
    [198013] = 10,
    [198590] = 4,
    [205021] = 5,
    [206931] = 3,
    [212084] = 10,
    [234153] = 5,
    [257044] = 7,
    [291944] = 6,
    [356995] = 3,
    [47757] = 3,
    [47758] = 3,
    [373129] = 3,
    [400171] = 3,
}
local TALENT_TICKS = { [356995] = { spellID = 1219723, ticks = 4 } }
local CHAIN_TICKS = { [356995] = { extra = 1, within = 3 } } -- Disintegrate chained into itself gains a tick

---@class CDMCastState
local cast = { stage = 0 }
local castLayers = {} ---@type table<CDMLayer, CDMTrigger>
local stageTimers = {} ---@type table[]
local sentAt ---@type number?
local lastChannelEnd = {} ---@type table<number, number> spellID -> when its last channel ended
local zeroDuration = CreateDuration()

-- Cast state --

---@param trigger CDMTrigger
---@return boolean
local function Matches(trigger)
    if trigger.Casts == 'all' then return true end
    -- Specific casts with none listed match nothing
    if not trigger.SpellIDs then return false end

    for _, spellID in ipairs(trigger.SpellIDs) do
        if spellID == cast.spellID then return true end
    end
    return false
end

---@param trigger CDMTrigger
---@return boolean
local function IsHeld(trigger)
    return cast.result ~= nil and trigger.HoldTime > 0 and GetTime() < cast.endedAt + trigger.HoldTime and Matches(trigger)
end

local function Refresh()
    for layer in pairs(castLayers) do
        if layer.owner.shown then
            CDM:UpdateLayer(layer)
        end
    end
end

local function CancelStageTimers()
    for i = #stageTimers, 1, -1 do
        stageTimers[i]:Cancel()
        stageTimers[i] = nil
    end
end

---@param spellID number
---@return number[]?
local function ChannelTicks(spellID)
    local count = CHANNEL_TICKS[spellID]
    if not count then return nil end

    local talent = TALENT_TICKS[spellID]
    if talent and IsSpellKnown(talent.spellID) then
        count = talent.ticks
    end

    local chain = CHAIN_TICKS[spellID]
    if chain and lastChannelEnd[spellID] and GetTime() - lastChannelEnd[spellID] <= chain.within then
        count = count + chain.extra
    end

    local ticks = {}
    for i = 1, count - 1 do
        ticks[i] = i / count
    end
    return ticks
end

-- Where each empower stage ends along the bar, with a timer per stage to recolor it
---@param elapsed number
local function ScheduleStages(elapsed)
    CancelStageTimers()
    local percentages = UnitEmpoweredStagePercentages('player')
    if not (percentages and cast.total) then return end

    local stages, sum = {}, 0
    for i = 1, #percentages - 1 do -- The last part is the hold at max, not a stage
        sum = sum + percentages[i]
        stages[i] = sum
        local at = sum * cast.total - elapsed
        if at > 0 then
            stageTimers[#stageTimers + 1] = NewTimer(at, function()
                cast.stage = i
                Refresh()
            end)
        else
            cast.stage = i
        end
    end
    cast.stages = stages
end

---@param duration LuaDurationObject?
local function ReadTiming(duration)
    local total = duration and duration:GetTotalDuration()
    if issecretvalue(total) then
        total = nil
    end
    cast.total = total
    if cast.kind == 'empower' and total then
        local elapsed = duration:GetElapsedDuration()
        ScheduleStages(issecretvalue(elapsed) and 0 or elapsed)
    end
end

local function Start()
    local name, _, texture, _, _, _, _, _, spellID, castBarID = UnitCastingInfo('player')
    local kind, duration
    if castBarID then
        kind, duration = 'cast', UnitCastingDuration('player')
    else
        local isEmpowered
        name, _, texture, _, _, _, _, spellID, isEmpowered, _, castBarID = UnitChannelInfo('player')
        if castBarID then
            kind = isEmpowered and 'empower' or 'channel'
            duration = isEmpowered and UnitEmpoweredChannelDuration('player') or UnitChannelDuration('player')
        end
    end

    CancelStageTimers()
    cast.castBarID, cast.kind, cast.duration = castBarID, kind, duration
    cast.stages, cast.stage, cast.ticks = nil, 0, nil
    if not castBarID then
        Refresh()
        return
    end

    cast.spellID, cast.name, cast.texture = spellID, name, texture
    cast.result, cast.endedAt = nil, nil
    local now = GetTime()
    local latency = sentAt and now - sentAt
    if not (latency and latency <= MAX_LATENCY) then
        latency = select(4, GetNetStats()) / 1000
    end
    cast.latency = latency
    sentAt = nil
    ReadTiming(duration)
    if kind == 'channel' then
        cast.ticks = ChannelTicks(spellID)
    end
    Refresh()
end

-- Pushback, a clipped channel or a held empower re-issue the running cast's duration
local function Update()
    if cast.kind == 'cast' then
        cast.duration = UnitCastingDuration('player')
    elseif cast.kind == 'empower' then
        cast.duration = UnitEmpoweredChannelDuration('player')
    else
        cast.duration = UnitChannelDuration('player')
    end
    ReadTiming(cast.duration)
    Refresh()
end

---@param result 'success'|'failed'|'interrupted'
local function Finish(result)
    CancelStageTimers()
    if cast.kind == 'channel' then
        lastChannelEnd[cast.spellID] = GetTime()
    end
    cast.castBarID, cast.duration = nil, nil
    cast.result, cast.endedAt = result, GetTime()
    for layer, trigger in pairs(castLayers) do
        if layer.castHoldTimer then
            layer.castHoldTimer:Cancel()
        end
        layer.castHoldTimer = nil
        if trigger.HoldTime > 0 and layer.owner.shown then
            layer.castHoldTimer = NewTimer(trigger.HoldTime, function()
                layer.castHoldTimer = nil
                CDM:UpdateLayer(layer)
            end)
        end
    end
    Refresh()
end

---@param interruptedBy any a GUID, possibly secret
---@return 'success'|'interrupted'
local function StopResult(interruptedBy)
    if issecretvalue(interruptedBy) or interruptedBy ~= nil then
        return 'interrupted'
    end
    return 'success'
end

---@param castBarID number?
---@return boolean
local function IsCurrent(castBarID)
    return castBarID ~= nil and castBarID == cast.castBarID
end

-- Events --

-- Pushback and clipping, the payload is castGUID, spellID, castBarID
local function OnUpdated(_, _, castBarID)
    if IsCurrent(castBarID) then
        Update()
    end
end

local handlers = {
    UNIT_SPELLCAST_SENT = function()
        sentAt = GetTime()
    end,
    UNIT_SPELLCAST_START = Start,
    UNIT_SPELLCAST_CHANNEL_START = Start,
    UNIT_SPELLCAST_EMPOWER_START = Start,
    UNIT_SPELLCAST_DELAYED = OnUpdated,
    UNIT_SPELLCAST_CHANNEL_UPDATE = OnUpdated,
    UNIT_SPELLCAST_EMPOWER_UPDATE = OnUpdated,
    UNIT_SPELLCAST_STOP = function(_, _, castBarID)
        if IsCurrent(castBarID) then
            Finish('success')
        end
    end,
    UNIT_SPELLCAST_CHANNEL_STOP = function(_, _, interruptedBy, castBarID)
        if IsCurrent(castBarID) then
            Finish(StopResult(interruptedBy))
        end
    end,
    UNIT_SPELLCAST_EMPOWER_STOP = function(_, _, _, interruptedBy, castBarID)
        if IsCurrent(castBarID) then
            Finish(StopResult(interruptedBy))
        end
    end,
    UNIT_SPELLCAST_FAILED = function(_, _, castBarID)
        if IsCurrent(castBarID) then
            Finish('failed')
        end
    end,
    UNIT_SPELLCAST_INTERRUPTED = function(_, _, _, castBarID)
        if IsCurrent(castBarID) then
            Finish('interrupted')
        end
    end,
}

local eventFrame ---@type Frame?

-- After the unit, castGUID, spellID, then the event's own fields ending in castBarID
local function OnEvent(_, event, _, ...)
    handlers[event](...)
end

-- Trigger --

---@param layer CDMLayer
local function ClearExtras(layer)
    layer.max = nil
    CDM:SetLayerTicks(layer, nil)
    CDM:SetBarLatency(layer, nil, false)
end

-- The player's own cast, channel or empower and how it ended, held for a moment
TriggerTypes.cast = {
    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        -- A save from before the mode picked its casts by listing them
        if not CDM.IsChoice(CDM.CAST_MODES, trigger.Casts) then
            trigger.Casts = trigger.SpellIDs and 'specific' or 'all'
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        layer.spellID, layer.baseSpellID = nil, nil
        castLayers[layer] = trigger
    end,

    ---@param layer CDMLayer
    ---@param style CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, style, trigger)
        if cast.castBarID and Matches(trigger) then
            layer.duration = cast.duration
            layer.max = cast.total -- At Value ticks are seconds into the cast
            CDM:SetLayerTimer(layer, cast.duration, cast.kind == 'channel' and CDM.BAR_REMAINING or CDM.BAR_ELAPSED)
            CDM:SetIconTexture(layer, cast.texture)
            CDM:SetLayerName(layer, cast.name or '')
            if layer.isBar then
                CDM:SetLayerTicks(layer, cast.kind == 'empower' and cast.stages or cast.ticks)
                local latency = trigger.ShowLatency and cast.kind ~= 'empower' and cast.total and cast.total > 0 and cast.latency / cast.total or nil
                CDM:SetBarLatency(layer, latency, cast.kind == 'channel', style.LatencyColor)
            end
        elseif IsHeld(trigger) then
            layer.duration = zeroDuration
            CDM:SetLayerValue(layer, 1, 1)
            local success = cast.result == 'success'
            CDM:SetLayerName(layer, success and (cast.name or '') or cast.result == 'failed' and FAILED or INTERRUPTED)
            if layer.isBar then
                ClearExtras(layer)
            end
        elseif CDM.IsPreviewingLayer(layer) then
            local spellID
            if trigger.Casts ~= 'all' and trigger.SpellIDs then
                spellID = trigger.SpellIDs[1]
            end
            layer.duration = CDM.PreviewDuration(layer, PREVIEW_CAST)
            CDM:SetLayerTimer(layer, layer.duration, CDM.BAR_ELAPSED)
            CDM:SetIconTexture(layer, spellID and GetSpellTexture(spellID))
            CDM:SetLayerName(layer, spellID and GetSpellName(spellID) or L['Cast Bar'])
            if layer.isBar then
                ClearExtras(layer)
            end
        else
            layer.duration = nil
            CDM:SetLayerTimer(layer, nil)
            if layer.isBar then
                ClearExtras(layer)
            end
        end
        CDM:UpdateTexts(layer)
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    ---@return boolean
    IsActive = function(layer, trigger)
        return (cast.castBarID ~= nil and Matches(trigger)) or IsHeld(trigger) or CDM.IsPreviewingLayer(layer)
    end,

    ---@param id string
    Unwatch = function(id)
        for layer in pairs(castLayers) do
            if layer.owner.id == id then
                if layer.castHoldTimer then
                    layer.castHoldTimer:Cancel()
                end
                layer.castHoldTimer = nil
                castLayers[layer] = nil
            end
        end
    end,

    RegisterEvents = function()
        if not eventFrame then
            eventFrame = CreateFrame('Frame')
            eventFrame:SetScript('OnEvent', OnEvent)
        end

        for event in pairs(handlers) do
            eventFrame:RegisterUnitEvent(event, 'player')
        end
        Start() -- A reload mid-cast
    end,

    UnregisterEvents = function()
        eventFrame:UnregisterAllEvents()
        CancelStageTimers()
    end,

    ---@return string name
    Name = function() return L['Cast Bar'] end,

    ---@param i number
    ---@param trigger CDMTrigger
    ---@param warnings string[]
    Warnings = function(i, trigger, warnings)
        if trigger.Casts == 'all' or not trigger.SpellIDs then return end

        for _, spellID in ipairs(trigger.SpellIDs) do
            CDM:WarnUnknownSpell(warnings, i, spellID)
        end
    end,
}

-- Conditions --

-- The running cast's kind and stage or how the held one ended, a preview reads as a cast
---@param layer CDMLayer
---@param trigger CDMTrigger
---@return 'cast'|'channel'|'empower'|nil kind
---@return number stage
---@return 'success'|'failed'|'interrupted'|nil result
local function CastStatus(layer, trigger)
    if cast.castBarID and Matches(trigger) then
        return cast.kind, cast.stage, nil
    end
    if IsHeld(trigger) then
        return nil, 0, cast.result
    end
    if CDM.IsPreviewingLayer(layer) then
        return 'cast', 0, nil
    end
    return nil, 0, nil
end

CDM.ConditionChecks.cast = {
    active       = { type = 'bool', get = TriggerTypes.cast.IsActive },
    casting      = { type = 'bool', get = function(layer, trigger) return CastStatus(layer, trigger) == 'cast' end },
    channeling   = { type = 'bool', get = function(layer, trigger) return CastStatus(layer, trigger) == 'channel' end },
    empowering   = { type = 'bool', get = function(layer, trigger) return CastStatus(layer, trigger) == 'empower' end },
    empowerStage = { type = 'number', get = function(layer, trigger) return (select(2, CastStatus(layer, trigger))) end },
    succeeded    = { type = 'bool', get = function(layer, trigger) return select(3, CastStatus(layer, trigger)) == 'success' end },
    interrupted  = { type = 'bool', get = function(layer, trigger) return select(3, CastStatus(layer, trigger)) == 'interrupted' end },
    failed       = { type = 'bool', get = function(layer, trigger) return select(3, CastStatus(layer, trigger)) == 'failed' end },
}
