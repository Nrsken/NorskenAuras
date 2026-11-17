---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local LoadConditions = NRSKNUI.LoadConditions
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL

--[[
The CDM module starting and stopping
Building is in Build.lua, what shows in Visibility.lua, Blizzard's frames in Blizzard.lua
]]

local format = string.format
local ipairs = ipairs
local pairs = pairs
local next = next
local type = type

---@param display table
---@param id string
---@param message string
local function MoveToTop(display, id, message)
    display.parent = nil
    local name = type(display.name) == 'string' and display.name or id
    NRSKNUI:Print(format(message, name))
end

-- Every group can hold what's in it and none sits inside itself, as on import
-- After this every walk up the tree ends
---@param displays table<string, CDMDisplay>
local function RepairTree(displays)
    for id, display in pairs(displays) do
        if type(display) == 'table' and display.parent ~= nil then
            -- A broken group is left to SetAsideBroken, which takes what it holds along
            local parent = displays[display.parent]
            if parent == nil then
                MoveToTop(display, id, L["%s's group is gone, so it was moved to the top level."])
            elseif type(parent) == 'table' and CDM.DISPLAY_TYPES[parent.type]
                and not CDM:HoldsType(parent.type, display.type) then
                MoveToTop(display, id, L["%s was in a group that can't hold it, so it was moved to the top level."])
            end
        end
    end

    -- 1 on the walk being followed, 2 known to reach the top
    local state = {}
    for id in pairs(displays) do
        local path = {}
        local walk = id
        while walk and not state[walk] do
            state[walk] = 1
            path[#path + 1] = walk
            local display = displays[walk]
            local up = type(display) == 'table' and display.parent or nil
            if up and state[up] == 1 then
                MoveToTop(display, walk, L['%s was in a group inside itself, so it was moved to the top level.'])
                up = nil
            end
            walk = up
        end
        for _, visited in ipairs(path) do
            state[visited] = 2
        end
    end
end

-- The outermost broken display at or above this one, nil when it and its groups are sound
---@param displays table<string, CDMDisplay>
---@param broken table<string, true>
---@param id string
---@return string?
local function BrokenRoot(displays, broken, id)
    local root
    while id do
        if broken[id] then
            root = id
        end
        local display = displays[id]
        id = type(display) == 'table' and display.parent or nil
    end
    return root
end

-- Repaired as an import is, what can't be leaves the store with all it holds
---@param displays table<string, CDMDisplay>
---@param aside CDMSetAside[]
local function SetAsideBroken(displays, aside)
    local broken = {}
    for id, display in pairs(displays) do
        if type(display) ~= 'table' or not CDM:ConformDisplay(display, id) then
            broken[id] = true
        end
    end
    if not next(broken) then return end

    local held, leaving = {}, {}
    for id in pairs(displays) do
        local root = BrokenRoot(displays, broken, id)
        if root then
            held[root] = (held[root] or 0) + (root == id and 0 or 1)
            leaving[id] = displays[id]
        end
    end
    -- Kept in a list, as a key here could be handed to a new display later
    for id, display in pairs(leaving) do
        aside[#aside + 1] = { key = id, display = display }
        displays[id] = nil
    end

    for root, count in pairs(held) do
        local display = leaving[root]
        local name = type(display) == 'table' and type(display.name) == 'string' and display.name or root
        if count > 0 then
            NRSKNUI:Print(format(L["%s has broken settings that couldn't be repaired, so it and the %d displays in it were set aside. Please report it."], name, count))
        else
            NRSKNUI:Print(format(L["%s has broken settings that couldn't be repaired, so it was set aside. Please report it."], name))
        end
    end
end

function CDM:OnInitialize()
    self.db = NRSKNUI.db.global
    if self.db.Version == 0 then
        self:SeedBuiltins()
        self.db.Version = self.SCHEMA_VERSION
    end

    RepairTree(self.db.Displays)
    SetAsideBroken(self.db.Displays, self.db.BrokenDisplays)
    self:EnsureUids()
    self.icons = {} ---@type table<string, CDMIcon>
    self.containers = {} ---@type table<string, Frame|NorskenCore.DynamicGroup>
    self.spareStatic = {} ---@type Frame[]
    self.spareDynamic = {} ---@type NorskenCore.DynamicGroup[]
    self.spareChain = {} ---@type CDMChainGroup[]
    self.preview = {} ---@type table<string, number>
    self.selectionPreview = {} ---@type string[]
end

function CDM:OnEnable()
    self:SetBlizzardViewers(true)
    if self.db.HidePlayerCastBar then
        self:HidePlayerCastBar()
    end

    self:RegisterTriggerEvents()
    self.Catalogue:RegisterEvents()
    LoadConditions:RegisterCallback(self, function(aceModule, playerChanged)
        aceModule:RefreshLoad(true)
        if playerChanged then
            aceModule:RefreshPlayerConditions()
        end
    end)
    NRSKNUI.AuraTriggers:RegisterCallback(self, function(aceModule) aceModule:ReapplyAuraTriggers() end)

    self:ApplySettings(Apply.All)

    -- Windows close in combat, so shared changes never pile up in the queue
    self:RegisterMessage('NRSKNUI_SHARED_SETTINGS_CHANGED', function(_, part)
        NRSKNUI:RunWhenSafe(function() self:ApplySettings(part) end)
    end)

    -- On the addon, as the triggers own this event on the module
    -- Talents and spells settle by the first world entry
    NRSKNUI:RegisterEvent('PLAYER_ENTERING_WORLD', function()
        NRSKNUI:UnregisterEvent('PLAYER_ENTERING_WORLD')
        NRSKNUI:RunWhenSafe(function() self:ApplySettings(Apply.All) end)
    end)
end

function CDM:OnDisable()
    self:SetBlizzardViewers(false)

    self:UnregisterTriggerEvents()
    self.Catalogue:UnregisterEvents()
    LoadConditions:UnregisterCallback(self)
    NRSKNUI.AuraTriggers:UnregisterCallback(self)

    for id in pairs(self.icons) do
        self:Release(id)
    end
    for id in pairs(self.containers) do
        self:Release(id)
    end
    self:ReleaseAuraGroups()
end
