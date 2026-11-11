---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local AuraPreview = NRSKNUI.AuraPreview
local Anchors = NRSKNUI.Anchors

local pairs = pairs
local min = math.min
local tostring = tostring
local format = string.format
local CreateFrame = CreateFrame
local CopyTable = CopyTable
local ipairs = ipairs

local hosts = {} ---@type table<string, Frame>

--[[
Aura groups: a native AuraContainer showing many auras at once, on a host frame placed like any display.
]]

-- Config --

---The container config built from a tracker's settings; it grows the way a dynamic group with the same Layout does.
---Its buttons are drawn by CDM:InitAuraGroupButton, so nothing here describes their look.
---@param db table
---@return table
function CDM:GetAuraContainerConfig(db)
    local style = self:GetStyle(db)
    local config = NRSKNUI:ResolveAuraFlow(db.Layout, style.Width, style.Height)
    config.width, config.height = style.Width, style.Height
    -- the layout otherwise reads each button's own size, which a restyle changes after the layout ran
    config.elementWidth, config.elementHeight = style.Width, style.Height
    config.maxFrameCount = db.maxFrameCount
    config.sortMethod = AuraContainerSortMethod[db.sortMethod]
    config.sortDirection = AuraContainerSortDirection[db.sortDirection]
    return config
end

---Most auras a tracker's settings can put on screen, one group per trigger branch.
---@param db table
---@return number
function CDM:GetAuraPreviewCount(db)
    return min(db.maxFrameCount * NRSKNUI:GetTriggerBranchCount(db.Trigger), db.previewLimit)
end

---The unit a tracker watches, saved variables can outlive the unit list the GUI offers.
---@param db table
---@param name string
---@return string
function CDM:ResolveAuraUnit(db, name)
    local unit = db.Trigger and db.Trigger.Unit
    if not unit then return 'player' end

    if not NRSKNUI:IsValidUnitToken(unit) then
        NRSKNUI:Print(format(L['Aura group "%s" has an unusable unit (%s), falling back to player.'], name, tostring(unit)))
        return 'player'
    end

    return unit
end

---@param id string
---@return Frame?
function CDM:GetAuraHost(id)
    return hosts[id]
end

-- Build --

---Attach the native container to an aura group's host.
---@param id string
function CDM:BuildAuraContainer(id)
    local display, host = self:Get(id), hosts[id]
    if not (display and host) or host.container then return end

    local config = self:GetAuraContainerConfig(display)
    config.skin = host.skin
    local container = host:CreateAuraContainer(config)
    if not container then return end

    container:ClearAllPoints()
    container:SetPoint(config.containerPoint, host, config.containerPoint)
    container:AddFilteredGroup(display.Trigger, { initializeBranchFrame = host.initButton })
    container:SetUnit(self:ResolveAuraUnit(display, self:GetName(id)))
    container:UpdateUnitGate() -- also starts the container watching what can move a gate verdict
    host.container = container

    AuraPreview:Attach(container, host, config.containerPoint)
    AuraPreview:Update(container, config, self:GetAuraPreviewCount(display), display.Trigger)
    host.previewShown = nil
    self:RefreshAuraGroups()
end

