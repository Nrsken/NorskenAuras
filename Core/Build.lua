---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Anchors = NRSKNUI.Anchors
local Apply = NRSKNUI.Enum.Apply

--[[
Turns saved displays into frames and gives them back
An edit rebuilds only the displays and the part it changed
]]

local debugprofilestop = debugprofilestop
local CreateFrame = CreateFrame
local sort = table.sort
local wipe = table.wipe
local ipairs = ipairs
local pairs = pairs
local type = type

-- Build and release --

---@param frame CDMIcon
local function DetachFromGroup(frame)
    local group = frame.groupId and CDM.containers[frame.groupId]
    ---@cast group NorskenCore.DynamicGroup?
    if group then
        group:DetachChild(frame)
    end
    frame.groupId = nil
end

-- Placed on its own or in its dynamic group at its size and order
---@param frame CDMIcon
---@param id string
---@param display CDMDisplay
local function PlaceIcon(frame, id, display)
    if not CDM:IsDynamic(display.parent) then
        CDM:Place(frame, id, display)
        return
    end

    local group = CDM.containers[display.parent]
    ---@cast group NorskenCore.DynamicGroup
    if frame.groupId ~= display.parent then
        group:AttachChild(frame, id, display.order)
        frame.groupId = display.parent
        frame:Show()
    end
    group:SetChildOrder(id, display.order or 0)
    group:NotifyChildResized(id, frame.style.Width, frame.style.Height)
    CDM:RegisterAnchor(frame, id, true)
end

---Build an icon, bar or text, only the changed part on a built one
---Position only places, any other part restyles and re-reads triggers, Layout places too
---@param id string
---@param part NorskenCore.Apply
function CDM:BuildIcon(id, part)
    -- A disabled display keeps a hidden frame so the options can preview it
    local display = self:Get(id)
    if not display then
        return self:Release(id)
    end

    local frame = self.icons[id]
    if frame and part ~= Apply.All then
        if part ~= Apply.Position then
            frame.style = display.Style
            frame.curveGates = self:CurveGates(display)
            self:StyleIcon(frame, display, frame.style)
        end
        if part == Apply.Layout or part == Apply.Position then
            PlaceIcon(frame, id, display)
        end
        -- The restyle resets what triggers set while resolving
        -- A power bar's pips and color, the icon art, an aura's buttons
        if part ~= Apply.Position then
            self:ResolveTriggers(frame, display)
        end
        return
    end

    -- Adding a group's first aura trigger or removing its last one swaps the group's layout
    local parentFrame = display.parent and self.containers[display.parent]
    if display.parent and not parentFrame then
        self:BuildContainer(display.parent)
    elseif parentFrame and self:IsDynamic(display.parent) and (parentFrame.isChain == true) ~= self:WantsChain(display.parent) then
        -- The swap detaches every icon in the group, so all of them rebuild
        return self:ApplySettings(Apply.All, display.parent)
    end

    if not frame then
        frame = self:AcquireIcon(id)
        self.icons[id] = frame
    end

    if frame.groupId ~= display.parent then
        DetachFromGroup(frame)
    end

    frame.style = display.Style
    frame.curveGates = self:CurveGates(display)
    self:StyleIcon(frame, display, frame.style)
    PlaceIcon(frame, id, display)

    -- After joining its group, as the client locks an aura button soon after making it
    self:ResolveTriggers(frame, display)
end

