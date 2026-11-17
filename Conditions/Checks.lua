---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local LoadConditions = NRSKNUI.LoadConditions

--[[
What a condition can check on each trigger type, each trigger file adds its own
A curve check reads a secret, so the game runs it through a curve or count formatter
]]

local UnitCanAttack = UnitCanAttack
local UnitExists = UnitExists
local pairs = pairs

---@type table<string, table<string, CDMCheckDef>>
CDM.ConditionChecks = {}

CDM.ConditionChecks.global = {
    combat     = { type = 'bool', get = function() return CDM.inCombat == true end },
    hasTarget  = { type = 'bool', get = function() return UnitExists('target') == true end },
    attackable = { type = 'bool', get = function() return UnitCanAttack('player', 'target') == true end },
}

-- Player and Unit checks
-- Spec and talents can't change in combat, so a group can move on them
CDM.ConditionChecks.group = {
    -- Negatable takes = or ~= in check.op, to ask for a missing class too
    classInGroup = { type = 'select', options = 'class', negatable = true, match = function(class) return NRSKNUI:IsClassInGroup(class) end },
    spec = { type = 'select', options = 'spec', match = function(specID) return LoadConditions:GetSpecID() == specID end },
    -- check.entries maps entryID to true for must have, false for must not
    talent = {
        type = 'select',
        options = 'spec',
        talents = true,
        match = function(specID, _, check)
            if LoadConditions:GetSpecID() ~= specID then return false end
            for entryID, wanted in pairs(check.entries) do
                if LoadConditions:HasTalent(entryID) ~= wanted then return false end
            end
            return true
        end,
    },
}

-- A group holding aura buttons can't move in combat, so it checks only these
CDM.GROUP_CHECKS = { spec = true, talent = true }

-- Stand-in triggers, so global and group checks resolve through Type
CDM.GLOBAL_TRIGGER = { Type = 'global' }
CDM.GROUP_TRIGGER = { Type = 'group' }

---The trigger a check reads, 0 being global and -1 group
---@param display CDMDisplay
---@param index number?
---@return CDMTrigger?
function CDM:GetCheckTrigger(display, index)
    if index == 0 then
        return self.GLOBAL_TRIGGER
    end
    if index == -1 then
        return self.GROUP_TRIGGER
    end

    return index and display.Triggers and display.Triggers[index] -- A group has no triggers
end
