---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

--[[
Blizzard frames the CDM changes, its own Cooldown Manager and the player cast bar
]]

local PlayerCastingBarFrame = PlayerCastingBarFrame
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local _G = _G

local SetCVar = C_CVar.SetCVar

-- Cooldown Manager --

local BLIZZARD_VIEWERS = {
    'EssentialCooldownViewer',
    'UtilityCooldownViewer',
    'BuffIconCooldownViewer',
    'BuffBarCooldownViewer',
}

local hideViewers = false -- Faded out but running while the module is on
local hookedViewers = {} ---@type table<Frame, true>

-- Each icon takes the mouse for its own tooltip
---@param viewer CooldownViewerMixin|Frame
---@param item Frame
local function ApplyItemMouse(viewer, item)
    item:SetMouseMotionEnabled(viewer.tooltipsShown and not hideViewers)
end

---@param viewer CooldownViewerMixin|Frame
local function ApplyViewerVisibility(viewer)
    viewer:SetAlpha(hideViewers and 0 or 1)
    viewer:EnableMouse(not hideViewers)
    for item in viewer.itemFramePool:EnumerateActive() do
        ApplyItemMouse(viewer, item)
    end
end

---Fade Blizzard's Cooldown Manager out while ours runs and back in when it stops
---It keeps running, as tracked bars and charge state are only readable off it
---@param hide boolean
function CDM:SetBlizzardViewers(hide)
    hideViewers = hide

    NRSKNUI:RunWhenSafe(function()
        SetCVar('cooldownViewerEnabled', '1')

        for _, name in ipairs(BLIZZARD_VIEWERS) do
            local viewer = _G[name]
            if not hookedViewers[viewer] then
                hookedViewers[viewer] = true
                -- Blizzard fades the viewers itself from its visibility and combat settings
                hooksecurefunc(viewer, 'SetAlpha', function(bar, alpha)
                    if hideViewers and alpha ~= 0 then
                        bar:SetAlpha(0)
                    end
                end)
                -- Not Visibility Hidden, as a hidden viewer drops the events our triggers read
                hooksecurefunc(viewer, 'OnAcquireItemFrame', ApplyItemMouse)
                hooksecurefunc(viewer, 'SetTooltipsShown', ApplyViewerVisibility)
            end
            ApplyViewerVisibility(viewer)
        end
    end)
end

---The frame a viewer draws for a Cooldown Manager entry, nil while none of them draws it
---@param viewers string[]
---@param cooldownID number
---@return table? item
function CDM:FindViewerItem(viewers, cooldownID)
    for _, name in ipairs(viewers) do
        for item in _G[name].itemFramePool:EnumerateActive() do
            if item.cooldownID == cooldownID then
                return item
            end
        end
    end
end

-- Cast bar --

function CDM:HidePlayerCastBar()
    NRSKNUI:RunWhenSafe(function()
        PlayerCastingBarFrame:NCBanish()
    end)
end
