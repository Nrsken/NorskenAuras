---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local LoadConditions = NRSKNUI.LoadConditions

--[[
Which displays show, from their load state and the options' previews
]]

local format = string.format
local tostring = tostring
local wipe = table.wipe
local ipairs = ipairs
local pairs = pairs

CDM.previewPages = 'cooldownManager'

-- Load state --

local STATE_RANK = {
    loaded = 3,
    standby = 2,
    unloaded = 1
}

---Whether any trigger is known, the one load input that changes in combat
---@param display CDMDisplay
---@return boolean
function CDM:IsDisplayKnown(display)
    for _, trigger in ipairs(display.Triggers) do
        local triggerType = self.TriggerTypes[trigger.Type]
        if triggerType and triggerType.IsKnown(trigger) then return true end
    end
    return false
end

---Whether a known trigger appeared or went away since the last load refresh
---@return boolean
function CDM:KnownChanged()
    for id, frame in pairs(self.icons) do
        local display = self:Get(id)
        if display and self:IsDisplayKnown(display) ~= frame.known then return true end
    end
    return false
end

---Standby when only situational load conditions fail, unloaded when a hard one does
---A group takes the best state inside it
---@param id string
---@return 'loaded'|'standby'|'unloaded'
---@return string? reason why a single display is not loaded, for the debug report
function CDM:GetLoadState(id)
    local display = self:Get(id)
    if not display then
        return 'unloaded', 'missing'
    end
    if not display.Enabled then
        return 'unloaded', 'disabled'
    end

    if self:IsGroup(id) then
        local best
        for _, leafId in ipairs(self:GetLeaves(id)) do
            local state = self:GetLoadState(leafId)
            if not best or STATE_RANK[state] > STATE_RANK[best] then
                best = state
            end
        end
        return best or 'loaded'
    end

    for _, ancestor in ipairs(self:GetAncestors(id)) do
        if not self:Get(ancestor).Enabled then
            return 'unloaded', format("group '%s' disabled", self:GetName(ancestor))
        end
    end

    if self.LAYERED_TYPES[display.type] and not self:IsDisplayKnown(display) then
        return 'unloaded', 'no trigger is known'
    end

    local hard, hardFailed = LoadConditions:Check(display.Load, true)
    if not hard then
        return 'unloaded', 'load condition ' .. tostring(hardFailed)
    end

    local situational, failed = LoadConditions:Check(display.Load)
    if not situational then
        return 'standby', 'load condition ' .. tostring(failed)
    end

    return 'loaded'
end

-- Preview --

---Opening the page previews every loaded display at level 1
function CDM:ShowPreview()
    self.previewing = true
    for id, display in pairs(self.db.Displays) do
        if (self.icons[id] or display.type == 'auragroup') and (self.preview[id] or 0) == 0 and self:GetLoadState(id) == 'loaded' then
            self.preview[id] = 1
        end
    end

    self:RefreshLoad()
end

function CDM:HidePreview()
    self.previewing = false
    for id, level in pairs(self.preview) do
        if level == 1 then
            self.preview[id] = nil
        end
    end
    wipe(self.selectionPreview)

    self:RefreshLoad()
end

---@param id string
---@return string[]
function CDM:GetPreviewTargets(id)
    if self:IsGroup(id) then
        return self:GetLeaves(id)
    end

    return { id }
end

---@param id string
---@return number level 0 hidden, 1 shown by selection or partly (a group), 2 pinned by the eye
function CDM:GetPreview(id)
    if not self:IsGroup(id) then
        return self.preview[id] or 0
    end

    local pinned, hidden, total = 0, 0, 0
    for _, iconId in ipairs(self:GetLeaves(id)) do
        local level = self.preview[iconId] or 0
        total = total + 1
        if level == 2 then
            pinned = pinned + 1
        elseif level == 0 then
            hidden = hidden + 1
        end
    end

    if total == 0 or hidden == total then
        return 0
    end

    return pinned == total and 2 or 1
end

---Pin or clear the preview of a display or of every display in a group
---@param id string
---@param level number
function CDM:SetPreview(id, level)
    for _, iconId in ipairs(self:GetPreviewTargets(id)) do
        self.preview[iconId] = level
    end

    self:RefreshLoad(true) -- A display reads whether it shows, never its level
end

---The selected display previews at level 1, the last one drops back unless pinned
---@param id string?
function CDM:SetSelectionPreview(id)
    local previous = {}
    for _, key in ipairs(self.selectionPreview) do
        previous[key] = true
    end

    -- Takes what nothing else shows and what it previewed itself last time
    local wanted, same = {}, true
    if id and self:Get(id) then
        for _, iconId in ipairs(self:GetPreviewTargets(id)) do
            local level = self.preview[iconId] or 0
            if level == 0 or (level == 1 and previous[iconId]) then
                wanted[#wanted + 1] = iconId
                same = same and level == 1
            end
        end
    end
    if same and #wanted == #self.selectionPreview then return end

    local keep = {}
    for _, key in ipairs(wanted) do
        keep[key] = true
        if (self.preview[key] or 0) == 0 then
            self.preview[key] = 1
        end
    end
    for key in pairs(previous) do
        if not keep[key] and self.preview[key] == 1 then
            self.preview[key] = nil
        end
    end
    wipe(self.selectionPreview)
    for i, key in ipairs(wanted) do
        self.selectionPreview[i] = key
    end

    self:RefreshLoad(true)
end

---@param id string
---@return boolean
function CDM:IsPreviewed(id)
    return self.previewing == true and (self.preview[id] or 0) > 0
end

-- Visibility --

-- A container shows while anything under it does
---@param id string
---@param childIndex table<string, CDMTreeEntry[]>
---@param shown table<string, boolean>
---@return boolean
local function AnyShown(id, childIndex, shown)
    local children = childIndex[id]
    if not children then return false end

    for _, child in ipairs(children) do
        if shown[child.key] or AnyShown(child.key, childIndex, shown) then return true end
    end
    return false
end

---Show what's loaded, only what's previewed while the options are open
---Hidden displays stop updating
---@param changedOnly boolean? rebuild only what just loaded, a display that stayed is current
function CDM:RefreshLoad(changedOnly)
    local previewing = self.previewing
    local shown = {}
    for id, display in pairs(self.db.Displays) do
        if self.icons[id] or display.type == 'auragroup' then
            if previewing then
                shown[id] = self:IsPreviewed(id)
            else
                shown[id] = self:GetLoadState(id) == 'loaded'
            end
        end
    end

    local childIndex = self:GetChildrenIndex()
    for id, container in pairs(self.containers) do
        container:SetShown(AnyShown(id, childIndex, shown))
    end

    for id, frame in pairs(self.icons) do
        local display = self:Get(id)
        frame.known = display ~= nil and self:IsDisplayKnown(display)
        if not changedOnly or (frame.shown == true) ~= (shown[id] == true) then
            frame.shown = shown[id]
            if shown[id] then
                self:UpdateIcon(id)
            else
                self:ApplyVisibility(id, frame)
            end
        end
    end
    self:RefreshAuraGroups()

    -- Tell whoever follows the CDM, its anchors, the options page and Blizzard's viewers
    self:SendMessage('NRSKNUI_CDM_LAYOUT_CHANGED')
    if self.onStateChanged then
        self.onStateChanged()
    end
end

-- Exports --

CDM.STATE_RANK = STATE_RANK
