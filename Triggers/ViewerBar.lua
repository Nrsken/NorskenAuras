---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local wipe = table.wipe
local pairs = pairs
local next = next

local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName

local viewerLayers = {} ---@type table<CDMLayer, table|true> layers following a Cooldown Manager bar -> their trigger
local runningLayers = {} ---@type table<CDMLayer, true> those whose bar is running
local changedLayers = {} ---@type table<CDMLayer, true> those Blizzard changed this frame

-- Mirror --

local driver ---@type Frame?

-- Copy Blizzard's tracked bar onto ours or onto a split power bar's progress source
---@param layer CDMLayer
---@return boolean active
local function Mirror(layer)
    local child = layer.viewerChild
    local active = child ~= nil and child:IsActive() == true

    local target = layer.viewerTarget or (layer.isBar and layer.Bar)
    if active and target and not layer.viewerHold then
        local source = child.Bar
        target:SetMinMaxValues(source:GetMinMaxValues())
        target:SetValue(source:GetValue())
        if target == layer.Bar then
            layer.Bar.spark:SetAlpha(1)
        end
    end
    return active
end

-- Every frame, as Blizzard writes its bar every frame with no event to follow
local function Drive()
    for layer in pairs(runningLayers) do
        if layer.owner.shown then
            Mirror(layer)
        end
    end
end

local function UpdateDriver()
    local running = next(runningLayers) ~= nil
    if running and not driver then
        driver = CreateFrame('Frame')
        driver:SetScript('OnUpdate', Drive)
    end
    if driver then
        driver:SetShown(running)
    end
end

---@param layer CDMLayer
local function SetRunning(layer)
    local child = layer.viewerChild
    runningLayers[layer] = child and child:IsActive() == true or nil
    UpdateDriver()
end

-- Blizzard's bars --

local BAR_VIEWERS = { 'BuffBarCooldownViewer' }

local hookedItems = {} ---@type table<table, true>
local changeFrame ---@type Frame?

-- A frame later, once Blizzard's relayout is done and the bar's state is final
local function ApplyChanges()
    for layer in pairs(changedLayers) do
        SetRunning(layer)
        CDM:UpdateLayer(layer)
    end
    wipe(changedLayers)
end

-- Blizzard started, stopped or handed one of its bars to another entry
---@param item table
local function OnItemChanged(item)
    local id = item.cooldownID
    for layer in pairs(viewerLayers) do
        local follows = id ~= nil and id == layer.viewerCooldownID
        if follows or layer.viewerChild == item then
            layer.viewerChild = follows and item or nil
            changedLayers[layer] = true
            changeFrame:NCScheduleUpdate()
        end
    end
end

-- ResetCooldownData too, as a release clears isActive without OnActiveStateChanged
---@param item table
local function HookItem(_, item)
    if hookedItems[item] then return end

    hookedItems[item] = true
    hooksecurefunc(item, 'OnActiveStateChanged', OnItemChanged)
    hooksecurefunc(item, 'OnCooldownIDSet', OnItemChanged)
    hooksecurefunc(item, 'ResetCooldownData', OnItemChanged)
end

-- Picks up a bar already running, the hooks report every change after
---@param layer CDMLayer
---@param cooldownID number?
---@param owner table|true
local function Follow(layer, cooldownID, owner)
    if not changeFrame then
        changeFrame = CreateFrame('Frame')
        changeFrame:NCSetScheduledUpdate(ApplyChanges)
        local viewer = _G.BuffBarCooldownViewer
        hooksecurefunc(viewer, 'OnAcquireItemFrame', HookItem)
        for item in viewer.itemFramePool:EnumerateActive() do
            HookItem(viewer, item)
        end
    end

    viewerLayers[layer] = owner
    layer.viewerCooldownID = cooldownID
    layer.viewerChild = cooldownID and CDM:FindViewerItem(BAR_VIEWERS, cooldownID)
    SetRunning(layer)
end

---Follow a tracked bar onto target every frame, for a split power bar's progress source
---@param layer CDMLayer
---@param cooldownID number
---@param target StatusBar
function CDM:WatchViewerBar(layer, cooldownID, target)
    layer.viewerTarget = target
    Follow(layer, cooldownID, true)
end

---Mirror once and say whether the tracked bar is running
---@param layer CDMLayer
---@return boolean active
function CDM:MirrorViewerBar(layer)
    local active = Mirror(layer)
    layer.viewerActive = active
    return active
end

-- Trigger --

-- For Cooldown Manager entries that aren't real auras
CDM.TriggerTypes.viewerbar = {
    ---@param trigger table
    ---@return boolean
    IsKnown = function(trigger) return trigger.CooldownID ~= nil end,

    ---@param layer CDMLayer
    ---@param trigger table
    Resolve = function(layer, trigger)
        layer.spellID, layer.baseSpellID = nil, nil
        Follow(layer, trigger.CooldownID, trigger)

        local info = trigger.CooldownID and CDM.Catalogue:GetEntry(trigger.CooldownID)
        local spellID = info and CDM.Catalogue:ResolveSpell(info) or trigger.SpellID
        layer.viewerSpellID = spellID
        CDM:SetIconTexture(layer, spellID and GetSpellTexture(spellID))
    end,

    ---@param layer CDMLayer
    ---@param style table
    Update = function(layer, style)
        layer.duration = nil
        local spellID = layer.viewerSpellID
        local active = Mirror(layer)
        layer.viewerActive = active
        if active then
            CDM:SetLayerName(layer, spellID and GetSpellName(spellID) or '')
        elseif CDM.IsPreviewingLayer(layer) then
            layer.duration = CDM.PreviewDuration(layer, CDM.PREVIEW_LENGTH)
            CDM:SetLayerTimer(layer, layer.duration)
            CDM:SetLayerName(layer, spellID and GetSpellName(spellID) or L['Cooldown Bar'])
        else
            CDM:SetLayerTimer(layer, nil)
        end
        if active then
            layer.Cooldown:Clear()
        end
        CDM:UpdateTexts(layer)
    end,

    ---@param layer CDMLayer
    ---@return boolean
    IsActive = function(layer)
        return layer.viewerActive == true or CDM.IsPreviewingLayer(layer)
    end,

    ---@param id string
    Unwatch = function(id)
        for layer in pairs(viewerLayers) do
            if layer.owner.id == id then
                viewerLayers[layer], runningLayers[layer], changedLayers[layer] = nil, nil, nil
                layer.viewerChild, layer.viewerActive, layer.viewerTarget, layer.viewerHold = nil, nil, nil, nil
            end
        end
        UpdateDriver()
    end,

    UnregisterEvents = function()
        wipe(viewerLayers)
        wipe(runningLayers)
        wipe(changedLayers)
        UpdateDriver()
    end,
}

-- Conditions --

CDM.ConditionChecks.viewerbar = {
    active = { type = 'bool', get = function(layer) return CDM.TriggerTypes.viewerbar.IsActive(layer) end },
}