---Create or re-apply an aura group, its host is placed like any display, the container follows its settings.
---@param id string
function CDM:BuildAuraGroup(id)
    local display = self:Get(id)
    if not display then return self:Release(id) end
    if display.parent and not self.containers[display.parent] then
        self:BuildContainer(display.parent)
    end

    display.Trigger = display.Trigger or NRSKNUI.AuraTriggers:New()
    -- saved before aura groups grew and looked like dynamic groups of icons
    display.Layout = display.Layout or CopyTable(CDM.AURA_GROUP_TEMPLATE.Layout)
    display.Style = display.Style or CopyTable(CDM.AURA_GROUP_TEMPLATE.Style)
    display.SubRegions = display.SubRegions or self:DefaultAuraGroupSubRegions()
    local host = hosts[id]
    if not host then
        host = CreateFrame('Frame', nil, UIParent)
        hosts[id] = host
        local owner = { id = id }
        host.owner, host.buttons = owner, {}
        -- the only time the game hands a button over, so it is kept to restyle later
        host.initButton = function(button, branch)
            host.buttons[#host.buttons + 1] = self:InitAuraGroupButton(button, owner, branch)
        end
        host.restyle = function()
            for _, layer in ipairs(host.buttons) do
                self:StyleAuraGroupButton(layer)
            end
        end
        -- a preview stand-in takes the same look, built once and restyled after
        host.skin = function(button, branch)
            local layer = button.nuiGroupLayer
            if layer then
                layer.index = branch -- a dummy can stand in for another trigger on the next pass
                self:StyleAuraGroupButton(layer)
            else
                button.nuiGroupLayer = self:InitAuraGroupButton(button, owner, branch)
            end
        end
    end
    host.owner.style = self:GetStyle(display)
    host:SetAlpha(host.owner.style.Alpha)
    local config = self:GetAuraContainerConfig(display)
    config.skin = host.skin
    host:SetSize(NRSKNUI:GetAuraGridSize(config, self:GetAuraPreviewCount(display)))
    self:EvaluateGroupConditions(display, host)
    self:Place(host, id, display)

    local container = host.container
    if not container then
        -- one function per host, so building again in combat doesn't queue another
        host.buildContainer = host.buildContainer or function()
            self:BuildAuraContainer(id)
        end
        NRSKNUI:RunWhenSafe(host.buildContainer)
        return
    end

    -- existing buttons deny access while auras are secret, so a restyle waits for that to end
    self:QueueAuraRestyle(host, host.restyle)
    container:ClearAllPoints()
    container:SetPoint(config.containerPoint, host, config.containerPoint)
    container:ApplyLayout(config)
    container:SetUnit(self:ResolveAuraUnit(display, self:GetName(id)))
    container:RebindFilteredGroups(display.Trigger)
    container:UpdateUnitGate()
    AuraPreview:Attach(container, host, config.containerPoint)
    AuraPreview:Update(container, config, self:GetAuraPreviewCount(display), display.Trigger)
end

-- Refresh --

---Re-read every aura group's trigger; one trigger page edit can reach any of them.
function CDM:ReapplyAuraTriggers()
    for id, host in pairs(hosts) do
        local display, container = self:Get(id), host.container
        if display and container then
            host:SetSize(NRSKNUI:GetAuraGridSize(self:GetAuraContainerConfig(display), self:GetAuraPreviewCount(display)))
            container:SetUnit(self:ResolveAuraUnit(display, self:GetName(id)))
            container:RebindFilteredGroups(display.Trigger)
            container:UpdateUnitGate()
        end
    end
end

---Show what is loaded, while the options are open a previewed aura group swaps its live auras for dummies.
function CDM:RefreshAuraGroups()
    for id, host in pairs(hosts) do
        local previewed = self:IsPreviewed(id)
        local shown
        if self.previewing then
            shown = previewed
        else
            shown = self:GetLoadState(id) == 'loaded'
        end
        host:SetShown(shown)

        local container = host.container
        local preview = shown and previewed
        if container and host.previewShown ~= preview then
            host.previewShown = preview
            AuraPreview:SetShown(container, preview)
            container:SetShown(not preview)
        end
    end
end

-- Release --

---@param id string
function CDM:ReleaseAuraGroup(id)
    local host = hosts[id]
    if not host then return end
    -- A container can't be torn down, so the host is parked hidden and stops processing; a new display gets a fresh one.
    host:Hide()
    host:ClearAllPoints()
    hosts[id] = nil
    Anchors:Unregister(id)
    local container = host.container
    if container then
        NRSKNUI:RunWhenSafe(function()
            container:SetEnabled(false)
        end)
    end
end

function CDM:ReleaseAuraGroups()
    for id in pairs(hosts) do
        self:ReleaseAuraGroup(id)
    end
end