---@param id string
function CDM:Release(id)
    local frame = self.icons[id]
    if frame then
        self:UnwatchIcon(id)
        DetachFromGroup(frame)
        self:ReleaseIcon(frame)
        self.icons[id] = nil
    end

    local container = self.containers[id]
    if container then
        container:Hide()
        container:ClearAllPoints()
        container.onLayout = nil
        self.containers[id] = nil

        local spare = container.isChain and self.spareChain or container.SetConfig and self.spareDynamic or self.spareStatic
        spare[#spare + 1] = container
        self:PlaceMatchedBars(id)
    end

    self:ReleaseAuraGroup(id)
    Anchors:Unregister(id)
end

-- Resolve --

-- Milliseconds per frame, every display at once froze ~25 ms when combat ended
local RESOLVE_BUDGET = 1
local resolveQueue, resolveNext = {}, 1
local resolveFrame ---@type Frame?

---@param self Frame
local function ResolveStep(self)
    -- In combat an override swap is resolved per spell, the rest waits
    if CDM.inCombat then return end

    local start = debugprofilestop()
    while resolveNext <= #resolveQueue do
        local id = resolveQueue[resolveNext]
        resolveNext = resolveNext + 1
        local frame, display = CDM.icons[id], CDM:Get(id)
        if frame and display then
            CDM:ResolveTriggers(frame, display)
            CDM:UpdateIcon(id)
        end
        if debugprofilestop() - start >= RESOLVE_BUDGET then return end
    end

    self:Hide()
    CDM:RefreshLoad(true)
end

---Re-resolve every display's triggers a few per frame, after a talent or override change
function CDM:ResolveAll()
    wipe(resolveQueue)
    for id in pairs(self.icons) do
        resolveQueue[#resolveQueue + 1] = id
    end
    resolveNext = 1

    if not resolveFrame then
        resolveFrame = CreateFrame('Frame')
        resolveFrame:SetScript('OnUpdate', ResolveStep)
    end
    resolveFrame:Show()
end

-- Apply settings --

---@param id string
---@param built string[] gets every icon, bar and text built
local function ApplySubtree(id, built)
    if CDM:IsGroup(id) then
        CDM:BuildContainer(id)
        for _, child in ipairs(CDM:GetChildren(id)) do
            ApplySubtree(child.key, built)
        end
    elseif CDM:IsAuraGroup(id) then
        CDM:BuildAuraGroup(id, Apply.All)
    else
        CDM:BuildIcon(id, Apply.All)
        built[#built + 1] = id
    end
end

-- As RefreshLoad would leave them, shown ones re-read their triggers
---@param ids string[]
local function ShowBuilt(ids)
    for _, id in ipairs(ids) do
        local frame = CDM.icons[id]
        if frame and frame.shown then
            CDM:UpdateIcon(id)
        elseif frame then
            CDM:ApplyVisibility(id, frame)
        end
    end
end

-- Parents before children, so each finds the frame it hangs off
local function BuildEverything()
    local containers = {}
    for key in pairs(CDM.db.Displays) do
        if CDM:IsGroup(key) then
            containers[#containers + 1] = key
        end
    end

    sort(containers, function(a, b)
        return CDM:GetDepth(a) < CDM:GetDepth(b)
    end)
    for _, key in ipairs(containers) do
        CDM:BuildContainer(key)
    end

    for key, display in pairs(CDM.db.Displays) do
        if CDM.LAYERED_TYPES[display.type] then
            CDM:BuildIcon(key, Apply.All)
        elseif display.type == 'auragroup' then
            CDM:BuildAuraGroup(key, Apply.All)
        end
    end
    CDM:RefreshLoad()
end

-- Each with everything inside it, skipping gone ones and ones inside another listed one
---@param ids string[]
---@param built string[]
local function BuildSubtrees(ids, built)
    local listed, done = {}, {}
    for _, id in ipairs(ids) do
        listed[id] = true
    end

    for _, id in ipairs(ids) do
        local skip = done[id] or not CDM:Get(id)
        for _, ancestor in ipairs(CDM:GetAncestors(id)) do
            if listed[ancestor] then
                skip = true
                break
            end
        end
        if not skip then
            done[id] = true
            ApplySubtree(id, built)
        end
    end
end

---Apply what an edit changed to one display, several or every one
---All rebuilds, Position only places, the rest restyle and re-read triggers
---Layout places too and Visibility reloads, a group takes any part as a relayout
---@param part NorskenCore.Apply
---@param scope (string|string[])? nil for every display
function CDM:ApplySettings(part, scope)
    if not self:IsEnabled() then return end

    if part == Apply.All and not scope then
        BuildEverything()
        return
    end

    local ids = scope
    if type(scope) == 'string' then
        ids = { scope }
    elseif not scope then
        ids = {}
        for key in pairs(self.db.Displays) do
            ids[#ids + 1] = key
        end
    end
    ---@cast ids string[]

    local built = {}
    local reload = part == Apply.All or part == Apply.Visibility
    if part == Apply.All then
        BuildSubtrees(ids, built)
    else
        for _, id in ipairs(ids) do
            if self:IsGroup(id) then
                local frame = self.containers[id]
                -- Grid and chain are different frames, so a swap hands every icon over
                -- A spare frame comes back hidden and only the load pass shows it
                if frame and self:IsDynamic(id) and (frame.isChain == true) ~= self:WantsChain(id) then
                    ApplySubtree(id, built)
                    reload = true
                else
                    self:BuildContainer(id)
                end
            elseif self:IsAuraGroup(id) then
                self:BuildAuraGroup(id, part)
            elseif self:Get(id) then
                self:BuildIcon(id, part)
                built[#built + 1] = id
            end
        end
    end

    if part ~= Apply.Position then
        ShowBuilt(built)
    end
    if reload then
        self:RefreshLoad(true)
        return
    end
    -- Dynamic groups and the unit frame anchor follow a size change
    self:SendMessage('NRSKNUI_CDM_LAYOUT_CHANGED')
end
