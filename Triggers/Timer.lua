---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local format = string.format
local GetTime = GetTime
local ipairs = ipairs
local pairs = pairs
local next = next

local GetOverrideSpell = C_Spell.GetOverrideSpell
local GetSpellTexture = C_Spell.GetSpellTexture
local IsSpellKnown = C_SpellBook.IsSpellKnown

local timerIndex = {} ---@type table<number, table<CDMLayer, true>> cast spellID -> timer layers it starts

-- Trigger --

CDM.TriggerTypes.timer = {
    ---@param trigger CDMTrigger
    ---@return boolean
    IsKnown = function(trigger)
        local spellID = trigger.SpellID
        if not spellID then return false end

        -- A talent-replaced spell is only known as its override
        return IsSpellKnown(spellID) or IsSpellKnown(GetOverrideSpell(spellID))
    end,

    ---Which casts start this layer's timer and its icon
    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        local base = trigger.SpellID

        -- An override swap re-resolves without Unwatch, so the old casts come off here
        if layer.castIDs then
            for _, oldID in ipairs(layer.castIDs) do
                local layers = timerIndex[oldID]
                if layers then
                    layers[layer] = nil
                    if not next(layers) then
                        timerIndex[oldID] = nil
                    end
                end
            end
        end

        -- Casting the base spell, its override or one of the extra spells starts the timer
        local spellID = base
        local castIDs = {}
        if base then
            spellID = trigger.IgnoreOverride and base or GetOverrideSpell(base)
            castIDs[1], castIDs[2] = base, spellID
            if trigger.AlsoSpellIDs then
                for _, extraID in ipairs(trigger.AlsoSpellIDs) do
                    castIDs[#castIDs + 1] = extraID
                end
            end
        end
        for _, castID in ipairs(castIDs) do
            timerIndex[castID] = timerIndex[castID] or {}
            timerIndex[castID][layer] = true
        end
        layer.castIDs = castIDs
        layer.spellID, layer.baseSpellID = spellID, base
        layer.timerLength = trigger.Duration

        -- ResolveOverrides finds the displays to re-resolve through the spell index
        CDM:WatchSpell(base, layer.owner.id)
        CDM:SetIconTexture(layer, spellID and GetSpellTexture(spellID))
    end,

    Update = CDM.UpdateCountdown,

    IsActive = CDM.IsCountdownActive,
}

---Warning text for Information tab's problem list
---@param i number
---@param trigger CDMTrigger
---@param warnings string[]
CDM.TriggerTypes.timer.Warnings = function(i, trigger, warnings)
    if trigger.SpellID then
        CDM:WarnUnknownSpell(warnings, i, trigger.SpellID)
    else
        warnings[#warnings + 1] = format(L['Trigger %d: no spell chosen.'], i)
    end
end

---@param id string
CDM.TriggerTypes.timer.Unwatch = function(id)
    for spellID, layers in pairs(timerIndex) do
        for layer in pairs(layers) do
            if layer.owner.id == id then
                layers[layer] = nil
            end
        end

        if not next(layers) then
            timerIndex[spellID] = nil
        end
    end
end

-- Events --

local castFrame ---@type Frame?

---@param spellID number
local function OnCast(_, _, _, _, spellID)
    -- A secret key can't index timerIndex
    if issecretvalue(spellID) then return end

    -- Nearly every cast is on a spell no timer watches
    local layers = timerIndex[spellID]
    if not layers then return end

    for layer in pairs(layers) do
        CDM.StartCountdown(layer)
    end
end

CDM.TriggerTypes.timer.RegisterEvents = function()
    if not castFrame then
        castFrame = CreateFrame('Frame')
        castFrame:SetScript('OnEvent', OnCast)
    end

    castFrame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
end

CDM.TriggerTypes.timer.UnregisterEvents = function()
    castFrame:UnregisterAllEvents()
end

-- Conditions --

CDM.ConditionChecks.timer = {
    active    = { type = 'bool', get = function(layer) return CDM.TriggerTypes.timer.IsActive(layer) end },
    remaining = { type = 'number', get = function(layer) return layer.endTime and layer.endTime - GetTime() or 0 end },
}
