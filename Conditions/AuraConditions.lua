---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

--[[
We never know when an aura is up, the game does
So its conditions only style the button and the game shows each part at the right time
]]

local ipairs = ipairs

---What an aura trigger's conditions put on its button and its While Missing stand-in
---@param display CDMDisplay
---@param triggerIndex number
---@return table<string, any> active
---@return number[]? pandemicColor
---@return table<string, any> pandemic
---@return table<string, any> missing
function CDM:GetAuraConditionChanges(display, triggerIndex)
    local active, pandemicColor, pandemic, missing = {}, nil, {}, {}

    for _, condition in ipairs(display.Conditions) do
        local check = condition.check
        if check.trigger == triggerIndex and check.value ~= false then
            for _, change in ipairs(condition.changes) do
                if check.variable == 'active' and change.property and change.property ~= 'sound' then
                    active[change.property] = change.value
                elseif check.variable == 'pandemic' and change.property == 'pandemicColor' then
                    pandemicColor = change.value
                elseif check.variable == 'pandemic' and change.property then
                    pandemic[change.property] = change.value
                elseif check.variable == 'missing' and change.property and change.property ~= 'sound' then
                    missing[change.property] = change.value
                end
            end
        end
    end

    return active, pandemicColor, pandemic, missing
end
