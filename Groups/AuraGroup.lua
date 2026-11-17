---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Anchors = NRSKNUI.Anchors
local Apply = NRSKNUI.Enum.Apply

local UIParent = UIParent
local pairs = pairs

-- An aura group's button has no spell of its own to name
local AURA_GROUP_TRIGGER = { Type = 'aura', Source = 'custom' }

local groups = {} ---@type table<string, { aura: AuraDisplay, owner: { id: string, style: NorskenCore.IconStyle } }>

-- Host --

---@param id string
---@return Frame?
function CDM:GetAuraHost(id)
    local group = groups[id]
    return group and group.aura.host
end

-- Show --

-- With the options open a previewed group shows dummies, otherwise what's loaded shows
---@param id string
---@param aura AuraDisplay
local function ShowAuraGroup(id, aura)
    local previewed = CDM:IsPreviewed(id)
    local shown
    if CDM.previewing then
        shown = previewed
    else
        shown = CDM:GetLoadState(id) == 'loaded'
    end
    aura.host:SetShown(shown)
    aura:SetPreview(shown and previewed)
end

function CDM:RefreshAuraGroups()
    for id, group in pairs(groups) do
        ShowAuraGroup(id, group.aura)
    end
end

-- Build --

---Create or re-apply an aura group, a part re-applies only what it names
---@param id string
---@param part NorskenCore.Apply
function CDM:BuildAuraGroup(id, part)
    local display = self:Get(id)
    if not display then
        return self:Release(id)
    end
    if display.parent and not self.containers[display.parent] then
        self:BuildContainer(display.parent)
    end

    local group, created = groups[id], false
    if not group then
        local owner = { id = id }
        group = { owner = owner }
        group.aura = NRSKNUI:NewAuraDisplay(UIParent, {
            shape = 'group',
            style = function(entry)
                -- A button handed over before the container parks can outlive its group
                local saved = self:Get(id)
                if not saved then return end

                -- Each button stands in for a layer of its own, styled like an icon's aura
                local layer = entry.layer
                if not layer then
                    layer = { owner = owner, auraRefs = entry.refs, isGroupButton = true } --[[@as CDMLayer]]
                    entry.layer = layer
                end
                layer.index = entry.branch
                layer.subRegions = saved.SubRegions
                self:StyleAuraButton(layer, AURA_GROUP_TRIGGER)
            end,
        })
        groups[id] = group
        created = true
    end

    local all = created or part == Apply.All
    local looks = all or not (part == Apply.Position or part == Apply.Visibility)
    -- Set before the display reads it, as SetTrigger can hand a button over at once
    local style = display.Style
    group.owner.style = style
    local aura, host = group.aura, group.aura.host
    if looks then
        aura:Restyle()
        host:SetAlpha(style.Alpha)
    end
    if all or part == Apply.Layout then
        aura:SetLayout(NRSKNUI:GetAuraGroupConfig(display, style), NRSKNUI:GetAuraPreviewCount(display))
    end
    if all or part == Apply.Visibility then
        aura:SetTrigger(display.Trigger)
        aura:SetUnit(display.Trigger.Unit)
        self:EvaluateGroupConditions(display, host)
    end
    -- A condition can move it too
    if all or part == Apply.Layout or part == Apply.Position or part == Apply.Visibility then
        self:Place(host, id, display)
    end
    if created then
        ShowAuraGroup(id, aura)
    end
end

-- Refresh --

---Re-read every aura group's trigger, as one trigger page edit can reach any of them
function CDM:ReapplyAuraTriggers()
    for id, group in pairs(groups) do
        local display = self:Get(id)
        if display then
            local aura = group.aura
            aura:SetLayout(NRSKNUI:GetAuraGroupConfig(display, display.Style), NRSKNUI:GetAuraPreviewCount(display))
            aura:SetTrigger(display.Trigger)
            aura:SetUnit(display.Trigger.Unit)
        end
    end
end

-- Release --

---@param id string
function CDM:ReleaseAuraGroup(id)
    local group = groups[id]
    if not group then return end

    -- A new display gets a fresh one, this one stays parked
    group.aura:Release()
    group.aura.host:ClearAllPoints()
    groups[id] = nil
    Anchors:Unregister(id)
end

function CDM:ReleaseAuraGroups()
    for id in pairs(groups) do
        self:ReleaseAuraGroup(id)
    end
end
