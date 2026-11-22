---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local LoadConditions = NRSKNUI.LoadConditions

local pairs = pairs
local next = next

local CONDITIONS_ICON = 'Interface\\Icons\\INV_Misc_Gear_01'
local CONDITIONS_TYPES = { conditions = true }

local conditionLayers = {} ---@type table<CDMLayer, true>

local function OnStateChanged()
    CDM:UpdateAllTriggers(CONDITIONS_TYPES)
end

-- Trigger --

-- Active while the player's states match, its Conditions read as a load block
TriggerTypes.conditions = {
    IsKnown = function() return true end,

    ---@param layer CDMLayer
    Resolve = function(layer)
        layer.spellID, layer.baseSpellID = nil, nil
        if not next(conditionLayers) then
            LoadConditions:RegisterStateCallback(CDM, OnStateChanged)
        end
        conditionLayers[layer] = true
        CDM:SetIconTexture(layer, CONDITIONS_ICON)
    end,

    ---@param layer CDMLayer
    Update = function(layer)
        CDM:SetLayerName(layer, '')
        CDM:SetLayerValue(layer, 1, 1)
        CDM:UpdateTexts(layer)
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    ---@return boolean
    IsActive = function(layer, trigger)
        if CDM.IsPreviewingLayer(layer) then return true end
        return (LoadConditions:Check(trigger.Conditions))
    end,

    ---@param id string
    Unwatch = function(id)
        local watching = next(conditionLayers) ~= nil
        for layer in pairs(conditionLayers) do
            if layer.owner.id == id then
                conditionLayers[layer] = nil
            end
        end

        if watching and not next(conditionLayers) then
            LoadConditions:UnregisterStateCallback(CDM)
        end
    end,

    ---@return string icon
    Texture = function() return CONDITIONS_ICON end,
}

-- Conditions --

CDM.ConditionChecks.conditions = {
    active = { type = 'bool', get = TriggerTypes.conditions.IsActive },
}
