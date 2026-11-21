---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local GetInventoryItemDurability = GetInventoryItemDurability
local CreateFrame = CreateFrame
local floor = math.floor
local ipairs = ipairs
local min = math.min
local pairs = pairs
local next = next

local durabilityLayers = {} ---@type table<CDMLayer, true>
local lowestPercent = 100

-- Durability --

-- Gear without durability is skipped, so naked or all trinkets reads 100
---@return boolean changed
local function ReadDurability()
    local percent = 100
    for _, info in ipairs(NRSKNUI.ITEM_SLOTS) do
        local current, max = GetInventoryItemDurability(info.slot)
        if current and max and max > 0 then
            percent = min(percent, floor(current / max * 100))
        end
    end
    if percent == lowestPercent then return false end

    lowestPercent = percent
    return true
end

-- Events --

local eventFrame ---@type Frame?
local DURABILITY_TYPES = { durability = true }

local function OnDurabilityEvent()
    if ReadDurability() then
        CDM:UpdateAllTriggers(DURABILITY_TYPES)
    end
end

local function StartWatching()
    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnDurabilityEvent)
    end

    eventFrame:RegisterEvent('UPDATE_INVENTORY_DURABILITY')
    eventFrame:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
    ReadDurability()
end

local function StopWatching()
    eventFrame:UnregisterAllEvents()
end

-- Trigger --

-- %p the lowest percent, active always or at a value
CDM.TriggerTypes.durability = {
    Value = true,
    Decimals = 0,

    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        if not CDM.IsChoice(CDM.DURABILITY_SHOW_ON, trigger.ShowOn) then
            trigger.ShowOn = nil
        end
        if not CDM.OPERATORS[trigger.Operator] then
            trigger.Operator = nil
        end
    end,

    ---@param layer CDMLayer
    Resolve = function(layer)
        layer.spellID, layer.baseSpellID = nil, nil
        if not next(durabilityLayers) then
            StartWatching()
        end
        durabilityLayers[layer] = true
        CDM:SetIconTexture(layer, nil)
    end,

    ---@param layer CDMLayer
    Update = function(layer)
        layer.value, layer.max = lowestPercent, 100
        CDM:SetLayerValue(layer, lowestPercent, 100)
        CDM:UpdateTexts(layer)
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    ---@return boolean
    IsActive = function(layer, trigger)
        if trigger.ShowOn == 'always' or CDM.IsPreviewingLayer(layer) then return true end
        return CDM.OPERATORS[trigger.Operator](lowestPercent, trigger.Threshold)
    end,

    ---@param id string
    Unwatch = function(id)
        local watching = next(durabilityLayers) ~= nil
        for layer in pairs(durabilityLayers) do
            if layer.owner.id == id then
                durabilityLayers[layer] = nil
            end
        end

        if watching and not next(durabilityLayers) then
            StopWatching()
        end
    end,

    ---@return string name
    Name = function() return L['Durability'] end,

}

-- Conditions --

CDM.ConditionChecks.durability = {
    active = { type = 'bool', get = function(layer, trigger) return CDM.TriggerTypes.durability.IsActive(layer, trigger) end },
    percent = { type = 'number', get = function() return lowestPercent end },
}
